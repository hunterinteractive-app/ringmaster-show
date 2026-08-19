import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Widget _host({bool canFinalizeShow = true}) {
  return MaterialApp(
    home: ShowCloseoutV2PreviewPage(
      showId: 'show-1',
      showName: 'Preview Show',
      canFinalizeShow: canFinalizeShow,
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('shows Close Show/Reports V2 and all closeout steps', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    expect(find.text('Preview Show • Close Show/Reports V2'), findsOneWidget);
    expect(find.byKey(const ValueKey('closeout-v2-step-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('closeout-v2-step-7')), findsOneWidget);
    expect(find.text('Needs Fixed'), findsOneWidget);
    expect(find.text('ARBA Final Closeout Confirmation'), findsOneWidget);
  });

  testWidgets('wraps the steps onto additional rows on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());

    final firstStep = tester.getTopLeft(
      find.byKey(const ValueKey('closeout-v2-step-0')),
    );
    final thirdStep = tester.getTopLeft(
      find.byKey(const ValueKey('closeout-v2-step-2')),
    );
    expect(thirdStep.dy, greaterThan(firstStep.dy));
  });

  testWidgets('opens the live report-generation panel from cube 5', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('closeout-v2-step-4')));
    await tester.pump();

    expect(find.text('Generate Reports'), findsWidgets);
    expect(
      find.textContaining('All non-ARBA reports are prepared and generated'),
      findsOneWidget,
    );
  });

  testWidgets('opens the financial and payout review panel from cube 4', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('closeout-v2-step-3')));
    await tester.pump();

    expect(find.text('Financial and Payout Review'), findsWidgets);
    expect(
      find.textContaining('No payments or payouts can be changed here.'),
      findsOneWidget,
    );
  });

  testWidgets('does not expose content without closeout permission', (
    tester,
  ) async {
    await tester.pumpWidget(_host(canFinalizeShow: false));

    expect(
      find.text(
        'You do not have permission to close this show or manage reports.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Report generation is live'), findsNothing);
  });
}
