class GroupedSpecialtyBreedScope {
  const GroupedSpecialtyBreedScope({
    required this.value,
    required this.label,
    required this.catalogBreedNames,
  });

  final String value;
  final String label;
  final List<String> catalogBreedNames;
}

const groupedSpecialtyBreedScopes = <GroupedSpecialtyBreedScope>[
  GroupedSpecialtyBreedScope(
    value: 'grouped_wool',
    label: 'Wool Breed Specialty',
    catalogBreedNames: [
      'English Angora',
      'French Angora',
      'Giant Angora',
      'Satin Angora',
      'American Fuzzy Lop',
      'Jersey Wooly',
      'Lionhead',
    ],
  ),
  GroupedSpecialtyBreedScope(
    value: 'grouped_commercial',
    label: 'Commercial Breed Specialty',
    catalogBreedNames: [
      'Californian',
      'New Zealand',
      'Satin',
      'Silver Fox',
      "Champagne d'Argente",
      "Creme d'Argente",
      'Palomino',
      'American Chinchilla',
      'Florida White',
      'American Sable',
      'Argente Brun',
      'Cinnamon',
      'Rex',
      'Silver Marten',
      'Blanc de Hotot',
    ],
  ),
  GroupedSpecialtyBreedScope(
    value: 'grouped_under_3_5',
    label: '3 1/2 Pound and Under Specialty',
    catalogBreedNames: [
      'Netherland Dwarf',
      'Britannia Petite',
      'Polish',
      'Dwarf Hotot',
    ],
  ),
  GroupedSpecialtyBreedScope(
    value: 'grouped_marked',
    label: 'Marked Breed Specialty',
    catalogBreedNames: [
      'English Spot',
      'Checkered Giant',
      'Dutch',
      'Rhinelander',
      'Harlequin',
      'Dwarf Papillon',
      'Himalayan',
      'Tan',
    ],
  ),
  GroupedSpecialtyBreedScope(
    value: 'grouped_full_arch',
    label: 'Full Arch Specialty',
    catalogBreedNames: [
      'Belgian Hare',
      'Britannia Petite',
      'English Spot',
      'Checkered Giant',
      'Rhinelander',
      'Tan',
    ],
  ),
  GroupedSpecialtyBreedScope(
    value: 'grouped_semi_arch',
    label: 'Semi-Arch Specialty',
    catalogBreedNames: [
      'American',
      'Beveren',
      'Flemish Giant',
      'Giant Chinchilla',
      'English Lop',
    ],
  ),
];

GroupedSpecialtyBreedScope? groupedSpecialtyBreedScopeForValue(String value) {
  for (final preset in groupedSpecialtyBreedScopes) {
    if (preset.value == value) return preset;
  }
  return null;
}

bool isGroupedSpecialtyBreedScope(Object? value) =>
    groupedSpecialtyBreedScopeForValue(
      value?.toString().trim().toLowerCase() ?? '',
    ) !=
    null;
