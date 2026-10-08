import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/raha_adsense.dart';
import '../core/raha_ads_debug_log.dart';
import '../core/ad_request_log_context.dart';
import '../core/signal_equality.dart';
import '../core/viewability_policy.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';
import 'visible_ad_request_scheduler.dart';

/// A widget that displays a Raha video ad.
///
/// The ad loads automatically and plays once it is ready. It tracks viewability
/// before reporting an impression and supports tap-to-click behavior.
class RahaVideoAd extends StatefulWidget {
  const RahaVideoAd({
    super.key,
    this.signals = const <String, Object?>{},
    this.language,
    this.differenceTime,
    this.onLoaded,
    this.onImpression,
    this.onCompleted,
    this.onClick,
    this.onError,
  });

  /// Optional contextual signals sent with the video ad request.
  final Map<String, Object?> signals;

  /// Optional content language for generated request signals.
  final String? language;

  /// Optional time offset for generated day and time request signals.
  final Duration? differenceTime;

  /// Called when the video ad has loaded successfully.
  final ValueChanged<RahaAdInfo>? onLoaded;

  /// Called when the video ad impression has been recorded.
  final ValueChanged<RahaAdInfo>? onImpression;

  /// Called when the video playback reaches completion.
  final ValueChanged<RahaAdInfo>? onCompleted;

  /// Called when the user taps the video ad.
  final ValueChanged<RahaAdInfo>? onClick;

  /// Called when there is an error loading, displaying, or tracking the ad.
  final ValueChanged<RahaAdsException>? onError;

  @override
  State<RahaVideoAd> createState() => _RahaVideoAdState();
}

