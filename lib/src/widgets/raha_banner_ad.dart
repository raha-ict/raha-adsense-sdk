import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/raha_adsense.dart';
import '../core/raha_ads_debug_log.dart';
import '../core/ad_request_log_context.dart';
import '../core/signal_equality.dart';
import '../core/viewability_policy.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';
import 'banner_creative.dart';
import 'visible_ad_request_scheduler.dart';

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
    this.language,
    this.differenceTime,
    this.fit = BoxFit.none,
    this.onLoaded,
    this.onImpression,
    this.onClick,
    this.onError,
  });

  /// The requested banner size.
  final RahaBannerSize size;

  /// Optional contextual signals that are sent with the ad request.
  final Map<String, Object?> signals;

  /// Optional content language for generated request signals.
  final String? language;

  /// Optional time offset for generated day and time request signals.
  final Duration? differenceTime;

  /// How the fixed-size banner creative should fit inside parent constraints.
  ///
  /// Defaults to [BoxFit.none], which preserves exact-size rendering.
  final BoxFit fit;

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
  late VisibleAdRequestScheduler _requestScheduler;
  RahaAdRequestLogContext? _activeRequestContext;
  RahaBannerAdResponse? _ad;
  bool _noFill = false;
  bool _imageDecoded = false;
  bool _foreground = true;
  double _visibleFraction = 0;
  Timer? _impressionTimer;
  bool _impressionRecorded = false;
  late final String _widgetInstanceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cancelToken = CancelToken();
    _widgetInstanceId = nextRahaWidgetInstanceId();
    _debugLog('event=widget_mount');
    _requestScheduler = VisibleAdRequestScheduler(
      load: _load,
      tryAcquireRequestSlot: _tryAcquireRequestSlot,
      onLog: _debugLog,
      placementId: _placementId,
      widgetInstanceId: _widgetInstanceId,
    );
  }

  @override
  void didUpdateWidget(covariant RahaBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size ||
        !samePublisherSignals(oldWidget.signals, widget.signals) ||
        oldWidget.language != widget.language ||
        oldWidget.differenceTime != widget.differenceTime) {
      _requestScheduler.requestRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _requestScheduler.updateVisibility(
      _foreground ? _visibleFraction : 0,
    );
    _evaluateViewability();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debugLog('event=widget_dispose placementId=${_placementId()}');
    _requestScheduler.dispose();
    _impressionTimer?.cancel();
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _load(RahaAdRequestLogContext requestContext) async {
    _activeRequestContext = requestContext;
    _cancelToken.cancel();
    _cancelToken = CancelToken();
    try {
      final ad = await RahaAdsense.runtime.requestBannerAd(
        size: widget.size,
        signals: widget.signals,
        language: widget.language,
        differenceTime: widget.differenceTime,
        cancelToken: _cancelToken,
        requestContext: requestContext,
      );
      if (!mounted || _cancelToken.isCancelled) return;
      _impressionTimer?.cancel();
      _impressionTimer = null;
      _imageDecoded = false;
      _impressionRecorded = false;
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
    return VisibilityDetector(
      key: ObjectKey(this),
      onVisibilityChanged: (info) {
        _visibleFraction = info.visibleFraction;
        _requestScheduler.updateVisibility(info.visibleFraction);
        _evaluateViewability();
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_noFill) {
      return _buildBannerFrame(
        width: widget.size.width.toDouble(),
        height: widget.size.height.toDouble(),
        child: const SizedBox.expand(),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.fit == BoxFit.none &&
            !canRenderExactBanner(constraints, widget.size)) {
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
          return _buildBannerFrame(
            width: widget.size.width.toDouble(),
            height: widget.size.height.toDouble(),
            child: const SizedBox.expand(),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleClick(ad),
          child: _buildFilledBanner(ad),
        );
      },
    );
  }

  Widget _buildFilledBanner(RahaBannerAdResponse ad) {
    return _buildBannerFrame(
      width: ad.width.toDouble(),
      height: ad.height.toDouble(),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RahaBannerCreative(
              url: ad.imageUrl,
              width: ad.width.toDouble(),
              height: ad.height.toDouble(),
              onRendered: () {
                if (!mounted || _imageDecoded) return;
                _imageDecoded = true;
                _evaluateViewability();
              },
              onError: (error) {
                widget.onError?.call(_asRahaError(error));
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

  Widget _buildBannerFrame({
    required Widget child,
    required double width,
    required double height,
  }) {
    final content = SizedBox(width: width, height: height, child: child);

    if (widget.fit == BoxFit.none) return content;

    return SizedBox.expand(
      child: FittedBox(
        fit: widget.fit,
        child: content,
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
    _impressionTimer = null;
    final ad = _ad;
    if (ad == null || _impressionRecorded) return;
    _impressionRecorded = true;
    try {
      await ad.recordImpression();
      if (!mounted) return;
      widget.onImpression?.call(ad.info);
    } on Object catch (error) {
      _impressionRecorded = false;
      if (mounted) widget.onError?.call(_asRahaError(error));
    }
  }

  String _placementId() => RahaAdsense.isReady
      ? RahaAdsense.runtime.automaticBannerPlacementId(widget.size)
      : 'banner:${widget.size.wireValue}';

  Duration? _tryAcquireRequestSlot() {
    if (!RahaAdsense.isReady) return const Duration(minutes: 30);
    return RahaAdsense.runtime.tryAcquireAutomaticRequest(_placementId());
  }

  void _debugLog(String message) {
    if (RahaAdsense.isReady && RahaAdsense.runtime.config.enableDebugLogs) {
      final requestContext = _activeRequestContext;
      rahaAdsDebugLog(
        '$message format=banner visitorIdHash='
        '${RahaAdsense.runtime.visitorIdLogFingerprint} '
        'widgetInstanceId=$_widgetInstanceId '
        'requestId=${requestContext?.requestId ?? 'none'} '
        'requestSource=${requestContext?.requestSource ?? 'widget_lifecycle'} '
        'trigger=${requestContext?.trigger ?? 'state'} '
        'visibleFraction=$_visibleFraction',
      );
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
