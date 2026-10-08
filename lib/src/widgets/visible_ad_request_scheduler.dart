import 'dart:async';

/// Coordinates automatic ad requests for one visible widget slot.
final class VisibleAdRequestScheduler {
  VisibleAdRequestScheduler({
    required this.interval,
    required this.load,
    required this.onLog,
    required this.placementId,
  });

  final Duration interval;
  final Future<void> Function() load;
  final void Function(String message) onLog;
  final String Function() placementId;

  Timer? _timer;
  DateTime? _lastRequestAt;
  bool _visible = false;
  bool _pending = true;
  bool _loading = false;
  bool _disposed = false;

  void updateVisibility(double visibleFraction) {
    if (_disposed) return;
    final wasVisible = _visible;
    _visible = visibleFraction > 0;
    if (!_visible) {
      if (_timer != null && _pending) {
        onLog('refresh_skip placementId=${placementId()} reason=not_visible');
      }
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (!wasVisible) {
      onLog(
        'visible placementId=${placementId()} '
        'visibleFraction=$visibleFraction',
      );
    }
    _scheduleOrLoad();
  }

  void requestRefresh() {
    if (_disposed) return;
    _pending = true;
    if (!_visible) {
      onLog('refresh_skip placementId=${placementId()} reason=not_visible');
      return;
    }
    _scheduleOrLoad();
  }

  void _scheduleOrLoad() {
    if (_disposed || !_visible || _loading || !_pending) return;
    final lastRequestAt = _lastRequestAt;
    final elapsed = lastRequestAt == null
        ? interval
        : DateTime.now().difference(lastRequestAt);
    if (lastRequestAt != null && elapsed < interval) {
      final remaining = interval - elapsed;
      onLog(
        'refresh_skip placementId=${placementId()} '
        'reason=interval_not_reached',
      );
      _timer?.cancel();
      _timer = Timer(remaining, () {
        _timer = null;
        if (_visible && !_disposed && _pending) {
          onLog('refresh_allowed placementId=${placementId()}');
          _startLoad();
        }
      });
      return;
    }
    if (lastRequestAt != null) {
      onLog('refresh_allowed placementId=${placementId()}');
    }
    _startLoad();
  }

  void _startLoad() {
    if (_disposed || !_visible || _loading || !_pending) return;
    _pending = false;
    _loading = true;
    _lastRequestAt = DateTime.now();
    unawaited(_runLoad());
  }

  Future<void> _runLoad() async {
    try {
      await load();
    } finally {
      _loading = false;
      if (!_disposed && _visible) {
        // Schedule the next automatic refresh, including after no-fill.
        _pending = true;
        _scheduleOrLoad();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
