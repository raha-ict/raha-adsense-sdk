import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(RahaAdsense.resetForTesting);

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

  testWidgets('video coalesces difference-time change until refresh interval',
      (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      RahaVideoAd(
        differenceTime: Duration.zero,
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      RahaVideoAd(
        differenceTime: const Duration(hours: 1),
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    expect(errors, 1);
  });

  testWidgets('video coalesces language change until refresh interval',
      (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      RahaVideoAd(
        language: 'fa',
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      RahaVideoAd(
        language: 'ps',
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    expect(errors, 1);
  });
}
