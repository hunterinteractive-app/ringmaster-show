// Overrides the same-letter Youth/Open entry blocker for selected shows.

const String beatTheHeat2026ShowId = '208c4ee8-16b8-43c8-8a1b-2c0c72a2e268';

const Set<String> sameLetterOpenYouthShowIds = {
  beatTheHeat2026ShowId,
  // 'NEW-SHOW-UUID-HERE',
};

bool allowsSameLetterOpenYouthEntries(String showId) {
  return sameLetterOpenYouthShowIds.contains(showId);
}
