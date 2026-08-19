enum RahaInventoryPlacementFormat {
  banner,
  video,
  native,
  interstitial,
  unknown;

  static RahaInventoryPlacementFormat fromJson(Object? value) {
    return switch (value) {
      'banner' => banner,
      'video' => video,
      'native' => native,
      'interstitial' => interstitial,
      _ => unknown,
    };
  }
}

/// Public ad formats supported by the Raha SDK.
enum RahaAdFormat { banner, video, interstitial, native }

enum RahaAdDecisionFormat {
  banner,
  video,
  interstitial,
  native;

  static RahaAdDecisionFormat fromJson(Object? value) {
    return switch (value) {
      'banner' => banner,
      'video' => video,
      'interstitial' => interstitial,
      'native' => native,
      _ => throw FormatException('Unsupported ad decision format: $value.'),
    };
  }

  RahaAdFormat get publicFormat {
    return switch (this) {
      RahaAdDecisionFormat.banner => RahaAdFormat.banner,
      RahaAdDecisionFormat.video => RahaAdFormat.video,
      RahaAdDecisionFormat.interstitial => RahaAdFormat.interstitial,
      RahaAdDecisionFormat.native => RahaAdFormat.native,
    };
  }
}

/// Standard banner sizes that can be requested from the Raha SDK.
enum RahaBannerSize {
  leaderboard728x90(width: 728, height: 90),
  mediumRectangle300x250(width: 300, height: 250),
  mobile320x50(width: 320, height: 50),
  wideSkyscraper160x600(width: 160, height: 600);

  const RahaBannerSize({required this.width, required this.height});

  final int width;
  final int height;

  String get wireValue => '${width}x$height';
}

/// Inventory payload returned by the Raha inventory endpoint.
///
/// Includes the list of publisher apps and their supported placements.
final class RahaInventoryResponse {
  const RahaInventoryResponse({this.apps = const <RahaPublisherApp>[]});

  factory RahaInventoryResponse.fromJson(Map<String, Object?> json) {
    return RahaInventoryResponse(
      apps: _list(json['apps'])
          .map((item) => RahaPublisherApp.fromJson(_object(item)))
          .toList(growable: false),
    );
  }

  final List<RahaPublisherApp> apps;
}

/// Describes a publisher application in the Raha inventory.
final class RahaPublisherApp {
  const RahaPublisherApp({
    required this.id,
    required this.name,
    required this.type,
    this.domain,
    this.landingPageUrl,
    this.placements = const <RahaPlacement>[],
  });

