// lib/utils/cavy/cavy_sop_order.dart

/// Official ARBA SOP order for Cavy breeds
const List<String> cavyBreedOrder = [
  'Abyssinian',
  'Abyssinian Satin',
  'American',
  'American Satin',
  'Coronet',
  'Peruvian',
  'Peruvian Satin',
  'Silkie',
  'Silkie Satin',
  'Texel',
  'Teddy',
  'Teddy Satin',
  'White Crested',
];

/// Shared varieties for long-haired breeds
const List<String> _longHairedCavyVarieties = [
  'Self',
  'Agouti',
  'Broken Color',
  'Tortoise Shell & White',
  'Any Other Variety',
  'Tan Pattern',
  'Cal Pattern',
];

/// SOP variety order per breed
const Map<String, List<String>> cavyVarietyOrderByBreed = {
  'Abyssinian': [
    'Self',
    'Agouti',
    'Brindle',
    'Roan',
    'Ticked Solid',
    'Marked',
    'Tan Pattern',
    'Cal Pattern',
  ],
  'Abyssinian Satin': [
    'Self',
    'Agouti',
    'Brindle',
    'Roan',
    'Ticked Solid',
    'Marked',
    'Tan Pattern',
    'Cal Pattern',
  ],

  'American': [
    'Beige',
    'Black',
    'Blue',
    'Chocolate',
    'Cream',
    'Gold',
    'Lilac',
    'Orange',
    'Red',
    'Slate',
    'White',
    'Brindle',
    'Roan',
    'Dilute Solid',
    'Golden Solid',
    'Silver Solid',
    'Dilute Agouti',
    'Golden Agouti',
    'Silver Agouti',
    'Broken Color',
    'Dalmatian',
    'Dutch',
    'Himalayan',
    'Tortoise Shell',
    'Tortoise Shell & White',
    'Marten',
    'Otter',
    'Tan',
    'Cal Pattern',
  ],

  'American Satin': [
    'Black',
    'Cream',
    'Orange',
    'Red',
    'White',
    'Any Other Self',
    'Agouti',
    'Intermixed Solids',
    'Ticked Solids',
    'Broken Colors & Tortoise Shell',
    'Any Other Marked',
    'Tan Pattern',
    'Cal Pattern',
  ],

  'Coronet': _longHairedCavyVarieties,
  'Peruvian': _longHairedCavyVarieties,
  'Peruvian Satin': _longHairedCavyVarieties,
  'Silkie': _longHairedCavyVarieties,
  'Silkie Satin': _longHairedCavyVarieties,
  'Texel': _longHairedCavyVarieties,

  'Teddy': [
    'Black',
    'Red',
    'Any Other Self',
    'Agouti',
    'Intermixed Solids',
    'Ticked Solids',
    'Broken Color',
    'Tortoise Shell & White',
    'Any Other Marked',
    'Tan Pattern',
    'Cal Pattern',
  ],

  'Teddy Satin': [
    'Self',
    'Agouti',
    'Solid',
    'Broken Color',
    'Tortoise Shell & White',
    'Any Other Marked',
    'Tan Pattern',
    'Cal Pattern',
  ],

  'White Crested': [
    'Black',
    'Red',
    'Any Other Self',
    'Agouti',
    'Brindle',
    'Ticked Solid',
    'Marked',
    'Tan Pattern',
    'Cal Pattern',
  ],
};

/// Class order (important for control sheets)
const List<String> cavyClassOrder = [
  'Junior Boar',
  'Junior Sow',
  'Intermediate Boar',
  'Intermediate Sow',
  'Senior Boar',
  'Senior Sow',
];

int cavyBreedSortIndex(String breed) {
  final index = cavyBreedOrder.indexOf(breed.trim());
  return index == -1 ? 9999 : index;
}

int cavyVarietySortIndex(String breed, String variety) {
  final varieties = cavyVarietyOrderByBreed[breed.trim()];
  if (varieties == null) return 9999;

  final index = varieties.indexOf(variety.trim());
  return index == -1 ? 9999 : index;
}

int cavyClassSortIndex(String className) {
  final index = cavyClassOrder.indexOf(className.trim());
  return index == -1 ? 9999 : index;
}
