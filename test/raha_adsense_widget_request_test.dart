import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:raha_adsense/src/config/raha_adsense_config.dart';
import 'package:raha_adsense/src/config/raha_adsense_endpoints.dart';
import 'package:raha_adsense/src/core/raha_adsense_runtime.dart';
import 'package:raha_adsense/src/network/raha_adsense_api.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldVisibilityInterval =
      VisibilityDetectorController.instance.updateInterval;
  late _FakeAdBackend backend;
  late _FakeVideoPlayer videoPlayer;
  late VideoPlayerPlatform oldVideoPlayer;

  setUp(() async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    backend = _FakeAdBackend();
    oldVideoPlayer = VideoPlayerPlatform.instance;
    videoPlayer = _FakeVideoPlayer();
    VideoPlayerPlatform.instance = videoPlayer;
    final config = RahaAdsenseConfig.forTesting(
      appId: _appId,
      endpoints: RahaAdsenseEndpoints.forTesting(
        apiOrigin: Uri.parse('https://api.example.test'),
        cdnBaseUrl: Uri.parse('https://cdn.example.test/ads/'),
      ),
      deviceType: 'phone',
      os: 'android',
      adRefreshInterval: const Duration(minutes: 30),
      enableDebugLogs: false,
    );
    final dio = buildRahaDio(config)..httpClientAdapter = backend;
    final runtime = RahaAdsenseRuntime(
      config: config,
      api: RahaAdsenseApi(dio: dio),
      visitorIdLoader: () async => 'visitor-test-1',
    );
    await runtime.initialize();
    RahaAdsense.setRuntimeForTesting(runtime);
  });

  tearDown(() async {
    RahaAdsense.resetForTesting();
    VideoPlayerPlatform.instance = oldVideoPlayer;
    VisibilityDetectorController.instance.updateInterval =
        oldVisibilityInterval;
    await videoPlayer.close();
  });

  for (final entry in <(String, Widget Function())>[
    ('banner', () => const RahaBannerAd(size: RahaBannerSize.mobile320x50)),
    ('native', () => const RahaNativeAd()),
    ('video', () => const RahaVideoAd()),
  ]) {
    testWidgets('${entry.$1} offscreen widget does not request',
        (tester) async {
      backend.noFillPlacements.add(_placementFor(entry.$1));
      final scrollController = ScrollController();
      await tester.pumpWidget(
        _scrollHost(scrollController, entry.$2()),
      );
      await tester.pump();
      expect(backend.adRequests, isEmpty);

      scrollController.jumpTo(600);
      await tester.pump();
      await _pumpUntil(tester, () => backend.adRequests.length == 1);
      expect(backend.adRequests, hasLength(1));
      expect(backend.adRequests.single.path, _placementFor(entry.$1));
      await tester.pumpWidget(const SizedBox.shrink());
      scrollController.dispose();
    });
  }

  testWidgets('entering view requests once and a rebuild does not reload',
      (tester) async {
    backend.noFillPlacements.add('banner-placement');
    final scrollController = ScrollController();
    final banner = const RahaBannerAd(size: RahaBannerSize.mobile320x50);
    await tester.pumpWidget(_scrollHost(scrollController, banner));
    await tester.pump();
    expect(backend.adRequests, isEmpty);

    scrollController.jumpTo(600);
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();
    expect(backend.adRequests, hasLength(1));

    await tester.pumpWidget(_scrollHost(scrollController, banner));
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pumpWidget(const SizedBox.shrink());
    scrollController.dispose();
  });

  testWidgets('changed signals coalesce until the shared interval',
      (tester) async {
    backend.noFillPlacements.add('banner-placement');
    await tester.pumpWidget(
      _visibleHost(
        const RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          signals: {'genre': 'first'},
        ),
      ),
    );
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();

    await tester.pumpWidget(
      _visibleHost(
        const RahaBannerAd(
          size: RahaBannerSize.mobile320x50,
          signals: {'genre': 'latest'},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 29, seconds: 59));
    expect(backend.adRequests, hasLength(1));

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 2);
    expect(backend.adRequests.last.body['genre'], 'latest');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('automatic cooldown survives widget remounts', (tester) async {
    backend.noFillPlacements.add('banner-placement');
    await tester.pumpWidget(
      _visibleHost(
        const RahaBannerAd(
          key: ValueKey('first-state'),
          size: RahaBannerSize.mobile320x50,
        ),
      ),
    );
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();

    await tester.pumpWidget(
      _visibleHost(
        const RahaBannerAd(
          key: ValueKey('remounted-state'),
          size: RahaBannerSize.mobile320x50,
        ),
      ),
    );
    await tester.pump();
    expect(backend.adRequests, hasLength(1));

    await tester.pump(const Duration(minutes: 30));
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only one visible same-placement widget requests per interval',
      (tester) async {
    backend.noFillPlacements.add('banner-placement');
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const RahaBannerAd(size: RahaBannerSize.mobile320x50),
            const RahaBannerAd(size: RahaBannerSize.mobile320x50),
          ],
        ),
      ),
    );
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(backend.adRequests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing an automatic widget cancels its refresh timer',
      (tester) async {
    backend.noFillPlacements.add('banner-placement');
    await tester.pumpWidget(
      _visibleHost(
        const RahaBannerAd(size: RahaBannerSize.mobile320x50),
      ),
    );
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 31));
    expect(backend.adRequests, hasLength(1));
  });

  testWidgets('disposing video widget detaches its controller listener',
      (tester) async {
    await tester.pumpWidget(_visibleHost(const RahaVideoAd()));
    await _pumpUntil(tester, () => backend.impressionRequests.isNotEmpty);
    await _pumpUntil(tester, () => videoPlayer.activeEventListeners == 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => videoPlayer.activeEventListeners == 0);
    expect(backend.adRequests, hasLength(1));
  });

  testWidgets('no-fill waits for the configured refresh interval',
      (tester) async {
    backend.noFillPlacements.add('banner-placement');
    final scrollController = ScrollController();
    await tester.pumpWidget(
      _scrollHost(
        scrollController,
        const RahaBannerAd(size: RahaBannerSize.mobile320x50),
      ),
    );
    scrollController.jumpTo(600);
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();
    expect(backend.adRequests, hasLength(1));

    await tester.pump(const Duration(minutes: 29, seconds: 59));
    expect(backend.adRequests, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 2);
    await tester.pumpWidget(const SizedBox.shrink());
    scrollController.dispose();
  });

  testWidgets('refresh waits until interval and while placement is visible',
      (tester) async {
    backend.noFillPlacements.add('banner-placement');
    final scrollController = ScrollController();
    await tester.pumpWidget(
      _scrollHost(
        scrollController,
        const RahaBannerAd(size: RahaBannerSize.mobile320x50),
      ),
    );
    scrollController.jumpTo(600);
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 1);
    await tester.pump();

    scrollController.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(minutes: 30));
    expect(backend.adRequests, hasLength(1));

    scrollController.jumpTo(600);
    await tester.pump();
    await _pumpUntil(tester, () => backend.adRequests.length == 2);
    await tester.pumpWidget(const SizedBox.shrink());
    scrollController.dispose();
  });

  testWidgets('video impression fires once after visible playback',
      (tester) async {
    final video = const RahaVideoAd();
    await tester.pumpWidget(_visibleHost(video));
    await _pumpUntil(tester, () => backend.adRequests.isNotEmpty);
    await _pumpUntil(tester, () => backend.impressionRequests.isNotEmpty);
    expect(backend.adRequests, hasLength(1));
    expect(backend.impressionRequests, hasLength(1));
    expect(backend.impressionRequests.single.path,
        '/tracking/impression/video-ad');

    await tester.pumpWidget(_visibleHost(video));
    videoPlayer.emitBuffering(true);
    await tester.pump();
    videoPlayer.emitBuffering(false);
    await tester.pump();
    expect(backend.adRequests, hasLength(1));
    expect(backend.impressionRequests, hasLength(1));
    expect(backend.clickRequests, isEmpty);

    await tester.tap(find.byType(RahaVideoAd));
    await _pumpUntil(tester, () => backend.clickRequests.isNotEmpty);
    expect(backend.clickRequests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('video impression retries once on a later eligible event',
      (tester) async {
    backend.impressionStatuses.addAll([500, 200]);
    var errors = 0;
    await tester.pumpWidget(
      _visibleHost(RahaVideoAd(onError: (_) => errors++)),
    );
    await _pumpUntil(tester, () => backend.adRequests.isNotEmpty);
    await _pumpUntil(tester, () => backend.impressionRequests.isNotEmpty);
    await _pumpUntil(tester, () => errors == 1);
    expect(backend.impressionRequests, hasLength(1));

    videoPlayer.emitBuffering(true);
    await tester.pump();
    videoPlayer.emitBuffering(false);
    await tester.pump();
    await _pumpUntil(tester, () => backend.impressionRequests.length == 2);
    expect(
      backend.impressionRequests[0].queryParameters['eventId'],
      backend.impressionRequests[1].queryParameters['eventId'],
    );

    videoPlayer.emitBuffering(true);
    await tester.pump();
    videoPlayer.emitBuffering(false);
    await tester.pump();
    expect(backend.impressionRequests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('permanent impression 4xx does not retry', (tester) async {
    backend.impressionStatuses.add(400);
    var errors = 0;
    await tester.pumpWidget(
      _visibleHost(RahaVideoAd(onError: (_) => errors++)),
    );
    await _pumpUntil(tester, () => backend.adRequests.isNotEmpty);
    await _pumpUntil(tester, () => backend.impressionRequests.isNotEmpty);
    await _pumpUntil(tester, () => errors == 1);
    videoPlayer.emitBuffering(true);
    await tester.pump();
    videoPlayer.emitBuffering(false);
    await tester.pump(const Duration(seconds: 1));
    expect(backend.impressionRequests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _appId = '743e8c4b-08e0-4152-877e-e035f7d92d9a';

String _placementFor(String format) => switch (format) {
      'banner' => 'banner-placement',
      'native' => 'native-placement',
      'video' => 'video-placement',
      _ => throw ArgumentError.value(format),
    };

Widget _scrollHost(ScrollController controller, Widget ad) {
  return MaterialApp(
    home: SizedBox(
      height: 400,
      child: ListView(
        controller: controller,
        children: [
          const SizedBox(height: 800),
          SizedBox(height: ad is RahaBannerAd ? 50 : 240, child: ad),
        ],
      ),
    ),
  );
}

Widget _visibleHost(Widget ad) => MaterialApp(
      home: Center(child: SizedBox(width: 320, height: 240, child: ad)),
    );

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int limit = 30,
}) async {
  for (var i = 0; i < limit && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: 'Timed out waiting for the async ad flow.');
}

final class _FakeAdBackend implements HttpClientAdapter {
  final adRequests = <({String path, Map<String, Object?> body})>[];
  final impressionRequests = <Uri>[];
  final clickRequests = <Uri>[];
  final noFillPlacements = <String>{};
  final impressionStatuses = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' &&
        options.path.endsWith('/api/v1/ad-requests/public/inventory')) {
      return _json(200, _inventory);
    }
    if (options.method == 'POST' &&
        options.path.contains('/api/v1/ad-requests/request/')) {
      final placementId = options.path.split('/').last;
      final encoded = options.data as String;
      adRequests.add((
        path: placementId,
        body: (jsonDecode(encoded) as Map).cast<String, Object?>(),
      ));
      if (noFillPlacements.contains(placementId)) {
        return ResponseBody.fromString('', 204);
      }
      return _json(200, _decision(placementId));
    }
    if (options.uri.path.startsWith('/tracking/impression/')) {
      impressionRequests.add(options.uri);
      final status =
          impressionStatuses.isEmpty ? 200 : impressionStatuses.removeAt(0);
      return _json(status, const {'isValid': true});
    }
    if (options.uri.path.startsWith('/tracking/click/')) {
      clickRequests.add(options.uri);
      return _json(200, const {'redirectUrl': 'https://advertiser.example'});
    }
    return _json(404, const {'error': 'not found'});
  }

  ResponseBody _json(int status, Object value) => ResponseBody.fromString(
        jsonEncode(value),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

const _inventory = <String, Object?>{
  'apps': [
    {
      'id': _appId,
      'name': 'Test app',
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
          'id': 'native-placement',
          'name': 'Native',
          'format': 'native',
          'currency': 'AFN',
        },
        {
          'id': 'video-placement',
          'name': 'Video',
          'format': 'video',
          'currency': 'AFN',
        },
      ],
    },
  ],
};

Map<String, Object?> _decision(String placementId) => switch (placementId) {
      'banner-placement' => const {
          'id': 'banner-ad',
          'format': 'banner',
          'impressionUrl': '/tracking/impression/banner-ad',
          'clickTrackingUrl': '/tracking/click/banner-ad',
          'asset': {
            'url': 'banner.png',
            'width': 320,
            'height': 50,
          },
        },
      'native-placement' => const {
          'id': 'native-ad',
          'format': 'native',
          'impressionUrl': '/tracking/impression/native-ad',
          'clickTrackingUrl': '/tracking/click/native-ad',
          'asset': {
            'title': 'Title',
            'description': '',
            'imageUrl': '',
            'iconUrl': '',
            'cta': '',
          },
        },
      _ => const {
          'id': 'video-ad',
          'format': 'video',
          'impressionUrl': '/tracking/impression/video-ad',
          'clickTrackingUrl': '/tracking/click/video-ad',
          'asset': {
            'url': 'video.mp4',
            'posterUrl': 'poster.jpg',
            'duration': 30,
          },
        },
    };

final class _FakeVideoPlayer extends VideoPlayerPlatform {
  int _nextId = 0;
  final _streams = <int, StreamController<VideoEvent>>{};

  int get activePlayers => _streams.length;
  int get activeEventListeners =>
      _streams.values.where((stream) => stream.hasListener).length;

  void emitBuffering(bool buffering) {
    for (final stream in _streams.values) {
      stream.add(
        VideoEvent(
          eventType: buffering
              ? VideoEventType.bufferingStart
              : VideoEventType.bufferingEnd,
        ),
      );
    }
  }

  Future<void> close() async {
    for (final stream in _streams.values) {
      await stream.close();
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 30),
        size: const Size(320, 180),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.black);
}
