// lib/screens/admin/edit_show_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'show_breed_settings_screen.dart';
import 'show_sanctions_dialog.dart';
import 'show_fees_dialog.dart';
import 'show_rules_dialog.dart';
import 'show_payment_settings_dialog.dart';
import 'show_sections_dialog.dart';
import 'show_judges_dialog.dart';

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

  // Show fields
  final _name = TextEditingController();
  final _location = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? _entryOpenAt;
  DateTime? _entryCloseAt;

  bool _published = false;

  String _timezone = 'America/Indiana/Indianapolis';
  String _showNameForTitle = 'Show';

  // ✅ New show setting
  String _finalAwardMode = 'four_six_bis';

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------

  DateTime _asLocal(DateTime dt) => dt.toLocal();

  String _effectiveShowName() {
    final n = _name.text.trim();
    return n.isEmpty ? _showNameForTitle : n;
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

  // ---------- Load ----------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select(
            'id,name,location_name,start_date,end_date,timezone,is_published,entry_open_at,entry_close_at,final_award_mode',
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

      _entryOpenAt = _parseTs(show['entry_open_at']?.toString());
      _entryCloseAt = _parseTs(show['entry_close_at']?.toString());

      _finalAwardMode = (show['final_award_mode'] ?? 'four_six_bis').toString();

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------- Pickers ----------

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

  // ---------- Save ----------

  bool _validate() {
    if (_name.text.trim().isEmpty) {
      setState(() => _msg = 'Show name is required.');
      return false;
    }
    if (_location.text.trim().isEmpty) {
      setState(() => _msg = 'Location is required.');
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
        'entry_open_at': _entryOpenAt?.toUtc().toIso8601String(),
        'entry_close_at': _entryCloseAt?.toUtc().toIso8601String(),
        'final_award_mode': _finalAwardMode,
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

  // ---------- Navigation ----------

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

  void _openPaymentSettings() {
    ShowPaymentSettingsDialog.open(
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

  // ---------- Post-show ----------

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

  void _openResultsValidation() {
    _showPostShowPlaceholder(
      title: 'Results Validation',
      body:
          'This is the next post-show screen to build.\n\nUse it to review missing placements, inconsistent specials, and incomplete class results before publishing.',
    );
  }

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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Show Settings — $_showNameForTitle'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _saving ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_msg != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _msg!,
                                  style: TextStyle(
                                    color: (_msg == 'Saved.') ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          // Basic show info
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Show name (required)'),
                            enabled: !_saving,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _location,
                            decoration: const InputDecoration(labelText: 'Location (required)'),
                            enabled: !_saving,
                          ),
                          const SizedBox(height: 12),

                          // Dates
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Start: ${_startDate == null ? '(required)' : _fmtDate(_startDate)}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving ? null : _pickStartDate,
                                child: const Text('Pick'),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'End: ${_endDate == null ? '(required)' : _fmtDate(_endDate)}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving ? null : _pickEndDate,
                                child: const Text('Pick'),
                              ),
                            ],
                          ),

                          const Divider(height: 24),

                          // Entry window
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Entry window (date/time)',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: Text('Entry open: ${_fmtDateTime(_entryOpenAt)}')),
                              TextButton(
                                onPressed: _saving ? null : _pickEntryOpenAt,
                                child: const Text('Pick'),
                              ),
                              TextButton(
                                onPressed: _saving ? null : () => setState(() => _entryOpenAt = null),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(child: Text('Entry close: ${_fmtDateTime(_entryCloseAt)}')),
                              TextButton(
                                onPressed: _saving ? null : _pickEntryCloseAt,
                                child: const Text('Pick'),
                              ),
                              TextButton(
                                onPressed: _saving ? null : () => setState(() => _entryCloseAt = null),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Timezone: $_timezone',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),

                          const Divider(height: 24),

                          // Publish toggle
                          SwitchListTile(
                            title: const Text('Published'),
                            subtitle: const Text('If off, exhibitors won’t see this show in the public list.'),
                            value: _published,
                            onChanged: _saving ? null : (v) => setState(() => _published = v),
                          ),

                          // ✅ Pre-show Operations
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Admin Operations (Pre-show)',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 6),

                          ListTile(
                            leading: const Icon(Icons.gavel),
                            title: const Text('Judges'),
                            subtitle: const Text('Select judges available for staff assignment'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving
                                ? null
                                : () async {
                                    final changed = await ShowJudgesDialog.open(
                                      context,
                                      showId: widget.showId,
                                      showName: _showNameForTitle,
                                    );
                                    if (changed == true && mounted) {
                                      setState(() => _msg = 'Judges updated.');
                                    }
                                  },
                          ),

                          ListTile(
                            leading: const Icon(Icons.edit_note),
                            title: const Text('Entry Management'),
                            subtitle: const Text('Search, edit, scratch, move class, add notes'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openEntryManagement,
                          ),

                          ListTile(
                            leading: const Icon(Icons.bar_chart),
                            title: const Text('Breed Counts'),
                            subtitle: const Text('Totals by breed/show'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openShowReports,
                          ),

                          ListTile(
                            leading: const Icon(Icons.print),
                            title: const Text('Print Packs'),
                            subtitle: const Text('Check-In Sheets, Control Sheets, Coop Tags, Comment Cards'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openPrintPacks,
                          ),

                          const Divider(height: 24),

                          // ✅ Post-Show Operations
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Post-Show Operations',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 6),

                          ListTile(
                            leading: const Icon(Icons.fact_check),
                            title: const Text('Results Entry'),
                            subtitle: const Text('Enter placements, DQs, and specials by class'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openResultsEntry,
                          ),

                          ListTile(
                            leading: const Icon(Icons.verified),
                            title: const Text('Results Validation'),
                            subtitle: const Text('Check for missing or inconsistent results before publishing'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openResultsValidation,
                          ),

                          ListTile(
                            leading: const Icon(Icons.public),
                            title: const Text('Publish Results'),
                            subtitle: const Text('Future: make finalized results visible to exhibitors and the public'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openPublishResultsFuture,
                          ),

                          ListTile(
                            leading: const Icon(Icons.request_quote),
                            title: const Text('Financial Closeout'),
                            subtitle: const Text('Future: finalize balances and reconcile show payments'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openFinancialCloseoutLater,
                          ),

                          ListTile(
                            leading: const Icon(Icons.archive),
                            title: const Text('Close Show'),
                            subtitle: const Text('Finalize, Send Reports,Lock/Download copy'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openShowCloseout,
                          ),

                          const Divider(height: 24),

                          // ✅ Show Settings Operations
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Show Settings',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 6),

                          ListTile(
                            title: const Text('Breed Settings'),
                            subtitle: const Text('Manage allowed breeds/varieties for this show'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openBreedSettings,
                          ),

                          ListTile(
                            leading: const Icon(Icons.view_module),
                            title: const Text('Show Sections'),
                            subtitle: const Text('Open A/B, Youth A/B (enable the ones this show runs)'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving
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

                          ListTile(
                            leading: const Icon(Icons.confirmation_number),
                            title: const Text('Sanction Numbers'),
                            subtitle: const Text('Add/edit ARBA and breed/club sanction numbers'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openSanctions,
                          ),

                          ListTile(
                            leading: const Icon(Icons.attach_money),
                            title: const Text('Show Fees'),
                            subtitle: const Text('Per-animal fees and optional discounts'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openFees,
                          ),

                          ListTile(
                            leading: const Icon(Icons.rule),
                            title: const Text('Show Rules'),
                            subtitle: const Text('Validations like tattoo required, limits, required fields'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openRules,
                          ),

                          ListTile(
                            leading: const Icon(Icons.payments),
                            title: const Text('Payment Settings'),
                            subtitle: const Text('Day-of-show vs online (Stripe/Square later)'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _saving ? null : _openPaymentSettings,
                          ),

                          const Spacer(),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: Text(_saving ? 'Saving…' : 'Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}