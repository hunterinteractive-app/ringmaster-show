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

  final _name = TextEditingController();
  final _location = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? _entryOpenAt;
  DateTime? _entryCloseAt;

  bool _published = false;

  String _timezone = 'America/Indiana/Indianapolis';
  String _showNameForTitle = 'Show';

  String _finalAwardMode = 'four_six_bis';

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
                        if (_msg != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_msg == 'Saved.')
                                  ? Colors.green.withOpacity(.08)
                                  : Colors.red.withOpacity(.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (_msg == 'Saved.')
                                    ? Colors.green.withOpacity(.25)
                                    : Colors.red.withOpacity(.25),
                              ),
                            ),
                            child: Text(
                              _msg!,
                              style: TextStyle(
                                color: (_msg == 'Saved.') ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        _buildSectionCard(
                          title: 'Basic Show Info',
                          children: [
                            TextField(
                              controller: _name,
                              enabled: !_saving,
                              decoration: const InputDecoration(
                                labelText: 'Show name (required)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _location,
                              enabled: !_saving,
                              decoration: const InputDecoration(
                                labelText: 'Location (required)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Dates',
                          children: [
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
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Entry Window',
                          subtitle: 'Date and time for when exhibitors can begin and stop entering.',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Entry open: ${_fmtDateTime(_entryOpenAt)}'),
                                ),
                                TextButton(
                                  onPressed: _saving ? null : _pickEntryOpenAt,
                                  child: const Text('Pick'),
                                ),
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _entryOpenAt = null),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Entry close: ${_fmtDateTime(_entryCloseAt)}'),
                                ),
                                TextButton(
                                  onPressed: _saving ? null : _pickEntryCloseAt,
                                  child: const Text('Pick'),
                                ),
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _entryCloseAt = null),
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
                                'If off, exhibitors won’t see this show in the public list.',
                              ),
                              value: _published,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _published = v),
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
                                  child: Text('Best 4-Class / Best 6-Class / Best in Show'),
                                ),
                                DropdownMenuItem(
                                  value: 'bis_ris',
                                  child: Text('Best in Show / Reserve in Show'),
                                ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(
                                        () => _finalAwardMode = v ?? 'four_six_bis',
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
                              subtitle: 'Select judges available for staff assignment',
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
                            _buildSettingsActionTile(
                              icon: Icons.edit_note,
                              title: 'Entry Management',
                              subtitle: 'Search, edit, scratch, move class, add notes',
                              onTap: _saving ? null : _openEntryManagement,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.bar_chart,
                              title: 'Breed Counts',
                              subtitle: 'Totals by breed/show',
                              onTap: _saving ? null : _openShowReports,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.print,
                              title: 'Print Packs',
                              subtitle: 'Check-In Sheets, Control Sheets, Coop Tags, Comment Cards',
                              onTap: _saving ? null : _openPrintPacks,
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Post-Show Operations',
                          children: [
                            _buildSettingsActionTile(
                              icon: Icons.fact_check,
                              title: 'Results Entry',
                              subtitle: 'Enter placements, DQs, and specials by class',
                              onTap: _saving ? null : _openResultsEntry,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.verified,
                              title: 'Results Validation',
                              subtitle: 'Check for missing or inconsistent results before publishing',
                              onTap: _saving ? null : _openResultsValidation,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.public,
                              title: 'Publish Results',
                              subtitle: 'Future: make finalized results visible to exhibitors and the public',
                              onTap: _saving ? null : _openPublishResultsFuture,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.request_quote,
                              title: 'Financial Closeout',
                              subtitle: 'Future: finalize balances and reconcile show payments',
                              onTap: _saving ? null : _openFinancialCloseoutLater,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.archive,
                              title: 'Close Show',
                              subtitle: 'Finalize, send reports, and lock/download copy',
                              onTap: _saving ? null : _openShowCloseout,
                            ),
                          ],
                        ),

                        _buildSectionCard(
                          title: 'Show Settings',
                          children: [
                            _buildSettingsActionTile(
                              icon: Icons.pets,
                              title: 'Breed Settings',
                              subtitle: 'Manage allowed breeds and varieties for this show',
                              onTap: _saving ? null : _openBreedSettings,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.view_module,
                              title: 'Show Sections',
                              subtitle: 'Open A/B, Youth A/B, and enabled section setup',
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
                            _buildSettingsActionTile(
                              icon: Icons.confirmation_number,
                              title: 'Sanction Numbers',
                              subtitle: 'Add or edit ARBA and breed/club sanction numbers',
                              onTap: _saving ? null : _openSanctions,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.attach_money,
                              title: 'Show Fees',
                              subtitle: 'Per-animal fees and optional discounts',
                              onTap: _saving ? null : _openFees,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.rule,
                              title: 'Show Rules',
                              subtitle: 'Validations like tattoo required, limits, and required fields',
                              onTap: _saving ? null : _openRules,
                            ),
                            _buildSettingsActionTile(
                              icon: Icons.payments,
                              title: 'Payment Settings',
                              subtitle: 'Day-of-show vs online payment setup',
                              onTap: _saving ? null : _openPaymentSettings,
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A623),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _saving ? null : _save,
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