class _RahaVideoAdState extends State<RahaVideoAd> with WidgetsBindingObserver {
  late CancelToken _cancelToken;
  late VisibleAdRequestScheduler _requestScheduler;
  RahaAdRequestLogContext? _activeRequestContext;
  RahaVideoAdResponse? _ad;
  VideoPlayerController? _controller;
  bool _noFill = false;
  bool _foreground = true;
  bool _impressionRecorded = false;
  bool _impressionInFlight = false;
  bool _impressionAbandoned = false;
  int _impressionAttempts = 0;
  bool _completed = false;
  bool _lastPlayingState = false;
  bool _wasPlayingBeforeBackground = false;
  double _visibleFraction = 0;
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
  void didUpdateWidget(covariant RahaVideoAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!samePublisherSignals(oldWidget.signals, widget.signals) ||
        oldWidget.language != widget.language ||
        oldWidget.differenceTime != widget.differenceTime) {
      _requestScheduler.requestRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _wasPlayingBeforeBackground = _controller?.value.isPlaying ?? false;
      _controller?.pause();
    } else if (_wasPlayingBeforeBackground) {
      _wasPlayingBeforeBackground = false;
      _controller?.play();
    }
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
    _reset();
    super.dispose();
  }

  void _reset() {
    _cancelToken.cancel();
    _cancelToken = CancelToken();
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _controller = null;
    _ad = null;
    _noFill = false;
    _impressionRecorded = false;
    _impressionInFlight = false;
    _impressionAbandoned = false;
    _impressionAttempts = 0;
    _completed = false;
  }

  Future<void> _load(RahaAdRequestLogContext requestContext) async {
    _activeRequestContext = requestContext;
    _cancelToken.cancel();
    _cancelToken = CancelToken();
    try {
      final ad = await RahaAdsense.runtime.requestVideoAd(
        signals: widget.signals,
        language: widget.language,
        differenceTime: widget.differenceTime,
        cancelToken: _cancelToken,
        requestContext: requestContext,
      );
      if (!mounted || _cancelToken.isCancelled) return;
      if (ad == null) {
        _disposeController();
        setState(() => _noFill = true);
        return;
      }

      final controller = VideoPlayerController.networkUrl(ad.videoUrl);
      await controller.initialize();
      if (!mounted || _cancelToken.isCancelled) {
        await controller.dispose();
        return;
      }
      controller
        ..setLooping(false)
        ..addListener(_onVideoChanged);
      final oldController = _controller;
      oldController?.removeListener(_onVideoChanged);
      setState(() {
        _ad = ad;
        _controller = controller;
        _noFill = false;
        _impressionRecorded = false;
        _impressionInFlight = false;
        _impressionAbandoned = false;
        _impressionAttempts = 0;
        _completed = false;
        _lastPlayingState = false;
      });
      oldController?.dispose();
      widget.onLoaded?.call(ad.info);
      _debugLog('event=video_initialized placementId=${ad.info.placementId}');
      await controller.play();
      _logPlayingState(controller.value.isPlaying, ad.info.placementId);
      _evaluateViewability();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          widget.onError?.call(
            const RahaAdsException(
              RahaAdsErrorCode.layout,
              'RahaVideoAd requires bounded parent constraints.',
            ),
          );
          return const SizedBox.shrink();
        }
        final controller = _controller;
        final ad = _ad;
        if (_noFill || controller == null || ad == null) {
          return const SizedBox.expand(
            child: ColoredBox(color: Colors.black),
          );
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleClick(ad),
          child: _buildVideoSurface(controller),
        );
      },
    );
  }

  Widget _buildVideoSurface(VideoPlayerController controller) {
    final value = controller.value;
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }

  void _onVideoChanged() {
    final controller = _controller;
    final ad = _ad;
    if (controller == null || ad == null) return;
    final value = controller.value;
    _logPlayingState(value.isPlaying, ad.info.placementId);
    if (!_completed &&
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _completed = true;
      widget.onCompleted?.call(ad.info);
    }
    _evaluateViewability();
  }

  void _evaluateViewability() {
    final controller = _controller;
    final value = controller?.value;
    final ad = _ad;
    if (_impressionRecorded || _impressionAbandoned) {
      _debugLog(
        'event=impression_skip placementId=${ad?.info.placementId ?? 'video'} '
        'reason=already_sent',
      );
      return;
    }

    final String? reason;
    if (_visibleFraction < videoVisibleFraction) {
      reason = 'not_visible';
    } else if (!_foreground) {
      reason = 'background';
    } else if (value?.isBuffering == true) {
      reason = 'buffering';
    } else if (value?.isPlaying != true || value?.isInitialized != true) {
      reason = 'not_playing';
    } else if (ad == null || controller == null) {
      reason = 'not_playing';
    } else {
      reason = null;
    }

    if (reason != null) {
      _debugLog(
        'event=impression_skip placementId=${ad?.info.placementId ?? 'video'} '
        'reason=$reason',
      );
      return;
    }
    if (_impressionInFlight) return;
    if (_impressionAttempts >= 2) {
      _debugLog(
        'event=impression_skip placementId=${ad!.info.placementId} '
        'reason=already_sent',
      );
      return;
    }

    _debugLog(
      'event=impression_eligible placementId=${ad!.info.placementId} '
      'reason=visible_playing',
    );
    _recordImpression();
  }

  Future<void> _recordImpression() async {
    final ad = _ad;
    if (ad == null ||
        _impressionRecorded ||
        _impressionInFlight ||
        _impressionAttempts >= 2) {
      return;
    }
    _impressionInFlight = true;
    _impressionAttempts++;
    try {
      await ad.recordImpression();
      if (!mounted) return;
      _impressionRecorded = true;
      widget.onImpression?.call(ad.info);
    } on Object catch (error) {
      if (!_isRetryableImpressionError(error)) _impressionAbandoned = true;
      if (mounted) widget.onError?.call(_asRahaError(error));
    } finally {
      _impressionInFlight = false;
    }
  }

  bool _isRetryableImpressionError(Object error) {
    if (error is! RahaAdsException) return true;
    final status = error.statusCode;
    if (status != null) return status == 408 || status == 429 || status >= 500;
    return error.code == RahaAdsErrorCode.network ||
        error.code == RahaAdsErrorCode.timeout ||
        error.code == RahaAdsErrorCode.rateLimited;
  }

  void _disposeController() {
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _controller = null;
    _ad = null;
  }

  void _logPlayingState(bool isPlaying, String placementId) {
    if (isPlaying == _lastPlayingState) return;
    _lastPlayingState = isPlaying;
    if (isPlaying) _debugLog('event=video_playing placementId=$placementId');
  }

  String _placementId() => RahaAdsense.isReady
      ? RahaAdsense.runtime.automaticVideoPlacementId()
      : 'video';

  Duration? _tryAcquireRequestSlot() {
    if (!RahaAdsense.isReady) return const Duration(minutes: 30);
    return RahaAdsense.runtime.tryAcquireAutomaticRequest(_placementId());
  }

  void _debugLog(String message) {
    if (RahaAdsense.isReady && RahaAdsense.runtime.config.enableDebugLogs) {
      final requestContext = _activeRequestContext;
      rahaAdsDebugLog(
        '$message format=video visitorIdHash='
        '${RahaAdsense.runtime.visitorIdLogFingerprint} '
        'widgetInstanceId=$_widgetInstanceId '
        'requestId=${requestContext?.requestId ?? 'none'} '
        'requestSource=${requestContext?.requestSource ?? 'widget_lifecycle'} '
        'trigger=${requestContext?.trigger ?? 'state'} '
        'visibleFraction=$_visibleFraction',
      );
    }
  }

  Future<void> _handleClick(RahaVideoAdResponse ad) async {
    try {
      await ad.openClick();
      if (mounted) widget.onClick?.call(ad.info);
    } on Object catch (error) {
      if (mounted) widget.onError?.call(_asRahaError(error));
    }
  }
}

RahaAdsException _asRahaError(Object error) {
  if (error is RahaAdsException) return error;
  return RahaAdsException(
    RahaAdsErrorCode.network,
    'Raha video ad failed.',
    cause: error,
  );
}
