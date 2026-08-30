import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:raha_adsense/src/models/models.dart';
import 'package:raha_adsense/src/widgets/raha_banner_ad.dart';

void main() {
  tearDown(RahaAdsense.resetForTesting);

  test('canRenderExactBanner accepts loose exact-compatible constraints', () {
    expect(
      canRenderExactBanner(
        const BoxConstraints(maxWidth: 400, maxHeight: 100),
        RahaBannerSize.mobile320x50,
      ),
      isTrue,
    );
  });

  test('canRenderExactBanner rejects tight stretched constraints', () {
    expect(
      canRenderExactBanner(
        const BoxConstraints.tightFor(width: 400, height: 50),
        RahaBannerSize.mobile320x50,
      ),
      isFalse,
    );
  });

  testWidgets('reloads when difference time changes', (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 50,
          child: RahaBannerAd(
            size: RahaBannerSize.mobile320x50,
            differenceTime: Duration.zero,
            onError: (_) => errors++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 50,
          child: RahaBannerAd(
            size: RahaBannerSize.mobile320x50,
            differenceTime: const Duration(hours: 1),
            onError: (_) => errors++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(errors, 2);
  });

  testWidgets('reloads when language changes', (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 50,
          child: RahaBannerAd(
            size: RahaBannerSize.mobile320x50,
            language: 'fa',
            onError: (_) => errors++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 50,
          child: RahaBannerAd(
            size: RahaBannerSize.mobile320x50,
            language: 'ps',
            onError: (_) => errors++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(errors, 2);
  });
}
