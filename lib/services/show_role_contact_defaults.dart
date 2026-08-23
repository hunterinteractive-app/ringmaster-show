import 'package:supabase_flutter/supabase_flutter.dart';

/// Contact details derived from the current show secretary and superintendent
/// role assignments. These are suggestions only; callers keep saved show
/// details when they already exist.
class ShowRoleContactDefaults {
  const ShowRoleContactDefaults({
    this.secretaryName = '',
    this.secretaryAddress = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
    this.superintendentName = '',
    this.superintendentArbaNumber = '',
  });

  final String secretaryName;
  final String secretaryAddress;
  final String secretaryEmail;
  final String secretaryPhone;
  final String superintendentName;
  final String superintendentArbaNumber;

  static Future<ShowRoleContactDefaults?> load(String showId) async {
    final raw = await Supabase.instance.client.rpc(
      'show_role_contact_defaults',
      params: {'p_show_id': showId},
    );
    if (raw is! List || raw.isEmpty || raw.first is! Map) return null;

    final row = Map<String, dynamic>.from(raw.first as Map);
    String value(String key) => (row[key] ?? '').toString().trim();
    return ShowRoleContactDefaults(
      secretaryName: value('secretary_name'),
      secretaryAddress: value('secretary_address'),
      secretaryEmail: value('secretary_email'),
      secretaryPhone: value('secretary_phone'),
      superintendentName: value('superintendent_name'),
      superintendentArbaNumber: value('superintendent_arba_number'),
    );
  }
}
