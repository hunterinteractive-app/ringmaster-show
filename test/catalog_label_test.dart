import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/catalog_label.dart';

void main() {
  const options = [
    {'id': 'tan', 'name': 'Tan'},
    {'id': 'black', 'name': 'Black'},
    {'id': 'rew', 'name': 'REW'},
    {'id': 'cod', 'name': 'Blue (COD)'},
  ];
  test('typed matches save catalog capitalization', () {
    expect(canonicalCatalogLabel(' tan ', options, selectedId: 'tan'), 'Tan');
    expect(canonicalCatalogLabel('black', options), 'Black');
    expect(canonicalCatalogLabel('rew', options), 'REW');
    expect(canonicalCatalogLabel('blue (cod)', options), 'Blue (COD)');
  });
  test('unknown, stale and ambiguous selections do not silently map', () {
    expect(canonicalCatalogLabel('Tann', options), isNull);
    expect(canonicalCatalogLabel('Tan', options, selectedId: 'black'), isNull);
    expect(canonicalCatalogLabel('', options), isNull);
    expect(
      canonicalCatalogLabel('tan', [
        {'name': 'Tan'},
        {'name': 'TAN'},
      ]),
      isNull,
    );
  });
}
