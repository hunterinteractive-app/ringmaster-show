import 'dart:async';
import 'package:ringmaster_show/reporting_core/rendering/render_isolate.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_task.dart';
import 'package:test/test.dart';

Future<int> _spin() async {
  while (true) {}
}

Future<int> _answer() async => 42;
Future<int> _badLayout() async => throw StateError('bad layout');

void main() {
  test(
    'CPU-bound layout is killed while the worker timer stays responsive',
    () async {
      var beats = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => beats++,
      );
      try {
        await expectLater(
          runInRenderIsolate(_spin, timeout: const Duration(milliseconds: 150)),
          throwsA(
            isA<RenderFailure>().having(
              (e) => e.category,
              'category',
              'render_timeout',
            ),
          ),
        );
        expect(beats, greaterThan(1));
        expect(
          await runInRenderIsolate(
            _answer,
            timeout: const Duration(seconds: 5),
          ),
          42,
        );
      } finally {
        timer.cancel();
      }
    },
  );
  test(
    'builder exceptions cross the isolate boundary as permanent failures',
    () async {
      await expectLater(
        runInRenderIsolate(_badLayout, timeout: const Duration(seconds: 5)),
        throwsA(
          isA<RenderFailure>()
              .having((e) => e.retryable, 'retryable', false)
              .having(
                (e) => e.diagnostic,
                'diagnostic',
                contains('bad layout'),
              ),
        ),
      );
    },
  );
}
