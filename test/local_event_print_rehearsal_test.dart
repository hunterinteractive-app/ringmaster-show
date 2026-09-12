// Opt-in local integration probe. Real UI, data reads, fonts and PDF builders;
// only the native Save dialog is replaced with a known local output path.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/print_packs/coop_cards_generator_sheet.dart';
import 'package:ringmaster_show/screens/admin/print_packs/check_in_generator_sheet.dart';
import 'package:ringmaster_show/screens/admin/print_packs/control_sheets_generator_sheet.dart';
import 'package:ringmaster_show/screens/admin/print_packs/remark_cards_generator_sheet.dart';

class _LocalBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _LocalSaveDialog extends FileSelectorPlatform {
  _LocalSaveDialog(this.output);
  final Directory output;
  String? selectedPath;
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    selectedPath = '${output.path}/${options.suggestedName}';
    return FileSaveLocation(selectedPath!);
  }
}

void main() {
  final env = Platform.environment;
  if (env['EVENT_PRINT_MODE'] == null) {
    test(
      'local event print probe is opt-in',
      () {},
      skip: 'Requires a local rehearsal',
    );
    return;
  }
  _LocalBinding();
  testWidgets(
    'full local print pack through its actual generator screen',
    (tester) async {
      final uri = Uri.parse(env['EVENT_API_URL']!);
      expect(uri.scheme, 'http');
      expect(['127.0.0.1', 'localhost'], contains(uri.host));
      final output = Directory(env['EVENT_PRINT_OUTPUT']!).absolute;
      expect(output.path, contains('/output/full_e2e/'));
      output.createSync(recursive: true);
      final mode = env['EVENT_PRINT_MODE']!;
      final dialog = _LocalSaveDialog(output);
      FileSelectorPlatform.instance = dialog;
      SharedPreferences.setMockInitialValues({});
      const showId = '95000000-0000-0000-0000-000000000001';
      final sections = await tester.runAsync(() async {
        await Supabase.initialize(
          url: uri.toString(),
          anonKey: env['EVENT_ANON_KEY']!,
          accessToken: () async => env['EVENT_STAFF_ACCESS_TOKEN'],
          authOptions: FlutterAuthClientOptions(
            localStorage: EmptyLocalStorage(),
            detectSessionInUri: false,
            autoRefreshToken: false,
          ),
        );
        final client = Supabase.instance.client;
        final show = await client
            .from('shows')
            .select('is_test')
            .eq('id', showId)
            .single();
        expect(show['is_test'], true);
        return List<Map<String, dynamic>>.from(
          await client
              .from('show_sections')
              .select()
              .eq('show_id', showId)
              .order('sort_order'),
        );
      });
      expect(sections, hasLength(2));
      final section = sections!.firstWhere(
        (s) => s['kind'] == (mode.endsWith('youth') ? 'youth' : 'open'),
      );
      final sid = section['id'] as String;
      final label = section['display_name'] as String;
      const name = 'LOCAL E2E Convention 25711';
      final Widget sheet;
      String button;
      if (mode.startsWith('coop')) {
        sheet = const CoopCardsGeneratorSheet(showId: showId, showName: name);
        button = 'Save PDF';
      } else if (mode.startsWith('checkin')) {
        sheet = CheckInGeneratorSheet(
          showId: showId,
          showName: name,
          sections: sections,
          sectionId: sid,
          sectionLabel: label,
          includeScratched: false,
          combineSections: false,
          pairOpenYouthByLetter: false,
          youthFirst: false,
        );
        button = 'Generate PDF';
      } else if (mode.startsWith('control')) {
        sheet = ControlSheetsGeneratorSheet(
          showId: showId,
          showName: name,
          sections: sections,
          sectionId: sid,
          sectionIds: [sid],
          sectionLabel: label,
          includeScratched: false,
          combineSections: false,
          youthFirst: false,
        );
        button = 'Generate Compact PDF with QR Code';
      } else {
        sheet = RemarkCardsGeneratorSheet(
          showId: showId,
          showName: name,
          sections: [section],
          includeScratched: false,
        );
        button = 'Generate PDF';
      }
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: sheet)));
      final watch = Stopwatch()..start();
      final target = find.ancestor(
        of: find.text(button),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      expect(target, findsOneWidget);
      await tester.ensureVisible(target);
      final callback = tester.widget<ButtonStyleButton>(target).onPressed!;
      // runAsync uses real time/network and awaits the generator's UI completion.
      await tester.runAsync(() async {
        final work = Function.apply(callback, const []);
        if (work is Future) await work.timeout(const Duration(minutes: 25));
      });
      await tester.pump();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final path = dialog.selectedPath;
      final okay =
          path != null &&
          File(path).existsSync() &&
          File(path).lengthSync() > 0;
      File('${output.path}/result.json').writeAsStringSync(
        jsonEncode({
          'mode': mode,
          'passed': okay,
          'elapsed_ms': watch.elapsedMilliseconds,
          'file': path,
          'bytes': okay ? File(path).lengthSync() : 0,
          'ui_text': texts,
          'native_save_dialog_replaced': true,
          'builders_and_network_mocked': false,
        }),
      );
      await tester.runAsync(() => Supabase.instance.client.dispose());
      expect(okay, true, reason: texts.join('\n'));
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
