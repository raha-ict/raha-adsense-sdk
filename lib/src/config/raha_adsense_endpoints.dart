import 'package:flutter/foundation.dart';

final class RahaAdsenseEndpoints {
  const RahaAdsenseEndpoints._({
    required this.apiOrigin,
    required this.cdnBaseUrl,
  });

  static final RahaAdsenseEndpoints production = RahaAdsenseEndpoints._validated(
    apiOrigin: Uri.parse('https://api.adsense.raha.af'),
    cdnBaseUrl: Uri.parse('https://cdn.raha.af/adsense/'),
    allowInsecureHttp: false,
  );

  static final RahaAdsenseEndpoints development =
      RahaAdsenseEndpoints._validated(
    apiOrigin: Uri.parse('https://dev.api.adsense.raha.af'),
    cdnBaseUrl: Uri.parse('https://dev.cdn.raha.af/adsense/'),
    allowInsecureHttp: false,
  );

  final Uri apiOrigin;
  final Uri cdnBaseUrl;

  factory RahaAdsenseEndpoints._validated({
    required Uri apiOrigin,
    required Uri cdnBaseUrl,
    required bool allowInsecureHttp,
  }) {
    _validateBaseUri(
      apiOrigin,
      label: 'API origin',
      allowPath: false,
      allowInsecureHttp: allowInsecureHttp,
    );
    _validateBaseUri(
      cdnBaseUrl,
      label: 'CDN base URL',
      allowPath: true,
      allowInsecureHttp: allowInsecureHttp,
    );
    return RahaAdsenseEndpoints._(
      apiOrigin: apiOrigin,
      cdnBaseUrl: cdnBaseUrl,
    );
  }

  @visibleForTesting
  factory RahaAdsenseEndpoints.forTesting({
    required Uri apiOrigin,
    required Uri cdnBaseUrl,
    bool allowInsecureHttp = false,
  }) {
    return RahaAdsenseEndpoints._validated(
      apiOrigin: apiOrigin,
      cdnBaseUrl: cdnBaseUrl,
      allowInsecureHttp: allowInsecureHttp,
    );
  }

  static void _validateBaseUri(
    Uri value, {
    required String label,
    required bool allowPath,
    required bool allowInsecureHttp,
  }) {
    final scheme = value.scheme.toLowerCase();
    final validScheme =
        scheme == 'https' || (allowInsecureHttp && scheme == 'http');
    final hasDisallowedPath =
        !allowPath && value.path.isNotEmpty && value.path != '/';

    if (!value.isAbsolute ||
        value.host.isEmpty ||
        !validScheme ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        hasDisallowedPath) {
      throw StateError('Invalid internal Raha $label configuration.');
    }
  }
}
