import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:raha_adsense/src/config/raha_adsense_config.dart';
import 'package:raha_adsense/src/config/raha_adsense_endpoints.dart';
import 'package:raha_adsense/src/errors/raha_adsense_exception.dart';
import 'package:raha_adsense/src/models/models.dart';
import 'package:raha_adsense/src/network/raha_adsense_api.dart';

void main() {
  test('adds pretty dio logger when debug logs are enabled', () {
    final dio = buildRahaDio(
      RahaAdsenseConfig.forTesting(
        appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
        endpoints: RahaAdsenseEndpoints.production,
        deviceType: 'phone',
        os: 'android',
        enableDebugLogs: true,
      ),
    );

    expect(dio.interceptors.whereType<PrettyDioLogger>(), hasLength(1));
  });

  test('does not add pretty dio logger when debug logs are disabled', () {
    final dio = buildRahaDio(
      RahaAdsenseConfig.forTesting(
        appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
        endpoints: RahaAdsenseEndpoints.production,
        deviceType: 'phone',
        os: 'android',
      ),
    );

    expect(dio.interceptors.whereType<PrettyDioLogger>(), isEmpty);
  });

  test('normalizes signal keys and preserves scalar values', () {
    final result = validateAndNormalizePublisherSignals(
      const {
        'Genre': 'news',
        'score': 1.5,
        'live': true,
        'tags': ['fa', null],
      },
    );

    expect(result, {
      'genre': 'news',
      'score': 1.5,
      'live': true,
      'tags': ['fa', null],
    });
  });

  test('merges default device and request signal metadata', () {
    final result = mergeRequestSignals(
      signals: const {'screen': 'home'},
      deviceType: 'phone',
      os: 'android',
      language: 'ps',
      dayOfWeek: 'Saturday',
      timeOfDay: '23:40',
    );

    expect(result, {
      'device_type': 'phone',
      'os': 'android',
      'language': 'ps',
      'day_of_week': 'Saturday',
      'time_of_day': '23:40',
      'screen': 'home',
    });
  });

  test('allows passing device metadata through setup config', () {
    final config = RahaAdsenseConfig.production(
      appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
      deviceType: 'tablet',
      os: 'ios',
    );

    expect(config.deviceType, 'tablet');
    expect(config.os, 'ios');
  });

  test('rejects duplicate normalized signal keys', () {
    expect(
      () => validateAndNormalizePublisherSignals(
        const {'Genre': 'news', 'genre': 'sports'},
      ),
      throwsA(
        isA<RahaAdsException>().having(
          (error) => error.code,
          'code',
          RahaAdsErrorCode.invalidRequest,
        ),
      ),
    );
  });

  test('rejects unsupported signal values', () {
    expect(
      () => validateAndNormalizePublisherSignals(
        const {
          'genre': {'nested': true},
        },
      ),
      throwsA(isA<RahaAdsException>()),
    );
  });

  test('normalizes partial tracking JSON', () {
    final result = RahaTrackingResult.normalized(
      json: const {'redirectUrl': 'https://advertiser.example.com'},
      eventId: 'client-event',
      type: 'click',
    );

    expect(result.eventId, 'client-event');
    expect(result.type, 'click');
    expect(result.isValid, isTrue);
    expect(result.duplicate, isFalse);
    expect(result.redirectUrl, 'https://advertiser.example.com');
  });

  test('respects explicit rejected tracking JSON', () {
    final result = RahaTrackingResult.normalized(
      json: const {'isValid': false, 'invalidReason': 'invalid_ad_id'},
      eventId: 'client-event',
      type: 'impression',
    );

    expect(result.isValid, isFalse);
    expect(result.invalidReason, 'invalid_ad_id');
  });

  test('normalizes redirect location tracking JSON', () {
    final result = RahaTrackingResult.normalized(
      json: const {'redirectUrl': 'https://advertiser.example.com/path'},
      eventId: 'click-event',
      type: 'click',
    );

    expect(result.isValid, isTrue);
    expect(result.redirectUrl, 'https://advertiser.example.com/path');
  });
}
