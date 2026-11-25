import 'package:supabase/supabase.dart';

import 'report_data_reader.dart';

/// Award plans inherit the last judge-change marker preceding them at their
/// table, just as the superintendent lineup does. Published breed judges are
/// intentionally not changed by those plans.
Future<Map<String, String>> loadFinalAwardJudgeRefs(
  SupabaseClient client, {
  required String showId,
  required Iterable<String> sectionIds,
}) async {
  final requestedSections = sectionIds.toSet();
  final sections = await loadReportRowsByIds(
    client,
    table: 'show_sections',
    columns: 'id,kind,letter,display_name,is_enabled,judging_date',
    ids: [showId],
    idColumn: 'show_id',
  );
  final cavyAliases = legacyCavyFinalsSections(sections, requestedSections);
  final plans = await loadReportRowsByIds(
    client,
    table: 'workspace_specialties',
    columns: 'id,award_section_id,award_code,table_number,sort_order',
    ids: {...requestedSections, ...cavyAliases.keys},
    idColumn: 'award_section_id',
  );
  if (plans.isEmpty) return {};
  final markers = await loadReportRowsByIds(
    client,
    table: 'show_judging_assignments',
    columns: 'id,table_number,sort_order,judge_id',
    ids: [showId],
    idColumn: 'show_id',
    filters: const {'is_judge_change': true},
  );
  final refs = resolveFinalAwardJudgeRefs(plans, markers);
  for (final alias in cavyAliases.entries) {
    for (final award in ['BIS', 'RIS', 'FINALS']) {
      final sourceKey = finalAwardJudgeKey(alias.key, award);
      if (refs.containsKey(sourceKey)) {
        refs[finalAwardJudgeKey(alias.value, award, species: 'cavy')] =
            refs[sourceKey]!;
      }
    }
  }
  return refs;
}

String finalAwardJudgeKey(
  String sectionId,
  String award, {
  String species = '',
}) => '$sectionId|${award.trim().toUpperCase()}|$species';

/// Older shows moved cavies into shared A/B sections but retained their
/// separate finals plans on disabled sections named "ACBA Open Show A/B".
/// Only that explicit legacy naming convention, scope, and judging date can
/// establish an alias; never use the old physical letter (often D/E), a fuzzy
/// name match, or the rabbit finals judge in place of the saved cavy plan.
Map<String, String> legacyCavyFinalsSections(
  ReportRows sections,
  Set<String> requested,
) {
  final aliases = <String, String>{};
  final seenTargets = <String>{};
  final name = RegExp(
    r'^ACBA (Open|Youth) Show ([A-Z])$',
    caseSensitive: false,
  );
  for (final source in sections) {
    if (source['is_enabled'] != false) continue;
    final match = name.firstMatch(
      (source['display_name'] ?? '').toString().trim(),
    );
    if (match == null) continue;
    final kind = match[1]!.toLowerCase();
    final date = source['judging_date']?.toString();
    if (date == null ||
        date.isEmpty ||
        source['kind']?.toString().toLowerCase() != kind) {
      continue;
    }
    final targets = sections
        .where(
          (target) =>
              requested.contains(target['id']) &&
              target['is_enabled'] != false &&
              target['kind']?.toString().toLowerCase() == kind &&
              target['letter']?.toString().toUpperCase() ==
                  match[2]!.toUpperCase() &&
              target['judging_date']?.toString() == date,
        )
        .toList();
    if (targets.isEmpty) continue;
    if (targets.length != 1 ||
        !seenTargets.add(targets.single['id'].toString())) {
      throw StateError(
        'Ambiguous legacy cavy finals section. Review its saved award plans.',
      );
    }
    aliases[source['id'].toString()] = targets.single['id'].toString();
  }
  return aliases;
}

Map<String, String> resolveFinalAwardJudgeRefs(
  ReportRows plans,
  ReportRows markers,
) {
  final result = <String, String>{};
  for (final plan in plans) {
    final section = (plan['award_section_id'] ?? '').toString();
    final award = (plan['award_code'] ?? '').toString().trim().toUpperCase();
    final table = (plan['table_number'] ?? '').toString();
    final position = plan['sort_order'] as num?;
    if (section.isEmpty || award.isEmpty || table.isEmpty || position == null) {
      continue;
    }
    final preceding =
        markers
            .where(
              (marker) =>
                  marker['table_number']?.toString() == table &&
                  marker['sort_order'] is num &&
                  (marker['sort_order'] as num) <= position,
            )
            .toList()
          ..sort(
            (a, b) =>
                (b['sort_order'] as num).compareTo(a['sort_order'] as num),
          );
    // Keep an unresolved explicit plan so a generic FINALS plan cannot
    // override it merely because its table is missing a judge marker.
    final refs = preceding.isEmpty
        ? <String>{''}
        : preceding
              .where(
                (marker) =>
                    marker['sort_order'] == preceding.first['sort_order'],
              )
              .map((marker) => (marker['judge_id'] ?? '').toString().trim())
              .toSet();
    if (refs.length != 1) {
      throw StateError(
        'Conflicting finals judges for section $section at table $table.',
      );
    }
    final key = finalAwardJudgeKey(section, award);
    final ref = refs.single;
    if (result.containsKey(key) && result[key] != ref) {
      throw StateError(
        'Conflicting $award judge assignments for section $section.',
      );
    }
    result[key] = ref;
  }
  return result;
}
