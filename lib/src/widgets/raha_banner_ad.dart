import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/raha_adsense.dart';
import '../core/viewability_policy.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';

/// A widget that displays a Raha banner ad.
///
/// The banner is loaded automatically when the widget is created. It tracks
/// viewability before sending an impression event, and reports clicks via the
/// configured click opener.
class RahaBannerAd extends StatefulWidget {
  const RahaBannerAd({
    required this.size,
    super.key,
    this.signals = const <String, Object?>{},
    this.differenceTime,
    this.onLoaded,
    this.onImpression,
    this.onClick,
    this.onError,
  });

  /// The requested banner size.
  final RahaBannerSize size;

  /// Optional contextual signals that are sent with the ad request.
  final Map<String, Object?> signals;

  /// Optional time offset for generated day and time request signals.
  final Duration? differenceTime;

  /// Called when the banner ad is successfully loaded.
  final ValueChanged<RahaAdInfo>? onLoaded;

  /// Called when the banner ad impression is recorded.
  final ValueChanged<RahaAdInfo>? onImpression;

  /// Called when the banner ad is clicked.
  final ValueChanged<RahaAdInfo>? onClick;

  /// Called when a banner ad fails to load or display.
  final ValueChanged<RahaAdsException>? onError;

  @override
  State<RahaBannerAd> createState() => _RahaBannerAdState();
}

class _RahaBannerAdState extends State<RahaBannerAd>
    with WidgetsBindingObserver {
  late CancelToken _cancelToken;
  RahaBannerAdResponse? _ad;
  bool _noFill = false;
  bool _imageDecoded = false;
  bool _foreground = true;
  double _visibleFraction = 0;
  Timer? _impressionTimer;
  bool _impressionRecorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cancelToken = CancelToken();
    _load();
  }

  @override
  void didUpdateWidget(covariant RahaBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size ||
        oldWidget.signals != widget.signals ||
        oldWidget.differenceTime != widget.differenceTime) {
      _cancelToken.cancel();
      _impressionTimer?.cancel();
      _cancelToken = CancelToken();
      _ad = null;
      _noFill = false;
      _imageDecoded = false;
      _impressionRecorded = false;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _evaluateViewability();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _impressionTimer?.cancel();
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ad = await RahaAdsense.runtime.requestBannerAd(
        size: widget.size,
        signals: widget.signals,
        differenceTime: widget.differenceTime,
        cancelToken: _cancelToken,
      );
      if (!mounted || _cancelToken.isCancelled) return;
      setState(() {
        _ad = ad;
        _noFill = ad == null;
      });
      if (ad != null) widget.onLoaded?.call(ad.info);
    } on Object catch (error) {
      if (!mounted || _cancelToken.isCancelled) return;
      widget.onError?.call(_asRahaError(error));
      setState(() => _noFill = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_noFill) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!canRenderExactBanner(constraints, widget.size)) {
          widget.onError?.call(
            RahaAdsException(
              RahaAdsErrorCode.layout,
              'Parent constraints cannot render the exact banner size '
              '${widget.size.wireValue}.',
            ),
          );
          return const SizedBox.shrink();
        }

        final ad = _ad;
        if (ad == null) {
          return SizedBox(
            width: widget.size.width.toDouble(),
            height: widget.size.height.toDouble(),
          );
        }

        return VisibilityDetector(
          key: ValueKey('raha-banner-${ad.info.adId}-${ad.info.placementId}'),
          onVisibilityChanged: (info) {
            _visibleFraction = info.visibleFraction;
            _evaluateViewability();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleClick(ad),
            child: _buildFilledBanner(ad),
          ),
        );
      },
    );
  }

  Widget _buildFilledBanner(RahaBannerAdResponse ad) {
    return SizedBox(
      width: ad.width.toDouble(),
      height: ad.height.toDouble(),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              ad.imageUrl.toString(),
              width: ad.width.toDouble(),
              height: ad.height.toDouble(),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.low,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if ((frame != null || wasSynchronouslyLoaded) &&
                    !_imageDecoded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _imageDecoded = true;
                    _evaluateViewability();
                  });
                }
                return child;
              },
              errorBuilder: (context, error, stackTrace) {
                widget.onError?.call(_asRahaError(error));
                return const SizedBox.shrink();
              },
            ),
            const PositionedDirectional(
              top: 2,
              end: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x99000000)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  child: Text(
                    'Ad',
                    style: TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _evaluateViewability() {
    if (_impressionRecorded) return;

    // Only record an impression when the ad is visible, decoded, and in
    // the foreground for the configured duration.
    final qualified = _ad != null &&
        _imageDecoded &&
        _foreground &&
        _visibleFraction >= bannerVisibleFraction;
    if (!qualified) {
      _impressionTimer?.cancel();
      _impressionTimer = null;
      return;
    }
    _impressionTimer ??= Timer(bannerVisibleDuration, _recordImpression);
  }

  Future<void> _recordImpression() async {
    final ad = _ad;
    if (ad == null || _impressionRecorded) return;
    try {
      await ad.recordImpression();
      if (!mounted) return;
      _impressionRecorded = true;
      widget.onImpression?.call(ad.info);
    } on Object catch (error) {
      if (mounted) widget.onError?.call(_asRahaError(error));
    }
  }

  Future<void> _handleClick(RahaBannerAdResponse ad) async {
    try {
      await ad.openClick();
      if (mounted) widget.onClick?.call(ad.info);
    } on Object catch (error) {
      if (mounted) widget.onError?.call(_asRahaError(error));
    }
  }
}

bool canRenderExactBanner(BoxConstraints constraints, RahaBannerSize size) {
  final width = size.width.toDouble();
  final height = size.height.toDouble();
  return constraints.minWidth <= width &&
      width <= constraints.maxWidth &&
      constraints.minHeight <= height &&
      height <= constraints.maxHeight;
}

RahaAdsException _asRahaError(Object error) {
  if (error is RahaAdsException) return error;
  return RahaAdsException(
    RahaAdsErrorCode.network,
    'Raha banner ad failed.',
    cause: error,
  );
}
