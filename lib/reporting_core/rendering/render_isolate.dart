import 'dart:async';
import 'dart:isolate';

import 'render_task.dart';

/// A real cancellation boundary for synchronous layouts, including AOT builds.
/// Future.timeout alone cannot interrupt a CPU-bound PDF on the worker isolate.
Future<T> runInRenderIsolate<T>(
  Future<T> Function() build, {
  required Duration timeout,
}) async {
  final port = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      _render<T>,
      (port.sendPort, build),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final message = await port.first.timeout(
      timeout,
      onTimeout: () {
        throw const RenderFailure.permanent(
          'render_timeout',
          'The report layout exceeded its time limit. Please review the report.',
          'The isolated PDF builder was terminated after its deadline.',
        );
      },
    );
    if (message is _RenderSuccess<T>) return message.value;
    if (message is _RenderError) {
      throw RenderFailure.permanent(
        'pdf_build_error',
        'The report layout could not be built.',
        message.diagnostic,
      );
    }
    throw RenderFailure.permanent(
      'render_isolate_exit',
      'The report builder stopped unexpectedly.',
      '$message',
    );
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

Future<void> _render<T>((SendPort, Future<T> Function()) request) async {
  try {
    Isolate.exit(request.$1, _RenderSuccess<T>(await request.$2()));
  } catch (error, stack) {
    Isolate.exit(request.$1, _RenderError('$error\n$stack'));
  }
}

class _RenderSuccess<T> {
  _RenderSuccess(this.value);
  final T value;
}

class _RenderError {
  _RenderError(this.diagnostic);
  final String diagnostic;
}
