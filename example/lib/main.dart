import 'package:flutter/material.dart';
import 'package:raha_adsense/raha_adsense.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RahaAdsense.setup(
    appId: const String.fromEnvironment('RAHA_ADSENSE_APP_ID'),
    deviceType: 'phone',
    os: 'android',
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raha Adsense Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raha Adsense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Fixed 320x50 banner'),
          const SizedBox(height: 12),
          const Center(
            child: RahaBannerAd(
              size: RahaBannerSize.mobile320x50,
              signals: {'genre': 'news', 'language': 'fa'},
            ),
          ),
          const SizedBox(height: 24),
          const RahaNativeAd(
            signals: {'genre': 'business', 'language': 'fa'},
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManualBannerPage(),
                ),
              );
            },
            child: const Text('Manual banner request'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const VideoAdPage(),
                ),
              );
            },
            child: const Text('Open video placement'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManualVideoPage(),
                ),
              );
            },
            child: const Text('Manual video request'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final ad = await RahaAdsense.adRequest(
                type: RahaAdFormat.interstitial,
                signals: const {'screen': 'article_complete'},
              );
              if (ad is RahaInterstitialAdResponse && context.mounted) {
                await RahaInterstitialPresenter.show(context: context, ad: ad);
              }
            },
            child: const Text('Show interstitial'),
          ),
        ],
      ),
    );
  }
}

class ManualBannerPage extends StatefulWidget {
  const ManualBannerPage({super.key});

  @override
  State<ManualBannerPage> createState() => _ManualBannerPageState();
}

class _ManualBannerPageState extends State<ManualBannerPage> {
  Future<RahaAdResponse?>? _future;
  bool _decoded = false;

  @override
  void initState() {
    super.initState();
    _future = RahaAdsense.adRequest(
      type: RahaAdFormat.banner,
      bannerSize: RahaBannerSize.mobile320x50,
      signals: const {'genre': 'news', 'language': 'fa'},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual banner')),
      body: Center(
        child: FutureBuilder<RahaAdResponse?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(width: 320, height: 50);
            }
            final ad = snapshot.data;
            if (ad is! RahaBannerAdResponse) return const SizedBox.shrink();
            return VisibilityDetector(
              key: ValueKey('manual-banner-${ad.info.adId}'),
              onVisibilityChanged: (info) {
                if (_decoded && info.visibleFraction >= 0.5) {
                  ad.recordImpression();
                }
              },
              child: GestureDetector(
                onTap: ad.openClick,
                child: Image.network(
                  ad.imageUrl.toString(),
                  width: ad.width.toDouble(),
                  height: ad.height.toDouble(),
                  fit: BoxFit.fill,
                  frameBuilder: (context, child, frame, sync) {
                    if (frame != null || sync) _decoded = true;
                    return child;
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class VideoAdPage extends StatelessWidget {
  const VideoAdPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: RahaVideoAd(
          signals: {'genre': 'sports', 'playback_position': 'pre_roll'},
        ),
      ),
    );
  }
}

class ManualVideoPage extends StatefulWidget {
  const ManualVideoPage({super.key});

  @override
  State<ManualVideoPage> createState() => _ManualVideoPageState();
}

class _ManualVideoPageState extends State<ManualVideoPage> {
  RahaVideoAdResponse? _ad;
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response = await RahaAdsense.adRequest(
      type: RahaAdFormat.video,
      signals: const {'genre': 'sports', 'playback_position': 'pre_roll'},
    );
    if (response is! RahaVideoAdResponse || !mounted) return;
    final controller = VideoPlayerController.networkUrl(response.videoUrl);
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _ad = response;
      _controller = controller;
    });
    await controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ad == null || controller == null
          ? const SizedBox.shrink()
          : VisibilityDetector(
              key: ValueKey('manual-video-${ad.info.adId}'),
              onVisibilityChanged: (info) {
                if (controller.value.isPlaying && info.visibleFraction >= 0.5) {
                  ad.recordImpression();
                }
              },
              child: GestureDetector(
                onTap: ad.openClick,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),
    );
  }
}
