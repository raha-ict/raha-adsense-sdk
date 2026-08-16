import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/src/core/placement_registry.dart';
import 'package:raha_adsense/src/errors/raha_adsense_exception.dart';
import 'package:raha_adsense/src/models/models.dart';

void main() {
  test('resolves exact banner size', () {
    final registry = PlacementRegistry(app: _app([_banner('320x50')]));

    expect(
      registry.resolveBanner(RahaBannerSize.mobile320x50).id,
      'banner-320x50',
    );
  });

  test('rejects missing banner size', () {
    final registry = PlacementRegistry(app: _app([_banner('728x90')]));

    expect(
      () => registry.resolveBanner(RahaBannerSize.mobile320x50),
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.placementNotFound,
        ),
      ),
    );
  });

  test('rejects duplicate video placements', () {
    final registry = PlacementRegistry(app: _app([_video('a'), _video('b')]));

    expect(
      registry.resolveVideo,
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.ambiguousPlacement,
        ),
      ),
    );
  });

  test('resolves native and interstitial placements', () {
    final registry = PlacementRegistry(
      app: _app([
        _format('native-id', RahaInventoryPlacementFormat.native),
        _format('interstitial-id', RahaInventoryPlacementFormat.interstitial),
      ]),
    );

    expect(registry.resolveNative().id, 'native-id');
    expect(registry.resolveInterstitial().id, 'interstitial-id');
  });

  test('resolves placement by exact trimmed id', () {
    final registry = PlacementRegistry(
      app: _app([_format('native-id', RahaInventoryPlacementFormat.native)]),
    );

    expect(registry.resolveById(' native-id ').id, 'native-id');
  });

  test('rejects empty placement id', () {
    final registry = PlacementRegistry(app: _app([]));

    expect(
      () => registry.resolveById('  '),
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.placementNotFound,
        ),
      ),
    );
  });

  test('rejects missing placement id', () {
    final registry = PlacementRegistry(
      app: _app([_format('native-id', RahaInventoryPlacementFormat.native)]),
    );

    expect(
      () => registry.resolveById('missing-id'),
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.placementNotFound,
        ),
      ),
    );
  });
}

RahaPublisherApp _app(List<RahaPlacement> placements) {
  return RahaPublisherApp(
    id: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
    name: 'Publisher App',
    type: 'mobile_app',
    placements: placements,
  );
}

RahaPlacement _banner(String size) {
  return RahaPlacement(
    id: 'banner-$size',
    name: 'Banner $size',
    format: RahaInventoryPlacementFormat.banner,
    size: size,
    currency: 'AFN',
  );
}

RahaPlacement _video(String id) {
  return _format(id, RahaInventoryPlacementFormat.video);
}

RahaPlacement _format(String id, RahaInventoryPlacementFormat format) {
  return RahaPlacement(
    id: id,
    name: '$format $id',
    format: format,
    currency: 'AFN',
  );
}
