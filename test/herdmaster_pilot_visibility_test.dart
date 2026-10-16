import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/herdmaster_pilot_link_button.dart';

User user(String email, {bool verified = true}) => User.fromJson({
  'id': 'pilot-owner',
  'aud': 'authenticated',
  'email': email,
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-15T12:00:00Z',
  if (verified) 'email_confirmed_at': '2026-10-15T12:00:00Z',
})!;

void main() {
  testWidgets('pilot account sees the linking action and can open it', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HerdMasterPilotLinkButton(
            user: user('ZayneTort2@gmail.com'),
            ownerUserId: 'pilot-owner',
            supportMode: false,
            onPressed: () => opened = true,
          ),
        ),
      ),
    );
    expect(find.text('Link HerdMaster'), findsOneWidget);
    await tester.tap(find.text('Link HerdMaster'));
    expect(opened, true);
  });

  testWidgets('other and unverified users never see the pilot action', (
    tester,
  ) async {
    for (final actor in [
      null,
      user('someone@example.com'),
      user('zaynetort2@gmail.com', verified: false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HerdMasterPilotLinkButton(
              user: actor,
              ownerUserId: 'pilot-owner',
              supportMode: false,
              onPressed: () => fail('Hidden action was invoked'),
            ),
          ),
        ),
      );
      expect(find.text('Link HerdMaster'), findsNothing);
    }
  });

  testWidgets('pilot action is hidden in other households and support mode', (
    tester,
  ) async {
    for (final mode in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HerdMasterPilotLinkButton(
              user: user('zaynetort2@gmail.com'),
              ownerUserId: mode ? 'pilot-owner' : 'someone-else',
              supportMode: mode,
              onPressed: () => fail('Hidden action was invoked'),
            ),
          ),
        ),
      );
      expect(find.text('Link HerdMaster'), findsNothing);
    }
  });
}
