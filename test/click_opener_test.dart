import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:raha_adsense/src/config/raha_adsense_config.dart';
import 'package:raha_adsense/src/config/raha_adsense_endpoints.dart';
import 'package:raha_adsense/src/models/models.dart';

void main() {
  test('production config uses production endpoints by default', () {
    final config = RahaAdsenseConfig.production(
      appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
    );

    expect(config.endpoints.apiOrigin, Uri.parse('https://api.adsense.raha.af'));
    expect(
      config.endpoints.cdnBaseUrl,
      Uri.parse('https://cdn.raha.af/adsense/'),
    );
  });

  test('production config accepts explicit production environment', () {
    final config = RahaAdsenseConfig.production(
      appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
      environment: RahaAdsenseEnvironment.production,
    );

    expect(config.endpoints.apiOrigin, Uri.parse('https://api.adsense.raha.af'));
    expect(
      config.endpoints.cdnBaseUrl,
      Uri.parse('https://cdn.raha.af/adsense/'),
    );
  });

  test('production config accepts development environment', () {
    final config = RahaAdsenseConfig.production(
      appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
      environment: RahaAdsenseEnvironment.development,
    );

    expect(
      config.endpoints.apiOrigin,
      Uri.parse('https://dev.api.adsense.raha.af'),
    );
    expect(
      config.endpoints.cdnBaseUrl,
      Uri.parse('https://dev.cdn.raha.af/adsense/'),
    );
  });

  test('stores custom click opener in config', () {
    Future<void> opener(Uri destinationUrl, RahaAdInfo info) async {
      expect(destinationUrl, isA<Uri>());
      expect(info, isA<RahaAdInfo>());
    }

    final config = RahaAdsenseConfig.forTesting(
      appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
      endpoints: RahaAdsenseEndpoints.forTesting(
        apiOrigin: Uri.parse('http://localhost:3000'),
        cdnBaseUrl: Uri.parse('http://localhost:3000/cdn/'),
        allowInsecureHttp: true,
      ),
      clickOpener: opener,
    );

    expect(config.clickOpener, same(opener));
  });

  test('public click opener type receives destination and ad info', () async {
    Uri? capturedUrl;
    RahaAdInfo? capturedInfo;
    final RahaClickOpener opener = (destinationUrl, info) {
      capturedUrl = destinationUrl;
      capturedInfo = info;
    };

    const info = RahaAdInfo(
      adId: 'ad_123',
      format: RahaAdFormat.banner,
      placementId: 'placement_123',
    );
    await opener(Uri.parse('https://advertiser.example.com'), info);

    expect(capturedUrl, Uri.parse('https://advertiser.example.com'));
    expect(capturedInfo, same(info));
  });
}
