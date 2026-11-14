import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_finances_screen.dart';
import 'package:ringmaster_show/services/show_finances_service.dart';
import 'package:ringmaster_show/services/assistant_suggestions.dart';
import 'package:ringmaster_show/services/assistant_context.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

class FakeFinance extends ShowFinanceGateway {
  bool failLoad = false, failHistory = false, failSave = false;
  int loads = 0;
  final saved = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[
    {
      'exhibitor_id': 'one',
      'name': 'Demo Exhibitor',
      'currency': 'usd',
      'charges_cents': 1000,
      'manual_cents': 0,
      'online_cents': 0,
      'refunded_cents': 0,
      'due_cents': 1000,
      'entry_count': 2,
      'email': 'demo@example.test',
    },
    {
      'exhibitor_id': 'two',
      'name': 'Paid Exhibitor',
      'currency': 'usd',
      'charges_cents': 8000,
      'manual_cents': 0,
      'online_cents': 8000,
      'due_cents': 0,
      'entry_count': 16,
    },
  ];
  @override
  Future<Map<String, dynamic>> load(String id) async {
    loads++;
    if (failLoad) throw Exception('offline');
    return {
      'show_name': 'Finance Test Show',
      'exhibitors': rows,
      'section_ids': [],
    };
  }

  @override
  Future<Map<String, dynamic>> history(String show, String exhibitor) async {
    if (failHistory) throw Exception('offline');
    return {'payments': [], 'events': [], 'allocations': []};
  }

  @override
  Future<void> record(
    String show,
    String exhibitor,
    Map<String, dynamic> values,
  ) async {
    saved.add(Map.of(values));
    if (failSave) throw Exception('response lost');
    rows.first['due_cents'] = 1000 - (values['p_amount_cents'] as int);
    rows.first['manual_cents'] = values['p_amount_cents'];
  }
}

Future<void> start(WidgetTester tester, FakeFinance gateway) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: ShowFinancesScreen(showId: 'show', gateway: gateway),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void checkDialogTheme(WidgetTester tester) {
  final theme = Theme.of(tester.element(find.byType(AlertDialog)));
  expect(theme.dialogTheme.backgroundColor, AppColors.surface);
  final bg = AppColors.surface.computeLuminance();
  for (final color in [
    theme.dialogTheme.contentTextStyle!.color!,
    theme.inputDecorationTheme.floatingLabelStyle!.color!,
    theme.inputDecorationTheme.errorStyle!.color!,
    theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
  ]) {
    expect(
      (bg + .05) / (color.computeLuminance() + .05),
      greaterThanOrEqualTo(4.5),
    );
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://finance-fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDown(() => Supabase.instance.dispose());
  test('amount parser preserves cents and rejects invalid financial input', () {
    expect(parseFinanceAmount('12.01'), 1201);
    expect(parseFinanceAmount(' 0.10 '), 10);
    for (final value in [
      '0',
      '-1',
      '1.001',
      'NaN',
      '1e3',
      '1,000',
      '21474836.48',
    ]) {
      expect(parseFinanceAmount(value), isNull, reason: value);
    }
  });
  test('Chester routes external payment questions to Show Finances', () {
    for (final q in [
      'Where do I mark PayPal payments?',
      'How can I record a Venmo payment?',
      'How do I log Zelle payments?',
    ]) {
      expect(assistantPreparedAnswer(q), contains('Show Finances'));
      expect(assistantQuestionNeedsRecords(q), isFalse);
    }
  });
  testWidgets(
    'phone payment form validates and retry reuses the exact request',
    (tester) async {
      final gateway = FakeFinance()..failSave = true;
      await start(tester, gateway);
      await reveal(tester, find.text('Record payment'));
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();
      checkDialogTheme(tester);
      await tester.enterText(find.byType(TextFormField).first, '11');
      await tester.tap(find.text('Record payment').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Amount cannot exceed the balance due.'),
        findsOneWidget,
      );
      expect(gateway.saved, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, '4.25');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('PayPal'), findsOneWidget);
      expect(find.text('Zelle'), findsOneWidget);
      await tester.tap(find.text('Venmo').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Receipt 123');
      await tester.tap(find.text('Record payment').last);
      await tester.pumpAndSettle();
      expect(gateway.saved.single['p_amount_cents'], 425);
      expect(gateway.saved.single['p_method'], 'venmo');
      expect(
        find.textContaining('Retry uses the same request'),
        findsOneWidget,
      );
      gateway.failSave = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(gateway.saved.length, 2);
      expect(gateway.saved[0], gateway.saved[1]);
      expect(gateway.loads, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('credit requires a reason, stays readable with phone keyboard', (
    tester,
  ) async {
    final gateway = FakeFinance();
    await start(tester, gateway);
    await reveal(tester, find.text('Apply credit'));
    await tester.tap(find.text('Apply credit'));
    await tester.pumpAndSettle();
    checkDialogTheme(tester);
    await tester.tap(find.text('Apply credit').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a reason of at least 5 characters.'),
      findsOneWidget,
    );
    expect(gateway.saved, isEmpty);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(
      find.byType(TextFormField).last,
      'Paid entry moved from Open',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply credit').last);
    await tester.pumpAndSettle();
    expect(gateway.saved.single['credit'], true);
    expect(gateway.saved.single['p_reason'], 'Paid entry moved from Open');
    expect(gateway.saved.single.containsKey('p_method'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('screen filters, refresh recovery and history retry', (
    tester,
  ) async {
    final gateway = FakeFinance()..failLoad = true;
    await start(tester, gateway);
    expect(find.textContaining('Could not load show finances'), findsOneWidget);
    gateway.failLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'paid exhibitor');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Paid Exhibitor'));
    expect(find.text('Demo Exhibitor'), findsNothing);
    expect(find.text('Record payment'), findsNothing);
    gateway.failHistory = true;
    await reveal(tester, find.text('Payment history'));
    await tester.tap(find.text('Payment history'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load payment history.'), findsOneWidget);
    gateway.failHistory = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No recorded payments or adjustments.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
