import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/catalog/recognition_catalog_labels.dart';
import 'package:ringmaster_show/services/catalog/recognition_timeline.dart';
import 'package:ringmaster_show/utils/catalog_label.dart';

void main() {
  final history = <Map<String, dynamic>>[
    for (final variety in ['', 'Solid'])
      for (final transition in [
        ['cod', '2026-01-01'],
        ['recognized', '2026-12-01'],
      ])
        {
          'id': '$variety-${transition.first}',
          'species': 'rabbit',
          'breed_key': 'velveteen lop',
          'variety_name': variety,
          'status': transition.first,
          'effective_date': transition.last,
        },
    {
      'id': 'broken',
      'species': 'rabbit',
      'breed_key': 'velveteen lop',
      'variety_name': 'Broken',
      'status': 'cod',
      'effective_date': '2026-01-01',
    },
  ];
  test(
    'breed and variety names switch on the date without renaming identities',
    () {
      final before = RecognitionCatalogLabels(
        history,
        date: DateTime(2026, 11, 30),
      );
      final after = RecognitionCatalogLabels(
        history,
        date: DateTime(2026, 12, 1),
      );
      expect(before.label('rabbit', 'Velveteen Lop'), 'Velveteen Lop (COD)');
      expect(before.label('rabbit', 'Velveteen Lop', 'Solid'), 'Solid (COD)');
      expect(after.label('rabbit', 'Velveteen Lop (COD)'), 'Velveteen Lop');
      expect(
        after.label('rabbit', 'Velveteen Lop (COD)', 'Solid (COD)'),
        'Solid',
      );
      expect(after.label('rabbit', 'Velveteen Lop', 'Broken'), 'Broken (COD)');
      expect(before.label('cavy', 'Velveteen Lop'), 'Velveteen Lop');
    },
  );
  test('displayed names resolve back to the same stored catalog identity', () {
    final labels = RecognitionCatalogLabels(
      history,
      date: DateTime(2026, 12, 1),
    );
    final options = labels.decorate([
      {'id': 'breed', 'name': 'Velveteen Lop (COD)'},
    ], 'rabbit');
    expect(catalogDisplayName(options.single), 'Velveteen Lop');
    expect(
      canonicalCatalogLabel('Velveteen Lop', options, selectedId: 'breed'),
      'Velveteen Lop (COD)',
    );
    expect(
      canonicalCatalogLabel('Velveteen Lop (COD)', options),
      'Velveteen Lop (COD)',
    );
    expect(
      canonicalCatalogLabel('Velveteen Lop', options, selectedId: 'wrong'),
      isNull,
    );
  });
  test('suffix stays singular and does not strip COD from unrelated words', () {
    expect(
      recognitionDisplayName('Blue (COD) (cod)', RecognitionStatus.cod),
      'Blue (COD)',
    );
    expect(
      recognitionDisplayName('Blue (COD)', RecognitionStatus.recognized),
      'Blue',
    );
    expect(
      recognitionDisplayName('Cody', RecognitionStatus.recognized),
      'Cody',
    );
  });
}
