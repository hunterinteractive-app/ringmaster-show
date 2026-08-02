import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShowCheckinSettingsDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ShowCheckinSettingsDialog(showId: showId, showName: showName),
    );
  }
}

class _ShowCheckinSettingsDialog extends StatefulWidget {
  const _ShowCheckinSettingsDialog({
    required this.showId,
    required this.showName,
  });

  final String showId;
  final String showName;

  @override
  State<_ShowCheckinSettingsDialog> createState() =>
      _ShowCheckinSettingsDialogState();
}

class _ShowCheckinSettingsDialogState
    extends State<_ShowCheckinSettingsDialog> {
  final _supabase = Supabase.instance.client;
  static const _permissions = <String, String>{
    'ear_number': 'Ear Number',
    'breed': 'Breed',
    'variety': 'Variety',
    'class': 'Class',
    'sex': 'Sex',
    'fur_variety': 'Fur Variety',
    'scratch_entry': 'Scratch Entry',
    'add_entry': 'Add Entry',
  };
  static const _permissionLabels = <String, String>{
    'disabled': 'Disabled',
    'automatic': 'Allowed automatically',
    'approval': 'Secretary approval required',
  };

  bool _loading = true;
  bool _saving = false;
  bool _isReadOnly = false;
  bool _isEnabled = false;
  bool _requireInitials = false;
  bool _requireSignature = false;
  DateTime? _opensAt;
  DateTime? _closesAt;
  String? _portalUrl;
  String? _message;
  final Map<String, String> _editPermissions = {
    for (final key in _permissions.keys) key: 'disabled',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final show = await _supabase
          .from('shows')
          .select('is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();
      final settings = await _supabase
          .from('show_checkin_settings')
          .select(
            'is_enabled,opens_at,closes_at,require_initials,require_signature,entry_edit_permissions',
          )
          .eq('show_id', widget.showId)
          .maybeSingle();
      if (!mounted) return;
      final rawPermissions = settings?['entry_edit_permissions'];
      final permissions = rawPermissions is Map
          ? rawPermissions.map((key, value) => MapEntry('$key', '$value'))
          : const <String, String>{};
      setState(() {
        _isReadOnly =
            show['is_locked'] == true ||
            (show['finalized_at'] ?? '').toString().trim().isNotEmpty;
        _isEnabled = settings?['is_enabled'] == true;
        _requireInitials = settings?['require_initials'] == true;
        _requireSignature = settings?['require_signature'] == true;
        _opensAt = DateTime.tryParse(
          '${settings?['opens_at'] ?? ''}',
        )?.toLocal();
        _closesAt = DateTime.tryParse(
          '${settings?['closes_at'] ?? ''}',
        )?.toLocal();
        for (final key in _permissions.keys) {
          final value = permissions[key];
          _editPermissions[key] = _permissionLabels.containsKey(value)
              ? value!
              : 'disabled';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message =
            'Check-In Settings are not installed in this database yet. '
            'Apply the Check-In Portal database update, then reopen this screen.';
      });
    }
  }

  Future<void> _save() async {
    if (_opensAt != null &&
        _closesAt != null &&
        !_closesAt!.isAfter(_opensAt!)) {
      setState(() => _message = 'Closing time must be after opening time.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _supabase.from('show_checkin_settings').upsert({
        'show_id': widget.showId,
        'is_enabled': _isEnabled,
        'opens_at': _opensAt?.toUtc().toIso8601String(),
        'closes_at': _closesAt?.toUtc().toIso8601String(),
        'require_initials': _requireInitials,
        'require_signature': _requireSignature,
        'entry_edit_permissions': _editPermissions,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _message = 'Check-In Settings saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Save failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generatePortalLink() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final token =
          await _supabase.rpc(
                'regenerate_show_checkin_portal_token',
                params: {'p_show_id': widget.showId},
              )
              as String;
      if (!mounted) return;
      setState(() {
        _portalUrl = 'https://checkin.ringmasterone.com/#/checkin?token=$token';
        _message =
            'New QR code and portal link generated. Previous links no longer work.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Could not generate a portal link: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDateTime({required bool opening}) async {
    final current = opening ? _opensAt : _closesAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (opening) {
        _opensAt = selected;
      } else {
        _closesAt = selected;
      }
    });
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Not scheduled';
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:${value.minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _loading || _saving || _isReadOnly;
    final foreground = AppColors.headerForeground;
    final mutedForeground = foreground.withValues(alpha: 0.82);
    final sectionStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w700,
    );
    return AlertDialog(
      backgroundColor: AppColors.pageBackground,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: AppColors.headerForeground,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.headerForeground),
      title: Text('Check-In Settings — ${widget.showName}'),
      content: SizedBox(
        width: 680,
        child: _loading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isReadOnly)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'This show is locked or finalized. Check-in settings are view-only.',
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Enable Exhibitor Check-In Portal',
                        style: TextStyle(color: foreground),
                      ),
                      subtitle: Text(
                        'Allow exhibitors to verify identity and complete check-in from the QR link.',
                        style: TextStyle(color: mutedForeground),
                      ),
                      value: _isEnabled,
                      onChanged: disabled
                          ? null
                          : (value) => setState(() => _isEnabled = value),
                    ),
                    Divider(color: foreground.withValues(alpha: 0.22)),
                    Text('Availability', style: sectionStyle),
                    _timeRow('Opens', _opensAt, true, disabled),
                    _timeRow('Closes', _closesAt, false, disabled),
                    Divider(color: foreground.withValues(alpha: 0.22)),
                    Text('Confirmation', style: sectionStyle),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      fillColor: const WidgetStatePropertyAll(
                        AppColors.headerForeground,
                      ),
                      checkColor: AppColors.pageBackground,
                      side: const BorderSide(
                        color: AppColors.headerForeground,
                        width: 2,
                      ),
                      title: Text(
                        'Require digital initials',
                        style: TextStyle(color: foreground),
                      ),
                      value: _requireInitials,
                      onChanged: disabled
                          ? null
                          : (value) => setState(
                              () => _requireInitials = value ?? false,
                            ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      fillColor: const WidgetStatePropertyAll(
                        AppColors.headerForeground,
                      ),
                      checkColor: AppColors.pageBackground,
                      side: const BorderSide(
                        color: AppColors.headerForeground,
                        width: 2,
                      ),
                      title: Text(
                        'Require signature capture',
                        style: TextStyle(color: foreground),
                      ),
                      value: _requireSignature,
                      onChanged: disabled
                          ? null
                          : (value) => setState(
                              () => _requireSignature = value ?? false,
                            ),
                    ),
                    Divider(color: foreground.withValues(alpha: 0.22)),
                    Text('Entry editing permissions', style: sectionStyle),
                    const SizedBox(height: 4),
                    for (final entry in _permissions.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.headerForeground,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _editPermissions[entry.key],
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              items: _permissionLabels.entries
                                  .map(
                                    (option) => DropdownMenuItem(
                                      value: option.key,
                                      child: Text(
                                        option.value,
                                        style: const TextStyle(
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: disabled
                                  ? null
                                  : (value) => setState(
                                      () => _editPermissions[entry.key] =
                                          value ?? 'disabled',
                                    ),
                            ),
                          ],
                        ),
                      ),
                    Divider(
                      height: 32,
                      color: foreground.withValues(alpha: 0.22),
                    ),
                    Text('Public QR link', style: sectionStyle),
                    const SizedBox(height: 6),
                    Text(
                      'Generate a new link when you are ready to distribute it. Regenerating immediately invalidates all earlier links.',
                      style: TextStyle(color: mutedForeground),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: disabled ? null : _generatePortalLink,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.header,
                        side: const BorderSide(color: AppColors.header),
                      ),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Generate New QR Code'),
                    ),
                    if (_portalUrl != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: BarcodeWidget(
                          barcode: Barcode.qrCode(),
                          data: _portalUrl!,
                          width: 210,
                          height: 210,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _portalUrl!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: foreground),
                      ),
                      Center(
                        child: TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _portalUrl!),
                            );
                            if (mounted) {
                              setState(() => _message = 'Portal link copied.');
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy Link'),
                        ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        style: TextStyle(
                          color:
                              _message!.contains('failed') ||
                                  _message!.contains('Could not')
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: disabled ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Settings'),
        ),
      ],
    );
  }

  Widget _timeRow(String label, DateTime? value, bool opening, bool disabled) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: ${_formatDateTime(value)}',
            style: const TextStyle(color: AppColors.headerForeground),
          ),
        ),
        TextButton(
          onPressed: disabled ? null : () => _pickDateTime(opening: opening),
          child: const Text('Set'),
        ),
        TextButton(
          onPressed: disabled
              ? null
              : () => setState(() {
                  if (opening) {
                    _opensAt = null;
                  } else {
                    _closesAt = null;
                  }
                }),
          child: const Text('Clear'),
        ),
      ],
    );
  }
}
