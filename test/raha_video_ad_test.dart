import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';

void main() {
  test('public API exports v2 formats', () {
    expect(RahaAdFormat.values, [
      RahaAdFormat.banner,
      RahaAdFormat.video,
      RahaAdFormat.interstitial,
      RahaAdFormat.native,
    ]);
  });

  test('public banner sizes expose expected wire values', () {
    expect(RahaBannerSize.leaderboard728x90.wireValue, '728x90');
    expect(RahaBannerSize.mediumRectangle300x250.wireValue, '300x250');
    expect(RahaBannerSize.mobile320x50.wireValue, '320x50');
    expect(RahaBannerSize.wideSkyscraper160x600.wireValue, '160x600');
  });

  test('public API exports placement id request method', () {
    expect(RahaAdsense.requestByPlacementId, isA<Function>());
  });
}
