import '../models/exhibitor/exhibitor_report_data.dart';
import 'report_population_index.dart';

/// Competition populations for breed, group and variety specials. These are
/// counts, not a determination that the winning animal earned a leg.
class ExhibitorAwardPopulations {
  final _counts = ReportPopulationIndex();

  ExhibitorAwardPopulations(List<Map<String, dynamic>> rows) {
    final seen = <Object>{};
    for (final row in rows) {
      final section = _value(row, 'section_id');
      final entry = _value(row, 'entry_id');
      if (section.isEmpty ||
          entry.isEmpty ||
          row['is_fur'] == true ||
          !seen.add((section, entry))) {
        continue;
      }
      final outcome =
          '${row['result_status'] ?? ''} ${row['disqualified_reason'] ?? ''}'
              .toLowerCase()
              .replaceAll(RegExp(r'[_-]+'), ' ');
      if (row['is_shown'] == false ||
          _value(row, 'scratched_at').isNotEmpty ||
          outcome.contains('no show') ||
          outcome.contains('noshow') ||
          outcome.contains('scratch')) {
        continue;
      }
      final exhibitor = _value(row, 'exhibitor_id');
      final base = _base(row);
      final sex = _value(row, 'sex');
      final variety = _value(row, 'variety_name');
      final group = _value(row, 'group_name');
      final age = _age(row);
      // Match the existing leg report populations: wrong class still counts
      // within its breed/variety, but wrong variety cannot count in either.
      if (outcome.contains('wrong variety')) continue;
      _counts.add((base, 'breed'), exhibitor);
      _counts.add((base, 'breedSex', sex), exhibitor);
      if (!outcome.contains('wrong class')) {
        _counts.add((base, 'breedAge', age), exhibitor);
      }
      if (outcome.contains('wrong sex')) continue;
      _counts.add((base, 'variety', variety), exhibitor);
      _counts.add((base, 'varietySex', variety, sex), exhibitor);
      if (!outcome.contains('wrong class')) {
        _counts.add((base, 'varietyAge', variety, age), exhibitor);
      }
      if (row['uses_group_awards'] == true && group.isNotEmpty) {
        _counts.add((base, 'group', group), exhibitor);
        _counts.add((base, 'groupSex', group, sex), exhibitor);
      }
    }
  }

  Map<String, ExhibitorAwardCount> forEntry(
    Map<String, dynamic> row,
    Set<String> awards,
  ) {
    final base = _base(row);
    final sex = _value(row, 'sex');
    final variety = _value(row, 'variety_name');
    final group = _value(row, 'group_name');
    final result = <String, ExhibitorAwardCount>{};
    for (final award in awards) {
      final Object? key = switch (award) {
        'BOB' => (base, 'breed'),
        'BOSB' || 'BOS' => (base, 'breedSex', sex),
        'BOV' => (base, 'variety', variety),
        'BOSV' => (base, 'varietySex', variety, sex),
        'BOG' when row['uses_group_awards'] == true && group.isNotEmpty => (
          base,
          'group',
          group,
        ),
        'BOSG' when row['uses_group_awards'] == true && group.isNotEmpty => (
          base,
          'groupSex',
          group,
          sex,
        ),
        'BJB' => (base, 'breedAge', 'junior'),
        'BIB' => (base, 'breedAge', 'intermediate'),
        'BSB' => (base, 'breedAge', 'senior'),
        'BJV' => (base, 'varietyAge', variety, 'junior'),
        'BIV' => (base, 'varietyAge', variety, 'intermediate'),
        'BSV' => (base, 'varietyAge', variety, 'senior'),
        _ => null,
      };
      if (key == null) continue; // Never invent counts for an unknown scope.
      final count = _counts[key];
      result[award] = ExhibitorAwardCount(count.animals, count.exhibitors);
    }
    return result;
  }

  static Object _base(Map<String, dynamic> row) => (
    _value(row, 'section_id'),
    _value(row, 'species'),
    _value(row, 'breed_name'),
  );
  static String _value(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim().toLowerCase();
  static String _age(Map<String, dynamic> row) {
    final name = _value(row, 'class_name');
    if (name.replaceAll(RegExp(r'[^a-z]'), '').startsWith('prejunior')) {
      return 'pre-junior';
    }
    for (final age in ['junior', 'intermediate', 'senior']) {
      if (name.contains(age)) return age;
    }
    return name;
  }
}
