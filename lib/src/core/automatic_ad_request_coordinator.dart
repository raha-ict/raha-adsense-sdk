import 'package:clock/clock.dart';

/// Enforces an in-memory automatic request interval across widget States.
final class AutomaticAdRequestCoordinator {
  final Map<String, DateTime> _lastRequestAt = <String, DateTime>{};

  /// Returns null and records the slot when eligible, otherwise the wait.
  Duration? tryAcquire(String placementId, Duration interval) {
    final now = clock.now();
    final last = _lastRequestAt[placementId];
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < interval) return interval - elapsed;
    }
    _lastRequestAt[placementId] = now;
    return null;
  }
}
