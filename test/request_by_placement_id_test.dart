import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/src/config/raha_adsense_config.dart';
import 'package:raha_adsense/src/config/raha_adsense_endpoints.dart';
import 'package:raha_adsense/src/core/raha_adsense_runtime.dart';
import 'package:raha_adsense/src/errors/raha_adsense_exception.dart';
import 'package:raha_adsense/src/models/ad_response.dart';
import 'package:raha_adsense/src/models/models.dart';

void main() {
  late _TestAdServer server;

  setUp(() async {
    server = await _TestAdServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  test('returns banner response for placement id', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    final ad = await runtime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {'screen': 'home'},
    );

    expect(ad, isA<RahaBannerAdResponse>());
    final banner = ad as RahaBannerAdResponse;
    expect(banner.info.placementId, 'banner-placement');
    expect(banner.info.format, RahaAdFormat.banner);
    expect(banner.width, 320);
    expect(banner.height, 50);
    expect(banner.isClickable, isTrue);
    expect(server.requestedPlacementIds, contains('banner-placement'));
  });

  test('returns video native and interstitial responses for placement ids',
      () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    final video = await runtime.requestAdByPlacementId(
      placementId: 'video-placement',
      signals: const {},
    );
    final native = await runtime.requestAdByPlacementId(
      placementId: 'native-placement',
      signals: const {},
    );
    final interstitial = await runtime.requestAdByPlacementId(
      placementId: 'interstitial-placement',
      signals: const {},
    );

    expect(video, isA<RahaVideoAdResponse>());
    expect(native, isA<RahaNativeAdResponse>());
    expect(interstitial, isA<RahaInterstitialAdResponse>());
    expect((video as RahaVideoAdResponse).isClickable, isTrue);
    expect((native as RahaNativeAdResponse).isClickable, isTrue);
    expect((interstitial as RahaInterstitialAdResponse).isClickable, isTrue);
  });

  test('returns non-clickable ad when tracking URL is absent', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    final ad = await runtime.requestAdByPlacementId(
      placementId: 'non-clickable-placement',
      signals: const {},
    );

    expect(ad, isA<RahaNativeAdResponse>());
    final native = ad as RahaNativeAdResponse;
    expect(native.isClickable, isFalse);
    await expectLater(
      native.openClick(),
      throwsA(isA<RahaAdsException>()),
    );
  });

  test('returns null when placement request has no fill', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    final ad = await runtime.requestAdByPlacementId(
      placementId: 'nofill-placement',
      signals: const {},
    );

    expect(ad, isNull);
  });

  test('throws placementNotFound for missing placement id', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    expect(
      () => runtime.requestAdByPlacementId(
        placementId: 'missing-placement',
        signals: const {},
      ),
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.placementNotFound,
        ),
      ),
    );
  });

  test('throws invalidResponse for mismatched decision format', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    expect(
      () => runtime.requestAdByPlacementId(
        placementId: 'mismatch-placement',
        signals: const {},
      ),
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.invalidResponse,
        ),
      ),
    );
  });
}

Future<RahaAdsenseRuntime> _runtime(_TestAdServer server) async {
  final runtime = RahaAdsenseRuntime(
    config: RahaAdsenseConfig.forTesting(
      appId: _appId,
      endpoints: RahaAdsenseEndpoints.forTesting(
        apiOrigin: server.origin,
        cdnBaseUrl: server.origin.resolve('/cdn/'),
        allowInsecureHttp: true,
      ),
    ),
  );
  await runtime.initialize();
  return runtime;
}

final class _TestAdServer {
  _TestAdServer._(this._server);

  final HttpServer _server;
  final requestedPlacementIds = <String>[];

