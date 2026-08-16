import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/raha_adsense_config.dart';
import '../errors/raha_adsense_exception.dart';
import '../models/models.dart';
import 'retry_policy.dart';

Dio buildRahaDio(RahaAdsenseConfig config) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.endpoints.apiOrigin.toString().replaceAll(
            RegExp(r'/+$'),
            '',
          ),
      connectTimeout: config.requestTimeout,
      sendTimeout: config.requestTimeout,
      receiveTimeout: config.requestTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      headers: const {'Accept': 'application/json'},
    ),
  );

  if (config.enableDebugLogs) {
    dio.interceptors.add(
      PrettyDioLogger(
        requestHeader: true,
        responseHeader: true,
        error: true,
        compact: true,
        enabled: config.enableDebugLogs,
      ),
    );
  }

  return dio;
}

/// HTTP API client for Raha ad inventory, decision, and tracking endpoints.
///
/// This client centralizes request serialization, response validation, and
/// retry behavior for the Raha SDK.
final class RahaAdsenseApi {
  RahaAdsenseApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Fetch the publisher inventory from the Raha backend.
  ///
  /// This returns the configured list of apps, placements, and ad formats.
  Future<RahaInventoryResponse> fetchInventory({
    CancelToken? cancelToken,
  }) async {
    final response = await _guardNetwork(
      () => _dio.get<String>(
        '/api/v1/ad-requests/public/inventory',
        cancelToken: cancelToken,
      ),
    );
    _requireStatus(response, 200);
    final json = _decodeObject(
      response.data,
      maxBytes: 512 * 1024,
      label: 'inventory',
    );
    return RahaInventoryResponse.fromJson(json);
  }

  /// Request a single ad decision for a placement.
  ///
  /// The request may return `null` when no ad is available for the
  /// configured placement.
  Future<RahaAdDecisionDto?> requestAd({
    required String placementId,
    required Map<String, Object?> signals,
    CancelToken? cancelToken,
  }) async {
    final body = validateAndNormalizePublisherSignals(signals);
    final encoded = jsonEncode(body);
    if (utf8.encode(encoded).length > 16 * 1024) {
      throw const RahaAdsException.invalidRequest(
        'Signals exceed the 16 KiB request limit.',
      );
    }

    final response = await _guardNetwork(
      () => withOneRetry<Response<String>>(
        () => _dio.post<String>(
          '/api/v1/ad-requests/request/${Uri.encodeComponent(placementId)}',
          data: encoded,
          cancelToken: cancelToken,
        ),
        cancelToken: cancelToken,
      ),
    );

    if (response.statusCode == 204) return null;
    _requireStatus(response, 200);

    final raw = response.data?.trim();
    if (raw == null || raw == 'null' || raw.isEmpty) return null;
    final json = _decodeObject(raw, maxBytes: 256 * 1024, label: 'ad decision');
    try {
      return RahaAdDecisionDto.fromJson(json);
    } on FormatException catch (error) {
      throw RahaAdsException(
        RahaAdsErrorCode.invalidResponse,
        'Invalid Raha ad decision response.',
        cause: error,
      );
    }
  }

  /// Track an ad impression by calling the provided impression URI.
  Future<RahaTrackingResult> trackImpression(
    Uri uri, {
    required String eventId,
    CancelToken? cancelToken,
  }) async {
    return _track(
      uri,
      eventId: eventId,
      expectedType: 'impression',
      captureRedirect: false,
      cancelToken: cancelToken,
    );
  }

  /// Track an ad click URI, following redirects when necessary.
  Future<RahaTrackingResult> trackClick(
    Uri uri, {
    required String eventId,
    CancelToken? cancelToken,
  }) async {
    final trackedUri = _appendEventId(uri, eventId);
    final response = await _guardNetwork(
      () => withOneRetry<Response<String>>(
        () => _dio.getUri<String>(
          trackedUri,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: false,
            validateStatus: (status) =>
                status != null &&
                (status == 200 || status == 204 || _isRedirectStatus(status)),
          ),
        ),
        cancelToken: cancelToken,
      ),
    );

    if (_isRedirectStatus(response.statusCode)) {
      final redirectUri = _resolveRedirectLocation(
        trackedUri,
        response.headers.value('location'),
      );
      return _normalizedClickTrackingResult(
        eventId: eventId,
        redirectUrl: redirectUri?.toString(),
      );
    }

