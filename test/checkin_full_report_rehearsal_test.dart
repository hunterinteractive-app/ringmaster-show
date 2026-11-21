// Opt-in rehearsal using a read-only database snapshot. No live writes/emails.
// Exercises the actual screen, pagination, enrichment, fonts, and PDF builder.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/print_packs/check_in_generator_sheet.dart';

class _SaveDialog extends FileSelectorPlatform {
  _SaveDialog(this.path);
  final String path;
  bool saved = false;
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saved = true;
    return FileSaveLocation(path);
  }
}

void main() {
  final fixturePath = Platform.environment['CHECKIN_REPORT_FIXTURE'];
  testWidgets(
    'full combined check-in PDF from database snapshot',
    (tester) async {
      final fixture = jsonDecode(File(fixturePath!).readAsStringSync()) as Map;
      final show = (fixture['show'] as List).single as Map;
      final report = List<Map<String, dynamic>>.from(fixture['report'] as List)
        ..sort(
          (a, b) =>
              (a['entry_id'] as String).compareTo(b['entry_id'] as String),
        );
      final output = Platform.environment['CHECKIN_REPORT_OUTPUT']!;
      final dialog = _SaveDialog(output);
      FileSelectorPlatform.instance = dialog;
      SharedPreferences.setMockInitialValues({});
      var reportReads = 0;
      var rowsRead = 0;
      await tester.runAsync(
        () => Supabase.initialize(
          url: 'https://fixture.invalid',
          anonKey: 'fixture',
          authOptions: const FlutterAuthClientOptions(
            localStorage: EmptyLocalStorage(),
            detectSessionInUri: false,
            autoRefreshToken: false,
          ),
          httpClient: MockClient((request) async {
            final endpoint = request.url.pathSegments.last;
            dynamic result;
            List<Map<String, dynamic>>? rows;
            switch (endpoint) {
              case 'get_show_wave_schedule':
                result = fixture['wave'];
              case 'shows':
                result = show;
              case 'report_checkin_entries':
                final params = jsonDecode(request.body) as Map;
                expectSync(params['p_show_id'], show['id']);
                expectSync(params['p_section_id'], isNull);
                expectSync(params['p_include_scratched'], false);
                rows = report;
                reportReads++;
              case 'exhibitors':
                rows = List<Map<String, dynamic>>.from(
                  fixture['exhibitors'] as List,
                );
              case 'entries':
                rows = List<Map<String, dynamic>>.from(
                  fixture['entries'] as List,
                );
              case 'show_animal_coop_numbers':
                rows = List<Map<String, dynamic>>.from(fixture['coop'] as List);
              default:
                fail('Unexpected request: ${request.method} $endpoint');
            }
            if (rows != null) {
              final query = request.url.queryParameters;
              for (final key in ['id', 'animal_id']) {
                final filter = query[key];
                if (filter != null && filter.startsWith('in.(')) {
                  final ids = filter
                      .substring(4, filter.length - 1)
                      .replaceAll('"', '')
                      .split(',')
                      .toSet();
                  rows = rows!.where((r) => ids.contains(r[key])).toList();
                }
              }
              final offset = int.parse(query['offset'] ?? '0');
              final limit = int.parse(query['limit'] ?? '1000');
              result = rows!.skip(offset).take(limit).toList();
              if (endpoint == 'report_checkin_entries') {
                rowsRead += (result as List).length;
              }
            }
            return http.Response(
              jsonEncode(result),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      addTearDown(() => Supabase.instance.dispose());
      await tester.runAsync(() async {
        expect(
          await Supabase.instance.client.rpc('get_show_wave_schedule'),
          fixture['wave'],
        );
      });
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckInGeneratorSheet(
              showId: show['id'] as String,
              showName: show['name'] as String,
              sections: List<Map<String, dynamic>>.from(
                fixture['sections'] as List,
              ),
              sectionId: null,
              sectionLabel: 'All Shows (Open/Youth A/B/...)',
              includeScratched: false,
              combineSections: true,
              pairOpenYouthByLetter: false,
              youthFirst: false,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last name'));
      await tester.pumpAndSettle();
      final target = find.ancestor(
        of: find.text('Generate PDF'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      final callback = tester.widget<ButtonStyleButton>(target).onPressed;
      expect(
        callback,
        isNotNull,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('\n'),
      );
      final timer = Stopwatch()..start();
      var complete = false;
      final work = Function.apply(callback!, const []);
      if (work is Future) {
        work.whenComplete(() => complete = true);
      } else {
        complete = true;
      }
      while (!complete && timer.elapsed < const Duration(minutes: 5)) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();
      final messages = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(dialog.saved, true, reason: messages.join('\n'));
      expect(File(output).lengthSync(), greaterThan(1000));
      expect(rowsRead, report.length);
      expect(reportReads, greaterThan(1));
      File('$output.rehearsal.json').writeAsStringSync(
        jsonEncode({
          'entries': rowsRead,
          'exhibitors': report.map((r) => r['exhibitor_id']).toSet().length,
          'report_page_requests': reportReads,
          'elapsed_ms': timer.elapsedMilliseconds,
          'bytes': File(output).lengthSync(),
        }),
      );
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
