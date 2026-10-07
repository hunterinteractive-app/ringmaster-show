import 'dart:convert';

/// Optional contest rules. Empty settings preserve existing individual contests.
class ContestSettings {
  ContestSettings([Map<String, dynamic>? value])
    : data = jsonDecode(jsonEncode(value ?? {})) as Map<String, dynamic>;
  final Map<String, dynamic> data;
  String get entryType => data['entry_type'] as String? ?? 'individual';
  set entryType(String v) => data['entry_type'] = v;
  String get group => data['group'] as String? ?? 'Individual';
  set group(String v) => data['group'] = v;
  List<String> get categories => strings('categories');
  List<String> get animalSources => strings('animal_sources');
  List<String> get animalRoles => strings('animal_roles');
  List<Map<String, dynamic>> get sessions => rows('sessions');
  List<Map<String, dynamic>> get ageRules => rows('age_rules');
  List<Map<String, dynamic>> get awards => rows('awards');
  List<String> strings(String key) => (data[key] as List? ?? []).cast<String>();
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  int number(String key, [int fallback = 0]) =>
      (data[key] as num?)?.toInt() ?? fallback;
  bool flag(String key, [bool fallback = false]) =>
      data[key] as bool? ?? fallback;
  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  bool get needsBirthdate => ageRules.isNotEmpty || flag('collect_birthdate');
  bool get isTeam => entryType == 'team';
  bool get isProject => entryType == 'project';
  bool get expandedAnimals =>
      animalSources.isNotEmpty || animalRoles.isNotEmpty;
  Map<String, dynamic> toJson() => jsonDecode(jsonEncode(data));

  static DateTime? date(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        parsed.toIso8601String().substring(0, 10) != value) {
      return null;
    }
    return parsed;
  }

  static int ageOn(DateTime birthdate, DateTime cutoff) =>
      cutoff.year -
      birthdate.year -
      ((cutoff.month < birthdate.month ||
              (cutoff.month == birthdate.month && cutoff.day < birthdate.day))
          ? 1
          : 0);

  String? validate(List<String> divisions) {
    if (!['individual', 'team', 'project'].contains(entryType)) {
      return 'Choose an entry type.';
    }
    for (final values in [categories, animalRoles]) {
      if (values.length > 100 ||
          values.any((v) => v.trim().isEmpty || v.length > 120) ||
          values.toSet().length != values.length) {
        return 'Use unique, nonempty names.';
      }
    }
    if (isTeam &&
        (number('team_min', 3) < 1 ||
            number('team_max', 4) < number('team_min', 3) ||
            number('team_max', 4) > 20 ||
            number('team_alternates', 0) < 0 ||
            number('team_alternates', 0) > 10)) {
      return 'Check the minimum, maximum, and alternate team sizes.';
    }
    for (final r in ageRules) {
      if (!divisions.contains(r['division']) ||
          r['min'] is! num ||
          r['max'] is! num ||
          (r['min'] as num) < 0 ||
          (r['max'] as num) < (r['min'] as num) ||
          (r['max'] as num) > 120) {
        return 'Age rules need an existing division and a valid age range.';
      }
    }
    if (ageRules.isNotEmpty &&
        text('age_as_of', 'show_start') == 'custom' &&
        date(text('age_date')) == null) {
      return 'Set the age cutoff date.';
    }
    for (final s in sessions) {
      if ('${s['name'] ?? ''}'.trim().isEmpty) {
        return 'Each session needs a name.';
      }
      final start = DateTime.tryParse('${s['starts_at'] ?? ''}');
      final end = DateTime.tryParse('${s['ends_at'] ?? ''}');
      if (start == null || end == null || !end.isAfter(start)) {
        return 'Each session needs an ending after its start.';
      }
    }
    if (awards.any((a) => '${a['name'] ?? ''}'.trim().isEmpty)) {
      return 'Each award needs a name.';
    }
    return null;
  }
}

String contestEntryLabel(Map<String, dynamic> row) {
  final data = Map<String, dynamic>.from(
    row['registration_data'] as Map? ?? {},
  );
  final team = data['team'] as Map?;
  if (team != null && '${team['name'] ?? ''}'.isNotEmpty) {
    return '${team['name']}';
  }
  final project = '${data['project_title'] ?? ''}';
  return project.isEmpty
      ? '${row['exhibitor_name'] ?? ''}'
      : '$project — ${row['exhibitor_name'] ?? ''}';
}

String contestResultLabel(Map<String, dynamic>? result) {
  if (result == null) return 'Results not published';
  final labels = <String>[];
  if (result['place'] != null) labels.add('Place ${result['place']}');
  labels.addAll((result['awards'] as List? ?? []).map((v) => v.toString()));
  if ('${result['ribbon'] ?? ''}'.isNotEmpty) labels.add('${result['ribbon']}');
  if (labels.isEmpty) {
    labels.add(
      const {
            'recorded': 'No placing',
            'absent': 'Absent',
            'withdrawn': 'Withdrawn',
            'disqualified': 'Disqualified',
            'finalist': 'Finalist',
            'pending': 'Not recorded',
          }[result['status']] ??
          'Not recorded',
    );
  }
  return labels.join(' • ');
}
