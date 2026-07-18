import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/grouped_specialty_breed_scopes.dart';

void main() {
  test('contains all seven ARBA grouped specialty presets', () {
    expect(groupedSpecialtyBreedScopes, hasLength(7));
    expect(
      groupedSpecialtyBreedScopes.map((preset) => preset.value),
      containsAll(<String>[
        'grouped_wool',
        'grouped_commercial',
        'grouped_under_3_5',
        'grouped_marked',
        'grouped_full_arch',
        'grouped_semi_arch',
        'grouped_lop',
      ]),
    );
  });

  test('preset breed counts match the supplied sanction lists', () {
    final counts = {
      for (final preset in groupedSpecialtyBreedScopes)
        preset.value: preset.catalogBreedNames.length,
    };
    expect(counts['grouped_wool'], 7);
    expect(counts['grouped_commercial'], 16);
    expect(counts['grouped_under_3_5'], 4);
    expect(counts['grouped_marked'], 8);
    expect(counts['grouped_full_arch'], 6);
    expect(counts['grouped_semi_arch'], 5);
    expect(counts['grouped_lop'], 5);
  });
}
