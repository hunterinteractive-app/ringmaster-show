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
