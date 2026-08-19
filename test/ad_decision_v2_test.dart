import 'package:flutter_test/flutter_test.dart';
import 'package:raha_adsense/src/models/models.dart';

void main() {
  test('parses banner fixture into image asset', () {
    final decision = RahaAdDecisionDto.fromJson(bannerDecisionJson);

    expect(decision.id, 'ad_123');
    expect(decision.format, RahaAdDecisionFormat.banner);
    expect(decision.asset, isA<RahaImageAdAssetDto>());
    final asset = decision.asset as RahaImageAdAssetDto;
    expect(asset.url, 'adsense/banner-300x250.png');
    expect(asset.width, 300);
    expect(asset.height, 250);
  });

  test('parses video fixture into video asset', () {
    final decision = RahaAdDecisionDto.fromJson(videoDecisionJson);

    expect(decision.format, RahaAdDecisionFormat.video);
    final asset = decision.asset as RahaVideoAdAssetDto;
    expect(asset.posterUrl, 'adsense/poster.jpg');
    expect(asset.duration, 30);
  });

  test('parses interstitial fixture into image asset', () {
    final decision = RahaAdDecisionDto.fromJson(interstitialDecisionJson);

    expect(decision.format, RahaAdDecisionFormat.interstitial);
    final asset = decision.asset as RahaImageAdAssetDto;
    expect(asset.url, 'adsense/interstitial.png');
    expect(asset.width, 1080);
    expect(asset.height, 1920);
  });

  test('parses native fixture into native asset', () {
    final decision = RahaAdDecisionDto.fromJson(nativeDecisionJson);

    expect(decision.format, RahaAdDecisionFormat.native);
    final asset = decision.asset as RahaNativeAdAssetDto;
    expect(asset.title, 'Grow your business');
    expect(asset.cta, 'Learn more');
  });

  test('old generic payload fails', () {
    expect(
      () => RahaAdDecisionDto.fromJson(const {
        'adId': 'ad_123',
        'assetUrl': 'adsense/banner.png',
        'bannerAsset': <String, Object?>{},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('empty native title fails', () {
    final json = Map<String, Object?>.from(nativeDecisionJson);
    final asset = Map<String, Object?>.from(
      nativeDecisionJson['asset']! as Map<String, Object?>,
    );
    asset['title'] = '';
    json['asset'] = asset;

    expect(
      () => RahaAdDecisionDto.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('missing, null, empty, and whitespace tracking URLs are optional', () {
    for (final value in <Object?>[null, '', '   ']) {
      final json = Map<String, Object?>.from(bannerDecisionJson)
        ..remove('clickTrackingUrl');
      if (value != null) json['clickTrackingUrl'] = value;

      final decision = RahaAdDecisionDto.fromJson(json);

      expect(
        decision.clickTrackingUrl,
        value is String ? value.trim() : null,
      );
    }
  });
}

const bannerDecisionJson = <String, Object?>{
  'id': 'ad_123',
  'format': 'banner',
  'impressionUrl': '/tracking/impression/creative_123?placement=p1',
  'clickTrackingUrl': '/tracking/click/creative_123?placement=p1',
  'asset': <String, Object?>{
    'url': 'adsense/banner-300x250.png',
    'width': 300,
    'height': 250,
  },
};

const videoDecisionJson = <String, Object?>{
  'id': 'ad_123',
  'format': 'video',
  'impressionUrl': '/tracking/impression/creative_123?placement=p1',
  'clickTrackingUrl': '/tracking/click/creative_123?placement=p1',
  'asset': <String, Object?>{
    'url': 'adsense/video.mp4',
    'posterUrl': 'adsense/poster.jpg',
    'duration': 30,
  },
};

const interstitialDecisionJson = <String, Object?>{
  'id': 'ad_123',
  'format': 'interstitial',
  'impressionUrl': '/tracking/impression/creative_123?placement=p1',
  'clickTrackingUrl': '/tracking/click/creative_123?placement=p1',
  'asset': <String, Object?>{
    'url': 'adsense/interstitial.png',
    'width': 1080,
    'height': 1920,
  },
};

const nativeDecisionJson = <String, Object?>{
  'id': 'ad_123',
  'format': 'native',
  'impressionUrl': '/tracking/impression/creative_123?placement=p1',
  'clickTrackingUrl': '/tracking/click/creative_123?placement=p1',
  'asset': <String, Object?>{
    'title': 'Grow your business',
    'description': 'Reach more customers.',
    'imageUrl': 'https://cdn.example.com/native.jpg',
    'iconUrl': 'https://cdn.example.com/icon.png',
    'cta': 'Learn more',
  },
};
