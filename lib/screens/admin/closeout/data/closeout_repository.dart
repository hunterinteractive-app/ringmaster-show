// lib/screens/admin/closeout/data/closeout_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class CloseoutRepository {
  CloseoutRepository(this.supabase);

  final SupabaseClient supabase;

  // ---------------------------
  // EXISTING METHODS
  // ---------------------------

  Future<Map<String, dynamic>> loadShowBasics(String showId) async {
    return await supabase
        .from('shows')
        .select(
          'id,name,start_date,end_date,location_name,location_address,secretary_name,secretary_email,secretary_phone,created_by,is_national_show',
        )
        .eq('id', showId)
        .single();
  }

  Future<List<Map<String, dynamic>>> loadShowJudges(
    String showId,
  ) async {
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

  // ---------------------------
  // NEW METHODS FOR UNPAID REPORT
  // ---------------------------

  Future<Map<String, dynamic>?> loadShowFeeSettings(
    String showId,
  ) async {
    final row = await supabase
        .from('show_fee_settings')
        .select(
          'show_id,currency,fee_per_entry,fee_per_show,'
          'multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value',
        )
        .eq('show_id', showId)
        .maybeSingle();

    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> loadShowSections(
    String showId,
  ) async {
    final rows = await supabase
        .from('show_sections')
        .select('id,display_name,kind,letter,sort_order')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('sort_order');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadEntriesForBalanceReport(
    String showId,
  ) async {
    final rows = await supabase
        .from('entries')
        .select(
          'id,exhibitor_id,animal_id,section_id,'
          'scratched_at,is_disqualified,is_test',
        )
        .eq('show_id', showId);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadExhibitorsByIds(
    List<String> exhibitorIds,
  ) async {
    if (exhibitorIds.isEmpty) return [];

    final rows = await supabase
        .from('exhibitors')
        .select(
          'id,showing_name,display_name,first_name,last_name,phone,type',
        )
        .inFilter('id', exhibitorIds);

    return List<Map<String, dynamic>>.from(rows);
  }
}