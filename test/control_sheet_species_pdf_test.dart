@TestOn('vm')
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/screens/admin/print_packs/control_sheets_generator_sheet.dart';
import 'package:ringmaster_show/screens/admin/print_packs/print_pack_pdf_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://control-sheet-fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final combined in [false, true]) {
    for (final bubble in [false, true]) {
      testWidgets('species stay separate in PDF: paired=$combined bubble=$bubble', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ControlSheetsGeneratorSheet(
                showId: '00000000-0000-0000-0000-000000000001',
                showName: 'Control Sheet Order Test',
                sections: const [],
                sectionId: 'open-A',
                sectionIds: const ['open-A'],
                sectionLabel: 'Open A',
                includeScratched: false,
                combineSections: combined,
                youthFirst: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Deliberately interleave species, reverse cavy SOP order, and give
        // American rabbits/cavies the exact same variety, class and sex.
        final rows = <Map<String, dynamic>>[
          for (final (i, species, breed) in [
            (1, 'cavy', 'Teddy'),
            (2, 'rabbit', 'Rex'),
            (3, 'cavy', 'Texel'),
            (4, 'cavy', 'American'),
            (5, 'rabbit', 'American'),
            (6, 'cavy', 'Abyssinian'),
          ])
            for (final section in combined ? ['B', 'A'] : ['A'])
              {
                'entry_id':
                    '00000000-0000-0000-0000-0000000000$i${section == 'A' ? 1 : 2}',
                'exhibitor_id': 'exhibitor-$i',
                'section_id':
                    '00000000-0000-0000-0000-00000000000${section == 'A' ? 2 : 3}',
                'section_kind': 'open',
                'section_letter': section,
                'section_name': 'Open $section',
                'section_sort_order': section == 'A' ? 0 : 1,
                'species': species,
                'breed': breed,
                'variety': 'Black',
                'class_name': 'Senior',
                'sex': 'Buck',
                'tattoo': 'T$i',
                'coop_number': '$i',
                'judge_name': 'Sample Judge',
              },
        ];
        final dynamic state = tester.state(
          find.byType(ControlSheetsGeneratorSheet),
        );
        final pw.Document document = state.buildPdf(
          rows,
          await buildPrintPackPdfTheme(),
          includeQrCode: false,
          bubbleSheet: bubble,
          cavySopSortMap: <String, Map<String, int>>{},
        );
        final bytes = await tester.runAsync(document.save);
        expect(bytes, isNotNull);
        expect(bytes!.length, greaterThan(1000));
        // A merged American group would reduce this count by one per section.
        expect(document.document.pdfPageList.pages.length, combined ? 12 : 6);
        final output = Platform.environment['CONTROL_SHEET_PDF_OUTPUT'];
        if (output != null) {
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            await File(
              '$output/paired-$combined-bubble-$bubble.pdf',
            ).writeAsBytes(bytes);
          });
        }
      });
    }
  }
}
