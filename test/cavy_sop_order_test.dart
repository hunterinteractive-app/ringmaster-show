import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/cavy/cavy_sop_order.dart';

void main() {
  test('American Satin uses the official color-level varieties', () {
    expect(cavyVarietyOrderByBreed['American Satin'], const [
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
    ]);
  });
}
