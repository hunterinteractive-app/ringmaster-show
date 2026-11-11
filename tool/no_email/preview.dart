import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/closeout/widgets/manual_report_delivery_panel.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

// Local-only fixture: never connects to production or sends email.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final deliveries = <Map<String, dynamic>>[];
  const generation = 1;
  const missingContact = false;
  final pdf = pw.Document();
  for (final title in ['Sample Exhibitor Report', 'Sample Leg Certificate']) {
    pdf.addPage(
      pw.Page(
        build: (_) => pw.Column(
          children: [
            pw.Text(title),
            pw.Text('Offline Exhibitor — local test data'),
          ],
        ),
      ),
    );
  }
  final fixturePdf = await pdf.save();
  // This executable is an isolated test fixture, not a production entrypoint.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://fixture.invalid',
    anonKey: 'test',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
    httpClient: MockClient((request) async {
      final path = request.url.path.split('/').last;
      if (path == 'fixture.pdf') {
        return http.Response.bytes(
          fixturePdf,
          200,
          request: request,
          headers: {'content-type': 'application/pdf'},
        );
      }
      calls.add(path);
      Object? value;
      if (path == 'show_report_artifacts') {
        value = [
          for (final id in ['noemail', 'online'])
            for (final type in ['exhibitor_report', 'legs'])
              {
                'id': '$id-$type',
                'report_name': type,
                'artifact_status': 'generated',
                'generation': generation,
                'is_current': true,
                'metadata': {
                  'exhibitor_id': id,
                  'exhibitor_email': 'old@example.test',
                },
                'section_ids': ['section'],
              },
        ];
      } else if (path == 'exhibitors') {
        value = [
          if (!missingContact)
            {
              'id': 'noemail',
              'showing_name': 'Offline Exhibitor',
              'email': null,
              'address_line1': '1 Test Street',
              'city': 'Town',
              'state': 'IN',
              'zip': '46000',
            },
          {
            'id': 'online',
            'showing_name': 'Online Exhibitor',
            'email': 'fixture@example.test',
          },
        ];
      } else if (path == 'report_manual_deliveries') {
        value = deliveries;
      } else if (path == 'queue_manual_report_print_pack') {
        value = 'pack';
      } else if (path == 'exhibitor_print_packs') {
        value = {
          'id': 'pack',
          'artifact_status': 'generated',
          'file_name': 'packet.pdf',
          'storage_bucket': 'show-files',
          'storage_path': 'fixture.pdf',
        };
      } else if (path == 'mark_report_manual_delivery') {
        final body = jsonDecode(request.body) as Map;
        deliveries.clear();
        if (body['p_method'] != 'pending') {
          for (final a in body['p_artifacts']) {
            deliveries.add({
              'artifact_id': a['id'],
              'generation': a['generation'],
              'method': body['p_method'],
            });
          }
        }
      } else {
        throw StateError('Unexpected request: $path');
      }
      return http.Response(
        jsonEncode(value),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  runApp(
    MaterialApp(
      theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('LOCAL TEST — no emails or production changes'),
        ),
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showManualReportDelivery(
                context,
                showId: 'show',
                beforeEmail: true,
              ),
              child: const Text('Review print/mail reports'),
            ),
          ),
        ),
      ),
    ),
  );
}
