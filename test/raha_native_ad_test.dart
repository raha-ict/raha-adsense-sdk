import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(RahaAdsense.resetForTesting);

  testWidgets('native no-fill surface can be built', (tester) async {
    expect(RahaAdFormat.native, isNotNull);
  });

  testWidgets('coalesces difference-time change until refresh interval',
      (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      RahaNativeAd(
        differenceTime: Duration.zero,
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      RahaNativeAd(
        differenceTime: const Duration(hours: 1),
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    expect(errors, 1);
  });

  testWidgets('coalesces language change until refresh interval',
      (tester) async {
    var errors = 0;

    await tester.pumpWidget(
      RahaNativeAd(
        language: 'fa',
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      RahaNativeAd(
        language: 'ps',
        onError: (_) => errors++,
      ),
    );
    await tester.pump();

    expect(errors, 1);
  });
}
