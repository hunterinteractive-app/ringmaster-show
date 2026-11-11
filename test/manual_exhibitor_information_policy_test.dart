import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/policies/manual_exhibitor_information_policy.dart';

void main() {
  test('allows name-only manual exhibitors for Westmoreland Fair 2026', () {
    expect(allowsNameOnlyManualExhibitors(westmorelandFair2026ShowId), isTrue);
  });

  test('keeps normal manual exhibitor requirements by default', () {
    expect(
      allowsNameOnlyManualExhibitors('00000000-0000-0000-0000-000000000000'),
      isFalse,
    );
  });

  test('matching needs name and corroborating contact, with optional ARBA', () {
    bool matches({
      bool name = true,
      String email = '',
      String phone = '',
      String address = '',
      String zip = '',
      String arba = '',
    }) => manualExhibitorIdentityMatches(
      nameMatches: name,
      email: email,
      phone: phone,
      address: address,
      zip: zip,
      arbaNumber: arba,
      candidate: {
        'email': 'one@example.test',
        'phone': '(555) 123-4567',
        'address_line1': '10 Test St',
        'zip': '46000',
        'arba_number': 'AB123',
      },
    );
    expect(matches(), isFalse);
    expect(matches(phone: '5551234567'), isTrue);
    expect(matches(name: false, phone: '5551234567'), isFalse);
    expect(matches(address: ' 10  test st ', zip: '46000'), isTrue);
    expect(matches(address: '10 test st', zip: '99999'), isFalse);
    expect(matches(arba: 'ab123'), isTrue);
    expect(matches(email: 'one@example.test'), isTrue);
  });
}
