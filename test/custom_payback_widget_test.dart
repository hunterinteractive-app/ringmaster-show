// Run with flutter test --platform chrome.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/payback_settings_dialog.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/services/class_payback.dart';

void main() {
  var eligible = true;
  List<Map<String, dynamic>> stored = [];
  final saves = <String, Map<String, dynamic>>{};
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
      httpClient: MockClient((request) async {
        final method = request.url.path.split('/').last;
        Object? value;
        if (method == 'can_configure_best_opposite_final_award') {
          value = eligible;
        } else if (method == 'get_show_payback_setup') {
          value = {
            'sections': [
              {'id': 'open', 'kind': 'open', 'letter': 'A', 'label': 'Open A'},
              {
                'id': 'youth',
                'kind': 'youth',
                'letter': 'A',
                'label': 'Youth A',
              },
            ],
            'schedules': [
              {'section_id': 'open', 'rows': stored},
            ],
            'special_money_rules': [
              {
                'section_id': 'open',
                'award_code': 'BIS',
                'award_label': 'Best in Show',
                'amount_cents': 9900,
                'applies_to_species': 'rabbit',
              },
            ],
          };
        } else if (method.startsWith('save_')) {
          final body = Map<String, dynamic>.from(jsonDecode(request.body));
          saves[method] = body;
          if (method.endsWith('payback_schedule')) {
            stored = [
              for (final r in body['p_rows']) Map<String, dynamic>.from(r),
            ];
          }
          value = 'schedule-id';
        } else {
          throw StateError('Unexpected request $method');
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
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    eligible = true;
    saves.clear();
    // Exact five rows reviewed in Kyle's live Open Rabbit schedule.
    stored = [
      for (final (n, p, c) in [
        (2, 1, 200),
        (3, 1, 400),
        (3, 2, 200),
        (4, 1, 400),
        (4, 2, 200),
      ])
        {
          'applies_to_species': 'rabbit',
          'min_shown': n,
          'max_shown': n,
          'placement': p,
          'amount_cents': c,
        },
    ];
  });
  Future<void> open(WidgetTester tester, {double width = 1250}) async {
    tester.view.physicalSize = Size(width, width < 500 ? 844 : 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) =>
                    const PaybackSettingsDialog(showId: 'show'),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester) async {
    await tester.tap(find.text('Houston premium tables'));
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(AlertDialog).last));
    expect(theme.dialogTheme.backgroundColor, AppColors.surface);
    expect(theme.inputDecorationTheme.helperStyle?.color, AppColors.muted);
    expect(
      theme.inputDecorationTheme.floatingLabelStyle?.color,
      AppColors.secondaryButton,
    );
  }

  testWidgets(
    'existing five rows preserved, preset preview cancel does not replace or save',
    (tester) async {
      await open(tester);
      expect(find.text('6+'), findsNothing);
      await preview(tester);
      expect(find.text('3–4'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saves, isEmpty);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(stored.length, 5);
      expect(
        saves['save_show_custom_payback_schedule']!['p_section_id'],
        'open',
      );
      expect(stored.map((r) => r['amount_cents']), [200, 400, 200, 400, 200]);
    },
  );
  testWidgets(
    'Open preset preserves Cavy and special money, round-trips ranges without 6+ defaults',
    (tester) async {
      stored.add({
        'applies_to_species': 'cavy',
        'min_shown': 1,
        'max_shown': null,
        'placement': 1,
        'amount_cents': 123,
      });
      await open(tester);
      await preview(tester);
      await tester.tap(find.text('Use this table'));
      await tester.pumpAndSettle();
      expect(saves, isEmpty);
      expect(find.text('3-4'), findsOneWidget);
      await tester.tap(find.text('Add 6th placement'));
      await tester.pumpAndSettle();
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('10+'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(stored.length, 16);
      expect(
        stored
            .where((r) => r['applies_to_species'] == 'cavy')
            .single['amount_cents'],
        123,
      );
      expect(
        stored.where((r) => r['applies_to_species'] == 'rabbit').toList(),
        HoustonPaybackPreset.openRabbit
            .rows()
            .expand((r) => r.toRpcRows())
            .toList(),
      );
      expect(
        saves['save_show_special_money_rules']!['p_rules']
            .single['amount_cents'],
        9900,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.text('3-4'), findsOneWidget);
      expect(find.text('6+'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(stored.length, 16);
    },
  );
  testWidgets('ordinary shows retain the original editor and RPC', (
    tester,
  ) async {
    eligible = false;
    await open(tester);
    expect(find.text('Houston premium tables'), findsNothing);
    expect(find.text('Add class-size range'), findsNothing);
    expect(find.text('6+'), findsNWidgets(2));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves.containsKey('save_show_payback_schedule'), isTrue);
    expect(saves.containsKey('save_show_custom_payback_schedule'), isFalse);
  });
  testWidgets(
    'phone nested range dialog validates, blocks overlap, and keeps readable theme',
    (tester) async {
      await open(tester, width: 390);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Add class-size range'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog).last;
      final theme = Theme.of(tester.element(dialog));
      expect(theme.dialogTheme.backgroundColor, AppColors.surface);
      expect(theme.dialogTheme.titleTextStyle?.color, AppColors.text);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.first, '0');
      await tester.tap(find.text('Apply range'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a positive whole number.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(fields.first, '3');
      await tester.enterText(fields.last, '5');
      await tester.tap(find.text('Apply range'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('ranges overlap'), findsOneWidget);
      expect(saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('invalid money cannot be saved', (tester) async {
    await open(tester);
    final field = find.byKey(const ValueKey('premium-1')).first;
    await tester.enterText(field, '-3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, isEmpty);
    expect(find.textContaining('nonnegative amount'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Youth Cavy preset uses its own table and selected section', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Open A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Youth A').last);
    await tester.pumpAndSettle();
    await preview(tester);
    await tester.tap(find.text('Youth Rabbit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Youth Cavy').last);
    await tester.pumpAndSettle();
    expect(find.text('10+'), findsOneWidget);
    expect(find.text('15+'), findsNothing);
    await tester.tap(find.text('Use this table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      saves['save_show_custom_payback_schedule']!['p_section_id'],
      'youth',
    );
    expect(
      stored,
      HoustonPaybackPreset.youthCavy
          .rows()
          .expand((r) => r.toRpcRows())
          .toList(),
    );
  });
  testWidgets(
    'new custom range edits and removes without changing another range',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Add class-size range'));
      await tester.pumpAndSettle();
      var dialog = find.byType(AlertDialog).last;
      var fields = find.descendant(
        of: dialog,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.first, '5');
      await tester.tap(find.text('Apply range'));
      await tester.pumpAndSettle();
      expect(find.text('5+'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Edit 5+'));
      await tester.tap(find.byTooltip('Edit 5+'));
      await tester.pumpAndSettle();
      dialog = find.byType(AlertDialog).last;
      fields = find.descendant(
        of: dialog,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.last, '6');
      await tester.tap(find.text('Apply range'));
      await tester.pumpAndSettle();
      expect(find.text('5-6'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Remove 5–6'));
      await tester.tap(find.byTooltip('Remove 5–6'));
      await tester.pumpAndSettle();
      expect(find.text('5-6'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(stored.length, 5);
    },
  );
}
