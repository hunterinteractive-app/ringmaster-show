import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/show_addon.dart';
import 'app_session.dart';

class ShowAddonService {
  ShowAddonService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  void _writeAllowed() {
    if (AppSession.isSupportMode) {
      throw StateError('Exit support mode to make changes.');
    }
  }

  Future<Map<String, dynamic>> catalog(
    String showId, {
    bool admin = false,
  }) async => Map<String, dynamic>.from(
    await _client.rpc(
      'get_show_addons',
      params: {'p_show_id': showId, 'p_admin': admin},
    ),
  );
  Future<bool> available(String showId) async {
    try {
      final data = await catalog(showId);
      return (data['items'] as List).isNotEmpty;
    } on PostgrestException catch (e) {
      // Older servers do not offer this optional step during a staged rollout.
      if (e.code == 'PGRST202') return false;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> openContestShows() async {
    try {
      return _rows(await _client.rpc('get_open_contest_shows'));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') return [];
      rethrow;
    }
  }

  Future<void> enable(String showId, String kind, bool enabled) async {
    _writeAllowed();
    await _client.rpc(
      'set_show_addons_enabled',
      params: {'p_show_id': showId, 'p_kind': kind, 'p_enabled': enabled},
    );
  }

  Future<void> save(String showId, ShowAddon item) async {
    _writeAllowed();
    await _client.rpc(
      'save_show_addon',
      params: {'p_show_id': showId, 'p_item': item.toJson()},
    );
  }

  Future<void> deleteOffering(String showId, String offeringId) async {
    _writeAllowed();
    await _client.rpc(
      'delete_show_addon',
      params: {'p_show_id': showId, 'p_offering_id': offeringId},
    );
  }

  Future<List<Map<String, dynamic>>> cart(String cartId) async {
    try {
      return _rows(
        await _client.rpc('get_cart_addons', params: {'p_cart_id': cartId}),
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') return [];
      rethrow;
    }
  }

  Future<void> add({
    required String cartId,
    required String offeringId,
    required String exhibitorId,
    required int quantity,
    required Map<String, dynamic> answers,
    String? division,
    String? animalKey,
    String? selectionId,
    Map<String, dynamic>? registrationData,
  }) async {
    _writeAllowed();
    await _client.rpc(
      selectionId != null || registrationData != null
          ? 'save_contest_registration'
          : 'save_cart_addon',
      params: {
        'p_cart_id': cartId,
        'p_offering_id': offeringId,
        'p_exhibitor_id': exhibitorId,
        'p_quantity': quantity,
        'p_answers': answers,
        'p_division': division,
        'p_animal_key': animalKey,
        if (selectionId != null || registrationData != null)
          'p_selection_id': selectionId,
        if (selectionId != null || registrationData != null)
          'p_registration_data': registrationData ?? {},
      },
    );
  }

  Future<List<Map<String, dynamic>>> animals(
    String cartId,
    String exhibitorId,
  ) async => _rows(
    await _client.rpc(
      'get_contest_animals',
      params: {'p_cart_id': cartId, 'p_exhibitor_id': exhibitorId},
    ),
  );

  Future<void> remove(String id) async {
    _writeAllowed();
    await _client.rpc('remove_cart_addon', params: {'p_selection_id': id});
  }

  Future<List<Map<String, dynamic>>> registrations({
    String? showId,
    String? ownerId,
  }) async => _rows(
    await _client.rpc(
      'get_show_addon_registrations',
      params: {'p_show_id': showId, 'p_owner_id': ownerId},
    ),
  );
  Future<Map<String, dynamic>> walkupExhibitor(
    String offeringId,
    int number,
  ) async => Map<String, dynamic>.from(
    await _client.rpc(
      'get_contest_walkup_exhibitor',
      params: {'p_offering_id': offeringId, 'p_exhibitor_number': number},
    ),
  );
  Future<void> registerWalkup(
    String offeringId,
    String exhibitorId,
    String requestId,
    Map<String, dynamic> answers,
    String? division,
    String? animalKey,
    Map<String, dynamic> data,
  ) async {
    _writeAllowed();
    await _client.rpc(
      'register_contest_walkup',
      params: {
        'p_offering_id': offeringId,
        'p_exhibitor_id': exhibitorId,
        'p_request_id': requestId,
        'p_answers': answers,
        'p_division': division,
        'p_animal_key': animalKey,
        'p_registration_data': data,
      },
    );
  }

  Future<List<Map<String, dynamic>>> drafts(String cartId) async => _rows(
    await _client.rpc('get_contest_drafts', params: {'p_cart_id': cartId}),
  );
  Future<void> saveDraft(
    String cartId,
    String offeringId,
    String exhibitorId,
    String id,
    Map<String, dynamic> data,
  ) async {
    _writeAllowed();
    await _client.rpc(
      'save_contest_draft',
      params: {
        'p_cart_id': cartId,
        'p_offering_id': offeringId,
        'p_exhibitor_id': exhibitorId,
        'p_draft_id': id,
        'p_data': data,
      },
    );
  }

  Future<void> updateRegistration(
    String id,
    Map<String, dynamic> changes, {
    String reason = '',
    String? expectedAt,
  }) async {
    _writeAllowed();
    await _client.rpc(
      'update_contest_registration',
      params: {
        'p_selection_id': id,
        'p_changes': changes,
        'p_reason': reason,
        'p_expected_at': expectedAt,
      },
    );
  }

  Future<void> publish(String id, bool publish, {String reason = ''}) async {
    _writeAllowed();
    await _client.rpc(
      'publish_contest_results',
      params: {'p_offering_id': id, 'p_publish': publish, 'p_reason': reason},
    );
  }

  Future<List<Map<String, dynamic>>> results(String showId) async => _rows(
    await _client.rpc('get_contest_results', params: {'p_show_id': showId}),
  );
  Future<List<Map<String, dynamic>>> history(String offeringId) async => _rows(
    await _client.rpc(
      'get_contest_history',
      params: {'p_offering_id': offeringId},
    ),
  );
  Future<Map<String, dynamic>?> upload(String offeringId) async {
    _writeAllowed();
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'PDF or image',
          extensions: ['pdf', 'png', 'jpg', 'jpeg'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > 10 * 1024 * 1024) {
      throw StateError('Choose a file no larger than 10 MB.');
    }
    final extension = file.name.split('.').last.toLowerCase();
    final contentType = const {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
    }[extension];
    if (contentType == null) {
      throw StateError('Choose a PDF, PNG, or JPEG file.');
    }
    final bytes = await file.readAsBytes();
    final valid = extension == 'pdf'
        ? bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-'
        : extension == 'png'
        ? bytes.length >= 8 &&
              bytes[0] == 137 &&
              bytes[1] == 80 &&
              bytes[2] == 78 &&
              bytes[3] == 71
        : bytes.length >= 3 &&
              bytes[0] == 255 &&
              bytes[1] == 216 &&
              bytes[2] == 255;
    if (!valid) throw StateError('The file contents do not match its type.');
    final user = _client.auth.currentUser?.id;
    if (user == null) throw StateError('Sign in before uploading.');
    final path = '$offeringId/$user/${const Uuid().v4()}.$extension';
    await _client.storage
        .from('contest-submissions')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return {'path': path, 'name': file.name};
  }

  Future<void> openAttachment(Map<String, dynamic> attachment) async {
    final url = await _client.storage
        .from('contest-submissions')
        .createSignedUrl(attachment['path'].toString(), 300);
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Unable to open attachment.');
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List).map((r) => Map<String, dynamic>.from(r)).toList();
}
