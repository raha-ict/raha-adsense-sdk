import 'package:uuid/uuid.dart';

final Uuid _uuid = const Uuid();

final class RahaAdRequestLogContext {
  RahaAdRequestLogContext({
    required this.requestId,
    required this.requestSource,
    required this.trigger,
    this.widgetInstanceId,
    this.visibleFraction,
  });

  factory RahaAdRequestLogContext.manual(String requestSource) =>
      RahaAdRequestLogContext(
        requestId: _uuid.v4(),
        requestSource: requestSource,
        trigger: 'explicit',
      );

  final String requestId;
  final String requestSource;
  final String trigger;
  final String? widgetInstanceId;
  final double? visibleFraction;

  String fields({
    required String placementId,
    required String format,
    required String visitorIdHash,
  }) {
    final widget =
        widgetInstanceId == null ? '' : ' widgetInstanceId=$widgetInstanceId';
    final fraction =
        visibleFraction == null ? '' : ' visibleFraction=$visibleFraction';
    return 'requestId=$requestId placementId=$placementId format=$format '
        'visitorIdHash=$visitorIdHash$widget requestSource=$requestSource '
        'trigger=$trigger$fraction';
  }
}
