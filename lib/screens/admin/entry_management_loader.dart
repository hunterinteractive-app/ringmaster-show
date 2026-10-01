import 'package:supabase/supabase.dart';
import 'closeout/data/report_data_reader.dart';

/// No total row limit: read until the server returns an empty page.
Future<List<Map<String, dynamic>>> loadManagedEntries(
  SupabaseClient client, {
  required String showId,
  String? sectionId,
}) => readAllReportPages((from, to) {
  var q = client
      .from('entries')
      .select(
        'id,show_id,section_id,exhibitor_id,exhibitor_user_id,animal_id,species,'
        'tattoo,animal_name,breed,variety,fur_variety,sex,class_name,notes,status,created_at,updated_at,scratched_at,'
        'is_fur,fur_placement,fur_notes,'
        'show_sections(id,letter,display_name,kind),'
        'exhibitors!entries_exhibitor_id_fkey(id,display_name,showing_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,owner_user_id,is_local_only,type,is_merged,merged_into_exhibitor_id)',
      )
      .eq('show_id', showId);

  if (sectionId != null) {
    q = q.eq('section_id', sectionId);
  }
  return q
      .order('created_at', ascending: true)
      .order('id', ascending: true)
      .range(from, to);
});
