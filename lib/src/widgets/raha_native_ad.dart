import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/raha_adsense.dart';
import '../core/viewability_policy.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';

/// A widget that displays a Raha native ad.
///
/// Native ads render title, description, images, and click behavior while
/// preserving the app's existing layout and styling.
class RahaNativeAd extends StatefulWidget {
  const RahaNativeAd({
    super.key,
    this.signals = const <String, Object?>{},
    this.language,
    this.differenceTime,
    this.onLoaded,
    this.onImpression,
    this.onClick,
    this.onError,
  });

  /// Optional contextual signals included with the native ad request.
  final Map<String, Object?> signals;

  /// Optional content language for generated request signals.
  final String? language;

  /// Optional time offset for generated day and time request signals.
  final Duration? differenceTime;

  /// Called when the native ad is loaded successfully.
  final ValueChanged<RahaAdInfo>? onLoaded;

  /// Called when the native ad impression is recorded.
  final ValueChanged<RahaAdInfo>? onImpression;

  /// Called when the native ad is clicked.
  final ValueChanged<RahaAdInfo>? onClick;

  /// Called when the native ad cannot be loaded or displayed.
  final ValueChanged<RahaAdsException>? onError;

  @override
  State<RahaNativeAd> createState() => _RahaNativeAdState();
}

class _RahaNativeAdState extends State<RahaNativeAd>
    with WidgetsBindingObserver {
  late CancelToken _cancelToken;
  RahaNativeAdResponse? _ad;
  bool _noFill = false;
  bool _foreground = true;
  bool _primaryImageDecoded = false;
  bool _impressionRecorded = false;
  double _visibleFraction = 0;
  Timer? _impressionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cancelToken = CancelToken();
    _load();
  }

  @override
  void didUpdateWidget(covariant RahaNativeAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signals != widget.signals ||
        oldWidget.language != widget.language ||
        oldWidget.differenceTime != widget.differenceTime) {
      _reset();
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
    _reset();
    super.dispose();
  }

  void _reset() {
    _cancelToken.cancel();
    _cancelToken = CancelToken();
    _impressionTimer?.cancel();
    _impressionTimer = null;
    _ad = null;
    _noFill = false;
    _foreground = true;
    _primaryImageDecoded = false;
    _impressionRecorded = false;
    _visibleFraction = 0;
  }

  Future<void> _load() async {
    try {
      final ad = await RahaAdsense.runtime.requestNativeAd(
        signals: widget.signals,
        language: widget.language,
        differenceTime: widget.differenceTime,
        cancelToken: _cancelToken,
      );
      if (!mounted || _cancelToken.isCancelled) return;
      setState(() {
        _ad = ad;
        _noFill = ad == null;
        _primaryImageDecoded = ad?.imageUrl == null;
      });
      if (ad != null) widget.onLoaded?.call(ad.info);
      _evaluateViewability();
    } on Object catch (error) {
      if (!mounted || _cancelToken.isCancelled) return;
      widget.onError?.call(_asRahaError(error));
      setState(() => _noFill = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (_noFill || ad == null) return const SizedBox.shrink();
    return VisibilityDetector(
      key: ValueKey('raha-native-${ad.info.adId}-${ad.info.placementId}'),
      onVisibilityChanged: (info) {
        _visibleFraction = info.visibleFraction;
        _evaluateViewability();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleClick(ad),
        child: _NativeCard(
          ad: ad,
          onPrimaryImageDecoded: () {
            if (_primaryImageDecoded) return;
            _primaryImageDecoded = true;
            _evaluateViewability();
          },
          onImageError: (error) => widget.onError?.call(_asRahaError(error)),
        ),
      ),
    );
  }

  void _evaluateViewability() {
    if (_impressionRecorded) return;

    // Only count the native impression after the primary image has rendered,
    // the ad is visible enough, and the app is active.
    final qualified = _ad != null &&
        _foreground &&
        _primaryImageDecoded &&
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

  Future<void> _handleClick(RahaNativeAdResponse ad) async {
    try {
      await ad.openClick();
      if (mounted) widget.onClick?.call(ad.info);
    } on Object catch (error) {
      if (mounted) widget.onError?.call(_asRahaError(error));
    }
  }
}

class _NativeCard extends StatelessWidget {
  const _NativeCard({
    required this.ad,
    required this.onPrimaryImageDecoded,
    required this.onImageError,
  });

  final RahaNativeAdResponse ad;
  final VoidCallback onPrimaryImageDecoded;
  final ValueChanged<Object> onImageError;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ad.imageUrl;
    final iconUrl = ad.iconUrl;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (iconUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      iconUrl.toString(),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        onImageError(error);
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ad.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ad',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  imageUrl.toString(),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, sync) {
                    if (frame != null || sync) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        onPrimaryImageDecoded();
                      });
                    }
                    return child;
                  },
                  errorBuilder: (context, error, stackTrace) {
                    onImageError(error);
                    onPrimaryImageDecoded();
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
            if (ad.description != null) ...[
              const SizedBox(height: 8),
              Text(ad.description!),
            ],
            if (ad.cta != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      ad.cta!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

RahaAdsException _asRahaError(Object error) {
  if (error is RahaAdsException) return error;
  return RahaAdsException(
    RahaAdsErrorCode.network,
    'Raha native ad failed.',
    cause: error,
  );
}
