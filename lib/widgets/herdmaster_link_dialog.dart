import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_session.dart';
import 'herdmaster_pilot_link_button.dart';

class HerdMasterLinkDialog extends StatefulWidget {
  const HerdMasterLinkDialog({super.key, this.pedigreeHQ = false});

  final bool pedigreeHQ;
  @override
  State<HerdMasterLinkDialog> createState() => _HerdMasterLinkDialogState();
}

class _HerdMasterLinkDialogState extends State<HerdMasterLinkDialog> {
  String get _partner => widget.pedigreeHQ ? 'PedigreeHQ' : 'HerdMaster';
  String get _provider => widget.pedigreeHQ ? 'pedigreehq' : 'herdmaster';

  StreamSubscription<AuthState>? _authChanges;
  final _account = TextEditingController();
  bool _consent = false;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _credentials;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _authChanges = client.auth.onAuthStateChange.listen((_) {
      if (mounted &&
          !HerdMasterPilotLinkButton.canShow(
            client.auth.currentUser,
            AppSession.householdOwnerUserId,
            AppSession.isSupportMode,
          )) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    _account.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final client = Supabase.instance.client;
    if (!HerdMasterPilotLinkButton.canShow(
      client.auth.currentUser,
      AppSession.householdOwnerUserId,
      AppSession.isSupportMode,
    )) {
      setState(
        () => _error = 'Sign in to your pilot account to link $_partner.',
      );
      return;
    }
    final id = _account.text.trim();
    if (id.isEmpty || id.length > 200 || !_consent) return;
    final actor = client.auth.currentUser!.id;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await client.functions.invoke(
        '$_provider-api/v1/connections',
        body: {'${_provider}_account_id': id, 'consent': true},
      );
      if (result.status != 201 ||
          result.data is! Map ||
          result.data['token'] is! String ||
          result.data['refresh_token'] is! String) {
        throw StateError('Connection unavailable');
      }
      if (!mounted) return;
      if (client.auth.currentUser?.id != actor ||
          !HerdMasterPilotLinkButton.canShow(
            client.auth.currentUser,
            AppSession.householdOwnerUserId,
            AppSession.isSupportMode,
          )) {
        Navigator.of(context).pop();
        return;
      }
      setState(
        () => _credentials = Map<String, dynamic>.from(result.data as Map),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Linking could not be confirmed. A connection may have been created. Linking again replaces its credentials; use the newest credentials for setup.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credentials = _credentials;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          credentials == null
              ? 'Link $_partner'
              : '$_partner pilot credentials',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (credentials == null) ...[
                  Text(
                    'Enter the $_partner account ID supplied for your pilot setup. Linking again replaces that account connection’s credentials while preserving animal links.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _account,
                    enabled: !_saving,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: '$_partner account ID',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  CheckboxListTile(
                    value: _consent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _consent = value == true),
                    title: Text(
                      'Allow $_partner to view my existing Show animals for match review, send animal updates, and retrieve my results and exhibitor and leg reports.',
                    ),
                  ),
                ] else ...[
                  Text(
                    'The connection is authorized. Save these credentials for the agreed secure handoff to $_partner; they are shown only now. The automatic refresh integration still requires $_partner setup.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'Connection ID\n${credentials['connection_id']}\n\nAccess token\n${credentials['token']}\n\nAccess expires\n${credentials['expires_at']}\n\nRefresh token\n${credentials['refresh_token']}\n\nRefresh expires\n${credentials['refresh_expires_at']}',
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(credentials == null ? 'Cancel' : 'Done'),
          ),
          if (credentials == null)
            FilledButton(
              onPressed: _saving || !_consent || _account.text.trim().isEmpty
                  ? null
                  : _link,
              child: Text(_saving ? 'Linking…' : 'Authorize connection'),
            ),
        ],
      ),
    );
  }
}
