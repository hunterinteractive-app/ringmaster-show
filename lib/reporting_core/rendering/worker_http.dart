import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'closeout_worker.dart';
import 'worker_config.dart';

Handler buildWorkerHandler(CloseoutWorker worker, WorkerConfig config) {
  return (request) async {
    if (request.method == 'GET' && request.url.path == 'health') {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'version': config.buildVersion,
          'worker_id': config.workerId,
          'working': worker.isWorking,
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && request.url.path == 'work') {
      final expected = config.workToken;
      final schedulerToken = request.headers['x-work-token'];
      final supplied =
          schedulerToken ?? _bearerToken(request.headers['authorization']);
      if (expected == null || supplied != expected) {
        return Response.forbidden(
          jsonEncode({'error': 'internal authorization required'}),
          headers: {'content-type': 'application/json'},
        );
      }
      try {
        final result = await worker.workOnce();
        return Response.ok(
          jsonEncode(result.toJson()),
          headers: {'content-type': 'application/json'},
        );
      } on StateError catch (error) {
        return Response(409, body: jsonEncode({'error': '$error'}));
      }
    }
    return Response.notFound(jsonEncode({'error': 'not found'}));
  };
}

String? _bearerToken(String? authorization) {
  if (authorization == null) return null;
  final match = RegExp(
    r'^Bearer\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(authorization.trim());
  return match?.group(1);
}
