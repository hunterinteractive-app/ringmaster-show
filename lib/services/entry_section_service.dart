import '../utils/exhibitor_entry_order.dart';
import 'ringmaster_backend.dart';

class EntrySectionService {
  static Future<List<Map<String, dynamic>>> sectionsFor(
    Map<String, dynamic> entry,
  ) async {
    final animalId = (entry['animal_id'] ?? '').toString();
    var query = ringMasterClient
        .from('entries')
        .select('id,section_id,status,is_fur')
        .eq('show_id', entry['show_id'])
        .eq('exhibitor_id', entry['exhibitor_id']);
    final rows = await (animalId.isEmpty
        ? query.eq('id', entry['id'])
        : query.eq('animal_id', animalId));
    final sections = await ringMasterClient
        .from('show_sections')
        .select('id,kind,letter,display_name,sort_order')
        .eq('show_id', entry['show_id'])
        .order('sort_order', ascending: true);
    sections.sort(compareEntrySections);
    return [
      for (final section in sections)
        if (rows.any(
          (row) =>
              row['section_id'] == section['id'] &&
              ![
                'deleted',
                'removed',
                'withdrawn',
                'cancelled',
                'canceled',
              ].contains(row['status']),
        ))
          {
            ...section,
            'entry_count': rows
                .where(
                  (row) =>
                      row['section_id'] == section['id'] &&
                      ![
                        'deleted',
                        'removed',
                        'withdrawn',
                        'cancelled',
                        'canceled',
                      ].contains(row['status']),
                )
                .length,
          },
    ];
  }

  static Future<void> apply(
    Map<String, dynamic> entry,
    List<String> sections, {
    Map<String, dynamic> changes = const {},
    bool? scratched,
  }) async {
    await ringMasterClient.rpc(
      'apply_entry_section_changes',
      params: {
        'p_entry_id': entry['id'],
        'p_section_ids': sections,
        'p_changes': changes,
        'p_is_scratched': scratched,
      },
    );
  }
}
