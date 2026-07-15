import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'closeout_worker.dart';
import 'worker_config.dart';

typedef IdentityTokenProvider = Future<String> Function(Uri audience);

final class WorkDispatchOutcome {
  const WorkDispatchOutcome.success(this.result) : error = null;
  const WorkDispatchOutcome.failure(this.error) : result = null;

  final WorkResult? result;
  final Object? error;

  bool get isSuccess => result != null;
}

abstract interface class WorkRoundDispatcher {
  Future<List<WorkDispatchOutcome>> dispatchRound({
    required Uri workerBaseUrl,
    required String workToken,
    required int requestCount,
  });
}

final class CloudRunWorkRoundDispatcher implements WorkRoundDispatcher {
  CloudRunWorkRoundDispatcher({
    HttpClient? httpClient,
    IdentityTokenProvider? identityTokenProvider,
  }) : _httpClient = httpClient ?? HttpClient(),
       _identityTokenProvider =
           identityTokenProvider ?? _googleIdentityTokenFor;

  final HttpClient _httpClient;
  final IdentityTokenProvider _identityTokenProvider;

  @override
  Future<List<WorkDispatchOutcome>> dispatchRound({
    required Uri workerBaseUrl,
    required String workToken,
    required int requestCount,
  }) async {
    String identityToken;
    try {
      identityToken = await _identityTokenProvider(workerBaseUrl);
    } catch (error) {
      return List<WorkDispatchOutcome>.filled(
        requestCount,
        WorkDispatchOutcome.failure(error),
      );
    }

    final workUrl = workerBaseUrl.resolve('/work');
    return Future.wait(
      List<Future<WorkDispatchOutcome>>.generate(
        requestCount,
        (_) => _invokeWork(
          workUrl: workUrl,
          workToken: workToken,
          identityToken: identityToken,
        ),
      ),
    );
  }

  Future<WorkDispatchOutcome> _invokeWork({
    required Uri workUrl,
    required String workToken,
    required String identityToken,
  }) async {
    try {
      final request = await _httpClient.postUrl(workUrl);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $identityToken')
        ..set('X-Work-Token', workToken)
        ..contentType = ContentType.json;
      request.write('{}');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return WorkDispatchOutcome.failure(
          HttpException(
            'Work request failed with status ${response.statusCode}: $body',
            uri: workUrl,
          ),
        );
      }
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Work response must be a JSON object.');
      }
      return WorkDispatchOutcome.success(_workResultFromJson(json));
    } catch (error) {
      return WorkDispatchOutcome.failure(error);
    }
  }
}

Handler buildWorkerHandler(
  CloseoutWorker worker,
  WorkerConfig config, {
  WorkRoundDispatcher? dispatcher,
}) {
  final workDispatcher = dispatcher ?? CloudRunWorkRoundDispatcher();
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
    if (request.method == 'POST' &&
        const {'work', 'dispatch'}.contains(request.url.path)) {
      if (!_isAuthorized(request, config.workToken)) {
        return _jsonResponse(403, {'error': 'internal authorization required'});
      }
      if (request.url.path == 'work') {
        try {
          final result = await worker.workOnce();
          return _jsonResponse(200, result.toJson());
        } on StateError catch (error) {
          return _jsonResponse(409, {'error': '$error'});
        }
      }
      return _dispatch(workDispatcher, config);
    }
    return _jsonResponse(404, {'error': 'not found'});
  };
}

Future<Response> _dispatch(
  WorkRoundDispatcher dispatcher,
  WorkerConfig config,
) async {
  final workerBaseUrl = config.workerBaseUrl;
  if (workerBaseUrl == null) {
    return _jsonResponse(503, {'error': 'WORKER_BASE_URL is required'});
  }
  final workToken = config.workToken;
  if (workToken == null) {
    return _jsonResponse(503, {'error': 'WORK_TRIGGER_TOKEN is required'});
  }

  var rounds = 0;
  var requests = 0;
  var requestFailures = 0;
  var successfulRequests = 0;
  var claimed = 0;
  var completed = 0;
  var failed = 0;
  var recovered = 0;
  int? remaining;

  for (var round = 0; round < config.dispatchMaxRounds; round++) {
    rounds++;
    final outcomes = await dispatcher.dispatchRound(
      workerBaseUrl: workerBaseUrl,
      workToken: workToken,
      requestCount: config.dispatchConcurrency,
    );
    requests += outcomes.length;
    requestFailures += outcomes.where((outcome) => !outcome.isSuccess).length;
    final results = outcomes
        .where((outcome) => outcome.isSuccess)
        .map((outcome) => outcome.result!)
        .toList();
    successfulRequests += results.length;

    for (final result in results) {
      claimed += result.claimed;
      completed += result.completed;
      failed += result.failed;
      recovered += result.recovered;
    }
    final roundRemaining = results.isEmpty
        ? null
        : results
              .map((result) => result.remaining)
              .reduce((left, right) => left < right ? left : right);
    if (roundRemaining != null) remaining = roundRemaining;

    final allRequestsSucceeded = results.length == outcomes.length;
    final everyResponseClaimedZero =
        allRequestsSucceeded && results.every((result) => result.claimed == 0);
    if (everyResponseClaimedZero || roundRemaining == 0) {
      break;
    }
  }

  if (successfulRequests == 0) {
    return _jsonResponse(502, {
      'rounds': rounds,
      'requests': requests,
      'request_failures': requestFailures,
      'error': 'All dispatched work requests failed.',
    });
  }

  return _jsonResponse(200, {
    'rounds': rounds,
    'requests': requests,
    'request_failures': requestFailures,
    'claimed': claimed,
    'completed': completed,
    'failed': failed,
    'recovered': recovered,
    'remaining': remaining!,
  });
}

bool _isAuthorized(Request request, String? expected) {
  final schedulerToken = request.headers['x-work-token'];
  final supplied =
      schedulerToken ?? _bearerToken(request.headers['authorization']);
  return expected != null && supplied == expected;
}

String? _bearerToken(String? authorization) {
  if (authorization == null) return null;
  final match = RegExp(
    r'^Bearer\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(authorization.trim());
  return match?.group(1);
}

WorkResult _workResultFromJson(Map<String, dynamic> json) => WorkResult(
  claimed: _jsonInteger(json, 'claimed'),
  completed: _jsonInteger(json, 'completed'),
  failed: _jsonInteger(json, 'failed'),
  recovered: _jsonInteger(json, 'recovered'),
  remaining: _jsonInteger(json, 'remaining'),
);

int _jsonInteger(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('Work response field $key must be numeric.');
  }
  return value.toInt();
}

Response _jsonResponse(int statusCode, Object body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

Future<String> _googleIdentityTokenFor(Uri audience) async {
  final metadataUrl = Uri.http(
    'metadata.google.internal',
    '/computeMetadata/v1/instance/service-accounts/default/identity',
    {'audience': audience.toString(), 'format': 'full'},
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(metadataUrl);
    request.headers.set('Metadata-Flavor', 'Google');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Google identity token request failed with status '
        '${response.statusCode}: $body',
        uri: metadataUrl,
      );
    }
    final token = body.trim();
    if (token.isEmpty) {
      throw const FormatException('Google identity token was empty.');
    }
    return token;
  } finally {
    client.close(force: true);
  }
}
