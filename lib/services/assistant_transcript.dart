import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'support_impersonation_session.dart';

/// Ordered, idempotent append queue. Failed entries retry on the next interaction.
class AssistantTranscript {
  final String conversationId;
  AssistantTranscript(this.conversationId);
  final _pending = <Map<String, dynamic>>[];
  int _ordinal = 0;
  bool _saving = false;
  String? _actor;
  bool failed = false;
  Future<void> append({
    required String role,
    required String content,
    required String page,
    required String topic,
    String source = 'chat',
  }) async {
    final client = Supabase.instance.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null || SupportImpersonationSession.isActive) return;
    _actor ??= actor;
    if (_actor != actor) return;
    _pending.add({
      'p_conversation': conversationId,
      'p_id': const Uuid().v4(),
      'p_ordinal': _ordinal++,
      'p_role': role,
      'p_content': content,
      'p_page': page,
      'p_topic': topic,
      'p_source': source,
    });
    if (_saving) return;
    _saving = true;
    try {
      while (_pending.isNotEmpty &&
          client.auth.currentUser?.id == _actor &&
          !SupportImpersonationSession.isActive) {
        await client
            .rpc('chester_append', params: _pending.first)
            .timeout(const Duration(seconds: 15));
        _pending.removeAt(0);
      }
      failed = _pending.isNotEmpty;
    } catch (_) {
      failed = true;
    } finally {
      _saving = false;
    }
  }
}
