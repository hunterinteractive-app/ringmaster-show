import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/household_eligibility.dart';
import 'package:ringmaster_show/widgets/household_access_announcement.dart';

void main() {
  test('youth eligibility begins on the 14th birthday and needs a DOB', () {
    final now = DateTime(2026, 9, 13);
    expect(canInviteHouseholdExhibitor('adult', null, today: now), true);
    expect(canInviteHouseholdExhibitor('youth', null, today: now), false);
    expect(
      canInviteHouseholdExhibitor('youth', DateTime(2012, 9, 14), today: now),
      false,
    );
    expect(
      canInviteHouseholdExhibitor('youth', DateTime(2012, 9, 13), today: now),
      true,
    );
    expect(
      canInviteHouseholdExhibitor('youth', DateTime(2013, 9, 13), today: now),
      false,
    );
    expect(canInviteHouseholdExhibitor('group', null, today: now), false);
  });
  testWidgets(
    'announcement explains invitations, age and separate staff rights',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HouseholdAccessAnnouncement())),
      );
      expect(find.text('Your family can use their own logins'), findsOneWidget);
      expect(find.textContaining('Youth aged 14 or older'), findsOneWidget);
      expect(
        find.textContaining('Show Secretary and admin rights'),
        findsOneWidget,
      );
      expect(find.text('Open Household Access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
