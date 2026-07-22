// Override of the Youth show A and Open A blocker

const Set<String> sameLetterOpenYouthShowIds = {
  '208c4ee8-16b8-43c8-8a1b-2c0c72a2e268', // Beat the Heat 2026
  //'NEW-SHOW-UUID-HERE', 
};

bool allowsSameLetterOpenYouthEntries(String showId) {
  return sameLetterOpenYouthShowIds.contains(showId);
}