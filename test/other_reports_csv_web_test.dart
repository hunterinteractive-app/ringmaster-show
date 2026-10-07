@TestOn('browser')
library;

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';
import 'package:ringmaster_show/utils/csv_exporter.dart';
import 'package:ringmaster_show/services/show_addon_report_service.dart';

void main() {
  test(
    'browser download receives actual UTF-8 bytes and suggested CSV name',
    () async {
      final received = Completer<(String, Uint8List)>();
      final subscription = html.document.onClick.listen((event) {
        final anchor = event.target;
        if (anchor is! html.AnchorElement ||
            anchor.download?.endsWith('.csv') != true) {
          return;
        }
        event.preventDefault();
        html.HttpRequest.request(
          anchor.href!,
          responseType: 'arraybuffer',
        ).then((response) {
          received.complete((
            anchor.download!,
            (response.response as ByteBuffer).asUint8List(),
          ));
        }, onError: received.completeError);
      });
      try {
        final bytes = utf8.encode('\ufeff"Name"\r\n"Zoë, Hunter"\r\n');
        await exportCsvBytes(bytes: bytes, suggestedName: 'Test Report.csv');
        final result = await received.future.timeout(
          const Duration(seconds: 5),
        );
        expect(result.$1, 'Test Report.csv');
        expect(result.$2, bytes);
      } finally {
        await subscription.cancel();
      }
    },
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'closeout_v2_report_selection_show1': jsonEncode({
        'group': 'other',
        'report_name': 'entered_exhibitors_contact_report',
      }),
    });
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'anon',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object? value = [];
        if (path.endsWith('/shows')) {
          value = {
            'id': 'show1',
            'name': 'Show',
            'created_by': 'ordinary-secretary',
          };
        } else if (path.endsWith('can_access_exhibitor_print_pack')) {
          value = false;
        }
        return http.Response(
          jsonEncode(value),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  testWidgets('ordinary report users see CSV without the restricted features', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ShowCloseoutV2PreviewPage(
          showId: 'show1',
          showName: 'Show',
          canFinalizeShow: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final csv = find.byKey(const ValueKey('other-reports-download-csv'));
    expect(csv, findsOneWidget);
    expect(tester.widget<OutlinedButton>(csv).onPressed, isNotNull);
    expect(find.text('Download PDF'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final reportName in ShowAddonReportService.reportNames) {
    testWidgets(
      '$reportName downloads before finalization or any report artifacts',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'closeout_v2_report_selection_show1': jsonEncode({
            'group': 'other',
            'report_name': reportName,
          }),
        });
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(
            home: ShowCloseoutV2PreviewPage(
              showId: 'show1',
              showName: 'Show',
              canFinalizeShow: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final csv = find.byKey(const ValueKey('other-reports-download-csv'));
        final pdf = find.byKey(const ValueKey('other-reports-download-pdf'));
        expect(tester.widget<OutlinedButton>(csv).onPressed, isNotNull);
        expect(tester.widget<OutlinedButton>(pdf).onPressed, isNotNull);
        expect(find.textContaining('Available at any time.'), findsOneWidget);
        expect(find.text('Generate Selected Report'), findsNothing);
        expect(
          find.text('Optional message from the show secretary'),
          findsNothing,
        );
        final downloads = <String>[];
        final subscription = html.document.onClick.listen((event) {
          final target = event.target;
          if (target is html.AnchorElement &&
              target.download?.endsWith('.csv') == true) {
            event.preventDefault();
            downloads.add(target.download!);
          }
        });
        try {
          await tester.ensureVisible(csv);
          await tester.tap(csv);
          await tester.pumpAndSettle();
          expect(downloads, [
            '${ShowAddonReportService.title(reportName)} - Show.csv',
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.runAsync(subscription.cancel);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
