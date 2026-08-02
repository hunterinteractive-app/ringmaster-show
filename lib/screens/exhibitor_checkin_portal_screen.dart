import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExhibitorCheckinPortalScreen extends StatefulWidget {
  const ExhibitorCheckinPortalScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  State<ExhibitorCheckinPortalScreen> createState() =>
      _ExhibitorCheckinPortalScreenState();
}

class _ExhibitorCheckinPortalScreenState
    extends State<ExhibitorCheckinPortalScreen> {
  final _supabase = Supabase.instance.client;
  final _exhibitorNumber = TextEditingController();
  final _lastName = TextEditingController();
  final _initials = TextEditingController();
  final _signature = TextEditingController();

  String? _sessionToken;
  Map<String, dynamic>? _portalData;
  bool _verifying = false;
  bool _completing = false;
  bool _entriesConfirmed = false;
  String _receiptPreference = 'no_receipt';
  String? _message;
  String? _showName;

  @override
  void dispose() {
    _exhibitorNumber.dispose();
    _lastName.dispose();
    _initials.dispose();
    _signature.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadShowName();
  }

  Future<void> _loadShowName() async {
    final portalToken = widget.initialToken?.trim() ?? '';
    if (portalToken.isEmpty) return;
    try {
      final response = await _supabase.rpc(
        'get_exhibitor_checkin_portal_show',
        params: {'p_portal_token': portalToken},
      );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(response as Map);
      final name = (data['show_name'] ?? '').toString().trim();
      if (name.isNotEmpty) setState(() => _showName = name);
    } catch (_) {
      // Verification will show the appropriate message if this link is no
      // longer available. Do not disclose why a public link is unavailable.
    }
  }

  Future<void> _verify() async {
    final portalToken = widget.initialToken?.trim() ?? '';
    if (portalToken.isEmpty) {
      setState(() => _message = 'This QR link is missing its check-in token.');
      return;
    }
    if (_exhibitorNumber.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      setState(() => _message = 'Enter your exhibitor number and last name.');
      return;
    }
    setState(() {
      _verifying = true;
      _message = null;
    });
    try {
      final response = await _supabase.rpc(
        'authenticate_exhibitor_checkin',
        params: {
          'p_portal_token': portalToken,
          'p_exhibitor_number': _exhibitorNumber.text.trim(),
          'p_last_name': _lastName.text.trim(),
        },
      );
      final session = Map<String, dynamic>.from(response as Map);
      _sessionToken = (session['session_token'] ?? '').toString();
      await _loadReview();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'We could not verify those details. Check them and try again.';
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _loadReview() async {
    if (_sessionToken == null || _sessionToken!.isEmpty) return;
    try {
      final response = await _supabase.rpc(
        'get_exhibitor_checkin_portal_data',
        params: {'p_session_token': _sessionToken},
      );
      if (!mounted) return;
      setState(() => _portalData = Map<String, dynamic>.from(response as Map));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _sessionToken = null;
        _portalData = null;
        _message = error.code == '42501'
            ? 'Your check-in session expired. Please verify again.'
            : 'We could not load your entries. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sessionToken = null;
        _portalData = null;
        _message = 'We could not load your entries. Please try again.';
      });
    }
  }

  Future<void> _completeCheckin() async {
    if (!_entriesConfirmed) {
      setState(
        () => _message = 'Please confirm that your entries are correct.',
      );
      return;
    }
    setState(() {
      _completing = true;
      _message = null;
    });
    try {
      await _supabase.rpc(
        'complete_exhibitor_checkin',
        params: {
          'p_session_token': _sessionToken,
          'p_entries_confirmed': true,
          'p_initials': _initials.text.trim(),
          'p_signature_data': _signature.text.trim(),
          'p_receipt_preference': _receiptPreference,
        },
      );
      await _loadReview();
      if (!mounted) return;
      setState(() => _message = 'Check-in complete. Thank you!');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Could not complete check-in: $error');
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _requestChange(Map<String, dynamic> entry) async {
    final earNumber = TextEditingController(text: _text(entry, 'tattoo'));
    final breed = TextEditingController(text: _text(entry, 'breed'));
    final variety = TextEditingController(text: _text(entry, 'variety'));
    final className = TextEditingController(text: _text(entry, 'class_name'));
    final sex = TextEditingController(text: _text(entry, 'sex'));
    final furVariety = TextEditingController(text: _text(entry, 'fur_variety'));
    final note = TextEditingController();
    final requestedChanges = <String, dynamic>{};
    var scratchRequested = false;
    final editableFields =
        <
              ({
                String key,
                String label,
                TextEditingController controller,
                String original,
              })
            >[
              (
                key: 'ear_number',
                label: 'Tattoo / Ear #',
                controller: earNumber,
                original: _text(entry, 'tattoo'),
              ),
              (
                key: 'breed',
                label: 'Breed',
                controller: breed,
                original: _text(entry, 'breed'),
              ),
              (
                key: 'variety',
                label: 'Variety',
                controller: variety,
                original: _text(entry, 'variety'),
              ),
              (
                key: 'class',
                label: 'Class',
                controller: className,
                original: _text(entry, 'class_name'),
              ),
              (
                key: 'sex',
                label: 'Sex',
                controller: sex,
                original: _text(entry, 'sex'),
              ),
              (
                key: 'fur_variety',
                label: 'Fur Variety',
                controller: furVariety,
                original: _text(entry, 'fur_variety'),
              ),
            ]
            .where((field) => _canRequestEdit(field.key))
            .toList();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: AppColors.pageBackground,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Request Entry Change',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.headerForeground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Update the details that need corrected. Your show secretary will review the request.',
                    style: TextStyle(
                      color: AppColors.headerForeground.withValues(alpha: .82),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (editableFields.isEmpty &&
                      !_canRequestEdit('scratch_entry'))
                    Text(
                      'This show does not currently allow entry changes through the portal. You can still leave a note for the show secretary.',
                      style: TextStyle(
                        color: AppColors.headerForeground.withValues(
                          alpha: .82,
                        ),
                      ),
                    ),
                  for (final field in editableFields) ...[
                    _changeRequestField(
                      label: field.label,
                      controller: field.controller,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_canRequestEdit('scratch_entry'))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      checkColor: AppColors.pageBackground,
                      fillColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.primaryButton
                            : AppColors.surface,
                      ),
                      value: scratchRequested,
                      onChanged: (value) => setDialogState(
                        () => scratchRequested = value ?? false,
                      ),
                      title: Text(
                        'Scratch this entry',
                        style: TextStyle(color: AppColors.headerForeground),
                      ),
                    ),
                  _changeRequestField(
                    label: 'Notes for the show secretary',
                    controller: note,
                    hintText: 'Describe anything else that needs corrected',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          for (final field in editableFields) {
                            final value = field.controller.text.trim();
                            if (value != field.original) {
                              requestedChanges[field.key] = value;
                            }
                          }
                          if (scratchRequested) {
                            requestedChanges['scratch_entry'] = true;
                          }
                          if (requestedChanges.isEmpty &&
                              note.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Change a field, select scratch, or add a note first.',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(context, true);
                        },
                        child: const Text('Submit Request'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (submitted == true) {
      try {
        final response = await _supabase.rpc(
          'submit_exhibitor_checkin_change_request',
          params: {
            'p_session_token': _sessionToken,
            'p_entry_id': entry['id'],
            'p_request_type': 'entry_edit',
            'p_requested_changes': requestedChanges,
            'p_note': note.text.trim(),
          },
        );
        if (mounted) {
          final result = Map<String, dynamic>.from(response as Map);
          final automatic = Map<String, dynamic>.from(
            result['automatic_changes'] as Map? ?? const {},
          );
          final pending = Map<String, dynamic>.from(
            result['pending_review_changes'] as Map? ?? const {},
          );
          await _loadReview();
          if (!mounted) return;
          setState(
            () => _message = automatic.isNotEmpty && pending.isNotEmpty
                ? 'Allowed changes were applied. The remaining changes were sent to the show secretary.'
                : automatic.isNotEmpty
                ? 'Your allowed changes were applied.'
                : 'Your change request was sent to the show secretary.',
          );
        }
      } catch (error) {
        if (mounted) {
          setState(() => _message = 'Could not submit request: $error');
        }
      }
    }
    earNumber.dispose();
    breed.dispose();
    variety.dispose();
    className.dispose();
    sex.dispose();
    furVariety.dispose();
    note.dispose();
  }

  bool _canRequestEdit(String field) {
    final checkin = _portalData?['checkin'];
    final rawPermissions = checkin is Map
        ? checkin['entry_edit_permissions']
        : null;
    final permissions = rawPermissions is Map
        ? rawPermissions.map((key, value) => MapEntry('$key', '$value'))
        : const <String, String>{};
    final permission = permissions[field];
    return permission == 'automatic' || permission == 'approval';
  }

  Widget _changeRequestField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.headerForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: hintText,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _entries {
    final raw = _portalData?['entries'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : const [];
  }

  String _text(Map<String, dynamic> map, String key) =>
      (map[key] ?? '').toString().trim();

  String _entryTitle(Map<String, dynamic> entry) {
    final tattoo = _text(entry, 'tattoo');
    final animal = _text(entry, 'animal_name');
    if (tattoo.isNotEmpty && animal.isNotEmpty && animal != tattoo) {
      return '$tattoo — $animal';
    }
    return tattoo.isNotEmpty ? tattoo : (animal.isNotEmpty ? animal : 'Entry');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RingMaster Check-In')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _portalData == null ? _buildVerify() : _buildReview(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerify() {
    final bright = AppColors.headerForeground;
    final muted = bright.withValues(alpha: 0.82);
    if ((widget.initialToken ?? '').trim().isEmpty) {
      return ListView(
        shrinkWrap: true,
        children: [
          Icon(
            Icons.qr_code_scanner_outlined,
            size: 72,
            color: AppColors.primaryButton,
          ),
          const SizedBox(height: 18),
          Text(
            'Exhibitor Check-In',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: bright),
          ),
          const SizedBox(height: 10),
          Text(
            'Use the QR code or check-in link provided by your show secretary to review your entries and complete check-in.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: muted),
          ),
          const SizedBox(height: 18),
          Text(
            'Need help? Please contact your show secretary.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        Icon(
          Icons.fact_check_outlined,
          size: 64,
          color: AppColors.primaryButton,
        ),
        const SizedBox(height: 18),
        Text(
          'Exhibitor Check-In',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: bright),
        ),
        if (_showName != null) ...[
          const SizedBox(height: 6),
          Text(
            _showName!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.primaryButton,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Enter the information from your show entry to review your entries and complete check-in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        _buildVerificationField(
          label: 'Exhibitor number',
          controller: _exhibitorNumber,
          hintText: 'Enter exhibitor number',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _buildVerificationField(
          label: 'Last name',
          controller: _lastName,
          hintText: 'Enter last name',
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verifying ? null : _verify(),
        ),
        if (_message != null) ...[
          const SizedBox(height: 14),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _verifying ? null : _verify,
          child: _verifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildVerificationField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.headerForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    final bright = AppColors.headerForeground;
    final muted = bright.withValues(alpha: 0.82);
    final show = Map<String, dynamic>.from(
      _portalData?['show'] as Map? ?? const {},
    );
    final exhibitor = Map<String, dynamic>.from(
      _portalData?['exhibitor'] as Map? ?? const {},
    );
    final grouped = <String, List<Map<String, dynamic>>>{};
    final checkin = Map<String, dynamic>.from(
      _portalData?['checkin'] as Map? ?? const {},
    );
    final isCompleted = _text(checkin, 'status') == 'completed';
    for (final entry in _entries) {
      final label = _text(entry, 'show_label').isEmpty
          ? 'Show entries'
          : _text(entry, 'show_label');
      grouped.putIfAbsent(label, () => []).add(entry);
    }
    return ListView(
      children: [
        Text(
          _text(show, 'name'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: bright),
        ),
        const SizedBox(height: 4),
        Text(
          'Checking in: ${_text(exhibitor, 'name')} ${_text(exhibitor, 'number').isEmpty ? '' : '• #${_text(exhibitor, 'number')}'}',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Text(
          'Review your entries',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: bright),
        ),
        const SizedBox(height: 4),
        Text(
          'These are the entries currently on file. You will be able to confirm or request changes in the next step.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        if (grouped.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No entries were found for this exhibitor. Please see the show secretary.',
              ),
            ),
          ),
        for (final group in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              group.key,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: bright),
            ),
          ),
          for (final entry in group.value)
            Card(
              child: ListTile(
                onTap: () => _requestChange(entry),
                title: Text(_entryTitle(entry)),
                subtitle: Text(
                  [
                    _text(entry, 'breed'),
                    _text(entry, 'variety'),
                    _text(entry, 'class_name'),
                    _text(entry, 'sex'),
                    if (entry['is_fur'] == true) 'Fur / Wool',
                  ].where((value) => value.isNotEmpty).join(' • '),
                ),
                trailing:
                    _text(entry, 'scratched_at').isNotEmpty ||
                        _text(entry, 'status').toLowerCase() == 'scratched'
                    ? const Chip(label: Text('Scratched'))
                    : const Chip(label: Text('Entered')),
              ),
            ),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: isCompleted
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Check-In Complete',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Your entry confirmation has been recorded.'),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Complete check-in',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _entriesConfirmed,
                        onChanged: _completing
                            ? null
                            : (value) => setState(
                                () => _entriesConfirmed = value ?? false,
                              ),
                        title: const Text(
                          'I confirm these entries are correct.',
                        ),
                      ),
                      if (checkin['require_initials'] == true) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _initials,
                          enabled: !_completing,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Your initials',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (checkin['require_signature'] == true) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _signature,
                          enabled: !_completing,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText:
                                'Digital signature (type your full name)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _receiptPreference,
                        decoration: const InputDecoration(
                          labelText: 'Receipt preference',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'email_receipt',
                            child: Text('Email receipt confirmation'),
                          ),
                          DropdownMenuItem(
                            value: 'no_receipt',
                            child: Text('No receipt needed'),
                          ),
                        ],
                        onChanged: _completing
                            ? null
                            : (value) => setState(
                                () =>
                                    _receiptPreference = value ?? 'no_receipt',
                              ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _completing ? null : _completeCheckin,
                        child: _completing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Complete Check-In'),
                      ),
                    ],
                  ),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _message!.contains('Could not')
                  ? Colors.red
                  : Colors.green,
            ),
          ),
        ],
      ],
    );
  }
}
