import 'result_status.dart';
import 'results_rules_router.dart';

typedef ControlSheetSavedResult = ({bool matches, String? conflict});

/// Compare only the marked values. An unmarked special never removes an award
/// already recorded in Results Entry, including awards from a different sheet.
ControlSheetSavedResult compareControlSheetSavedResult({
  required Map<String, dynamic> entry,
  required String? placement,
  required ResultStatus? outcome,
  required Set<String> awards,
}) {
  const pending = (matches: false, conflict: null);
  const saved = (matches: true, conflict: null);
  if (placement == null && outcome == null && awards.isEmpty) return pending;
  String value(String key) =>
      (entry[key] ?? '').toString().trim().toLowerCase();
  final rules = rulesForSpecies(
    value('species').isEmpty ? 'rabbit' : value('species'),
  );
  final previousAwards = rules.normalizeStoredAwards(
    entry['_awards'] as List? ?? [],
  );
  final markedAwards = rules.normalizeStoredAwards(awards);
  final previousPlace = value('placement');
  final status = value('result_status');
  final scratched =
      value('scratched_at').isNotEmpty ||
      status == 'scratched' ||
      value('status') == 'scratched';
  final disqualified =
      entry['is_disqualified'] == true || status.startsWith('disqualified');
  final noShow =
      !scratched &&
      !disqualified &&
      (status == 'no show' || entry['is_shown'] == false);
  final unworthy = !scratched && !disqualified && status == 'unworthy of award';

  if (outcome != null) {
    if (placement != null || awards.isNotEmpty) return pending;
    String reason(String text) {
      final normalized = text.trim().toLowerCase();
      final suffix = normalized.startsWith('disqualified')
          ? normalized.split('-').skip(1).join('-').trim()
          : normalized;
      if (normalized.startsWith('disqualified') && suffix.isEmpty) {
        return 'other';
      }
      return suffix == 'weight' ? 'overweight' : suffix;
    }

    final sameOutcome = switch (outcome) {
      ResultStatus.scratched => scratched,
      ResultStatus.noShow => noShow,
      ResultStatus.unworthy => unworthy,
      _ =>
        !scratched &&
            disqualified &&
            reason(
                  value('disqualified_reason').isEmpty
                      ? status
                      : value('disqualified_reason'),
                ) ==
                reason(outcome.storedValue),
    };
    if (previousPlace.isNotEmpty ||
        previousAwards.isNotEmpty ||
        (!sameOutcome &&
            (scratched ||
                noShow ||
                unworthy ||
                disqualified ||
                value('disqualified_reason').isNotEmpty))) {
      return (
        matches: false,
        conflict:
            'This entry already has a different saved result. Skip it or correct it in Results Entry.',
      );
    }
    return sameOutcome ? saved : pending;
  }
  if (scratched ||
      noShow ||
      disqualified ||
      !const {'', 'shown'}.contains(status)) {
    return (
      matches: false,
      conflict:
          'This entry has a saved outcome other than Shown. Skip it or correct it in Results Entry.',
    );
  }
  if (previousPlace.isNotEmpty &&
      placement != null &&
      previousPlace != placement) {
    return (
      matches: false,
      conflict:
          'This entry already has ${previousPlace == '0' ? 'NP' : 'place $previousPlace'} saved. Skip it or correct it in Results Entry.',
    );
  }
  final matches =
      (placement == null || previousPlace == placement) &&
      previousAwards.containsAll(markedAwards);
  return (matches: matches, conflict: null);
}
