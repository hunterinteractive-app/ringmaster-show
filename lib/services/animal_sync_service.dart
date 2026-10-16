import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LinkedAnimalProvider {
  final String key;
  final String name;
  final bool canRefresh;
  final DateTime? lastRefreshedAt;
  final String? unavailableReason;

  LinkedAnimalProvider.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      name = json['name'] as String,
      canRefresh = json['can_refresh'] == true,
      lastRefreshedAt = DateTime.tryParse(json['last_refreshed_at'] ?? ''),
      unavailableReason = json['unavailable_reason'] as String?;
}

/// One owner-scoped controller shared by My Animals and show entry.
/// This never schedules a background herd refresh.
class AnimalSyncController extends ChangeNotifier {
  AnimalSyncController(this.ownerId, {this.transport});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? transport;
  final String ownerId;
  List<LinkedAnimalProvider> providers = [];
  bool loading = false;
  bool refreshing = false;
  bool loaded = false;
  String? error;
  Future<void>? _loading;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    if (transport != null) return transport!({...body, 'owner_id': ownerId});
    final result = await Supabase.instance.client.functions
        .invoke('animal-sync', body: {...body, 'owner_id': ownerId})
        .timeout(const Duration(seconds: 90));
    if (result.status != 200 || result.data is! Map) {
      throw StateError('Animal refresh is unavailable. Please try again.');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    loading = true;
    notifyListeners();
    try {
      final data = await _call({'action': 'status'});
      providers = (data['providers'] as List)
          .map(
            (p) => LinkedAnimalProvider.fromJson(Map<String, dynamic>.from(p)),
          )
          .toList();
      loaded = true;
      error = data['status_warning'] as String?;
    } catch (_) {
      error = 'Linked account status could not be checked. Please retry.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> refresh() async {
    if (refreshing) return false;
    refreshing = true;
    error = null;
    notifyListeners();
    var succeeded = false;
    final failures = <String>[];
    try {
      // Separate requests let one provider fail without undoing another.
      for (final provider in providers.where((p) => p.canRefresh)) {
        try {
          final data = await _call({
            'action': 'refresh',
            'provider_key': provider.key,
          });
          if (data['refreshed'] != true) throw StateError('Refresh incomplete');
          succeeded = true;
        } catch (_) {
          failures.add(provider.name);
        }
      }
      await load();
      if (failures.isNotEmpty) {
        error =
            '${failures.join(', ')} could not refresh. Last successful times are unchanged; saved animals remain available.';
      }
      return succeeded;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }
}

class AnimalSyncService {
  static final _controllers = <String, AnimalSyncController>{};
  static String? _sessionUser;
  static AnimalSyncController forOwner(String ownerId) {
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (user != _sessionUser) {
      // Do not carry another signed-in user's linked account state forward.
      _controllers.clear();
      _sessionUser = user;
    }
    return _controllers.putIfAbsent(
      ownerId,
      () => AnimalSyncController(ownerId),
    );
  }
}
