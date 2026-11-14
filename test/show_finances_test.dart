import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_finances_screen.dart';
import 'package:ringmaster_show/services/show_finances_service.dart';
import 'package:ringmaster_show/services/assistant_suggestions.dart';
import 'package:ringmaster_show/services/assistant_context.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/utils/date_time_utils.dart';

class FakeFinance extends ShowFinanceGateway {
  bool failLoad = false, failHistory = false, failSave = false;
  int loads = 0;
  List<Map<String, dynamic>>? summaries;
  Map<String, dynamic> historyData = {
    'payments': [],
    'events': [],
    'allocations': [],
  };
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
      if (summaries != null) 'summaries': summaries,
    };
  }

  @override
  Future<Map<String, dynamic>> history(String show, String exhibitor) async {
    if (failHistory) throw Exception('offline');
    return historyData;
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
  test('money uses grouping separators and preserves cents and sign', () {
    expect(financeMoney(1407400, 'usd'), 'USD 14,074.00');
    expect(financeMoney(123456789, 'cad'), 'CAD 1,234,567.89');
    expect(financeMoney(-123456, 'usd'), 'USD -1,234.56');
    expect(financeMoney(0, 'usd'), 'USD 0.00');
  });
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
  test('surname ordering keeps showing names and handles missing surnames', () {
    final rows = [
      ShowFinanceRow({
        'exhibitor_id': '1',
        'name': 'AAA Rabbitry',
        'first_name': 'Ada',
        'last_name': 'Miller',
      }),
      ShowFinanceRow({
        'exhibitor_id': '2',
        'name': 'ZZZ Rabbitry',
        'first_name': 'Zoe',
        'last_name': 'adams',
      }),
      ShowFinanceRow({
        'exhibitor_id': '3',
        'name': 'Bea Adams',
        'first_name': 'Bea',
        'last_name': ' Adams ',
      }),
      ShowFinanceRow({
        'exhibitor_id': '4',
        'name': 'Cedar Rabbitry',
        'last_name': ' ',
      }),
    ]..sort(ShowFinanceRow.compare);
    expect(rows.map((r) => r.name), [
      'Bea Adams',
      'ZZZ Rabbitry',
      'Cedar Rabbitry',
      'AAA Rabbitry',
    ]);
  });
  test('old backend does not fabricate fee or earnings totals', () {
    final data = {'exhibitors': FakeFinance().rows};
    final summary = showFinanceSummaries(data).single;
    expect(summary['charges_cents'], 9000);
    expect(summary['due_cents'], 1000);
    expect(summary['club_earned_cents'], isNull);
    expect(summary['online_fee_cents'], isNull);
  });
  testWidgets('six summary totals fit phone and stay fixed while filtering', (
    tester,
  ) async {
    final gateway = FakeFinance()
      ..summaries = [
        {
          'currency': 'usd',
          'charges_cents': 9000,
          'online_fee_cents': 444,
          'discount_cents': 150000,
          'refunded_cents': 123,
          'due_cents': 1000,
          'club_earned_cents': 7878,
        },
      ];
    // Deliberately reverse the visible-name order; surname must win.
    gateway.rows[0].addAll({'first_name': 'Demo', 'last_name': 'Zebra'});
    gateway.rows[1].addAll({'first_name': 'Paid', 'last_name': 'Adams'});
    await start(tester, gateway);
    for (final label in [
      'Charged for show',
      'Online fees charged',
      'Refunded',
      'Outstanding',
      'Discounts',
      'Club earned (estimate)',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('USD 4.44'), findsOneWidget);
    expect(find.text('USD 1,500.00'), findsOneWidget);
    expect(find.text('USD 78.78'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await reveal(tester, find.text('Paid Exhibitor'));
    expect(
      tester.getTopLeft(find.text('Paid Exhibitor')).dy,
      lessThan(tester.getTopLeft(find.text('Demo Exhibitor')).dy),
    );
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), 'demo');
    await tester.pumpAndSettle();
    expect(find.text('Paid Exhibitor'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Charged for show'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('USD 78.78'), findsOneWidget);
    expect(find.text('USD 90.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing earnings show a readable explanation', (tester) async {
    final gateway = FakeFinance()
      ..summaries = [
        {
          'currency': 'usd',
          'charges_cents': 9000,
          'online_fee_cents': 444,
          'discount_cents': 150000,
          'refunded_cents': 0,
          'due_cents': 1000,
          'club_earned_cents': null,
        },
      ];
    await start(tester, gateway);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      find.textContaining('some payment or fee details are missing'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
  testWidgets('history formats receipts and adjustments in local time', (
    tester,
  ) async {
    const paid = '2026-11-12T01:59:29.412151+00:00';
    const created = '2026-11-13T02:15:00+00:00';
    final gateway = FakeFinance()
      ..historyData = {
        'payments': [
          {
            'amount_cents': 3000,
            'method': 'stripe',
            'status': 'paid',
            'paid_at': paid,
          },
          {
            'amount_cents': 500,
            'method': 'cash',
            'status': 'paid',
            'created_at': created,
          },
        ],
        'events': [
          {
            'kind': 'credit',
            'amount_cents': 100,
            'reason': 'Correction',
            'created_at': created,
          },
        ],
      };
    await start(tester, gateway);
    await reveal(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'demo exhibitor');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Payment history'));
    await tester.tap(find.text('Payment history'));
    await tester.pumpAndSettle();
    expect(
      find.text('Times are shown in your local time zone.'),
      findsOneWidget,
    );
    expect(find.textContaining(formatLocalDateTime(paid)), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Credit: USD 1.00'),
      150,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.textContaining('Correction\n${formatLocalDateTime(created)}'),
      findsOneWidget,
    );
    expect(find.textContaining(paid), findsNothing);
    expect(find.textContaining(created), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
