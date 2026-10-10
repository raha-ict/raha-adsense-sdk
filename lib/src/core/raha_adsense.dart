import 'package:flutter/foundation.dart';

import '../config/raha_adsense_config.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';
import 'click_opener.dart';
import 'raha_adsense_runtime.dart';

/// Entry point for the Raha Adsense Flutter SDK.
///
/// This class provides the public setup and ad request APIs for the package.
abstract final class RahaAdsense {
  static RahaAdsenseRuntime? _runtime;

  /// Returns `true` after the SDK has been initialized with [setup].
  static bool get isReady => _runtime != null;

  /// Initialize the Raha SDK with the provided [appId].
  /// The publisher supplies a stable [visitorId] for backend frequency capping.
  ///
  /// The [appId] is the Raha application identifier used to fetch inventory
  /// and placement metadata. Optionally pass [clickOpener] to handle ad click
  /// navigation in a custom shell.
  static Future<void> setup({
    required String appId,
    required String visitorId,
    required String deviceType,
    required String os,
    RahaClickOpener? clickOpener,
    bool? enableDebugLogs,
    RahaAdsenseEnvironment environment = RahaAdsenseEnvironment.production,
  }) async {
    if (_runtime != null) {
      throw StateError('RahaAdsense.setup() may be called only once.');
    }
    if (visitorId.trim().isEmpty) {
      throw ArgumentError.value(visitorId, 'visitorId', 'Must not be empty.');
    }
    final runtime = RahaAdsenseRuntime(
      config: RahaAdsenseConfig.production(
        appId: appId,
        deviceType: deviceType,
        os: os,
        clickOpener: clickOpener,
        enableDebugLogs: enableDebugLogs,
        environment: environment,
      ),
      visitorId: visitorId,
    );
    try {
      await runtime.initialize();
      _runtime = runtime;
    } catch (_) {
      runtime.dispose();
      rethrow;
    }
  }

  /// Request a single ad response for the selected ad [type].
  ///
  /// For banner requests, provide [bannerSize]. For other ad formats,
  /// [bannerSize] must be omitted. Pass [differenceTime] to adjust generated
  /// day and time request signals for this request.
  static Future<RahaAdResponse?> adRequest({
    required RahaAdFormat type,
    RahaBannerSize? bannerSize,
    Map<String, Object?> signals = const <String, Object?>{},
    String? language,
    String? dayOfWeek,
    String? timeOfDay,
    Duration? differenceTime,
  }) {
    final value = runtime;
    return switch (type) {
      RahaAdFormat.banner => bannerSize == null
          ? throw const RahaAdsException.invalidRequest(
              'bannerSize is required for a banner ad request.',
            )
          : value.requestBannerAd(
              size: bannerSize,
              signals: signals,
              language: language,
              dayOfWeek: dayOfWeek,
              timeOfDay: timeOfDay,
              differenceTime: differenceTime,
            ),
      RahaAdFormat.video => bannerSize != null
          ? throw const RahaAdsException.invalidRequest(
              'bannerSize must be omitted for a video ad request.',
            )
          : value.requestVideoAd(
              signals: signals,
              language: language,
              dayOfWeek: dayOfWeek,
              timeOfDay: timeOfDay,
              differenceTime: differenceTime,
            ),
      RahaAdFormat.interstitial => bannerSize != null
          ? throw const RahaAdsException.invalidRequest(
              'bannerSize must be omitted for an interstitial ad request.',
            )
          : value.requestInterstitialAd(
              signals: signals,
              language: language,
              dayOfWeek: dayOfWeek,
              timeOfDay: timeOfDay,
              differenceTime: differenceTime,
            ),
      RahaAdFormat.native => bannerSize != null
          ? throw const RahaAdsException.invalidRequest(
              'bannerSize must be omitted for a native ad request.',
            )
          : value.requestNativeAd(
              signals: signals,
              language: language,
              dayOfWeek: dayOfWeek,
              timeOfDay: timeOfDay,
              differenceTime: differenceTime,
            ),
    };
  }

  /// Request a single ad response for an exact Raha [placementId].
  ///
  /// The placement must belong to the app inventory loaded during [setup].
  /// Pass [differenceTime] to adjust generated day and time request signals
  /// for this request.
  static Future<RahaAdResponse?> requestByPlacementId({
    required String placementId,
    Map<String, Object?> signals = const <String, Object?>{},
    String? language,
    String? dayOfWeek,
    String? timeOfDay,
    Duration? differenceTime,
  }) {
    return runtime.requestAdByPlacementId(
      placementId: placementId,
      signals: signals,
      language: language,
      dayOfWeek: dayOfWeek,
      timeOfDay: timeOfDay,
      differenceTime: differenceTime,
    );
  }

  /// Returns the active runtime instance.
  ///
  /// Throws [RahaAdsException] if the package has not yet been initialized.
  static RahaAdsenseRuntime get runtime {
    final value = _runtime;
    if (value == null) {
      throw const RahaAdsException(
        RahaAdsErrorCode.notInitialized,
        'Call and await RahaAdsense.setup() before requesting or building ads.',
      );
    }
    return value;
  }

  @visibleForTesting
  static void setRuntimeForTesting(RahaAdsenseRuntime runtime) {
    _runtime?.dispose();
    _runtime = runtime;
  }

  @visibleForTesting
  static void resetForTesting() {
    // Dispose and clear the cached runtime so tests can start from a clean
    // state between runs.
    _runtime?.dispose();
    _runtime = null;
  }
}
