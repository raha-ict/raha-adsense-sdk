import 'package:flutter/foundation.dart';

/// Compares the scalar and list values allowed in publisher signal maps.
bool samePublisherSignals(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key)) return false;
    final leftValue = entry.value;
    final rightValue = right[entry.key];
    if (leftValue is List && rightValue is List) {
      if (!listEquals(leftValue, rightValue)) return false;
    } else if (leftValue != rightValue) {
      return false;
    }
  }
  return true;
}
