import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/entries_by_breed_section_table.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final sections = [
    for (final kind in ['open', 'youth'])
      for (final letter in ['A', 'B', 'C', 'D'])
        {'id': '$kind-$letter', 'kind': kind, 'letter': letter},
  ];
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Roboto')
      ..addFont(
        File(
          'assets/fonts/NotoSans-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
    if (const bool.fromEnvironment('BREED_COUNTS_SCREENSHOTS')) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await iconLoader.load();
    }
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'sections': sections,
            'rows': [
              for (final breed in [
                'American Chinchilla',
                'Mini Rex',
                'Netherland Dwarf',
                'Rex',
              ])
                for (final section in sections)
                  for (var i = 0; i < 3; i++)
                    {
                      'entry_id': '$breed-${section['id']}-$i',
                      'section_id': section['id'],
                      'exhibitor_id': 'ex$i',
                      'species': 'rabbit',
                      'breed': breed,
                      'variety': 'Black',
                      'class_name': 'Senior',
                      'sex': i == 0 ? 'Doe' : 'Buck',
                    },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final config in [
    (320.0, 568.0, 1.0, false),
    (390.0, 844.0, 1.0, false),
    (430.0, 932.0, 1.0, false),
    (320.0, 568.0, 1.5, true),
    (1280.0, 900.0, 1.0, true),
  ]) {
    testWidgets(
      'breed counts scroll at ${config.$1}px scale ${config.$3} exports ${config.$4}',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, config.$2);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(config.$3)),
                child: Column(
                  children: [
                    Expanded(child: child!),
                    const Material(
                      color: AppColors.surface,
                      child: SizedBox(
                        height: 24,
                        child: Center(
                          child: Text(
                            'Version 1.00.44',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text(
                              'Breed Counts - Southern Adirondack',
                            ),
                          ),
                          body: EntriesByBreedSectionTable(
                            showId: 'fixture',
                            showName: 'Southern Adirondack',
                            title: 'Breed Counts',
                            showExportButton: config.$4,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open counts'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open counts'));
        await tester.runAsync(() async {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Entry Totals'), findsOneWidget);
        expect(find.text('96 entries · 3 exhibitors'), findsOneWidget);
        if (config.$1 < 600) {
          final totals = tester.widget<ExpansionTile>(
            find
                .ancestor(
                  of: find.text('Entry Totals'),
                  matching: find.byType(ExpansionTile),
                )
                .first,
          );
          expect(totals.initiallyExpanded, isFalse);
        }
        Future<void> capture(String suffix) async {
          if (!const bool.fromEnvironment('BREED_COUNTS_SCREENSHOTS')) return;
          await tester.runAsync(() async {
            final image =
                await (captureKey.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final dir = Directory('/tmp/ringmaster-jennifer-review')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/phone-${config.$1.toInt()}-${config.$3}-$suffix.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('initial');
        await tester.ensureVisible(find.text('American Chinchilla'));
        await tester.tap(find.text('American Chinchilla'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Black').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Black').first);
        await tester.pumpAndSettle();
        final table = find.byType(DataTable).first;
        await tester.ensureVisible(table);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Header and summary must scroll away, leaving the viewport for details.
        if (config.$1 < 600) {
          expect(find.text('Entry Totals').hitTestable(), findsNothing);
        }
        expect(find.text('Age / Sex Class'), findsWidgets);
        await capture('expanded');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