  Uri get origin => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_TestAdServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestAdServer._(server);
    testServer._listen();
    return testServer;
  }

  void _listen() {
    _server.listen((request) async {
      if (request.method == 'GET' &&
          request.uri.path == '/api/v1/ad-requests/public/inventory') {
        await _sendJson(request.response, _inventoryJson);
        return;
      }

      if (request.method == 'POST' &&
          request.uri.pathSegments.length == 4 &&
          request.uri.pathSegments[0] == 'api' &&
          request.uri.pathSegments[1] == 'v1' &&
          request.uri.pathSegments[2] == 'ad-requests' &&
          request.uri.pathSegments[3].startsWith('request')) {
        await _sendJson(
          request.response..statusCode = HttpStatus.notFound,
          const {'error': 'not found'},
        );
        return;
      }

      if (request.method == 'POST' &&
          request.uri.pathSegments.length == 5 &&
          request.uri.pathSegments[0] == 'api' &&
          request.uri.pathSegments[1] == 'v1' &&
          request.uri.pathSegments[2] == 'ad-requests' &&
          request.uri.pathSegments[3] == 'request') {
        final placementId = Uri.decodeComponent(request.uri.pathSegments[4]);
        requestedPlacementIds.add(placementId);
        await request.drain<void>();
        if (placementId == 'nofill-placement') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }
        await _sendJson(request.response, _decisionFor(placementId));
        return;
      }

      await _sendJson(
        request.response..statusCode = HttpStatus.notFound,
        const {'error': 'not found'},
      );
    });
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> _sendJson(
  HttpResponse response,
  Map<String, Object?> json,
) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(json));
  await response.close();
}

Map<String, Object?> _decisionFor(String placementId) {
  return switch (placementId) {
    'banner-placement' => _bannerDecision,
    'video-placement' => _videoDecision,
    'native-placement' => _nativeDecision,
    'interstitial-placement' => _interstitialDecision,
    'non-clickable-placement' => _nonClickableNativeDecision,
    'mismatch-placement' => _videoDecision,
    _ => _bannerDecision,
  };
}

const _appId = '743e8c4b-08e0-4152-877e-e035f7d92d9a';

const _inventoryJson = <String, Object?>{
  'apps': [
    {
      'id': _appId,
      'name': 'Publisher App',
      'type': 'mobile_app',
      'placements': [
        {
          'id': 'banner-placement',
          'name': 'Banner',
          'format': 'banner',
          'size': '320x50',
          'currency': 'AFN',
        },
        {
          'id': 'video-placement',
          'name': 'Video',
          'format': 'video',
          'currency': 'AFN',
        },
        {
          'id': 'native-placement',
          'name': 'Native',
          'format': 'native',
          'currency': 'AFN',
        },
        {
          'id': 'interstitial-placement',
          'name': 'Interstitial',
          'format': 'interstitial',
          'currency': 'AFN',
        },
        {
          'id': 'nofill-placement',
          'name': 'No Fill',
          'format': 'native',
          'currency': 'AFN',
        },
        {
          'id': 'mismatch-placement',
          'name': 'Mismatch',
          'format': 'native',
          'currency': 'AFN',
        },
        {
          'id': 'non-clickable-placement',
          'name': 'Non Clickable',
          'format': 'native',
          'currency': 'AFN',
        },
      ],
    },
  ],
};

const _bannerDecision = <String, Object?>{
  'id': 'banner-ad',
  'format': 'banner',
  'impressionUrl': '/tracking/impression/banner-ad',
  'clickTrackingUrl': '/tracking/click/banner-ad',
  'asset': {
    'url': 'banner.png',
    'width': 320,
    'height': 50,
  },
};

const _videoDecision = <String, Object?>{
  'id': 'video-ad',
  'format': 'video',
  'impressionUrl': '/tracking/impression/video-ad',
  'clickTrackingUrl': '/tracking/click/video-ad',
  'asset': {
    'url': 'video.mp4',
    'posterUrl': 'poster.jpg',
    'duration': 30,
  },
};

const _nativeDecision = <String, Object?>{
  'id': 'native-ad',
  'format': 'native',
  'impressionUrl': '/tracking/impression/native-ad',
  'clickTrackingUrl': '/tracking/click/native-ad',
  'asset': {
    'title': 'Grow your business',
    'description': 'Reach more customers.',
    'imageUrl': 'native.jpg',
    'iconUrl': 'icon.png',
    'cta': 'Learn more',
  },
};

const _interstitialDecision = <String, Object?>{
  'id': 'interstitial-ad',
  'format': 'interstitial',
  'impressionUrl': '/tracking/impression/interstitial-ad',
  'clickTrackingUrl': '/tracking/click/interstitial-ad',
  'asset': {
    'url': 'interstitial.png',
    'width': 1080,
    'height': 1920,
  },
};

const _nonClickableNativeDecision = <String, Object?>{
  'id': 'non-clickable-ad',
  'format': 'native',
  'impressionUrl': '/tracking/impression/non-clickable-ad',
  'asset': {
    'title': 'Grow your business',
    'description': 'Reach more customers.',
    'imageUrl': 'native.jpg',
    'iconUrl': 'icon.png',
    'cta': 'Learn more',
  },
};
