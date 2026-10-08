import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:raha_adsense/src/widgets/banner_creative_types.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
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

  test('detects svg banner creatives by URL path only', () {
    expect(isSvgBannerCreative(Uri.parse('https://cdn.example.com/ad.svg')),
        isTrue);
    expect(
      isSvgBannerCreative(
        Uri.parse('https://cdn.example.com/ad.SVG?cacheBust=1'),
      ),
      isTrue,
    );
    expect(isSvgBannerCreative(Uri.parse('https://cdn.example.com/ad.gif')),
        isFalse);
    expect(isSvgBannerCreative(Uri.parse('https://cdn.example.com/ad.png')),
        isFalse);
    expect(
      isSvgBannerCreative(Uri.parse('https://cdn.example.com/ad')),
      isFalse,
    );
  });

  testWidgets('default behavior rejects too-small constraints', (tester) async {
    final errors = <RahaAdsException>[];

    await tester.pumpWidget(
      _bannerHost(
        width: 100,
        height: 40,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          onError: errors.add,
        ),
      ),
    );

    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(RahaBannerAd), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
    expect(
      errors.where((error) => error.code == RahaAdsErrorCode.layout),
      hasLength(1),
    );
  });

  testWidgets('default behavior rejects stretched constraints', (tester) async {
    final errors = <RahaAdsException>[];

    await tester.pumpWidget(
      _bannerHost(
        width: 400,
        height: 50,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          onError: errors.add,
        ),
      ),
    );

    expect(find.byType(FittedBox), findsNothing);
    expect(
      errors.where((error) => error.code == RahaAdsErrorCode.layout),
      hasLength(1),
    );
  });

  testWidgets('fit contain accepts smaller constraints', (tester) async {
    final errors = <RahaAdsException>[];

    await tester.pumpWidget(
      _bannerHost(
        width: 100,
        height: 300,
        child: RahaBannerAd(
          size: RahaBannerSize.wideSkyscraper160x600,
          fit: BoxFit.contain,
          onError: errors.add,
        ),
      ),
    );

    expect(find.byType(FittedBox), findsOneWidget);
    expect(find.byType(RahaBannerAd), findsOneWidget);
    expect(
      errors.where((error) => error.code == RahaAdsErrorCode.layout),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exact-compatible constraints pass without fit', (tester) async {
    final errors = <RahaAdsException>[];

    await tester.pumpWidget(
      _bannerHost(
        width: 320,
        height: 50,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          onError: errors.add,
        ),
      ),
    );

    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(RahaBannerAd), findsOneWidget);
    expect(
      errors.where((error) => error.code == RahaAdsErrorCode.layout),
      isEmpty,
    );
  });

  testWidgets(
    'fit contain under smaller constraints renders a banner frame',
    (tester) async {
      await tester.pumpWidget(
        _bannerHost(
          width: 100,
          height: 300,
          child: const RahaBannerAd(
            size: RahaBannerSize.wideSkyscraper160x600,
            fit: BoxFit.contain,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FittedBox), findsOneWidget);
      expect(find.byType(RahaBannerAd), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 160 && widget.height == 600,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('coalesces difference-time change until refresh interval',
      (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      _bannerHost(
        width: 320,
        height: 50,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          differenceTime: Duration.zero,
          onError: (_) => errors++,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _bannerHost(
        width: 320,
        height: 50,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          differenceTime: const Duration(hours: 1),
          onError: (_) => errors++,
        ),
      ),
    );
    await tester.pump();

    expect(errors, 1);
  });

  testWidgets('coalesces language change until refresh interval',
      (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      _bannerHost(
        width: 320,
        height: 50,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          language: 'fa',
          onError: (_) => errors++,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _bannerHost(
        width: 320,
        height: 50,
        child: RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          language: 'ps',
          onError: (_) => errors++,
        ),
      ),
    );
    await tester.pump();

    expect(errors, 1);
  });
}

Widget _bannerHost({
  required double width,
  required double height,
  required Widget child,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    ),
  );
}
