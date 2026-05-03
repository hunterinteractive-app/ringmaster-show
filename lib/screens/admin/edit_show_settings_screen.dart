// lib/screens/admin/edit_show_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import '../show_list_screen.dart';
import '../../services/club_service.dart';
import 'show_breed_settings_screen.dart';
import 'show_sanctions_dialog.dart';
import 'show_fees_dialog.dart';
import 'show_rules_dialog.dart';
import 'show_sections_dialog.dart';
import 'show_judges_dialog.dart';
import '../../widgets/rm_timezone_notice_banner.dart';

// ✅ Admin Operations (Pre-show) screens
import 'admin_entry_management_screen.dart';
import 'admin_show_reports_screen.dart';
import 'admin_print_packs_screen.dart';

// ✅ Admin Operations (Post-show) screens
import 'results/admin_results_entry_screen.dart';
import 'package:ringmaster_show/screens/admin/show_closeout.dart';

final supabase = Supabase.instance.client;

class EditShowSettingsScreen extends StatefulWidget {
  final String showId;

  const EditShowSettingsScreen({
    super.key,
    required this.showId,
  });

  @override
  State<EditShowSettingsScreen> createState() => _EditShowSettingsScreenState();
}

class _EditShowSettingsScreenState extends State<EditShowSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  final _name = TextEditingController();
  final _location = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? _entryOpenAt;
  DateTime? _entryCloseAt;

  bool _published = false;
  bool _isNationalShow = false;
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  String _timezone = 'America/Indiana/Indianapolis';
  String _showNameForTitle = 'Show';
  String _finalAwardMode = 'four_six_bis';

  List<Map<String, dynamic>> _clubs = [];
  String? _selectedClubId;
  String? _selectedClubName;
  bool _loadingClubs = false;
  bool _canSwitchHostingClub = false;
  bool _canManageHostingClubs = false;
  static const String _addClubActionValue = '__add_new_club__';
  static const String _manageClubsActionValue = '__manage_clubs__';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  DateTime _asLocal(DateTime dt) => dt.toLocal();

  String _effectiveShowName() {
    final n = _name.text.trim();
    return n.isEmpty ? _showNameForTitle : n;
  }

  bool _entryClosed() {
    if (_entryCloseAt == null) return false;
    return DateTime.now().isAfter(_entryCloseAt!.toLocal());
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '(not set)';
    final x = _asLocal(d);
    return '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '(not set)';
    final x = _asLocal(d);
    final hh = x.hour.toString().padLeft(2, '0');
    final mm = x.minute.toString().padLeft(2, '0');
    return '${_fmtDate(x)} $hh:$mm';
  }

  DateTime? _parseDateOnly(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  DateTime? _parseTs(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return DateTime.tryParse(s);
  }

  void _showPostShowPlaceholder({
    required String title,
    required String body,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _finalAwardModeLabel(String mode) {
    switch (mode) {
      case 'bis_ris':
        return 'Best in Show / Reserve in Show';
      case 'four_six_bis':
      default:
        return 'Best 4-Class / Best 6-Class / Best in Show';
    }
  }

  Future<void> _toggleShowLock() async {
    if (_isFinalized) return;

    final nextLocked = !_isLocked;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(nextLocked ? 'Lock Show?' : 'Unlock Show?'),
            content: Text(
              nextLocked
                  ? 'This will prevent setup changes like sections, fees, judges, sanctions, rules, and show details.\n\n Show data and report files may be retained on the server for up to 1 year.\n\nYou can unlock it at any time.'
                  : 'This will allow setup changes again. Only unlock if corrections are needed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(nextLocked ? 'Lock Show' : 'Unlock Show'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.from('shows').update({
        'is_locked': nextLocked,
        'locked_at': nextLocked ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', widget.showId);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _isLocked = nextLocked;
        _msg = nextLocked ? 'Show locked.' : 'Show unlocked.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Failed to update lock status: $e';
      });
    }
  }

  Future<void> _loadClubs() async {
    setState(() => _loadingClubs = true);

    try {
      final clubs = await ClubService.loadMyClubs();
      final canSwitch = await ClubService.canSwitchHostingClub();
      final canManage = clubs.isEmpty ? true : canSwitch;

      if (!mounted) return;
      setState(() {
        _clubs = clubs;
        _canSwitchHostingClub = canSwitch;
        _canManageHostingClubs = canManage;

        if ((_selectedClubId == null || _selectedClubId!.isEmpty) &&
            _clubs.isNotEmpty) {
          _selectedClubId = _clubs.first['id']?.toString();
          _selectedClubName = _clubs.first['name']?.toString();
        }

        // Keep the show's saved hosting club even if it is not in the user's club list.
        // This prevents existing shows from "falling back" to the first club on your account.
        if (_selectedClubId != null &&
            _selectedClubId!.isNotEmpty &&
            !_clubs.any((club) => club['id']?.toString() == _selectedClubId)) {
          _clubs.insert(0, {
            'id': _selectedClubId,
            'name': (_selectedClubName == null || _selectedClubName!.trim().isEmpty)
                ? 'Current Hosting Club'
                : _selectedClubName,
          });
        }

        if (_selectedClubId != null && _selectedClubId!.isNotEmpty) {
          final selected = _clubs.cast<Map<String, dynamic>?>().firstWhere(
                (club) => club?['id']?.toString() == _selectedClubId,
                orElse: () => null,
              );

          if (selected != null) {
            _selectedClubName = selected['name']?.toString();
          }
        }

        _loadingClubs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingClubs = false;
        _msg = 'Failed to load clubs: $e';
      });
    }
  }

  Future<void> _showAddClubDialog() async {
    final controller = TextEditingController();
    bool submitting = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final name = controller.text.trim();

              if (name.isEmpty) {
                setDialogState(() => errorText = 'Club name is required.');
                return;
              }

              setDialogState(() {
                submitting = true;
                errorText = null;
              });

              try {
                final created = await ClubService.createClub(name: name);

                if (!mounted) return;

                await _loadClubs();

                if (!mounted) return;
                setState(() {
                  _selectedClubId = created['id']?.toString();
                  _selectedClubName = created['name']?.toString();
                  _msg = 'Club added.';
                });

                Navigator.of(dialogContext).pop();
              } catch (e) {
                setDialogState(() {
                  submitting = false;
                  errorText = 'Failed to add club: $e';
                });
              }
            }

            return AlertDialog(
              title: const Text('Add New Club'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    enabled: !submitting,
                    decoration: InputDecoration(
                      labelText: 'Club name',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? 'Adding…' : 'Add Club'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showManageClubsDialog() async {
    final renamedValues = <String, TextEditingController>{};

    for (final club in _clubs) {
      final id = club['id']?.toString() ?? '';
      final name = (club['name'] ?? '').toString();
      renamedValues[id] = TextEditingController(text: name);
    }

    bool saving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> saveChanges() async {
              setDialogState(() {
                saving = true;
                errorText = null;
              });

              try {
                for (final club in _clubs) {
                  final id = club['id']?.toString() ?? '';
                  final originalName = (club['name'] ?? '').toString();
                  final updatedName = renamedValues[id]!.text.trim();

                  if (updatedName.isEmpty) {
                    throw Exception('Club names cannot be blank.');
                  }

                  if (updatedName != originalName) {
                    await ClubService.updateClub(
                      clubId: id,
                      name: updatedName,
                    );
                  }
                }

                if (!mounted) return;

                await _loadClubs();

                if (!mounted) return;
                setState(() {
                  _msg = 'Clubs updated.';
                });

                Navigator.of(dialogContext).pop();
              } catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = 'Failed to update clubs: $e';
                });
              }
            }

            return AlertDialog(
              title: const Text('Manage Clubs'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (errorText != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.red.withOpacity(.25),
                            ),
                          ),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      for (final club in _clubs) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller:
                                renamedValues[club['id']?.toString() ?? ''],
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Club name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: saving ? null : saveChanges,
                  child: Text(saving ? 'Saving…' : 'Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in renamedValues.values) {
      controller.dispose();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select(
            'id,name,location_name,start_date,end_date,timezone,is_published,is_national_show,entry_open_at,entry_close_at,final_award_mode,club_id,club_name,is_locked,locked_at,finalized_at',
          )
          .eq('id', widget.showId)
          .single();

      _showNameForTitle = (show['name'] ?? 'Show').toString();

      _name.text = (show['name'] ?? '').toString();
      _location.text = (show['location_name'] ?? '').toString();

      _startDate = _parseDateOnly(show['start_date']?.toString());
      _endDate = _parseDateOnly(show['end_date']?.toString());

      _timezone = (show['timezone'] ?? _timezone).toString();
      _published = show['is_published'] == true;
      _isNationalShow = show['is_national_show'] == true;
      _isLocked = show['is_locked'] == true;

      final finalizedAt = (show['finalized_at'] ?? '').toString().trim();
      _isFinalized = finalizedAt.isNotEmpty;

      _entryOpenAt = _parseTs(show['entry_open_at']?.toString());
      _entryCloseAt = _parseTs(show['entry_close_at']?.toString());

      _finalAwardMode = (show['final_award_mode'] ?? 'four_six_bis').toString();

      _selectedClubId = show['club_id']?.toString();
      _selectedClubName = show['club_name']?.toString();

      await _loadClubs();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  Future<void> _pickStartDate() async {
    final initial = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _startDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickEndDate() async {
    final initial = _endDate ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final base = current?.toLocal() ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (t == null) return null;

    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pickEntryOpenAt() async {
    final picked = await _pickDateTime(_entryOpenAt);
    if (picked == null) return;
    setState(() => _entryOpenAt = picked);
  }

  Future<void> _pickEntryCloseAt() async {
    final picked = await _pickDateTime(_entryCloseAt);
    if (picked == null) return;
    setState(() => _entryCloseAt = picked);
  }

  bool _validate() {
    if (_name.text.trim().isEmpty) {
      setState(() => _msg = 'Show name is required.');
      return false;
    }

    if (_location.text.trim().isEmpty) {
      setState(() => _msg = 'Location is required.');
      return false;
    }

    if (_selectedClubId == null || _selectedClubId!.isEmpty) {
      setState(() => _msg = 'Hosting club is required.');
      return false;
    }

    if (_startDate == null || _endDate == null) {
      setState(() => _msg = 'Start and end dates are required.');
      return false;
    }

    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _msg = 'End date can’t be before start date.');
      return false;
    }

    if (_entryOpenAt != null && _entryCloseAt != null) {
      if (_entryCloseAt!.isBefore(_entryOpenAt!)) {
        setState(() => _msg = 'Entry close can’t be before entry open.');
        return false;
      }
    }

    if (_finalAwardMode != 'four_six_bis' && _finalAwardMode != 'bis_ris') {
      setState(() => _msg = 'Final award mode is invalid.');
      return false;
    }

    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.from('shows').update({
        'name': _name.text.trim(),
        'location_name': _location.text.trim(),
        'start_date': _startDate!.toIso8601String().substring(0, 10),
        'end_date': _endDate!.toIso8601String().substring(0, 10),
        'timezone': _timezone,
        'is_published': _published,
        'is_national_show': _isNationalShow,
        'entry_open_at': _entryOpenAt?.toUtc().toIso8601String(),
        'entry_close_at': _entryCloseAt?.toUtc().toIso8601String(),
        'final_award_mode': _finalAwardMode,
        'club_id': _selectedClubId,
        'club_name': _selectedClubName,
      }).eq('id', widget.showId);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _showNameForTitle = _name.text.trim();
        _msg = 'Saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  Future<void> _openBreedSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShowBreedSettingsScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openSanctions() {
    ShowSanctionsDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );
  }

  void _openFees() {
    ShowFeesDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );
  }

  void _openRules() {
    ShowRulesDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );
  }

  void _openEntryManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEntryManagementScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openShowReports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShowReportsScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openPrintPacks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPrintPacksScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openResultsEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminResultsEntryScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

//  void _openResultsValidation() {
//    _showPostShowPlaceholder(
//      title: 'Results Validation',
//      body:
//          'This is the next post-show screen to build.\n\nUse it to review missing placements, inconsistent specials, and incomplete class results before publishing.',
//    );
//  }

  void _openPublishResultsFuture() {
    _showPostShowPlaceholder(
      title: 'Publish Results',
      body:
          'Planned for a future phase.\n\nThis will make finalized results visible to exhibitors and the public.',
    );
  }

  void _openFinancialCloseoutLater() {
    _showPostShowPlaceholder(
      title: 'Financial Closeout',
      body:
          'Planned for a later phase.\n\nThis will finalize balances, reconcile payments, and close the books for the show.',
    );
  }

  Future<void> _downloadLockedShowData() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final session = supabase.auth.currentSession;
      final accessToken = session?.accessToken;

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('You must be signed in to download the archive.');
      }

      final uri = Uri.parse(
        'https://yzjoycrvqkyfrksmaixf.supabase.co/functions/v1/export-locked-show-data',
      );

      final request = await html.HttpRequest.request(
        uri.toString(),
        method: 'POST',
        requestHeaders: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        sendData: jsonEncode({
          'show_id': widget.showId,
        }),
        responseType: 'arraybuffer',
      );

      final status = request.status ?? 0;
      if (status < 200 || status >= 300) {
        throw Exception('Export failed with status $status.');
      }

      final buffer = request.response as ByteBuffer;
      final bytes = Uint8List.view(buffer);

      final safeShowName = _effectiveShowName()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');

      final fileName =
          '${safeShowName}_locked_show_export_${DateTime.now().millisecondsSinceEpoch}.zip';

      final blob = html.Blob([bytes], 'application/zip');
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..download = fileName
        ..click();

      html.Url.revokeObjectUrl(url);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Locked show ZIP downloaded.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Download failed: $e';
      });
    }
  }

  void _openShowCloseout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShowCloseoutPage(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withOpacity(.05),
        ),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _statusBadge({
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(.05)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _statusBadge(
            text: _published ? 'Published' : 'Draft',
            icon: _published ? Icons.public : Icons.edit_note,
            color: _published ? Colors.green : Colors.grey,
          ),
          if (_isFinalized)
            _statusBadge(
              text: 'Finalized',
              icon: Icons.verified,
              color: Colors.green,
            )
          else if (_isLocked)
            _statusBadge(
              text: 'Locked',
              icon: Icons.lock,
              color: Colors.orange,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            Image.asset(
              'assets/images/ringmaster_show_logo.png',
              height: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Show Settings — $_showNameForTitle',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const ShowListScreen(),
                      ),
                      (route) => false,
                    );
                  },
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _saving ? null : _load,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF11285A),
              Color(0xFF0B1C43),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : SafeArea(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const RMTimezoneNoticeBanner(),
                        _buildStatusBanner(),
                        if (_msg != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_msg == 'Saved.' ||
                                      _msg == 'Show locked.' ||
                                      _msg == 'Show unlocked.')
                                  ? Colors.green.withOpacity(.08)
                                  : Colors.red.withOpacity(.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (_msg == 'Saved.' ||
                                        _msg == 'Show locked.' ||
                                        _msg == 'Show unlocked.')
                                    ? Colors.green.withOpacity(.25)
                                    : Colors.red.withOpacity(.25),
                              ),
                            ),
                            child: Text(
                              _msg!,
                              style: TextStyle(
                                color: (_msg == 'Saved.' ||
                                        _msg == 'Show locked.' ||
                                        _msg == 'Show unlocked.')
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        _buildSectionCard(
                          title: 'Basic Show Info',
                          children: [
                            TextField(
                              controller: _name,
                              enabled: !_saving && !_isReadOnly,
                              decoration: const InputDecoration(
                                labelText: 'Show name (required)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _location,
                              enabled: !_saving && !_isReadOnly,
                              decoration: const InputDecoration(
                                labelText: 'Location (required)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                           if (_loadingClubs) const LinearProgressIndicator(),
                           DropdownButtonFormField<String>(
                            value: _clubs.any((club) => club['id']?.toString() == _selectedClubId)
                                ? _selectedClubId
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Hosting Club',
                              border: const OutlineInputBorder(),
                              helperText: _clubs.isEmpty
                                  ? 'No active clubs found. Add your first hosting club to continue.'
                                  : _canSwitchHostingClub
                                      ? 'Select a hosting club, add a new club, or manage your existing clubs.'
                                      : 'Locked to your account. Upgrade to Multi-Club Hosting to change this.',
                            ),
                            items: [
                              ..._clubs.map((club) {
                                return DropdownMenuItem<String>(
                                  value: club['id'].toString(),
                                  child: Text((club['name'] ?? 'Club').toString()),
                                );
                              }),
                              if (_canManageHostingClubs)
                                const DropdownMenuItem<String>(
                                  value: _addClubActionValue,
                                  child: Row(
                                    children: [
                                      Icon(Icons.add, size: 18),
                                      SizedBox(width: 8),
                                      Text('Add New Club'),
                                    ],
                                  ),
                                ),
                              if (_canSwitchHostingClub && _clubs.isNotEmpty)
                                const DropdownMenuItem<String>(
                                  value: _manageClubsActionValue,
                                  child: Row(
                                    children: [
                                      Icon(Icons.settings, size: 18),
                                      SizedBox(width: 8),
                                      Text('Manage Clubs'),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (_saving || _isReadOnly || _loadingClubs || !_canManageHostingClubs)
                                ? null
                                : (value) async {
                                    if (value == null) return;

                                    if (value == _addClubActionValue) {
                                      await _showAddClubDialog();
                                      return;
                                    }

                                    if (value == _manageClubsActionValue) {
                                      await _showManageClubsDialog();
                                      return;
                                    }

                                    setState(() {
                                      _selectedClubId = value;

                                      final selected = _clubs.firstWhere(
                                        (c) => c['id'].toString() == value,
                                        orElse: () => <String, dynamic>{},
                                      );

                                      _selectedClubName = (selected['name'] ?? '').toString();
                                    });
                                  },
                          ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Show Date',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Show Start: ${_startDate == null ? '(required)' : _fmtDate(_startDate)}',
                                  ),
                                ),
                                TextButton(
                                  onPressed: (_saving || _isReadOnly) ? null : _pickStartDate,
                                  child: const Text('Pick'),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Show End: ${_endDate == null ? '(required)' : _fmtDate(_endDate)}',
                                  ),
                                ),
                                TextButton(
                                  onPressed: (_saving || _isReadOnly) ? null : _pickEndDate,
                                  child: const Text('Pick'),
                                ),
                              ],
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Entry Window',
                          subtitle:
                              'Date and time for when exhibitors can begin and stop entering.',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Entry open: ${_fmtDateTime(_entryOpenAt)}',
                                  ),
                                ),
                                TextButton(
                                  onPressed: (_saving || _isReadOnly) ? null : _pickEntryOpenAt,
                                  child: const Text('Pick'),
                                ),
                                TextButton(
                                  onPressed: (_saving || _isReadOnly) ? null : () => setState(() => _entryOpenAt = null),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Entry close: ${_fmtDateTime(_entryCloseAt)}',
                                  ),
                                ),
                                TextButton(
                                  onPressed: (_saving || _isReadOnly) ? null : _pickEntryCloseAt,
                                  child: const Text('Pick'),
                                ),
                                TextButton(
                                  onPressed: (_saving || _isReadOnly) ? null : () => setState(() => _entryCloseAt = null),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Timezone: $_timezone',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Publication & Awards',
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Published'),
                              subtitle: const Text(
                                'Controls whether this show is published.',
                              ),
                              value: _published,
                              onChanged: (_saving || _isReadOnly)
                                  ? null
                                  : (v) async {
                                      final previous = _published;

                                      setState(() {
                                        _published = v;
                                        _saving = true;
                                        _msg = null;
                                      });

                                      try {
                                        await supabase
                                            .from('shows')
                                            .update({
                                              'is_published': v,
                                            })
                                            .eq('id', widget.showId);

                                        if (!mounted) return;
                                        setState(() {
                                          _saving = false;
                                          _msg = v
                                              ? 'Show published.'
                                              : 'Show unpublished.';
                                        });
                                      } catch (e) {
                                        if (!mounted) return;
                                        setState(() {
                                          _published = previous;
                                          _saving = false;
                                          _msg = 'Failed to update publish status: $e';
                                        });
                                      }
                                    },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('National Show'),
                              subtitle: const Text(
                                'Enables national show reporting rules, including Top 10 Breed reporting.',
                              ),
                              value: _isNationalShow,
                              onChanged: (_saving || _isReadOnly)
                                  ? null
                                  : (v) => setState(() => _isNationalShow = v),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _finalAwardMode,
                              decoration: const InputDecoration(
                                labelText: 'Final award format',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'four_six_bis',
                                  child: Text(
                                    'Best 4-Class / Best 6-Class / Best in Show',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'bis_ris',
                                  child: Text(
                                    'Best in Show / Reserve in Show',
                                  ),
                                ),
                              ],
                              onChanged:
                                  (_saving || _isReadOnly)
                                      ? null
                                      : (v) => setState(
                                        () =>
                                            _finalAwardMode =
                                                v ?? 'four_six_bis',
                                      ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Current mode: ${_finalAwardModeLabel(_finalAwardMode)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Admin Operations (Pre-show)',
                          children: [
                            _buildSettingsActionTile(
                              icon: Icons.gavel,
                              title: 'Judges',
                              subtitle:
                                  'Select judges available for staff assignment',
                              onTap:
                                  _saving
                                      ? null
                                      : () async {
                                        final changed =
                                            await ShowJudgesDialog.open(
                                              context,
                                              showId: widget.showId,
                                              showName: _showNameForTitle,
                                            );
                                        if (changed == true && mounted) {
                                          setState(
                                            () => _msg = 'Judges updated.',
                                          );
                                        }
                                      },
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.edit_note,
                              title: 'Entry Management',
                              subtitle:
                                  'Search, edit, scratch, move class, add notes',
                              onTap: (_saving || _isReadOnly) ? null : _openEntryManagement,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.bar_chart,
                              title: 'Breed Counts',
                              subtitle: 'Totals by breed/show',
                              onTap: (_saving || _isReadOnly) ? null : _openShowReports,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.print,
                              title: 'Print Packs',
                              subtitle:
                                  'Check-In Sheets, Control Sheets, Coop Tags, Comment Cards',
                              onTap: (_saving || _isReadOnly) ? null : _openPrintPacks,
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Post-Show Operations',
                          children: [
                            _buildSettingsActionTile(
                              icon: Icons.fact_check,
                              title: 'Results Entry',
                              subtitle:
                                  'Enter placements, DQs, and specials by class',
                              onTap: (_saving || _isReadOnly) ? null : _openResultsEntry,
                            ),
//                            _buildSettingsActionTile(
//                              icon: Icons.verified,
//                              title: 'Results Validation',
//                              subtitle:
//                                  'Check for missing or inconsistent results before publishing',
//                              onTap: (_saving || _isReadOnly) ? null : _openResultsValidation,
//                            ),
//                            _buildSettingsActionTile(
//                              icon: Icons.public,
//                              title: 'Publish Results',
//                              subtitle:
//                                  'Future: make finalized results visible to exhibitors and the public',
//                              onTap: (_saving || _isReadOnly) ? null : _openPublishResultsFuture,
//                            ),
//                            _buildSettingsActionTile(
//                              icon: Icons.request_quote,
//                              title: 'Financial Closeout',
//                              subtitle:
//                                  'Future: finalize balances and reconcile show payments',
//                              onTap:
//                                  _saving ? null : _openFinancialCloseoutLater,
//                            ),
                            _buildSettingsActionTile(
                              icon: Icons.archive,
                              title: 'Close Show/Reports',
                              subtitle:
                                  'Finalize, send reports, and lock/download copy',
                              onTap: _saving ? null : _openShowCloseout,
                            ),
                            _buildSettingsActionTile(
                              icon: _isLocked ? Icons.lock_open : Icons.lock,
                              title: _isLocked ? 'Unlock Show' : 'Lock Show',
                              subtitle: _isFinalized
                                  ? 'Finalized shows cannot be unlocked.'
                                  : _isLocked
                                      ? 'Allow setup changes again if corrections are needed'
                                      : 'Prevent further setup changes before closeout',
                              onTap: (_saving || _isFinalized) ? null : _toggleShowLock,
                            ),
                            if (_isLocked)
                            _buildSettingsActionTile(
                              icon: Icons.download_for_offline,
                              title: 'Download Locked Show Data',
                              subtitle: 'Download a ZIP backup of this show’s entries, results, settings, and reports',
                              onTap: _saving ? null : _downloadLockedShowData,
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Show Settings',
                          children: [
                            _buildSettingsActionTile(
                              icon: Icons.pets,
                              title: 'Breed Settings',
                              subtitle:
                                  'Manage allowed breeds and varieties for this show',
                              onTap: (_saving || _isReadOnly) ? null : _openBreedSettings,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.view_module,
                              title: 'Modify Number of Shows',
                              subtitle:
                                  'Open A/B, Youth A/B, and setup',
                              onTap:
                                  (_saving || _isReadOnly)
                                      ? null
                                      : () async {
                                        await ShowSectionsDialog.open(
                                          context,
                                          showId: widget.showId,
                                          showName: _effectiveShowName(),
                                        );

                                        if (!mounted) return;
                                        await _load();
                                      },
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.confirmation_number,
                              title: 'Sanction Numbers',
                              subtitle:
                                  'Add or edit ARBA and breed/club sanction numbers',
                              onTap: (_saving || _isReadOnly) ? null : _openSanctions,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.attach_money,
                              title: 'Show Fees & Payments',
                              subtitle:
                                  'Per-animal fees, discounts, day-of-show, and online payment setup',
                              onTap: (_saving || _isReadOnly) ? null : _openFees,
                            ),
//                             _buildSettingsActionTile(
//                               icon: Icons.rule,
//                               title: 'Show Rules',
//                               subtitle:
//                                   'Validations like tattoo required, limits, and required fields',
//                               onTap: (_saving || _isReadOnly) ? null : _openRules,
//                             ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A623),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: (_saving || _isReadOnly) ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save Changes'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}