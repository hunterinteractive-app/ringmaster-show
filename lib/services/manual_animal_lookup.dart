import 'package:supabase_flutter/supabase_flutter.dart';

/// Reuse a matching saved animal without treating its tattoo as a unique ID.
/// Entry duplicate checks must still use the returned animal ID and section.
Future<Map<String, dynamic>?> findManualEntryAnimal(
  SupabaseClient client, {
  required String tattoo,
  required String breed,
  required String variety,
  required String species,
  required String sex,
  required String ownerUserId,
  required String exhibitorId,
}) async {
  var query = client
      .from('animals')
      .select('id')
      .eq('tattoo', tattoo.trim().toUpperCase())
      .eq('breed', breed)
      .eq('species', species)
      .eq('sex', sex)
      .isFilter('deleted_at', null);
  query = variety.trim().isEmpty
      ? query.isFilter('variety', null)
      : query.eq('variety', variety.trim());
  query = ownerUserId.isNotEmpty
      ? query.eq('owner_user_id', ownerUserId)
      : query.eq('exhibitor_id', exhibitorId);
  return await query.maybeSingle();
}
