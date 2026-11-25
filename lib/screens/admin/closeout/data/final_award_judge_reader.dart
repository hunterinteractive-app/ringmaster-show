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
  final plans = await loadReportRowsByIds(
    client,
    table: 'workspace_specialties',
    columns: 'id,award_section_id,award_code,table_number,sort_order',
    ids: sectionIds,
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
  return resolveFinalAwardJudgeRefs(plans, markers);
}

String finalAwardJudgeKey(String sectionId, String award) =>
    '$sectionId|${award.trim().toUpperCase()}';

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
