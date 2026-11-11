import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/print_packs/print_reports_menu.dart';
import 'package:ringmaster_show/screens/admin/print_packs/print_reports_service.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_mailing_labels_loader.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Widget page(Widget menu) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: RingMasterPageShell(
      title: 'RingMaster One Show',
      subtitle: 'Print Show Sheets - Sample Show',
      showHomeButton: true,
      actions: [
        menu,
        IconButton(
          tooltip: 'Reload sections',
          onPressed: () {},
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: const Text('Control Sheets'),
    ),
  );

  for (final width in [390.0, 1200.0]) {
    testWidgets('banner reports filter and download at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PrintReport? selected;
      final pending = Completer<void>();
      await tester.pumpWidget(
        page(
          PrintReportsMenu(
            load: () async => const PrintReportAvailability(
              reports: {PrintReport.unpaid, PrintReport.numbers},
            ),
            download: (r, m, s) {
              selected = r;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.text('Unpaid Exhibitor Balance'), findsOneWidget);
      expect(find.text('Paid Exhibitor Report'), findsNothing);
      expect(find.text('Contest Registrations'), findsNothing);
      final text = tester.widget<Text>(find.text('Unpaid Exhibitor Balance'));
      expect(text.style!.color, AppColors.text);
      await tester.tap(find.text('Unpaid Exhibitor Balance'));
      await tester.pump();
      expect(selected, PrintReport.unpaid);
      expect(find.text('Preparing…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      pending.complete();
      await tester.pumpAndSettle();
    });
  }
  testWidgets('label options are readable on phone and preserve selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MailingLabelMode? selected;
    await tester.pumpWidget(
      page(
        PrintReportsMenu(
          load: () async => const PrintReportAvailability(
            reports: {PrintReport.labels},
            labelModes: {MailingLabelMode.exhibitorNumber},
          ),
          download: (r, m, s) async {
            selected = m;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exhibitor Labels'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).dialogTheme.backgroundColor,
      AppColors.surface,
    );
    expect(find.text('Mailing address'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Download PDF'));
    await tester.pumpAndSettle();
    expect(selected, MailingLabelMode.exhibitorNumber);
  });
  testWidgets('empty data and a failed check can be refreshed', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      page(
        PrintReportsMenu(
          load: () async {
            if (fail) throw StateError('network');
            return const PrintReportAvailability();
          },
          download: (r, m, s) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not check:'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Refresh report list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('No report data available yet'), findsOneWidget);
    expect(find.textContaining('Could not check:'), findsNothing);
  });
}
