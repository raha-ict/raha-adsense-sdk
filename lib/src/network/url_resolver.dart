import '../config/raha_adsense_endpoints.dart';
import '../errors/raha_adsense_exception.dart';

/// Resolves ad asset and tracking URLs returned in ad responses.
///
/// Asset URLs may be relative paths that must be joined with the configured
/// CDN origin, while tracking URLs may be relative to the API origin.
final class RahaUrlResolver {
  const RahaUrlResolver(this.endpoints);

  final RahaAdsenseEndpoints endpoints;

  Uri resolveAsset(String value) {
    final uri = _parse(value, 'asset URL');
    if (uri.hasScheme) {
      _requireSafeAbsolute(uri, 'asset URL');
      if (!_sameOrigin(uri, endpoints.cdnBaseUrl)) {
        throw const RahaAdsException(
          RahaAdsErrorCode.unsupportedCreative,
          'Creative asset URL is outside the Raha CDN origin.',
        );
      }
      return uri;
    }
    return _joinCdnPath(uri.path);
  }

  Uri resolveTracking(String value) {
    final uri = _parse(value, 'tracking URL');
    final resolved = uri.hasScheme ? uri : endpoints.apiOrigin.resolveUri(uri);
    _requireSafeAbsolute(resolved, 'tracking URL');
    if (!_sameOrigin(resolved, endpoints.apiOrigin)) {
      throw const RahaAdsException(
        RahaAdsErrorCode.malformedResponse,
        'Tracking URL is outside the Raha API origin.',
      );
    }
    return resolved;
  }

  Uri? resolveOptionalAsset(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return resolveAsset(value);
  }

  Uri _joinCdnPath(String path) {
    final baseSegments = endpoints.cdnBaseUrl.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final inputSegments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    var effectiveInput = inputSegments;
    while (baseSegments.isNotEmpty &&
        effectiveInput.isNotEmpty &&
        effectiveInput.first == baseSegments.last) {
      effectiveInput = effectiveInput.skip(1).toList(growable: false);
    }

    return endpoints.cdnBaseUrl.replace(
      pathSegments: <String>[...baseSegments, ...effectiveInput],
      query: null,
      fragment: null,
    );
  }

  Uri _parse(String value, String label) {
    if (value.startsWith('//')) {
      throw RahaAdsException(
        RahaAdsErrorCode.malformedResponse,
        'Protocol-relative $label values are not supported.',
      );
    }
    try {
      return Uri.parse(value.trim());
    } on FormatException catch (error) {
      throw RahaAdsException(
        RahaAdsErrorCode.malformedResponse,
        'Malformed $label in ad response.',
        cause: error,
      );
    }
  }

  void _requireSafeAbsolute(Uri uri, String label) {
    final scheme = uri.scheme.toLowerCase();
    final validScheme =
        scheme == 'https' || (endpoints.allowInsecureHttp && scheme == 'http');
    if (!uri.isAbsolute ||
        !validScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw RahaAdsException(
        RahaAdsErrorCode.malformedResponse,
        'Invalid $label in ad response.',
      );
    }
  }

  bool _sameOrigin(Uri left, Uri right) {
    final leftPort = left.hasPort ? left.port : _defaultPort(left.scheme);
    final rightPort = right.hasPort ? right.port : _defaultPort(right.scheme);
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        leftPort == rightPort;
  }

  int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;
}