  factory RahaPublisherApp.fromJson(Map<String, Object?> json) {
    return RahaPublisherApp(
      id: _nonEmptyString(json['id'], 'id'),
      name: _nonEmptyString(json['name'], 'name'),
      type: _nonEmptyString(json['type'], 'type'),
      domain: json['domain'] as String?,
      landingPageUrl: json['landingPageUrl'] as String?,
      placements: _list(json['placements'])
          .map((item) => RahaPlacement.fromJson(_object(item)))
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final String type;
  final String? domain;
  final String? landingPageUrl;
  final List<RahaPlacement> placements;
}

/// Placement metadata used to match ad requests to inventory.
final class RahaPlacement {
  const RahaPlacement({
    required this.id,
    required this.name,
    required this.format,
    this.size,
    this.floorPrice,
    required this.currency,
  });

  factory RahaPlacement.fromJson(Map<String, Object?> json) {
    return RahaPlacement(
      id: _nonEmptyString(json['id'], 'id'),
      name: _nonEmptyString(json['name'], 'name'),
      format: RahaInventoryPlacementFormat.fromJson(json['format']),
      size: json['size'] as String?,
      floorPrice: _doubleOrNull(json['floorPrice']),
      currency: _nonEmptyString(json['currency'], 'currency'),
    );
  }

  final String id;
  final String name;
  final RahaInventoryPlacementFormat format;
  final String? size;
  final double? floorPrice;
  final String currency;
}

/// Internal asset representation for ad decision payloads.
sealed class RahaAdAssetDto {
  const RahaAdAssetDto();
}

/// Image asset used for banner and interstitial ad decisions.
final class RahaImageAdAssetDto extends RahaAdAssetDto {
  const RahaImageAdAssetDto({
    required this.url,
    required this.width,
    required this.height,
  });

  final String url;
  final int width;
  final int height;
}

/// Video asset used for video ad decisions.
final class RahaVideoAdAssetDto extends RahaAdAssetDto {
  const RahaVideoAdAssetDto({
    required this.url,
    required this.posterUrl,
    required this.duration,
  });

  final String url;
  final String posterUrl;
  final int duration;
}

/// Native creative asset used for native ad decisions.
final class RahaNativeAdAssetDto extends RahaAdAssetDto {
  const RahaNativeAdAssetDto({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.iconUrl,
    required this.cta,
  });

  final String title;
  final String description;
  final String imageUrl;
  final String iconUrl;
  final String cta;
}

/// The server-side decision payload for a single ad request.
final class RahaAdDecisionDto {
  const RahaAdDecisionDto({
    required this.id,
    required this.format,
    required this.impressionUrl,
    required this.clickTrackingUrl,
    required this.asset,
  });

  factory RahaAdDecisionDto.fromJson(Map<String, Object?> json) {
    final format = RahaAdDecisionFormat.fromJson(json['format']);
    final assetJson = _object(json['asset'], 'asset');
    final asset = switch (format) {
      RahaAdDecisionFormat.banner ||
      RahaAdDecisionFormat.interstitial =>
        RahaImageAdAssetDto(
          url: _nonEmptyString(assetJson['url'], 'asset.url'),
          width: _positiveInt(assetJson['width'], 'asset.width'),
          height: _positiveInt(assetJson['height'], 'asset.height'),
        ),
      RahaAdDecisionFormat.video => RahaVideoAdAssetDto(
          url: _nonEmptyString(assetJson['url'], 'asset.url'),
          posterUrl: _requiredString(assetJson['posterUrl'], 'asset.posterUrl'),
          duration: _positiveInt(assetJson['duration'], 'asset.duration'),
        ),
      RahaAdDecisionFormat.native => RahaNativeAdAssetDto(
          title: _nonEmptyString(assetJson['title'], 'asset.title'),
          description:
              _requiredString(assetJson['description'], 'asset.description'),
          imageUrl: _requiredString(assetJson['imageUrl'], 'asset.imageUrl'),
          iconUrl: _requiredString(assetJson['iconUrl'], 'asset.iconUrl'),
          cta: _requiredString(assetJson['cta'], 'asset.cta'),
        ),
    };

    return RahaAdDecisionDto(
      id: _nonEmptyString(json['id'], 'id'),
      format: format,
      impressionUrl: _nonEmptyString(json['impressionUrl'], 'impressionUrl'),
      clickTrackingUrl:
          _optionalNonEmptyString(json['clickTrackingUrl'], 'clickTrackingUrl'),
      asset: asset,
    );
  }

  final String id;
  final RahaAdDecisionFormat format;
  final String impressionUrl;
  final String? clickTrackingUrl;
  final RahaAdAssetDto asset;
}

/// Normalized tracking result returned from impression or click endpoints.
final class RahaTrackingResult {
  const RahaTrackingResult({
    required this.eventId,
    required this.type,
    required this.isValid,
    required this.duplicate,
    this.invalidReason,
    this.redirectUrl,
  });

  factory RahaTrackingResult.normalized({
    required Map<String, Object?> json,
    required String eventId,
    required String type,
  }) {
    return RahaTrackingResult(
      eventId: _optionalNonEmptyString(json['eventId'], 'eventId') ?? eventId,
      type: _optionalNonEmptyString(json['type'], 'type') ?? type,
      isValid: _optionalBool(json['isValid'], 'isValid') ?? true,
      duplicate: _optionalBool(json['duplicate'], 'duplicate') ?? false,
      invalidReason: json['invalidReason'] as String?,
      redirectUrl: _optionalNonEmptyString(json['redirectUrl'], 'redirectUrl'),
    );
  }

  final String eventId;
  final String type;
  final bool isValid;
  final bool duplicate;
  final String? invalidReason;
  final String? redirectUrl;
}

final class RahaAdInfo {
  const RahaAdInfo({
    required this.adId,
    required this.format,
    required this.placementId,
  });

  final String adId;
  final RahaAdFormat format;
  final String placementId;
}

final class RahaResolvedAd {
  const RahaResolvedAd({
    required this.info,
    required this.decision,
    required this.impressionUri,
    required this.clickTrackingUri,
    required this.impressionEventId,
    required this.isClickable,
  });

  final RahaAdInfo info;
  final RahaAdDecisionDto decision;
  final Uri impressionUri;
  final Uri? clickTrackingUri;
  final String impressionEventId;
  final bool isClickable;
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

Map<String, Object?> _object(Object? value, [String label = 'value']) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Expected $label to be a JSON object.');
}

String _requiredString(Object? value, String name) {
  if (value is String) return value;
  throw FormatException('Expected string for $name.');
}

String? _optionalNonEmptyString(Object? value, String name) {
  if (value == null) return null;
  final text = _requiredString(value, name).trim();
  return text.isEmpty ? null : text;
}

String _nonEmptyString(Object? value, String name) {
  final text = _requiredString(value, name).trim();
  if (text.isNotEmpty) return text;
  throw FormatException('Expected non-empty string for $name.');
}

int _positiveInt(Object? value, String name) {
  final result = _int(value, name);
  if (result > 0) return result;
  throw FormatException('Expected positive integer for $name.');
}

int _int(Object? value, String name) {
  if (value is int) return value;
  if (value is num && value.isFinite && value % 1 == 0) return value.toInt();
  throw FormatException('Expected integer for $name.');
}

double? _doubleOrNull(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}

bool _bool(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('Expected boolean for $name.');
}

bool? _optionalBool(Object? value, String name) {
  if (value == null) return null;
  return _bool(value, name);
}
