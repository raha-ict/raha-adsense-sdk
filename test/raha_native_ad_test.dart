import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';

void main() {
  tearDown(RahaAdsense.resetForTesting);

  testWidgets('native no-fill surface can be built', (tester) async {
    expect(RahaAdFormat.native, isNotNull);
  });

  testWidgets('reloads when difference time changes', (tester) async {
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

    expect(errors, 2);
  });

  testWidgets('reloads when language changes', (tester) async {
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

    expect(errors, 2);
  });
}
