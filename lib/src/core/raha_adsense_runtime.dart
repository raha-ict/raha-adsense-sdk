import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../config/raha_adsense_config.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/ad_response.dart';
import '../models/models.dart';
import '../network/raha_adsense_api.dart';
import '../network/url_resolver.dart';
import 'placement_registry.dart';

/// Internal runtime for Raha Adsense.
///
/// This class is responsible for loading inventory, resolving placements,
/// requesting ad decisions, and tracking impressions and clicks.
final class RahaAdsenseRuntime {
  RahaAdsenseRuntime({
    required this.config,
    RahaAdsenseApi? api,
    RahaUrlResolver? resolver,
  })  : _api = api ?? RahaAdsenseApi(dio: buildRahaDio(config)),
        _resolver = resolver ?? RahaUrlResolver(config.endpoints);

  final RahaAdsenseConfig config;
  final RahaAdsenseApi _api;
  final RahaUrlResolver _resolver;
  final Uuid _uuid = const Uuid();

  PlacementRegistry? _registry;
  DateTime? _inventoryLoadedAt;
  Future<PlacementRegistry>? _inventoryRefresh;
  bool _disposed = false;

  /// Validate the configured app ID and load the placement registry.
  ///
  /// This method is called once during initial SDK setup.
  Future<void> initialize({CancelToken? cancelToken}) async {
    _validateAppId(config.appId);
    await _getRegistry(cancelToken: cancelToken, forceRefresh: true);
  }

