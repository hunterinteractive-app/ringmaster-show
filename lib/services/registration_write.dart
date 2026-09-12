import 'dart:convert';

import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'package:ringmaster_show/reporting_core/network/transient_retry.dart';

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

/// One form submission retains its IDs after an exhausted/ambiguous response.
/// A successful save clears the draft so a later intentional submission is new.
class RegistrationWrite {
  String? _fingerprint;
  List<Map<String, dynamic>>? _pending;

  /// After an authoritative lookup verifies this one-row submission, release
  /// its draft so a subsequent intentional creation can receive a new ID.
  void acknowledgeExistingRow(String id) {
    if (_pending != null &&
        (_pending!.length != 1 || _pending!.single['id'] != id)) {
      throw StateError(
        'A different save is still pending. Reload before creating another record.',
      );
    }
    _pending = null;
    _fingerprint = null;
  }

  Future<List<Map<String, dynamic>>> save(
    SupabaseClient client,
    String table,
    List<Map<String, dynamic>> values, {
    Future<void> Function(Duration)? wait,
  }) async {
    final fingerprint = jsonEncode([table, _canonical(values)]);
    if (_pending != null && _fingerprint != fingerprint) {
      throw StateError(
        'A previous save is still pending. Retry with the same fields or reload to check the saved records.',
      );
    }
    _fingerprint = fingerprint;
    _pending ??= values
        .map(
          (value) => Map<String, dynamic>.from(
            jsonDecode(jsonEncode({'id': const Uuid().v4(), ...value})) as Map,
          ),
        )
        .toList();
    late List<Map<String, dynamic>> saved;
    try {
      saved = await insertRegistrationRows(
        client,
        table,
        _pending!,
        wait: wait,
      );
    } on PostgrestException catch (error) {
      // A definitive rejection did not commit the insert. Let the user correct
      // validation fields; uncertain responses and ID collisions keep the draft.
      if (!isTransientServiceError(error) && error.code != '23505') {
        _pending = null;
        _fingerprint = null;
      }
      rethrow;
    }
    _pending = null;
    _fingerprint = null;
    return saved;
  }
}

/// Inserts explicit IDs once. After an uncertain response, read back under the
/// caller's RLS before retrying only missing rows. Never overwrite a collision.
Future<List<Map<String, dynamic>>> insertRegistrationRows(
  SupabaseClient client,
  String table,
  List<Map<String, dynamic>> rows, {
  Future<void> Function(Duration)? wait,
}) async {
  if (!const {
    'animals',
    'exhibitors',
    'entry_carts',
    'entry_cart_items',
  }.contains(table)) {
    throw ArgumentError.value(table, 'table');
  }
  if (rows.isEmpty) return [];
  final ids = rows.map((row) => row['id']).toList();
  if (ids.any((id) => id is! String || id.isEmpty) ||
      ids.toSet().length != rows.length) {
    throw ArgumentError('Every registration row needs a unique, stable ID.');
  }
  List<Map<String, dynamic>> validate(List<Map<String, dynamic>> found) {
    final byId = {for (final row in found) row['id']: row};
    for (final wanted in rows) {
      final actual = byId[wanted['id']];
      if (actual == null) continue;
      for (final key in wanted.keys) {
        if (jsonEncode(_canonical(wanted[key])) !=
            jsonEncode(_canonical(actual[key]))) {
          throw StateError(
            'A saved record differs from this submission. Reload before saving again.',
          );
        }
      }
    }
    return found;
  }

  Future<List<Map<String, dynamic>>> read() async => validate(
    await client.from(table).select().inFilter('id', ids.cast<String>()),
  );
  var attempts = 0;
  return retryTransient(() async {
    final existing = attempts++ == 0 ? <Map<String, dynamic>>[] : await read();
    final present = existing.map((row) => row['id']).toSet();
    final missing = rows.where((row) => !present.contains(row['id'])).toList();
    if (missing.isEmpty) return existing;
    try {
      final inserted = await client.from(table).insert(missing).select();
      final result = validate([...existing, ...inserted]);
      if (result.length != rows.length) {
        throw StateError('The complete save could not be verified.');
      }
      return result;
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      final saved = await read();
      if (saved.length != rows.length) rethrow;
      return saved;
    }
  }, wait: wait);
}