    if (response.statusCode == 204) {
      return _normalizedClickTrackingResult(eventId: eventId);
    }
    _requireStatus(response, 200);

    final raw = response.data?.trim();
    if (raw == null || raw.isEmpty) {
      return _normalizedClickTrackingResult(eventId: eventId);
    }

    final parsed = _tryDecodeObject(raw);
    if (parsed == null) {
      _logMalformedTracking(response, 'click');
      final redirectUri = _tryParseAbsoluteHttpsUri(raw);
      return _normalizedClickTrackingResult(
        eventId: eventId,
        redirectUrl: redirectUri?.toString(),
      );
    }

    try {
      return RahaTrackingResult.normalized(
        json: parsed,
        eventId: eventId,
        type: 'click',
      );
    } on FormatException {
      _logMalformedTracking(response, 'click');
      return _normalizedClickTrackingResult(eventId: eventId);
    }
  }

  Future<RahaTrackingResult> _track(
    Uri uri, {
    required String eventId,
    required String expectedType,
    required bool captureRedirect,
    CancelToken? cancelToken,
  }) async {
    final trackedUri = _appendEventId(uri, eventId);
    final response = await _guardNetwork(
      () => withOneRetry<Response<String>>(
        () => _dio.getUri<String>(
          trackedUri,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: !captureRedirect,
            validateStatus: captureRedirect
                ? (status) =>
                    status != null &&
                    (status == 200 ||
                        status == 204 ||
                        _isRedirectStatus(status))
                : null,
          ),
        ),
        cancelToken: cancelToken,
      ),
    );
    if (captureRedirect && _isRedirectStatus(response.statusCode)) {
      final location = response.headers.value('location');
      final redirectUri = _resolveRedirectLocation(trackedUri, location);
      if (redirectUri != null) {
        return RahaTrackingResult.normalized(
          json: <String, Object?>{
            'redirectUrl': redirectUri.toString(),
          },
          eventId: eventId,
          type: expectedType,
        );
      }
      return RahaTrackingResult.normalized(
        json: const <String, Object?>{},
        eventId: eventId,
        type: expectedType,
      );
    }
    if (response.statusCode == 204) {
      return RahaTrackingResult.normalized(
        json: const <String, Object?>{},
        eventId: eventId,
        type: expectedType,
      );
    }
    _requireStatus(response, 200);

    final raw = response.data?.trim();
    if (raw == null || raw.isEmpty) {
      return RahaTrackingResult.normalized(
        json: const <String, Object?>{},
        eventId: eventId,
        type: expectedType,
      );
    }

    try {
      return RahaTrackingResult.normalized(
        json: _decodeObject(raw, maxBytes: 64 * 1024, label: 'tracking'),
        eventId: eventId,
        type: expectedType,
      );
    } on RahaAdsException catch (_) {
      _logMalformedTracking(response, expectedType);
      return RahaTrackingResult.normalized(
        json: const <String, Object?>{},
        eventId: eventId,
        type: expectedType,
      );
    } on FormatException catch (error) {
      _logMalformedTracking(response, expectedType);
      final _ = error;
      return RahaTrackingResult.normalized(
        json: const <String, Object?>{},
        eventId: eventId,
        type: expectedType,
      );
    }
  }

  void dispose() => _dio.close(force: true);
}

RahaTrackingResult _normalizedClickTrackingResult({
  required String eventId,
  String? redirectUrl,
}) {
  return RahaTrackingResult.normalized(
    json: <String, Object?>{
      if (redirectUrl != null && redirectUrl.trim().isNotEmpty)
        'redirectUrl': redirectUrl,
    },
    eventId: eventId,
    type: 'click',
  );
}

Map<String, Object?>? _tryDecodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return null;
  } on Object {
    return null;
  }
}

