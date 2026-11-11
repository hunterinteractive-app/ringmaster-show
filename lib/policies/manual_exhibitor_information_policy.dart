// Allows name-only manual exhibitor creation for selected one-off shows.
//
// Add a show's UUID here when its manual exhibitor records should not require
// address, email, or phone information. All other shows retain the standard
// address requirements.

const String westmorelandFair2026ShowId =
    '373d1b96-45bb-4f29-a630-96279ed0e91e';

const Set<String> nameOnlyManualExhibitorShowIds = {
  westmorelandFair2026ShowId,
  // 'NEW-SHOW-UUID-HERE',
};

bool allowsNameOnlyManualExhibitors(String showId) =>
    nameOnlyManualExhibitorShowIds.contains(showId);

/// Contact matches suggest a record for staff review; they never claim an account.
bool manualExhibitorIdentityMatches({
  required bool nameMatches,
  required String email,
  required String phone,
  required String address,
  required String zip,
  required String arbaNumber,
  required Map<String, dynamic> candidate,
}) {
  String norm(Object? value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  String digits(Object? value) =>
      (value ?? '').toString().replaceAll(RegExp(r'\D'), '');
  bool same(String value, String key) =>
      norm(value).isNotEmpty && norm(value) == norm(candidate[key]);
  if (!nameMatches) return false;
  return same(email, 'email') ||
      same(arbaNumber, 'arba_number') ||
      (digits(phone).length >= 7 &&
          digits(phone) == digits(candidate['phone'])) ||
      (same(address, 'address_line1') && same(zip, 'zip'));
}
