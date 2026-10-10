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
  bool _hasRequested = false;
  double _visibleFraction = 0;
  String _pendingTrigger = 'visibility';
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
      _pending = true;
      if (!_hasRequested) _pendingTrigger = 'visibility';
      onLog(
        'event=visible placementId=${placementId()} '
        'visibleFraction=$visibleFraction',
      );
    }
    _scheduleOrLoad();
  }

  void requestRefresh() {
    if (_disposed) return;
    _pending = true;
    _pendingTrigger = 'changed_inputs';
    if (!_visible) {
      onLog('event=refresh_skip placementId=${placementId()} '
          'reason=not_visible');
      return;
    }
    _scheduleOrLoad();
  }

  void _scheduleOrLoad() {
    if (_disposed || !_visible || _loading || !_pending || !canLoad()) return;
    if (_hasRequested) {
      onLog('event=refresh_allowed placementId=${placementId()} '
          'requestSource=auto_refresh reason=inputs_changed');
    }
    _startLoad();
  }

  void _startLoad() {
    if (_disposed || !_visible || _loading || !_pending) return;
    _pending = false;
    _loading = true;
    final context = RahaAdRequestLogContext(
      requestId: _uuid.v4(),
      requestSource: _hasRequested ? 'auto_refresh' : 'auto_initial_visible',
      trigger: _pendingTrigger,
      widgetInstanceId: widgetInstanceId,
      visibleFraction: _visibleFraction,
    );
    _pendingTrigger = 'visibility';
    unawaited(_runLoad(context));
  }

  Future<void> _runLoad(RahaAdRequestLogContext context) async {
    var loaded = false;
    try {
      loaded = await load(context);
    } finally {
      _loading = false;
      if (!_disposed) {
        if (loaded) {
          _hasRequested = true;
        }
        if (_visible && _pending) _scheduleOrLoad();
      }
    }
  }

  void dispose() {
    _disposed = true;
  }
}
