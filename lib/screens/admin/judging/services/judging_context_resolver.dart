// lib/screens/admin/judging/services/judging_context_resolver.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/judging_entry_context.dart';

class JudgingContextResolver {
  JudgingContextResolver({SupabaseClient? supabase})
      : supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient supabase;

  Future<JudgingEntryContext> resolve({
    required String showId,
    required String sectionId,
    required String breedId,
    String? varietyKey,
    String? token,
  }) async {
    if (token != null && token.trim().isNotEmpty) {
      await _validateToken(
        showId: showId,
        sectionId: sectionId,
        breedId: breedId,
        varietyKey: varietyKey,
        token: token,
      );
    }

    final assignment = await _loadSuperintendentAssignment(
      showId: showId,
      sectionId: sectionId,
      breedId: breedId,
      varietyKey: varietyKey,
    );

    String? judgeId;
    String judgeName = 'Judge not assigned';
    String? tableNumber;
    bool fromSuperintendentAssignment = false;

    if (assignment != null) {
      judgeId = assignment['judge_id']?.toString();
      tableNumber = assignment['table_number']?.toString();
      fromSuperintendentAssignment = true;

      if (judgeId != null && judgeId.trim().isNotEmpty) {
        judgeName = await _loadJudgeName(judgeId) ?? 'Judge not assigned';
      }
    }

    if (judgeId == null || judgeId.trim().isEmpty) {
      final fallbackJudge = await _loadFallbackJudge(
        showId: showId,
        sectionId: sectionId,
        breedId: breedId,
        varietyKey: varietyKey,
      );

      judgeId = fallbackJudge.$1;
      judgeName = fallbackJudge.$2;
    }

    final resultsLocked = await _isResultsLocked(
      showId: showId,
      sectionId: sectionId,
      breedId: breedId,
      varietyKey: varietyKey,
    );

    return JudgingEntryContext(
      showId: showId,
      sectionId: sectionId,
      breedId: breedId,
      varietyKey: varietyKey,
      judgeId: judgeId,
      judgeName: judgeName,
      tableNumber: tableNumber,
      fromSuperintendentAssignment: fromSuperintendentAssignment,
      resultsLocked: resultsLocked,
      canEdit: !resultsLocked,
    );
  }

  Future<void> _validateToken({
    required String showId,
    required String sectionId,
    required String breedId,
    String? varietyKey,
    required String token,
  }) async {
    var query = supabase
        .from('show_result_entry_tokens')
        .select('id')
        .eq('show_id', showId)
        .eq('section_id', sectionId)
        .eq('breed_id', breedId)
        .eq('token', token)
        .eq('is_active', true);

    if ((varietyKey ?? '').trim().isNotEmpty) {
      query = query.eq('variety_key', varietyKey!.trim());
    }

    final rows = await query.limit(1);

    if ((rows as List).isEmpty) {
      throw Exception('This QR code is invalid or no longer active.');
    }
  }

  Future<Map<String, dynamic>?> _loadSuperintendentAssignment({
    required String showId,
    required String sectionId,
    required String breedId,
    String? varietyKey,
  }) async {
    var query = supabase
        .from('show_judging_assignments')
        .select('judge_id, table_number, status')
        .eq('show_id', showId)
        .eq('section_id', sectionId)
        .eq('breed_id', breedId);

    if ((varietyKey ?? '').trim().isNotEmpty) {
      query = query.eq('variety_key', varietyKey!.trim());
    }

    final rows = await query.limit(1);

    if ((rows as List).isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<String?> _loadJudgeName(String judgeId) async {
    final rows = await supabase
        .from('judges')
        .select('first_name, last_name, name')
        .eq('id', judgeId)
        .limit(1);

    if ((rows as List).isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first as Map);

    final first = (row['first_name'] ?? '').toString().trim();
    final last = (row['last_name'] ?? '').toString().trim();
    final name = (row['name'] ?? '').toString().trim();

    if ('$first $last'.trim().isNotEmpty) return '$first $last'.trim();
    if (name.isNotEmpty) return name;

    return null;
  }

  Future<(String?, String)> _loadFallbackJudge({
    required String showId,
    required String sectionId,
    required String breedId,
    String? varietyKey,
  }) async {
    // TODO: adjust this to match your actual result/judge storage.
    //
    // Priority:
    // 1. Existing result/breed judge field
    // 2. Section judge/default judge
    // 3. Judge not assigned

    return (null, 'Judge not assigned');
  }

  Future<bool> _isResultsLocked({
    required String showId,
    required String sectionId,
    required String breedId,
    String? varietyKey,
  }) async {
    // TODO: connect this to your actual locking source.
    //
    // Eventually this should check either:
    // - breed result status completed/locked
    // - show_judging_assignments.status == locked/completed
    // - a dedicated result lock table

    return false;
  }
}