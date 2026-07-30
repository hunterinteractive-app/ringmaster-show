import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/policies/manual_exhibitor_information_policy.dart';

void main() {
  test('allows name-only manual exhibitors for Westmoreland Fair 2026', () {
    expect(allowsNameOnlyManualExhibitors(westmorelandFair2026ShowId), isTrue);
  });

  test('keeps normal manual exhibitor requirements by default', () {
    expect(
      allowsNameOnlyManualExhibitors(
        '00000000-0000-0000-0000-000000000000',
      ),
      isFalse,
    );
  });
}
