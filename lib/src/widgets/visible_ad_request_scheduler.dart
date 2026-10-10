import 'dart:async';
import 'package:uuid/uuid.dart';

import '../core/ad_request_log_context.dart';

/// Coordinates automatic ad requests for one visible widget slot.
final class VisibleAdRequestScheduler {
  VisibleAdRequestScheduler({
    required this.load,
    required this.canLoad,
    required this.onLog,
    required this.placementId,
    required this.widgetInstanceId,
  });

  final Future<bool> Function(RahaAdRequestLogContext context) load;
  final bool Function() canLoad;
  final void Function(String message) onLog;
  final String Function() placementId;
  final String widgetInstanceId;

  bool _visible = false;
  bool _pending = true;
  bool _loading = false;
  bool _disposed = false;
  bool _requestStarted = false;
  double _visibleFraction = 0;
  static const Uuid _uuid = Uuid();

  void updateVisibility(double visibleFraction) {
    if (_disposed) return;
    final wasVisible = _visible;
    _visibleFraction = visibleFraction;
    _visible = visibleFraction > 0;
    if (!_visible) {
      return;
    }
    if (!wasVisible) {
      if (!_requestStarted) _pending = true;
      onLog(
        'event=visible placementId=${placementId()} '
        'visibleFraction=$visibleFraction',
      );
    }
    _scheduleOrLoad();
  }

  void _scheduleOrLoad() {
    if (_disposed ||
        _requestStarted ||
        !_visible ||
        _loading ||
        !_pending ||
        !canLoad()) {
      return;
    }
    _startLoad();
  }

  void _startLoad() {
    if (_disposed || _requestStarted || !_visible || _loading || !_pending) {
      return;
    }
    _pending = false;
    _requestStarted = true;
    _loading = true;
    final context = RahaAdRequestLogContext(
      requestId: _uuid.v4(),
      requestSource: 'auto_initial_visible',
      trigger: 'visibility',
      widgetInstanceId: widgetInstanceId,
      visibleFraction: _visibleFraction,
    );
    unawaited(_runLoad(context));
  }

  Future<void> _runLoad(RahaAdRequestLogContext context) async {
    try {
      await load(context);
    } finally {
      _loading = false;
    }
  }

  void dispose() {
    _disposed = true;
  }
}
