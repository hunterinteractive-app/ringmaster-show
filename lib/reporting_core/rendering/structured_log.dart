import 'dart:convert';

typedef LogSink = void Function(String line);

final class StructuredLog {
  StructuredLog({required this.workerId, LogSink? sink}) : sink = sink ?? print;

  final String workerId;
  final LogSink sink;

  void event(String event, [Map<String, Object?> fields = const {}]) {
    sink(
      jsonEncode(<String, Object?>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'event': event,
        'worker_id': workerId,
        ...fields,
      }),
    );
  }
}
