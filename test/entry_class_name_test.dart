import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/entry_class_name.dart';

void main() {
  test('canonicalizes age-class abbreviations', () {
    expect(canonicalEntryClassName('Sr'), 'Senior');
    expect(canonicalEntryClassName('SR.'), 'Senior');
    expect(canonicalEntryClassName('Sr Buck'), 'Senior');
    expect(canonicalEntryClassName('Jr Doe'), 'Junior');
    expect(canonicalEntryClassName('Int Buck'), 'Intermediate');
    expect(canonicalEntryClassName('Pre Jr'), 'Pre-Junior');
  });

  test('preserves non-age specialty classes', () {
    expect(canonicalEntryClassName('Wool'), 'Wool');
    expect(canonicalEntryClassName('Meat Pen'), 'Meat Pen');
  });
}
