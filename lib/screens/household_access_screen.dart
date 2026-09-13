import '../services/app_session.dart';
import '../widgets/household_exhibitor_invite_row.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../services/household_session.dart';
import '../widgets/ringmaster_page_shell.dart';

class HouseholdAccessScreen extends StatefulWidget {
  const HouseholdAccessScreen({super.key});
  @override
  State<HouseholdAccessScreen> createState() => _HouseholdAccessScreenState();
}

class _HouseholdAccessScreenState extends State<HouseholdAccessScreen> {
  List<Map<String, dynamic>> _exhibitors = [];
  bool _sharingReady = false;
  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _invitations = [];
  bool get _readOnly => AppSession.isSupportMode;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String action = 'list', String? id}) async {
    if (_readOnly && action != 'list') return;
    setState(() {
      _busy = true;
      _error = null;
      _sharingReady = false;
    });
    try {
      final actor = AppSession.effectiveUserId;
      if (actor == null) throw StateError('Not signed in.');
      final rows = await Supabase.instance.client
          .from('exhibitors')
          .select('id,showing_name,display_name,email,type,birth_date')
          .eq('owner_user_id', actor)
          .eq('is_active', true)
          .order('display_name');
      _exhibitors = List<Map<String, dynamic>>.from(rows);
      if (_readOnly) {
        final snapshot = await Supabase.instance.client.rpc(
          'support_household_access',
          params: {'p_target_user_id': actor},
        );
        _households = List<Map<String, dynamic>>.from(snapshot['households']);
        _invitations = List<Map<String, dynamic>>.from(snapshot['invitations']);
      } else {
        await HouseholdSession.refresh(action: action, id: id);
        _households = HouseholdSession.households;
        _invitations = HouseholdSession.invitations;
        _sharingReady = true;
      }
    } on FunctionException catch (e) {
      _error = e.details is Map
          ? (e.details['error'] ?? 'Invitation email could not be sent.')
                .toString()
          : 'Invitation email could not be sent. Please try again.';
    } on PostgrestException catch (e) {
      _error = e.code == 'PGRST202'
          ? 'Household sharing is not available on this server yet.'
          : e.message;
    } catch (e) {
      _error = 'Unable to update household access: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<String> _saveAndSend(
    Map<String, dynamic> exhibitor,
    String email,
  ) async {
    if (_readOnly || !_sharingReady) {
      throw StateError('Household sharing is not available yet.');
    }
    final client = Supabase.instance.client;
    final actor = client.auth.currentUser;
    if (actor == null) throw StateError('Not signed in.');
    await client
        .from('exhibitors')
        .update({'email': email})
        .eq('id', exhibitor['id'])
        .eq('owner_user_id', actor.id)
        .select('id')
        .single();
    if (email == actor.email?.trim().toLowerCase()) {
      return 'Email saved. Your login already has household access.';
    }
    try {
      await HouseholdSession.sendInvitation(email);
    } catch (e) {
      throw Exception(
        'Email saved, but the invitation could not be sent. Please try Save and Send again.',
      );
    }
    try {
      await HouseholdSession.refresh();
      _households = HouseholdSession.households;
      _invitations = HouseholdSession.invitations;
      if (mounted) setState(() {});
    } catch (_) {
      return 'Email saved and invitation ready. Refresh to update the members list.';
    }
    return 'Email saved. The household invitation is ready.';
  }

  Widget _invitationCard(Map<String, dynamic> i, {bool inDialog = false}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i['is_owner'] == true
                    ? i['email'].toString()
                    : 'Household: ${i['owner_email']}',
                style: const TextStyle(color: Colors.black87),
              ),
              Text(
                i['accepted_at'] == null
                    ? 'Invitation pending'
                    : 'Household access active',
                style: const TextStyle(color: Colors.black87),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (i['is_owner'] != true && i['accepted_at'] == null)
                    FilledButton(
                      onPressed: (_busy || _readOnly)
                          ? null
                          : () {
                              if (inDialog) Navigator.pop(context);
                              _load(action: 'accept', id: i['id'].toString());
                            },
                      child: const Text('Accept'),
                    ),
                  TextButton(
                    onPressed: (_busy || _readOnly)
                        ? null
                        : () {
                            if (inDialog) Navigator.pop(context);
                            _load(action: 'revoke', id: i['id'].toString());
                          },
                    child: Text(
                      i['is_owner'] == true
                          ? 'Revoke access'
                          : i['accepted_at'] == null
                          ? 'Decline'
                          : 'Leave household',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _manageHousehold(Map<String, dynamic> household) async {
    final invitations = _invitations
        .where((i) => i['owner_user_id'] == household['owner_user_id'])
        .toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          household['is_owner'] == true
              ? 'Manage household access'
              : 'Shared household access',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (invitations.isEmpty)
                const Text('No invitations or shared access yet.'),
              for (final i in invitations) _invitationCard(i, inDialog: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'RingMaster Show',
    subtitle: 'Household Access',
    showBackButton: true,
    useScrollView: true,
    body: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_readOnly)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Support mode — household access is view-only.'),
            ),
          Text(
            _households.length > 1 ? 'Choose a household' : 'Your household',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Show Secretary and admin permissions stay with your own login.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          for (final h in _households)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                textColor: const Color(0xFF281B45),
                iconColor: const Color(0xFF3B2078),
                title: Text(
                  h['label'].toString(),
                  style: const TextStyle(
                    color: Color(0xFF281B45),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  h['is_owner'] == true
                      ? 'Your exhibitors, animals, and entries'
                      : 'Shared exhibitors, animals, and entries',
                  style: const TextStyle(
                    color: Color(0xFF4D465B),
                    height: 1.35,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (AppSession.householdOwnerUserId == h['owner_user_id'])
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFF3B2078),
                        semanticLabel: 'Current household',
                      ),
                    IconButton(
                      tooltip: 'Manage household access',
                      icon: const Icon(
                        Icons.more_vert,
                        color: Color(0xFF3B2078),
                      ),
                      onPressed: _busy ? null : () => _manageHousehold(h),
                    ),
                  ],
                ),
                onTap: (_busy || _readOnly)
                    ? null
                    : () {
                        HouseholdSession.select(h['owner_user_id'].toString());
                        setState(() {});
                      },
              ),
            ),
          for (final i in _invitations.where(
            (i) => i['is_owner'] != true && i['accepted_at'] == null,
          ))
            _invitationCard(i),
          const SizedBox(height: 20),
          const Text(
            'Exhibitor emails and invitations',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Assign each exhibitor their own email, then select Save and Send. Adults and youth aged 14 or older can accept an invitation to the entire household using their own login.',
          ),
          const SizedBox(height: 12),
          for (final exhibitor in _exhibitors)
            HouseholdExhibitorInviteRow(
              key: ValueKey(exhibitor['id']),
              exhibitor: exhibitor,
              enabled: !_busy && _sharingReady,
              onSave: (email) => _saveAndSend(exhibitor, email),
            ),
          if (!_busy && _exhibitors.isEmpty)
            const Text(
              'No active exhibitors in your household. Add exhibitors in Account Settings first.',
            ),
        ],
      ),
    ),
  );
}
