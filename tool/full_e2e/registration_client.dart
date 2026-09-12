// Exercise the application's actual registration write implementation locally.
// Credentials are read from stdin and never included in output or command args.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/services/registration_write.dart';

class LostResponseClient extends http.BaseClient {
  final http.Client inner = http.Client();
  bool loseNextInsert;
  int posts = 0;
  LostResponseClient(this.loseNextInsert);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') posts++;
    final response = await inner.send(request);
    if (loseNextInsert &&
        request.method == 'POST' &&
        response.statusCode < 300) {
      loseNextInsert = false;
      await response.stream.drain<void>();
      throw http.ClientException('Injected lost response after real commit');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final url = Uri.parse(input['url'] as String);
  if (url.scheme != 'http' || !['127.0.0.1', 'localhost'].contains(url.host)) {
    throw StateError('This probe requires a local synthetic API.');
  }
  final transport = LostResponseClient(input['lose_response'] == true);
  final client = SupabaseClient(
    input['url'],
    input['anon'],
    accessToken: () async => input['token'] as String,
    httpClient: transport,
  );
  final results = <Map<String, dynamic>>[];
  try {
    for (final batch in input['batches'] as List) {
      final rows = (batch['rows'] as List).cast<Map<String, dynamic>>();
      final saved = await insertRegistrationRows(client, batch['table'], rows);
      results.add({
        'table': batch['table'],
        'ids': saved.map((r) => r['id']).toList(),
      });
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'results': results,
        'post_attempts': transport.posts,
      }),
    );
  } finally {
    await client.dispose();
    transport.close();
  }
}
