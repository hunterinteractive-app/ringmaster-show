import 'package:ringmaster_show/utils/cavy/cavy_sop_order.dart';

String _text(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value.toLowerCase();
  }
  return '';
}

int _rank(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 9999;

String _species(Map<String, dynamic> row) {
  final explicit = _text(row, ['species', 'animal_species', 'entry_species']);
  if (explicit.isNotEmpty) return explicit;
  final sex = _text(row, ['sex', 'class_name']);
  return sex.contains('boar') || sex.contains('sow') ? 'cavy' : 'rabbit';
}

int _index(Iterable<String> values, String value) =>
    values.map((e) => e.toLowerCase()).toList().indexOf(value);

int _knownIndex(Iterable<String> values, String value) {
  final index = _index(values, value);
  return index < 0 ? 9999 : index;
}

/// Standard catalog sequence within a section. Section selection/order remains
/// the caller's responsibility (including paired Open/Youth print packs).
/// Result loaders may still rank placements within each class.
int compareReportAnimalRows(Map<String, dynamic> a, Map<String, dynamic> b) {
  final species = _species(a).compareTo(_species(b));
  if (species != 0) return species;
  final breedA = _text(a, ['breed_name', 'breed']);
  final breedB = _text(b, ['breed_name', 'breed']);
  if (_species(a) == 'cavy') {
    final breed = _knownIndex(
      cavyBreedOrder,
      breedA,
    ).compareTo(_knownIndex(cavyBreedOrder, breedB));
    if (breed != 0) return breed;
  }
  final breed = breedA.compareTo(breedB);
  if (breed != 0) return breed;

  final furA = a['is_fur'] == true;
  final furB = b['is_fur'] == true;
  if (furA != furB) return furA ? 1 : -1;
  final variety = compareReportVarieties(a, b);
  if (variety != 0) return variety;
  final age = _ageRank(a).compareTo(_ageRank(b));
  if (age != 0) return age;
  // Unknown/local classes must remain together even when their ranks tie.
  if (_ageRank(a) >= 100) {
    final name = _text(a, ['class_name']).compareTo(_text(b, ['class_name']));
    if (name != 0) return name;
  }
  final sex = _sexRank(a).compareTo(_sexRank(b));
  if (sex != 0) return sex;
  final tattoo = _text(a, [
    'tattoo',
    'ear_number',
  ]).compareTo(_text(b, ['tattoo', 'ear_number']));
  if (tattoo != 0) return tattoo;
  return _text(a, ['entry_id', 'id']).compareTo(_text(b, ['entry_id', 'id']));
}

int compareReportVarieties(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (_species(a) == 'cavy' && _species(b) == 'cavy') {
    int cavyRank(Map<String, dynamic> row) {
      final breed = _text(row, ['breed_name', 'breed']);
      for (final catalog in cavyVarietyOrderByBreed.entries) {
        if (catalog.key.toLowerCase() == breed) {
          return _knownIndex(
            catalog.value,
            _text(row, ['variety_name', 'variety']),
          );
        }
      }
      return 9999;
    }

    final rank = cavyRank(a).compareTo(cavyRank(b));
    if (rank != 0) return rank;
  }
  final group = _rank(
    a['group_sort_order'],
  ).compareTo(_rank(b['group_sort_order']));
  if (group != 0) return group;
  final groupName = _text(a, [
    'group_name',
    'group',
  ]).compareTo(_text(b, ['group_name', 'group']));
  if (groupName != 0) return groupName;
  final variety = _rank(
    a['variety_sort_order'],
  ).compareTo(_rank(b['variety_sort_order']));
  if (variety != 0) return variety;
  return _text(a, [
    'variety_name',
    'variety',
    'fur_variety',
  ]).compareTo(_text(b, ['variety_name', 'variety', 'fur_variety']));
}

int _ageRank(Map<String, dynamic> row) {
  final age = _text(row, [
    'class_name',
    'class_age_label',
  ]).replaceAll(RegExp(r'[-_/]+'), ' ');
  final cavy = _species(row) == 'cavy';
  if (RegExp(r'\bpre\s*(junior|jr)\b').hasMatch(age)) return 2;
  if (RegExp(r'\b(senior|sr)\b').hasMatch(age)) return cavy ? 2 : 0;
  if (RegExp(r'\b(intermediate|inter|int|6\s*8|six eight)\b').hasMatch(age)) {
    return 1;
  }
  if (RegExp(r'\b(junior|jr)\b').hasMatch(age)) return cavy ? 0 : 3;
  return 100 + _rank(row['class_sort_order']);
}

int _sexRank(Map<String, dynamic> row) {
  final sex = _text(row, ['sex']);
  if (const {
    'b',
    'buck',
    'bucks',
    'boar',
    'boars',
    'm',
    'male',
  }.contains(sex)) {
    return 0;
  }
  if (const {'d', 'doe', 'does', 'sow', 'sows', 'f', 'female'}.contains(sex)) {
    return 1;
  }
  final className = _text(row, ['class_name']);
  if (RegExp(r'\b(buck|boar)\b').hasMatch(className)) return 0;
  if (RegExp(r'\b(doe|sow)\b').hasMatch(className)) return 1;
  return 9;
}

/// Open sections, then Youth, with each section kept intact.
int compareReportEntryRows(Map<String, dynamic> a, Map<String, dynamic> b) {
  int kind(Map<String, dynamic> row) =>
      switch (_text(row, ['resolved_section_kind', 'section_kind'])) {
        'open' => 0,
        'youth' => 1,
        _ => 9,
      };
  final scope = kind(a).compareTo(kind(b));
  if (scope != 0) return scope;
  final order = _rank(
    a['section_sort_order'],
  ).compareTo(_rank(b['section_sort_order']));
  if (order != 0) return order;
  final letter =
      _text(a, [
        'resolved_show_letter',
        'resolved_section_letter',
        'section_letter',
      ]).compareTo(
        _text(b, [
          'resolved_show_letter',
          'resolved_section_letter',
          'section_letter',
        ]),
      );
  if (letter != 0) return letter;
  final section = _text(a, [
    'section_id',
    'resolved_section_id',
  ]).compareTo(_text(b, ['section_id', 'resolved_section_id']));
  if (section != 0) return section;
  return compareReportAnimalRows(a, b);
}