Uri? _tryParseAbsoluteHttpsUri(String raw) {
  try {
    final uri = Uri.parse(raw.trim());
    if (!uri.isAbsolute ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

Map<String, Object?> validateAndNormalizePublisherSignals(
  Map<String, Object?> signals,
) {
  const keyPattern = r'^[a-z][a-z0-9_]*$';
  final keyRegex = RegExp(keyPattern);
  if (signals.length > 32) {
    throw const RahaAdsException.invalidRequest(
      'At most 32 publisher signals are allowed.',
    );
  }

  final normalized = <String, Object?>{};
  for (final entry in signals.entries) {
    final key = entry.key.toLowerCase();
    if (!keyRegex.hasMatch(key)) {
      throw RahaAdsException.invalidRequest(
        'Signal keys must match $keyPattern.',
      );
    }
    if (normalized.containsKey(key)) {
      throw RahaAdsException.invalidRequest(
        'Duplicate signal key after lowercase normalization: $key.',
      );
    }
    normalized[key] = _validateSignalValue(entry.value);
  }
  return normalized;
}

Object? _validateSignalValue(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    if (value.length > 32) {
      throw const RahaAdsException.invalidRequest(
        'Signal lists may contain at most 32 values.',
      );
    }
    return value.map(_validateSignalScalar).toList(growable: false);
  }
  throw const RahaAdsException.invalidRequest(
    'Signal values must be strings, finite numbers, booleans, null, or lists.',
  );
}

Object? _validateSignalScalar(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  throw const RahaAdsException.invalidRequest(
    'Signal list values must be scalar JSON values.',
  );
}

Map<String, Object?> _decodeObject(
  String? raw, {
  required int maxBytes,
  required String label,
}) {
  if (raw == null || utf8.encode(raw).length > maxBytes) {
    throw RahaAdsException(
      RahaAdsErrorCode.malformedResponse,
      'Malformed $label response.',
    );
  }
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) return decoded.cast<String, Object?>();
  throw RahaAdsException(
    RahaAdsErrorCode.malformedResponse,
    'Expected $label response to be a JSON object.',
  );
}

void _requireStatus(Response<dynamic> response, int statusCode) {
  if (response.statusCode == statusCode) return;
  final code = switch (response.statusCode) {
    401 || 403 => RahaAdsErrorCode.unauthorized,
    408 => RahaAdsErrorCode.timeout,
    429 => RahaAdsErrorCode.rateLimited,
    _ => RahaAdsErrorCode.network,
  };
  throw RahaAdsException(
    code,
    'Raha request failed with HTTP ${response.statusCode}.',
    statusCode: response.statusCode,
  );
}

Future<T> _guardNetwork<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on RahaAdsException {
    rethrow;
  } on DioException catch (error) {
    final code = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        RahaAdsErrorCode.timeout,
      _ => RahaAdsErrorCode.network,
    };
    throw RahaAdsException(
      code,
      'Raha network request failed: ${_describeDioError(error)}.',
      cause: error,
    );
  } on FormatException catch (error) {
    throw RahaAdsException(
      RahaAdsErrorCode.invalidResponse,
      'Malformed Raha response.',
      cause: error,
    );
  }
}

String _describeDioError(DioException error) {
  final parts = <String>[error.type.name];
  final message = error.message;
  if (message != null && message.trim().isNotEmpty) {
    parts.add(message.trim());
  }
  final cause = error.error;
  if (cause != null) {
    parts.add(cause.toString());
  }
  return parts.join(' | ');
}

void _logMalformedTracking(Response<dynamic> response, String expectedType) {
  if (!kDebugMode) return;
  final contentType = response.headers.value(Headers.contentTypeHeader);
  debugPrint(
    '[Raha Adsense] tracking $expectedType response malformed: '
    'HTTP ${response.statusCode}, content-type ${contentType ?? 'unknown'}',
  );
}

Uri _appendEventId(Uri uri, String eventId) {
  final withoutFragment = uri.removeFragment().toString();
  final separator = uri.hasQuery ? '&' : '?';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  return Uri.parse(
    '$withoutFragment${separator}eventId='
    '${Uri.encodeQueryComponent(eventId)}$fragment',
  );
}

bool _isRedirectStatus(int? statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

Uri? _resolveRedirectLocation(Uri requestUri, String? location) {
  if (location == null || location.trim().isEmpty) return null;
  final raw = location.trim();
  if (raw.startsWith('//')) return null;
  try {
    final uri = Uri.parse(raw);
    return uri.hasScheme ? uri : requestUri.resolveUri(uri);
  } on FormatException {
    return null;
  }
}
