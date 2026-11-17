import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final writes = <Map<String, dynamic>>[];
  final rpcs = <String>[];
  final uploads = <List<int>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object? body = [];
        if (path.contains('/storage/v1/object/')) {
          uploads.add(request.bodyBytes);
          body = {'Key': path};
        } else if (path.endsWith('/show_report_artifacts') &&
            request.method == 'POST') {
          final inserted = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          writes.add(inserted);
          body = {...inserted, 'id': 'artifact-1'};
        } else if (path.endsWith('/show_report_artifacts') &&
            request.method == 'PATCH') {
          writes.add(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
        } else if (path.endsWith('/shows')) {
          body = {
            'id': 'show-1',
            'name': 'Synthetic Show',
            'created_by': 'owner',
            'is_locked': false,
            'finalized_at': null,
            'start_date': '2026-11-17',
            'end_date': '2026-11-17',
          };
        } else if (path.endsWith('/show_sections')) {
          body = [
            {
              'id': 'section-1',
              'show_id': 'show-1',
              'kind': 'open',
              'letter': 'A',
              'is_enabled': true,
              'sort_order': 1,
            },
          ];
        } else if (path.endsWith('/show_arba_report_details')) {
          body = null;
        } else if (path.contains('/rpc/')) {
          rpcs.add(path.split('/').last);
          if (path.contains('can_access')) body = false;
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  for (final report in [
    'unpaid_balances_report',
    'paid_exhibitor_report',
    'entered_exhibitors_contact_report',
    'ribbon_payout_report',
    'payback_report',
    'judge_report',
    'breed_judged_totals_report',
  ]) {
    testWidgets('$report generates a PDF without a closeout run', (
      tester,
    ) async {
      writes.clear();
      rpcs.clear();
      uploads.clear();
      SharedPreferences.setMockInitialValues({
        'closeout_v2_report_selection_show-1': jsonEncode({
          'group': 'other',
          'report_name': report,
        }),
      });
      tester.view.physicalSize = const Size(1600, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ShowCloseoutV2PreviewPage(
            showId: 'show-1',
            showName: 'Synthetic Show',
            canFinalizeShow: true,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final generate = find.text('Generate Selected Report');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (writes.any(
          (row) => ['generated', 'failed'].contains(row['artifact_status']),
        )) {
          break;
        }
      }
      expect(writes.first['report_name'], report);
      expect(writes.first['finalize_run_id'], isNull);
      expect(writes.first['metadata']['operational_report'], true);
      expect(
        writes.where((row) => row['artifact_status'] == 'failed'),
        isEmpty,
        reason: '$writes',
      );
      expect(
        writes.any((row) => row['artifact_status'] == 'generated'),
        true,
        reason: '$writes',
      );
      expect(uploads, isNotEmpty);
      expect(latin1.decode(uploads.single), contains('%PDF-'));
      expect(latin1.decode(uploads.single), contains('%%EOF'));
      expect(
        rpcs.where(
          (rpc) => rpc.contains('finalize') || rpc.contains('requeue'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
