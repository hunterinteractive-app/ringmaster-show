import 'package:supabase_flutter/supabase_flutter.dart';

class CloseoutRepository {
  CloseoutRepository(this.supabase);

  final SupabaseClient supabase;

  Future<Map<String, dynamic>> loadShowBasics(String showId) async {
    return await supabase
        .from('shows')
        .select('id,name,start_date,end_date,location_name,location_address,secretary_name,secretary_email,secretary_phone,created_by')
        .eq('id', showId)
        .single();
  }

  Future<List<Map<String, dynamic>>> loadShowJudges(String showId) async {
    final rows = await supabase
        .from('show_judges')
        .select('judge_id,sort_order')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('sort_order');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadResults(String showId) async {
    final rows = await supabase
        .from('results')
        .select('id,entry_id,placing_label,award')
        .eq('show_id', showId);

    return List<Map<String, dynamic>>.from(rows);
  }
}