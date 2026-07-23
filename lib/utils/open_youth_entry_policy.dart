// Overrides the same-letter Youth/Open entry blocker for selected shows.

const String beatTheHeat2026ShowId = '208c4ee8-16b8-43c8-8a1b-2c0c72a2e268';
const String rollingHillsSecretaryUserId =
    '61184528-3278-407b-9819-a3ec142daaff';

const Set<String> sameLetterOpenYouthShowIds = {
  beatTheHeat2026ShowId,
  // 'NEW-SHOW-UUID-HERE',
};

const Set<String> sameLetterOpenYouthSecretaryUserIds = {
  rollingHillsSecretaryUserId,
  // 'NEW-SECRETARY-USER-UUID-HERE',
};

bool allowsSameLetterOpenYouthEntries(String showId, {String? ownerUserId}) {
  return sameLetterOpenYouthShowIds.contains(showId) ||
      sameLetterOpenYouthSecretaryUserIds.contains(ownerUserId);
}
