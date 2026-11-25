import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/print_packs/control_sheet_judging_order.dart';
import 'package:ringmaster_show/screens/admin/print_packs/control_sheet_page_order.dart';

Map<String, dynamic> page(
  String breed, {
  String species = 'cavy',
  String section = 'A',
  String kind = 'open',
  int? breedOrder,
  int varietyOrder = 0,
  String color = 'Black',
}) => {
  'breed': breed,
  'species': species,
  'sectionId': '$kind-$section',
  'sectionTitle': '$kind $section',
  'sectionKind': kind,
  'sectionLetter': section,
  'sectionSortOrder': section == 'A' ? 0 : 1,
  'cavyBreedSortOrder': breedOrder,
  'groupSortOrder': 0,
  'varietySortOrder': varietyOrder,
  'color': color,
  'classSortRank': 0,
  'sex': 'Buck',
};

void main() {
  for (final combined in [false, true]) {
    test('rabbits before cavy show order, combined=$combined', () {
      final sorted = sortControlSheetPages(
        [
          page('Teddy'),
          page('American'),
          page('Texel'),
          page('Rex', species: 'rabbit'),
          page('Abyssinian'),
          page('American', species: 'rabbit'),
        ],
        combineSections: combined,
        youthFirst: false,
      );
      expect(sorted.map((p) => '${p['species']}:${p['breed']}'), [
        'rabbit:American',
        'rabbit:Rex',
        'cavy:Abyssinian',
        'cavy:American',
        'cavy:Texel',
        'cavy:Teddy',
      ]);
    });
    test('catalog breed and variety order, combined=$combined', () {
      final sorted = sortControlSheetPages(
        [
          page('Teddy', breedOrder: 20),
          page('Texel', breedOrder: 10, varietyOrder: 2, color: 'Agouti'),
          page('Texel', breedOrder: 10, varietyOrder: 1, color: 'Self'),
        ],
        combineSections: combined,
        youthFirst: false,
      );
      expect(sorted.map((p) => '${p['breed']}:${p['color']}'), [
        'Texel:Self',
        'Texel:Agouti',
        'Teddy:Black',
      ]);
    });
    test('all rabbit sections precede cavy sections, combined=$combined', () {
      final sorted = sortControlSheetPages(
        [
          for (final species in ['cavy', 'rabbit'])
            for (final kind in ['open', 'youth'])
              for (final section in ['B', 'A'])
                page(
                  'American',
                  species: species,
                  kind: kind,
                  section: section,
                ),
        ],
        combineSections: combined,
        youthFirst: true,
      );
      expect(sorted.map((p) => '${p['species']}:${p['sectionId']}'), [
        'rabbit:youth-A',
        'rabbit:youth-B',
        'rabbit:open-A',
        'rabbit:open-B',
        'cavy:youth-A',
        'cavy:youth-B',
        'cavy:open-A',
        'cavy:open-B',
      ]);
    });
  }
  test('explicit judging lineup stays within each species', () {
    final order = ControlSheetJudgingOrder([
      for (final (index, breed, species) in [
        (0, 'Teddy', 'cavy'),
        (1, 'Rex', 'rabbit'),
        (2, 'Texel', 'cavy'),
        (3, 'American', 'rabbit'),
      ])
        {
          'id': '$index',
          'breed_id': breed,
          'species': species,
          'section_id': 'open-A',
          'judge_id': 'judge',
          'table_number': '1',
          'sort_order': index,
        },
    ]);
    final sorted = sortControlSheetPages(
      [
        page('Texel'),
        page('American', species: 'rabbit'),
        page('Teddy'),
        page('Rex', species: 'rabbit'),
      ],
      combineSections: true,
      youthFirst: false,
      judgingOrder: order,
    );
    expect(sorted.map((p) => p['breed']), [
      'Rex',
      'American',
      'Teddy',
      'Texel',
    ]);
  });
  test('unknown cavy breeds follow catalog breeds, rabbits unchanged', () {
    final sorted = sortControlSheetPages(
      [
        page('Unknown'),
        page('Teddy'),
        page('Z rabbit', species: 'rabbit'),
        page('A rabbit', species: 'rabbit'),
      ],
      combineSections: true,
      youthFirst: false,
    );
    expect(sorted.map((p) => p['breed']), [
      'A rabbit',
      'Z rabbit',
      'Teddy',
      'Unknown',
    ]);
  });
}