  /// Request a banner ad decision and convert it into a response object.
  Future<RahaBannerAdResponse?> requestBannerAd({
    required RahaBannerSize size,
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) async {
    final registry = await _getRegistry(cancelToken: cancelToken);
    final placement = registry.resolveBanner(size);
    final decision = await _requestDecision(
      placement: placement,
      signals: signals,
      cancelToken: cancelToken,
    );
    final ad = _buildAdResponse(placement, decision);
    if (ad == null) return null;
    if (ad is! RahaBannerAdResponse) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected a banner ad response.',
      );
    }
    return ad;
  }

  Future<RahaVideoAdResponse?> requestVideoAd({
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) async {
    final registry = await _getRegistry(cancelToken: cancelToken);
    final placement = registry.resolveVideo();
    final decision = await _requestDecision(
      placement: placement,
      signals: signals,
      cancelToken: cancelToken,
    );
    final ad = _buildAdResponse(placement, decision);
    if (ad == null) return null;
    if (ad is! RahaVideoAdResponse) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected a video ad response.',
      );
    }
    return ad;
  }

  Future<RahaInterstitialAdResponse?> requestInterstitialAd({
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) async {
    final registry = await _getRegistry(cancelToken: cancelToken);
    final placement = registry.resolveInterstitial();
    final decision = await _requestDecision(
      placement: placement,
      signals: signals,
      cancelToken: cancelToken,
    );
    final ad = _buildAdResponse(placement, decision);
    if (ad == null) return null;
    if (ad is! RahaInterstitialAdResponse) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected an interstitial ad response.',
      );
    }
    return ad;
  }

  Future<RahaNativeAdResponse?> requestNativeAd({
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) async {
    final registry = await _getRegistry(cancelToken: cancelToken);
    final placement = registry.resolveNative();
    final decision = await _requestDecision(
      placement: placement,
      signals: signals,
      cancelToken: cancelToken,
    );
    final ad = _buildAdResponse(placement, decision);
    if (ad == null) return null;
    if (ad is! RahaNativeAdResponse) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected a native ad response.',
      );
    }
    return ad;
  }

  Future<RahaAdResponse?> requestAdByPlacementId({
    required String placementId,
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) async {
    final registry = await _getRegistry(cancelToken: cancelToken);
    final placement = registry.resolveById(placementId);
    final decision = await _requestDecision(
      placement: placement,
      signals: signals,
      cancelToken: cancelToken,
    );
    return _buildAdResponse(placement, decision);
  }

  void dispose() {
    _disposed = true;
    _api.dispose();
  }

  Future<RahaAdDecisionDto?> _requestDecision({
    required RahaPlacement placement,
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) {
    return _api.requestAd(
      placementId: placement.id,
      signals: signals,
      cancelToken: cancelToken,
    );
  }

  /// Return the cached placement registry, refreshing it when needed.
  ///
  /// The registry is refreshed when there is no cached version, when a full
  /// refresh is requested, or when the cached inventory is older than the
  /// configured TTL.
  Future<PlacementRegistry> _getRegistry({
    CancelToken? cancelToken,
    bool forceRefresh = false,
  }) async {
    _ensureAlive();
    final registry = _registry;
    final loadedAt = _inventoryLoadedAt;
    final fresh = loadedAt != null &&
        DateTime.now().difference(loadedAt) < config.inventoryTtl;
    if (!forceRefresh && registry != null && fresh) return registry;

    return _inventoryRefresh ??= _refreshRegistry(cancelToken).whenComplete(
      () => _inventoryRefresh = null,
    );
  }

  /// Refresh the placement registry by fetching inventory from the backend.
  ///
  /// If the app ID cannot be found or is configured multiple times, this
  /// method throws a descriptive [RahaAdsException].
  Future<PlacementRegistry> _refreshRegistry(CancelToken? cancelToken) async {
    final inventory = await _api.fetchInventory(cancelToken: cancelToken);
    final matches = inventory.apps
        .where((app) => app.id.toLowerCase() == config.appId.toLowerCase())
        .toList(growable: false);
    if (matches.isEmpty) {
      throw RahaAdsException(
        RahaAdsErrorCode.inventory,
        'No approved Raha app inventory was found for app ${config.appId}.',
      );
    }
    if (matches.length > 1) {
      throw RahaAdsException(
        RahaAdsErrorCode.inventory,
        'Duplicate Raha app inventory was found for app ${config.appId}.',
      );
    }
    final registry = PlacementRegistry(app: matches.single);
    _registry = registry;
    _inventoryLoadedAt = DateTime.now();
    return registry;
  }

  RahaResolvedAd _resolveCommon(
    RahaPlacement placement,
    RahaAdDecisionDto decision,
  ) {
    final expected = _expectedDecisionFormat(placement.format);
    if (decision.format != expected) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Ad decision format does not match the resolved placement.',
      );
    }
    _validateClickUrl(decision.clickUrl);
    return RahaResolvedAd(
      info: RahaAdInfo(
        adId: decision.id,
        format: decision.format.publicFormat,
        placementId: placement.id,
      ),
      decision: decision,
      impressionUri: _resolver.resolveTracking(decision.impressionUrl),
      clickTrackingUri: _resolver.resolveTracking(decision.clickTrackingUrl),
      impressionEventId: _uuid.v4(),
      isClickable: decision.clickUrl != null,
    );
  }

  RahaAdResponse? _buildAdResponse(
    RahaPlacement placement,
    RahaAdDecisionDto? decision,
  ) {
    if (decision == null) return null;
    final resolved = _resolveCommon(placement, decision);
    return switch (placement.format) {
      RahaInventoryPlacementFormat.banner => _buildBannerAdResponse(
          placement,
          decision,
          resolved,
        ),
      RahaInventoryPlacementFormat.video => _buildVideoAdResponse(
          decision,
          resolved,
        ),
      RahaInventoryPlacementFormat.interstitial =>
        _buildInterstitialAdResponse(decision, resolved),
      RahaInventoryPlacementFormat.native => _buildNativeAdResponse(
          decision,
          resolved,
        ),
      RahaInventoryPlacementFormat.unknown => throw const RahaAdsException(
          RahaAdsErrorCode.invalidResponse,
          'Unsupported placement format.',
        ),
    };
  }

  RahaBannerAdResponse _buildBannerAdResponse(
    RahaPlacement placement,
    RahaAdDecisionDto decision,
    RahaResolvedAd resolved,
  ) {
    final asset = _requireImageAsset(decision, RahaAdDecisionFormat.banner);
    _validateBannerCreativeSize(placement, asset);
    return buildRahaBannerAdResponse(
      info: resolved.info,
      isClickable: resolved.isClickable,
      imageUrl: _resolver.resolveAsset(asset.url),
      width: asset.width,
      height: asset.height,
      recordImpression: () => _recordImpression(resolved),
      openClick: () => _openClick(resolved),
    );
  }

  RahaVideoAdResponse _buildVideoAdResponse(
    RahaAdDecisionDto decision,
    RahaResolvedAd resolved,
  ) {
    final asset = _requireVideoAsset(decision);
    return buildRahaVideoAdResponse(
      info: resolved.info,
      isClickable: resolved.isClickable,
      videoUrl: _resolver.resolveAsset(asset.url),
      posterUrl: _optionalAssetUrl(asset.posterUrl),
      duration: Duration(seconds: asset.duration),
      recordImpression: () => _recordImpression(resolved),
      openClick: () => _openClick(resolved),
    );
  }

  RahaInterstitialAdResponse _buildInterstitialAdResponse(
    RahaAdDecisionDto decision,
    RahaResolvedAd resolved,
  ) {
    final asset = _requireImageAsset(
      decision,
      RahaAdDecisionFormat.interstitial,
    );
    return buildRahaInterstitialAdResponse(
      info: resolved.info,
      isClickable: resolved.isClickable,
      imageUrl: _resolver.resolveAsset(asset.url),
      width: asset.width,
      height: asset.height,
      recordImpression: () => _recordImpression(resolved),
      openClick: () => _openClick(resolved),
    );
  }

  RahaNativeAdResponse _buildNativeAdResponse(
    RahaAdDecisionDto decision,
    RahaResolvedAd resolved,
  ) {
    final asset = _requireNativeAsset(decision);
    return buildRahaNativeAdResponse(
      info: resolved.info,
      isClickable: resolved.isClickable,
      title: asset.title.trim(),
      description: _optionalText(asset.description),
      imageUrl: _optionalAssetUrl(asset.imageUrl),
      iconUrl: _optionalAssetUrl(asset.iconUrl),
      cta: _optionalText(asset.cta),
      recordImpression: () => _recordImpression(resolved),
      openClick: () => _openClick(resolved),
    );
  }

  void _validateBannerCreativeSize(
    RahaPlacement placement,
    RahaImageAdAssetDto asset,
  ) {
    final size = placement.size?.trim().toLowerCase();
    if (size == null || size.isEmpty) return;
    RahaBannerSize? expected;
    for (final value in RahaBannerSize.values) {
      if (value.wireValue == size) {
        expected = value;
        break;
      }
    }
    if (expected == null) return;
    if (asset.width != expected.width || asset.height != expected.height) {
      throw const RahaAdsException(
        RahaAdsErrorCode.unsupportedCreative,
        'Banner creative dimensions do not match the requested size.',
      );
    }
  }

  /// Ensure the decision contains an image asset for the expected ad format.
  RahaImageAdAssetDto _requireImageAsset(
    RahaAdDecisionDto decision,
    RahaAdDecisionFormat format,
  ) {
    if (decision.format != format || decision.asset is! RahaImageAdAssetDto) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected an image ad asset.',
      );
    }
    return decision.asset as RahaImageAdAssetDto;
  }

  /// Ensure the decision contains a video asset.
  RahaVideoAdAssetDto _requireVideoAsset(RahaAdDecisionDto decision) {
    if (decision.format != RahaAdDecisionFormat.video ||
        decision.asset is! RahaVideoAdAssetDto) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected a video ad asset.',
      );
    }
    return decision.asset as RahaVideoAdAssetDto;
  }

  /// Ensure the decision contains a native ad asset.
  RahaNativeAdAssetDto _requireNativeAsset(RahaAdDecisionDto decision) {
    if (decision.format != RahaAdDecisionFormat.native ||
        decision.asset is! RahaNativeAdAssetDto) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Expected a native ad asset.',
      );
    }
    return decision.asset as RahaNativeAdAssetDto;
  }

  /// Resolve an optional asset URL, returning `null` when the value is empty.
  Uri? _optionalAssetUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    return _resolver.resolveAsset(normalized);
  }

  /// Trim optional text values and return `null` when the result is empty.
  String? _optionalText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  /// Validate the click URL included in the ad decision.
  ///
  /// A valid click URL must be absolute HTTPS with no user info.
  void _validateClickUrl(String? value) {
    if (value == null) return;
    final Uri uri;
    try {
      uri = Uri.parse(value);
    } on FormatException catch (error) {
      throw RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Malformed click URL in ad response.',
        cause: error,
      );
    }
    if (!uri.isAbsolute ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Invalid click URL in ad response.',
      );
    }
  }

  RahaAdDecisionFormat _expectedDecisionFormat(
    RahaInventoryPlacementFormat format,
  ) {
    return switch (format) {
      RahaInventoryPlacementFormat.banner => RahaAdDecisionFormat.banner,
      RahaInventoryPlacementFormat.video => RahaAdDecisionFormat.video,
      RahaInventoryPlacementFormat.interstitial =>
        RahaAdDecisionFormat.interstitial,
      RahaInventoryPlacementFormat.native => RahaAdDecisionFormat.native,
      RahaInventoryPlacementFormat.unknown => throw const RahaAdsException(
          RahaAdsErrorCode.invalidResponse,
          'Unsupported placement format.',
        ),
    };
  }

  Future<void> _recordImpression(RahaResolvedAd ad) async {
    final result = await _api.trackImpression(
      ad.impressionUri,
      eventId: ad.impressionEventId,
    );
    if (!result.isValid) {
      throw RahaAdsException(
        RahaAdsErrorCode.trackingRejected,
        'Raha rejected the impression event.',
      );
    }
  }

  Future<void> _openClick(RahaResolvedAd ad) async {
    final result = await _api.trackClick(
      ad.clickTrackingUri,
      eventId: _uuid.v4(),
    );
    if (!result.isValid) {
      throw RahaAdsException(
        RahaAdsErrorCode.trackingRejected,
        'Raha rejected the click event.',
      );
    }
    final redirect = result.redirectUrl;
    final uri = _parseTrackedRedirect(redirect);
    final opener = config.clickOpener ?? _launchWithUrlLauncher;
    try {
      await Future<void>.sync(() => opener(uri, ad.info));
    } on RahaAdsException {
      rethrow;
    } on Object catch (error) {
      throw RahaAdsException(
        RahaAdsErrorCode.clickLaunch,
        'Custom Raha click opener failed.',
        cause: error,
      );
    }
  }

  Uri _parseTrackedRedirect(String? value) {
    if (value == null || value.trim().isEmpty) {
      throw const RahaAdsException(
        RahaAdsErrorCode.clickLaunch,
        'Raha click tracking did not return a destination URL.',
      );
    }
    final Uri uri;
    try {
      uri = Uri.parse(value.trim());
    } on FormatException catch (error) {
      throw RahaAdsException(
        RahaAdsErrorCode.clickLaunch,
        'Malformed Raha click destination URL.',
        cause: error,
      );
    }
    if (!uri.isAbsolute ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const RahaAdsException(
        RahaAdsErrorCode.clickLaunch,
        'Invalid Raha click destination URL.',
      );
    }
    return uri;
  }

  Future<void> _launchWithUrlLauncher(Uri destinationUrl, RahaAdInfo _) async {
    final launched = await launchUrl(
      destinationUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const RahaAdsException(
        RahaAdsErrorCode.clickLaunch,
        'Unable to open Raha click destination.',
      );
    }
  }

  void _validateAppId(String value) {
    final pattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (!pattern.hasMatch(value)) {
      throw const RahaAdsException(
        RahaAdsErrorCode.invalidConfiguration,
        'Raha appId must be a valid UUID.',
      );
    }
  }

  void _ensureAlive() {
    if (_disposed) {
      throw const RahaAdsException(
        RahaAdsErrorCode.notInitialized,
        'This RahaAdsense runtime has been disposed.',
      );
    }
  }
}
