import 'package:flutter/material.dart';
import '../models/show_addon.dart';
import 'show_addons_screen.dart';
import '../models/contest_settings.dart';
import '../services/app_session.dart';
import '../services/show_addon_service.dart';
import '../services/contest_report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../widgets/contests/contest_result_dialog.dart';

class ShowAddonRegistrationsScreen extends StatefulWidget {
  const ShowAddonRegistrationsScreen({
    super.key,
    this.showId,
    this.showName,
    this.kind,
    this.service,
  });
  final String? showId, showName, kind;
  final ShowAddonService? service;
  @override
  State<ShowAddonRegistrationsScreen> createState() =>
      _ShowAddonRegistrationsScreenState();
}

class _ShowAddonRegistrationsScreenState
    extends State<ShowAddonRegistrationsScreen> {
  late final _service = widget.service ?? ShowAddonService();
  bool _loading = true, _busy = false;
  String? _error, _contest, _division, _category, _session;
  String _search = '', _tab = 'Registrations', _currency = 'usd';
  List<Map<String, dynamic>> _rows = [], _offerings = [];
  bool get _manage => widget.showId != null && widget.kind == 'contest';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.registrations(
        showId: widget.showId,
        ownerId: widget.showId == null ? AppSession.householdOwnerUserId : null,
      );
      final catalog = _manage
          ? await _service.catalog(widget.showId!, admin: true)
          : null;
      if (mounted) {
        setState(() {
          _rows = rows
              .where((r) => widget.kind == null || r['kind'] == widget.kind)
              .toList();
          _currency = '${catalog?['currency'] ?? 'usd'}';
          _offerings = (catalog?['items'] as List? ?? [])
              .map((r) => Map<String, dynamic>.from(r))
              .where((r) => r['kind'] == 'contest')
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered => _rows
      .where(
        (r) =>
            (_contest == null || r['offering_id'] == _contest) &&
            (_division == null || r['division'] == _division) &&
            (_category == null ||
                r['registration_data']?['category'] == _category) &&
            (_session == null ||
                r['registration_data']?['session_name'] == _session) &&
            '${r['name']} ${r['exhibitor_name']} ${r['exhibitor_number']} ${contestEntryLabel(r)}'
                .toLowerCase()
                .contains(_search),
      )
      .toList();
  Map<String, dynamic>? get _offering =>
      _offerings.where((o) => o['id'] == _contest).firstOrNull;
  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(
    Map<String, dynamic> row,
    Map<String, dynamic> changes, {
    String reason = '',
  }) => _action(
    () => _service.updateRegistration(
      '${row['id']}',
      changes,
      reason: reason,
      expectedAt: row['operation_updated_at']?.toString(),
    ),
  );
  Future<void> _result(Map<String, dynamic> row) async {
    final o = _offerings
        .where((o) => o['id'] == row['offering_id'])
        .firstOrNull;
    final cfg = ContestSettings(
      Map<String, dynamic>.from(
        o?['contest_config'] as Map? ?? row['config_snapshot'] as Map? ?? {},
      ),
    );
    final edit = await showDialog<ContestResultEdit>(
      context: context,
      builder: (_) => ContestResultDialog(row: row, settings: cfg),
    );
    if (edit != null && mounted) {
      await _change(row, {'result': edit.result}, reason: edit.reason);
    }
  }

  Future<void> _publish() async {
    final o = _offering!;
    final published = o['results_published_at'] != null;
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.surfaceTheme(Theme.of(context)),
        child: AlertDialog(
          title: Text(
            published ? 'Reopen results' : 'Publish ${o['name']} results',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  published
                      ? 'Results will be hidden from exhibitors while you make corrections.'
                      : 'Publish the reviewed placings and awards for this contest. Exhibitors will be able to see their results. Applications, birthdates, and contact details remain private.',
                ),
                if (published)
                  TextField(
                    controller: reason,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Reason for reopening *',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (published && reason.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: Text(published ? 'Reopen' : 'Publish'),
            ),
          ],
        ),
      ),
    );
    final note = reason.text.trim();
    reason.dispose();
    if (yes == true && mounted) {
      await _action(
        () => _service.publish('${o['id']}', !published, reason: note),
      );
    }
  }

  Future<void> _walkup() async {
    final o = _offering!;
    final number = TextEditingController();
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.surfaceTheme(Theme.of(context)),
        child: AlertDialog(
          title: const Text('Register a Walk-Up'),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Exhibitor number',
                helperText:
                    'The exhibitor must already have a RingMaster exhibitor number.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(number.text);
                if (n != null) Navigator.pop(context, n);
              },
              child: const Text('Find Exhibitor'),
            ),
          ],
        ),
      ),
    );
    number.dispose();
    if (chosen == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ex = await _service.walkupExhibitor('${o['id']}', chosen);
      if (!mounted) return;
      final result = await showDialog<AddonEntryValues>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AddonEntryDialog(
          item: ShowAddon.fromJson(o),
          currency: _currency,
          animals: (ex['animals'] as List)
              .map((a) => Map<String, dynamic>.from(a))
              .toList(),
          exhibitorName: '${ex['name']} • #${ex['number']}',
          upload: () => _service.upload('${o['id']}'),
          openFile: _service.openAttachment,
          allowDraft: false,
          submitLabel: 'Register & Add Balance',
        ),
      );
      if (result != null) {
        await _service.registerWalkup(
          '${o['id']}',
          '${ex['id']}',
          result.selectionId!,
          result.answers,
          result.division,
          result.animalKey,
          result.registrationData,
        );
        if (mounted) await _load();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history() async {
    try {
      final rows = await _service.history(_contest!);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Theme(
          data: AppTheme.surfaceTheme(Theme.of(context)),
          child: AlertDialog(
            title: const Text('Contest history'),
            content: SizedBox(
              width: 600,
              height: 480,
              child: ListView(
                children: [
                  if (rows.isEmpty) const Text('No changes recorded yet.'),
                  for (final r in rows)
                    ListTile(
                      title: Text('${r['action']} • ${r['created_at']}'),
                      subtitle: Text(
                        '${r['reason'] ?? ''}\n${r['after_value'] ?? ''}\nBy ${r['actor_id']}',
                      ),
                    ),
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
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Widget _filter(
    String label,
    String? value,
    Iterable<String> values,
    ValueChanged<String?> changed,
  ) {
    final options = values.where((v) => v.isNotEmpty).toSet().toList()..sort();
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value:${options.join()}'),
        initialValue: options.contains(value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('All')),
          for (final v in options)
            DropdownMenuItem(
              value: v,
              child: Text(v, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _busy ? null : (v) => changed(v == '' ? null : v),
      ),
    );
  }

  Future<void> _export(String value) async {
    final parts = value.split(':');
    setState(() => _busy = true);
    try {
      await ContestReportService.download(
        _filtered,
        title:
            '${widget.showName ?? 'Contests'}${parts[0] == 'results' && _filtered.any((r) => r['results_published_at'] == null) ? ' — DRAFT' : ''}',
        type: parts[0],
        asCsv: parts[1] == 'csv',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    useScrollView: true,
    title: _manage
        ? 'Manage Contests'
        : widget.kind == 'extra'
        ? 'Add-On Orders'
        : 'My Contests & Add-Ons',
    subtitle: widget.showName,
    showBackButton: true,
    actions: [
      IconButton(
        tooltip: 'Reload',
        icon: const Icon(Icons.refresh),
        onPressed: _busy ? null : _load,
      ),
    ],
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : AppTheme.surfaceTextScope(
            context,
            child: Card(
              color: Colors.white,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_manage) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tab in [
                            'Registrations',
                            'Check-In',
                            'Results',
                          ])
                            ChoiceChip(
                              label: Text(tab),
                              selected: _tab == tab,
                              onSelected: (_) => setState(() => _tab = tab),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _contest ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Contest'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All contests'),
                          ),
                          for (final o in _offerings)
                            DropdownMenuItem(
                              value: '${o['id']}',
                              child: Text('${o['name']}'),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _contest = v == '' ? null : v;
                                _division = null;
                                _category = null;
                                _session = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _filter(
                            'Division',
                            _division,
                            _rows
                                .where(
                                  (r) =>
                                      _contest == null ||
                                      r['offering_id'] == _contest,
                                )
                                .map((r) => '${r['division'] ?? ''}'),
                            (v) => setState(() => _division = v),
                          ),
                          _filter(
                            'Category',
                            _category,
                            _rows
                                .where(
                                  (r) =>
                                      _contest == null ||
                                      r['offering_id'] == _contest,
                                )
                                .map(
                                  (r) =>
                                      '${r['registration_data']?['category'] ?? ''}',
                                ),
                            (v) => setState(() => _category = v),
                          ),
                          _filter(
                            'Session',
                            _session,
                            _rows
                                .where(
                                  (r) =>
                                      _contest == null ||
                                      r['offering_id'] == _contest,
                                )
                                .map(
                                  (r) =>
                                      '${r['registration_data']?['session_name'] ?? ''}',
                                ),
                            (v) => setState(() => _session = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          PopupMenuButton<String>(
                            tooltip: 'Download report',
                            onSelected: _export,
                            enabled: !_busy,
                            itemBuilder: (_) => [
                              for (final type in const {
                                'roster': 'Contest roster',
                                'teams': 'Team roster',
                                'checkin': 'Check-in list',
                                'labels': 'Project labels',
                                'results': 'Placings & awards',
                              }.entries)
                                for (final format in ['pdf', 'csv'])
                                  PopupMenuItem(
                                    value: '${type.key}:$format',
                                    child: Text(
                                      '${type.value} (${format.toUpperCase()})',
                                    ),
                                  ),
                            ],
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Download PDF / CSV'),
                            ),
                          ),
                          if (_offering != null && _tab == 'Results')
                            FilledButton(
                              onPressed: _busy || AppSession.isSupportMode
                                  ? null
                                  : _publish,
                              child: Text(
                                _offering!['results_published_at'] == null
                                    ? 'Review & Publish'
                                    : 'Reopen Results',
                              ),
                            ),
                          if (_offering?['contest_config']?['allow_walkup'] ==
                                  true &&
                              _tab == 'Registrations')
                            FilledButton.icon(
                              onPressed: _busy || AppSession.isSupportMode
                                  ? null
                                  : _walkup,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Register Walk-Up'),
                            ),
                          if (_contest != null)
                            TextButton(
                              onPressed: _busy ? null : _history,
                              child: const Text('History'),
                            ),
                        ],
                      ),
                      if (_tab == 'Results')
                        const Text(
                          'Record the judges’ decisions here. Draft results stay private until published. Every accepted entry needs a recorded status before publishing.',
                        ),
                    ],
                    TextField(
                      decoration: const InputDecoration(
                        labelText:
                            'Search name, exhibitor, team, project, or number',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) =>
                          setState(() => _search = v.toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_filtered.length} completed registrations / orders',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SelectableText(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    if (_rows.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No registrations or orders have been submitted yet. Items still in a cart appear after checkout.',
                        ),
                      ),
                    for (final r in _filtered) _row(r),
                  ],
                ),
              ),
            ),
          ),
  );
  Widget _row(Map<String, dynamic> r) {
    final data = Map<String, dynamic>.from(
      r['registration_data'] as Map? ?? {},
    );
    final team = data['team'] as Map?;
    final published = r['results_published_at'] != null;
    final writable = _manage && !_busy && !AppSession.isSupportMode;
    return Card(
      child: ExpansionTile(
        key: ValueKey('${r['id']}:$_tab'),
        title: Text(
          '${r['name']}${r['kind'] == 'extra' ? ' × ${r['quantity']}' : ''}',
        ),
        subtitle: Text(
          '${contestEntryLabel(r)} • #${r['exhibitor_number'] ?? '—'}\n${r['show_name']}\n${addonMoney((r['quantity'] as num).toInt() * (r['unit_price_cents'] as num).toInt(), r['currency'].toString())} • ${r['payment_status']}${r['kind'] == 'contest' ? '\n${r['division'] ?? ''}${data['category'] == null ? '' : ' • ${data['category']}'}\n${contestResultLabel(r['result'] == null ? null : Map<String, dynamic>.from(r['result']))}${_manage && !published ? ' (draft)' : ''}' : ''}',
        ),
        initiallyExpanded: _manage && _tab != 'Registrations',
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r['kind'] == 'contest')
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Approval: ${r['approval_status'] ?? 'accepted'}',
                  ),
                ),
                Chip(
                  label: Text(
                    r['checked_in'] == true ? 'Checked in' : 'Not checked in',
                  ),
                ),
                if (_manage && _tab == 'Check-In')
                  FilledButton.icon(
                    onPressed: writable
                        ? () => _change(r, {
                            'checked_in': r['checked_in'] != true,
                          })
                        : null,
                    icon: const Icon(Icons.how_to_reg),
                    label: Text(
                      r['checked_in'] == true ? 'Undo Check-In' : 'Check In',
                    ),
                  ),
                if (_manage && _tab == 'Registrations')
                  PopupMenuButton<String>(
                    enabled: writable && !published,
                    tooltip: 'Change approval',
                    onSelected: (v) => _change(r, {
                      'approval_status': v,
                      'checked_in': v == 'accepted' && r['checked_in'] == true,
                    }),
                    itemBuilder: (_) => [
                      for (final s in [
                        'accepted',
                        'pending',
                        'waitlisted',
                        'declined',
                      ])
                        PopupMenuItem(value: s, child: Text(s)),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Change Approval'),
                    ),
                  ),
                if (_manage && _tab == 'Results')
                  FilledButton(
                    onPressed:
                        writable &&
                            !published &&
                            r['approval_status'] == 'accepted'
                        ? () => _result(r)
                        : null,
                    child: const Text('Record Result'),
                  ),
              ],
            ),
          if (data['session_name'] != null)
            Text('Session: ${data['session_name']}'),
          if (team != null) ...[
            Text('Team: ${team['name']}'),
            if (team['organization'] != null)
              Text('Organization: ${team['organization']}'),
            for (final m in (team['members'] as List? ?? []))
              Text(
                '${m['name']} • ${m['alternate'] == true ? 'Alternate' : 'Active'}${m['exhibitor_number'] == null ? '' : ' • #${m['exhibitor_number']}'}',
              ),
          ],
          if (r['animal_snapshot'] != null)
            Text('Animal: ${r['animal_snapshot']['label']}'),
          for (final a in (data['animals'] as List? ?? []))
            Text('${a['role']}: ${a['label'] ?? a['source']}'),
          if (widget.showId != null)
            SelectableText('Email: ${r['email'] ?? '—'}'),
          for (final f in (r['fields'] as List? ?? []))
            if ((r['answers'] as Map?)?.containsKey(f['id']) == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: f['type'] == 'file' && r['answers'][f['id']] is Map
                    ? TextButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: Text(
                          '${f['label']}: ${r['answers'][f['id']]['name']}',
                        ),
                        onPressed: () async {
                          try {
                            await _service.openAttachment(
                              Map<String, dynamic>.from(r['answers'][f['id']]),
                            );
                          } catch (e) {
                            if (mounted) setState(() => _error = e.toString());
                          }
                        },
                      )
                    : SelectableText(
                        '${f['label']}: ${_answer(r['answers'][f['id']])}',
                      ),
              ),
        ],
      ),
    );
  }

  String _answer(dynamic value) => value == null || value == ''
      ? '—'
      : value is bool
      ? (value ? 'Yes' : 'No')
      : value is List
      ? value.join(', ')
      : value.toString();
}
