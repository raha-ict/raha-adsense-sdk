import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raha_adsense/src/config/raha_adsense_config.dart';
import 'package:raha_adsense/src/config/raha_adsense_endpoints.dart';
import 'package:raha_adsense/src/core/raha_adsense_runtime.dart';
import 'package:raha_adsense/src/errors/raha_adsense_exception.dart';
import 'package:raha_adsense/src/models/ad_response.dart';
import 'package:raha_adsense/src/models/models.dart';

void main() {
  late _TestAdServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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

  test('explicit placement requests remain caller-controlled', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    await runtime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {},
    );
    await runtime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {},
    );

    expect(server.requestedPlacementIds, [
      'banner-placement',
      'banner-placement',
    ]);
  });

  test('structured request and tracking logs redact IDs and URLs', () async {
    final runtime = await _runtime(server, enableDebugLogs: true);
    addTearDown(runtime.dispose);
    final originalDebugPrint = debugPrint;
    final logs = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);

    final ad = await runtime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {'genre': 'news'},
    );
    await ad!.recordImpression();
    await ad.openClick();

    final combined = logs.join('\n');
    expect(combined, contains('[RAHA_ADS] 20'));
    expect(combined, contains('event=request_start'));
    expect(combined, contains('requestSource=manual_requestByPlacementId'));
    expect(combined, contains('event=request_body'));
    expect(combined, contains('bodyKeys='));
    expect(combined, contains('event=impression_attempt'));
    expect(combined, contains('event=click_attempt'));
    expect(combined, isNot(contains('stable-test-visitor-id')));
    expect(combined, isNot(contains('/tracking/')));
    expect(combined, isNot(contains('impressionUrl=')));
  });

  test('serializes exact visitorId and userAgent with flat contextual signals',
      () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);

    await runtime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {'genre': 'news', 'screen': 'home'},
    );

    final body = server.requestBodies.single;
    expect(body['visitorId'], 'stable-test-visitor-id');
    expect(body.containsKey('visitor_id'), isFalse);
    expect(body['userAgent'], {'deviceType': 'phone', 'os': 'android'});
    expect(body['genre'], 'news');
    expect(body['screen'], 'home');
    expect(body['device_type'], 'phone');
    expect(body['os'], 'ANDROID');
    expect(body.containsKey('signals'), isFalse);
  });

  test('persists the same visitorId across runtime instances', () async {
    final firstRuntime = await _runtime(server, usePersistedVisitorId: true);
    await firstRuntime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {},
    );
    final firstVisitorId = server.requestBodies.last['visitorId'];
    firstRuntime.dispose();

    final secondRuntime = await _runtime(server, usePersistedVisitorId: true);
    addTearDown(secondRuntime.dispose);
    await secondRuntime.requestAdByPlacementId(
      placementId: 'banner-placement',
      signals: const {},
    );

    expect(server.requestBodies.last['visitorId'], firstVisitorId);
    expect(firstVisitorId, isA<String>());
  });

  test('video click tracking is untouched until openClick is called', () async {
    final runtime = await _runtime(server);
    addTearDown(runtime.dispose);
    final ad = await runtime.requestVideoAd(signals: const {});

    expect(server.clickRequests, isEmpty);
    await ad!.openClick();
    expect(server.clickRequests, hasLength(1));
    expect(server.clickRequests.single.path, '/tracking/click/video-ad');
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

Future<RahaAdsenseRuntime> _runtime(
  _TestAdServer server, {
  bool usePersistedVisitorId = false,
  bool enableDebugLogs = false,
}) async {
  final runtime = RahaAdsenseRuntime(
    config: RahaAdsenseConfig.forTesting(
      appId: _appId,
      endpoints: RahaAdsenseEndpoints.forTesting(
        apiOrigin: server.origin,
        cdnBaseUrl: server.origin.resolve('/cdn/'),
        allowInsecureHttp: true,
      ),
      deviceType: 'phone',
      os: 'android',
      clickOpener: (uri, _) async {},
      enableDebugLogs: enableDebugLogs,
    ),
    visitorIdLoader:
        usePersistedVisitorId ? null : () async => 'stable-test-visitor-id',
  );
  await runtime.initialize();
  return runtime;
}

final class _TestAdServer {
  _TestAdServer._(this._server);

  final HttpServer _server;
  final requestedPlacementIds = <String>[];
  final requestBodies = <Map<String, Object?>>[];
  final impressionRequests = <Uri>[];
  final clickRequests = <Uri>[];
  int impressionFailureCount = 0;

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
        final rawBody = await utf8.decoder.bind(request).join();
        requestBodies.add(
          (jsonDecode(rawBody) as Map).cast<String, Object?>(),
        );
        if (placementId == 'nofill-placement') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }
        await _sendJson(request.response, _decisionFor(placementId));
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path.startsWith('/tracking/impression/')) {
        impressionRequests.add(request.uri);
        if (impressionFailureCount > 0) {
          impressionFailureCount--;
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
          return;
        }
        await _sendJson(request.response, const {'isValid': true});
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path.startsWith('/tracking/click/')) {
        clickRequests.add(request.uri);
        request.response
          ..statusCode = HttpStatus.found
          ..headers
              .set(HttpHeaders.locationHeader, 'https://advertiser.example');
        await request.response.close();
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
