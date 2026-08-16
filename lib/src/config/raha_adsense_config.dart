import 'package:flutter/foundation.dart';

import '../core/click_opener.dart';
import 'raha_adsense_endpoints.dart';

enum RahaAdsenseEnvironment { production, development }

/// SDK configuration used to build the Raha network client.
final class RahaAdsenseConfig {
  RahaAdsenseConfig.production({
    required this.appId,
    this.clickOpener,
    RahaAdsenseEnvironment environment = RahaAdsenseEnvironment.production,
  })  : endpoints = switch (environment) {
          RahaAdsenseEnvironment.production => RahaAdsenseEndpoints.production,
          RahaAdsenseEnvironment.development =>
            RahaAdsenseEndpoints.development,
        },
        enableDebugLogs = kDebugMode,
        requestTimeout = const Duration(seconds: 9),
        inventoryTtl = const Duration(minutes: 5);

  @visibleForTesting
  const RahaAdsenseConfig.forTesting({
    required this.appId,
    required this.endpoints,
    this.clickOpener,
    this.enableDebugLogs = false,
    this.requestTimeout = const Duration(seconds: 9),
    this.inventoryTtl = const Duration(minutes: 5),
  });

  final String appId;
  final RahaClickOpener? clickOpener;
  final RahaAdsenseEndpoints endpoints;
  final bool enableDebugLogs;
  final Duration requestTimeout;
  final Duration inventoryTtl;
}
