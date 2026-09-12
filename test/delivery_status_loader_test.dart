import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/delivery_status_loader.dart';

void main() {
  test(
    'delivery screen reads all 6370 artifacts and 2528 exhibitors under a lower API cap',
    () async {
      String id(int i) =>
          '94000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
      final client = SupabaseClient(
        'http://fixture.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.toString().length, lessThan(8000));
          final offset = int.parse(request.url.queryParameters['offset']!);
          List<Map<String, dynamic>> all;
          if (request.url.path.endsWith('/show_report_artifacts')) {
            all = List.generate(
              6370,
              (i) => {
                'id': id(i),
                'metadata': {'exhibitor_id': id(i % 2528)},
              },
            );
          } else if (request.url.path.endsWith('/show_email_deliveries')) {
            all = List.generate(
              3321,
              (i) => {'id': id(i), 'artifact_id': id(i)},
            );
          } else {
            final ids = request.url.queryParameters['id']!
                .substring(4)
                .replaceAll(')', '')
                .replaceAll('"', '')
                .split(',');
            expect(ids.length, lessThanOrEqualTo(100));
            all = ids
                .map((id) => {'id': id, 'email': '$id@example.invalid'})
                .toList();
          }
          return http.Response(
            jsonEncode(all.skip(offset).take(37).toList()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await loadDeliveryStatus(client, 'show');
      expect(result.artifacts, hasLength(6370));
      expect(result.deliveries, hasLength(3321));
      expect(result.exhibitors.map((e) => e['id']).toSet(), hasLength(2528));
    },
  );
}
