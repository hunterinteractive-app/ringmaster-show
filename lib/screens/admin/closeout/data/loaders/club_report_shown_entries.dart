import '../closeout_repository.dart';
import '../report_data_reader.dart';
import '../../utils/club_report_grouping.dart';

/// Count actual shown entries, including DQs/COD that may have no points.
/// An empty scoring result alone must never be labeled as none shown.
Future<int> loadShownClubReportEntryCount({
  required CloseoutRepository repo,
  required String breedName,
  required String showId,
  required String scope,
  required String showLetter,
  required String species,
}) async {
  final sectionResponse = await repo.supabase
      .from('show_sections')
      .select('id')
      .eq('show_id', showId)
      .eq('is_enabled', true)
      .eq('kind', scope.toLowerCase())
      .eq('letter', showLetter);

  final sectionIds = (sectionResponse as List)
      .map((row) => (row['id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  if (sectionIds.isEmpty) return 0;

  final entryIds = <String>{};
  for (final sectionId in sectionIds) {
    final response = await readAllReportPages(
      (from, to) => repo.supabase
          .from('entries')
          .select('id, breed, species, is_shown, scratched_at, is_disqualified')
          .eq('show_id', showId)
          .eq('section_id', sectionId)
          .order('id', ascending: true)
          .range(from, to),
    );

    for (final raw in (response as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final rowBreedName = (row['breed'] ?? '').toString();
      final rowSpecies = normalizeClubReportSpecies(
        (row['species'] ?? '').toString(),
      );
      final matchesSpecies =
          species.isEmpty ||
          rowSpecies == species ||
          (rowSpecies.isEmpty &&
              species == 'cavy' &&
              isKnownCavyBreed(rowBreedName));
      if (!matchesSpecies ||
          (breedName.isNotEmpty &&
              rowBreedName.trim().toLowerCase() !=
                  breedName.trim().toLowerCase()) ||
          row['is_shown'] != true ||
          row['scratched_at'] != null) {
        continue;
      }

      final entryId = (row['id'] ?? '').toString().trim();
      if (entryId.isNotEmpty) entryIds.add(entryId);
    }
  }

  return entryIds.length;
}
