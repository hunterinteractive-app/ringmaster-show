import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/discounts/show_discount_codes.dart';
import 'package:ringmaster_show/widgets/discounts/cart_discount_codes.dart';

void main() {
  testWidgets(
    'secretary generates a code, validates percentage and saves overall discount',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await Supabase.initialize(
          url: 'https://discount-fixture.invalid',
          anonKey: 'test',
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage(),
          ),
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['p_action'] == 'save') saved = body;
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
      });
      addTearDown(() => Supabase.instance.dispose());
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: ShowDiscountCodes(showId: 'show'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add discount code'));
      await tester.pumpAndSettle();
      final dialogTheme = Theme.of(tester.element(find.byType(AlertDialog)));
      expect(dialogTheme.dialogTheme.backgroundColor, AppColors.surface);
      expect(dialogTheme.dialogTheme.titleTextStyle?.color, AppColors.text);
      expect(dialogTheme.listTileTheme.textColor, AppColors.text);
      expect(
        dialogTheme.inputDecorationTheme.helperStyle?.color,
        AppColors.muted,
      );
      expect(
        dialogTheme.inputDecorationTheme.floatingLabelStyle?.color,
        AppColors.secondaryButton,
      );
      expect(
        dialogTheme.textButtonTheme.style!.foregroundColor!.resolve({}),
        AppColors.secondaryButton,
      );
      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();
      final code = tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text;
      expect(RegExp(r'^[A-Z2-9]{10}$').hasMatch(code), isTrue);
      await tester.tap(find.text('Per entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overall per exhibitor').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dollar amount off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Percentage off').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(2), '101');
      await tester.tap(find.text('Save Code'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        find.text('Enter a valid amount with up to two decimal places.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).at(2), '15');
      await tester.tap(find.text('Save Code'));
      await tester.pumpAndSettle();
      expect(saved?['p_value'], 15);
      expect(saved?['p_basis'], 'overall');
      expect(saved?['p_type'], 'percent');
      expect(saved?['p_code'], code);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cart applies code only for selected exhibitor and explains best savings on phone',
    (tester) async {
      String? recipient;
      String? received;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CartDiscountCodes(
                  exhibitors: const {
                    'one': 'Adult Exhibitor',
                    'two': 'Youth Exhibitor',
                  },
                  codes: const [],
                  apply: (code, id) async {
                    received = code;
                    recipient = id;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final buttonTheme = Theme.of(tester.element(find.text('Apply Code')));
      expect(
        buttonTheme.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
        AppColors.secondaryButton,
      );
      await tester.enterText(find.byType(TextField), 'member20');
      await tester.tap(find.text('Apply Code'));
      await tester.pumpAndSettle();
      expect(recipient, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Youth Exhibitor').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Code'));
      await tester.pumpAndSettle();
      expect(recipient, 'two');
      expect(received, 'member20');
      expect(
        find.text(
          'Code saved. The best eligible discount is applied automatically.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
