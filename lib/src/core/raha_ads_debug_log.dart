import 'package:flutter/foundation.dart';

int _widgetInstanceSequence = 0;

String nextRahaWidgetInstanceId() => 'w${++_widgetInstanceSequence}';

void rahaAdsDebugLog(String message) {
  debugPrint('[RAHA_ADS] ${DateTime.now().toIso8601String()} $message');
}
