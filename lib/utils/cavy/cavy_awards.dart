// lib/utils/cavy/cavy_awards.dart

/// Internal award codes for cavies
const List<String> cavyAwardCodes = [
  'BJV', // Best Junior Variety
  'BIV', // Best Intermediate Variety
  'BSV', // Best Senior Variety

  'BJB', // Best Junior of Breed
  'BIB', // Best Intermediate of Breed
  'BSB', // Best Senior of Breed

  'BOV', // Best of Variety
  'BOSV', // Best Opposite Sex of Variety

  'BOB', // Best of Breed
  'BOSB', // Best Opposite Sex of Breed

  'BIS', // Best in Show
  'RIS', // Reserve in Show
  'HM',  // Honorable Mention (2nd RIS)
];

/// Display labels (what prints on reports)
const Map<String, String> cavyAwardLabels = {
  'BJV': 'Best Junior Variety',
  'BIV': 'Best Intermediate Variety',
  'BSV': 'Best Senior Variety',

  'BJB': 'Best Junior of Breed',
  'BIB': 'Best Intermediate of Breed',
  'BSB': 'Best Senior of Breed',

  'BOV': 'Best of Variety',
  'BOSV': 'Best Opposite Sex of Variety',

  'BOB': 'Best of Breed',
  'BOSB': 'Best Opposite Sex of Breed',

  'BIS': 'Best in Show',
  'RIS': 'Reserve in Show',
  'HM': 'Honorable Mention / 2nd RIS',
};

/// Optional: enforce valid award codes
bool isValidCavyAward(String code) {
  return cavyAwardCodes.contains(code.trim());
}

/// Optional: safe label lookup
String getCavyAwardLabel(String code) {
  return cavyAwardLabels[code.trim()] ?? code;
}