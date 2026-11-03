import 'package:supabase/supabase.dart';
import 'recognition_timeline.dart';

/// Read fresh timelines when a catalog is opened. Evaluate names at read time,
/// so scheduled dates need no cron job and do not rewrite historical names.
class RecognitionCatalogLabels {
  RecognitionCatalogLabels(this.rows, {DateTime? date})
    : date = date ?? DateTime.now();
  final List<Map<String, dynamic>> rows;
  final DateTime date;

  static Future<RecognitionCatalogLabels> load(SupabaseClient client) async {
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final page = await client
          .from('catalog_recognition_history')
          .select()
          .order('id')
          .range(rows.length, rows.length + 999);
      if (page.isEmpty) break;
      rows.addAll(page);
    }
    return RecognitionCatalogLabels(rows);
  }

  String label(String species, String breed, [String variety = '']) {
    final events = rows
        .where(
          (row) =>
              row['species'] == species &&
              row['breed_key'] == recognitionKey(breed),
        )
        .map(RecognitionTransition.fromJson);
    final status = resolveRecognitionStatus(
      breedName: breed,
      varietyName: variety,
      judgingDate: date,
      transitions: events,
    );
    return recognitionDisplayName(variety.isEmpty ? breed : variety, status);
  }

  List<Map<String, dynamic>> decorate(
    List<Map<String, dynamic>> options,
    String species, {
    String? breed,
  }) => [
    for (final option in options)
      {
        ...option,
        'display_name': label(
          species,
          breed ?? option['name'].toString(),
          breed == null ? '' : option['name'].toString(),
        ),
      },
  ];
}

String catalogDisplayName(Map<String, dynamic> row) =>
    (row['display_name'] ?? row['name'] ?? '').toString();
