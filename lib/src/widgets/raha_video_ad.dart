import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/raha_adsense.dart';
import '../core/viewability_policy.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';

/// A widget that displays a Raha video ad.
///
/// The ad loads automatically and plays once it is ready. It tracks viewability
/// before reporting an impression and supports tap-to-click behavior.
class RahaVideoAd extends StatefulWidget {
  const RahaVideoAd({
    super.key,
    this.signals = const <String, Object?>{},
    this.differenceTime,
    this.onLoaded,
    this.onImpression,
    this.onCompleted,
    this.onClick,
    this.onError,
  });

  /// Optional contextual signals sent with the video ad request.
  final Map<String, Object?> signals;

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
  RahaVideoAdResponse? _ad;
  VideoPlayerController? _controller;
  bool _noFill = false;
  bool _foreground = true;
  bool _impressionRecorded = false;
  bool _completed = false;
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
  void didUpdateWidget(covariant RahaVideoAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signals != widget.signals ||
        oldWidget.differenceTime != widget.differenceTime) {
      _reset();
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _controller?.pause();
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
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _controller = null;
    _ad = null;
    _noFill = false;
    _impressionRecorded = false;
    _completed = false;
  }

  Future<void> _load() async {
    try {
      final ad = await RahaAdsense.runtime.requestVideoAd(
        signals: widget.signals,
        differenceTime: widget.differenceTime,
        cancelToken: _cancelToken,
      );
      if (!mounted || _cancelToken.isCancelled) return;
      if (ad == null) {
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
      setState(() {
        _ad = ad;
        _controller = controller;
      });
      widget.onLoaded?.call(ad.info);
      await controller.play();
      _evaluateViewability();
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
        if (controller == null || ad == null) {
          return const SizedBox.expand(
            child: ColoredBox(color: Colors.black),
          );
        }
        return VisibilityDetector(
          key: ValueKey('raha-video-${ad.info.adId}-${ad.info.placementId}'),
          onVisibilityChanged: (info) {
            _visibleFraction = info.visibleFraction;
            _evaluateViewability();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleClick(ad),
            child: _buildVideoSurface(controller),
          ),
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
    if (_impressionRecorded) return;

    // Record an impression only when the video is playing, visible enough, and
    // the app is in the foreground.
    final controller = _controller;
    final value = controller?.value;
    final qualified = _ad != null &&
        value != null &&
        value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        _foreground &&
        _visibleFraction >= videoVisibleFraction;
    if (!qualified) {
      _impressionTimer?.cancel();
      _impressionTimer = null;
      return;
    }
    _impressionTimer ??= Timer(videoVisibleDuration, _recordImpression);
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
