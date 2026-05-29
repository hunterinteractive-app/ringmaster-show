// lib/screens/admin/show_judges_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';

final supabase = Supabase.instance.client;

class ShowJudgesDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const ShowJudgesDialog({
    super.key,
    required this.showId,
    required this.showName,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width < 700
                ? MediaQuery.of(context).size.width - 16
                : 1180,
            maxHeight: MediaQuery.of(context).size.height < 900
                ? MediaQuery.of(context).size.height * 0.94
                : 820,
          ),
          child: ShowJudgesDialog(
            showId: showId,
            showName: showName,
          ),
        ),
      ),
    );
  }

  @override
  State<ShowJudgesDialog> createState() => _ShowJudgesDialogState();
}

class _ShowJudgesDialogState extends State<ShowJudgesDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  final TextEditingController _search = TextEditingController();

  List<Map<String, dynamic>> _assigned = [];
  List<Map<String, dynamic>> _allActiveJudges = [];
  List<Map<String, dynamic>> _searchResults = [];

  String _judgeTypeFilter = 'all'; // all | rabbit | cavy | dual
  String _stateFilter = 'all'; // all | IN | OH | etc.
  String _sortBy = 'name'; // name | state

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      unawaited(_runSearch());
    });
    _loadAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select('is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();

      _isLocked = show['is_locked'] == true;
      _isFinalized = (show['finalized_at'] ?? '').toString().trim().isNotEmpty;
      await Future.wait([
        _loadAssigned(),
        _loadActiveJudges(),
      ]);

      if (!mounted) return;
      await _runSearch();

      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Failed to load judges: $e';
      });
    }
  }

  Future<void> _loadAssigned() async {
    final rows = await supabase
        .from('judge_assignments')
        .select(
          'id,show_id,judge_id,created_at,'
          'judges(id,display_name,name,first_name,last_name,arba_judge_number,judge_type,email,city,state,is_active)',
        )
        .eq('show_id', widget.showId);

    final list = (rows as List).cast<Map<String, dynamic>>();

    list.sort((a, b) {
      final aj = a['judges'];
      final bj = b['judges'];

      final an = aj is Map
          ? _judgeDisplayName(aj.cast<String, dynamic>()).toLowerCase()
          : '';
      final bn = bj is Map
          ? _judgeDisplayName(bj.cast<String, dynamic>()).toLowerCase()
          : '';

      return an.compareTo(bn);
    });

    _assigned = list;
  }

  Future<void> _loadActiveJudges() async {
    final rows = await supabase
        .from('judges')
        .select(
          'id,display_name,name,first_name,last_name,arba_judge_number,judge_type,email,city,state,is_active',
        )
        .eq('is_active', true);

    _allActiveJudges = (rows as List).cast<Map<String, dynamic>>();
  }

  Set<String> _assignedJudgeIds() {
    return _assigned
        .map((a) => (a['judge_id'] ?? '').toString())
        .where((x) => x.isNotEmpty)
        .toSet();
  }

  String _judgeNameOnly(Map<String, dynamic> judge) {
    final displayName = (judge['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    final name = (judge['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final first = (judge['first_name'] ?? '').toString().trim();
    final last = (judge['last_name'] ?? '').toString().trim();
    final full = ('$first $last').trim();

    return full.isNotEmpty ? full : '(Unnamed Judge)';
  }

  String _judgeDisplayName(Map<String, dynamic> judge) {
    final displayName = (judge['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    final name = (judge['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final first = (judge['first_name'] ?? '').toString().trim();
    final last = (judge['last_name'] ?? '').toString().trim();
    final arba = (judge['arba_judge_number'] ?? '').toString().trim();

    final full = ('$first $last').trim();
    if (full.isNotEmpty && arba.isNotEmpty) return '$full (#$arba)';
    if (full.isNotEmpty) return full;
    if (arba.isNotEmpty) return '#$arba';

    return '(Unnamed Judge)';
  }

  String _judgeSubtitle(Map<String, dynamic> judge) {
    final parts = <String>[];

    final arba = (judge['arba_judge_number'] ?? '').toString().trim();
    final judgeType = (judge['judge_type'] ?? '').toString().trim();
    final city = (judge['city'] ?? '').toString().trim();
    final state = (judge['state'] ?? '').toString().trim();
    final email = (judge['email'] ?? '').toString().trim();
    final isActive = judge['is_active'] == true;

    if (arba.isNotEmpty) parts.add('#$arba');
    if (judgeType.isNotEmpty) parts.add(judgeType);
    if (city.isNotEmpty || state.isNotEmpty) {
      parts.add(
        city.isNotEmpty && state.isNotEmpty
            ? '$city, $state'
            : (city.isNotEmpty ? city : state),
      );
    }
    if (email.isNotEmpty) parts.add(email);
    if (!isActive) parts.add('Inactive');

    return parts.join(' • ');
  }

  bool _matchesJudgeTypeFilter(Map<String, dynamic> judge) {
    if (_judgeTypeFilter == 'all') return true;

    final raw = (judge['judge_type'] ?? '').toString().trim().toLowerCase();

    switch (_judgeTypeFilter) {
      case 'rabbit':
        return raw.contains('rabbit') && !raw.contains('dual');
      case 'cavy':
        return raw.contains('cavy') && !raw.contains('dual');
      case 'dual':
        return raw.contains('dual');
      default:
        return true;
    }
  }

  List<String> _availableStates() {
    final states = _allActiveJudges
        .map((j) => (j['state'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    states.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return states;
  }

  int _compareJudges(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (_sortBy == 'state') {
      final aState = (a['state'] ?? '').toString().trim().toLowerCase();
      final bState = (b['state'] ?? '').toString().trim().toLowerCase();
      final stateCmp = aState.compareTo(bState);
      if (stateCmp != 0) return stateCmp;

      final aName = _judgeDisplayName(a).toLowerCase();
      final bName = _judgeDisplayName(b).toLowerCase();
      return aName.compareTo(bName);
    }

    final aName = _judgeDisplayName(a).toLowerCase();
    final bName = _judgeDisplayName(b).toLowerCase();
    final nameCmp = aName.compareTo(bName);
    if (nameCmp != 0) return nameCmp;

    final aState = (a['state'] ?? '').toString().trim().toLowerCase();
    final bState = (b['state'] ?? '').toString().trim().toLowerCase();
    return aState.compareTo(bState);
  }

  Future<void> _runSearch() async {
    if (!mounted) return;

    final term = _search.text.trim().toLowerCase();
    final assignedIds = _assignedJudgeIds();

    var list = _allActiveJudges.where((j) {
      final id = (j['id'] ?? '').toString();
      if (assignedIds.contains(id)) return false;

      if (!_matchesJudgeTypeFilter(j)) return false;

      if (_stateFilter != 'all') {
        final state = (j['state'] ?? '').toString().trim().toUpperCase();
        if (state != _stateFilter.toUpperCase()) return false;
      }

      if (term.isEmpty) return true;

      final haystack = [
        _judgeDisplayName(j),
        (j['name'] ?? '').toString(),
        (j['first_name'] ?? '').toString(),
        (j['last_name'] ?? '').toString(),
        (j['arba_judge_number'] ?? '').toString(),
        (j['judge_type'] ?? '').toString(),
        (j['email'] ?? '').toString(),
        (j['city'] ?? '').toString(),
        (j['state'] ?? '').toString(),
      ].join(' ').toLowerCase();

      return haystack.contains(term);
    }).toList();

    list.sort(_compareJudges);

    if (!mounted) return;
    setState(() {
      _searchResults = list.take(500).toList();
    });
  }

  Future<void> _assignJudge(Map<String, dynamic> judge) async {
    if (_isReadOnly) {
      setState(() {
        _msg = _isFinalized
            ? 'This show has been finalized. Judges can no longer be changed.'
            : 'This show is locked. Judges can no longer be changed.';
      });
      return;
    }
    final judgeId = (judge['id'] ?? '').toString();
    if (judgeId.isEmpty) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      await supabase.from('judge_assignments').insert({
        'show_id': widget.showId,
        'judge_id': judgeId,
        'assignment_label': _judgeNameOnly(judge),
      });

      await _loadAssigned();
      await _runSearch();

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Judge assigned.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Assign failed: $e';
      });
    }
  }

  Future<void> _removeAssignment(Map<String, dynamic> assignment) async {
    if (_isReadOnly) {
      setState(() {
        _msg = _isFinalized
            ? 'This show has been finalized. Judges can no longer be changed.'
            : 'This show is locked. Judges can no longer be changed.';
      });
      return;
    }
    final assignmentId = (assignment['id'] ?? '').toString();
    if (assignmentId.isEmpty) return;

    final judge = assignment['judges'];
    final judgeName = judge is Map
        ? _judgeDisplayName(judge.cast<String, dynamic>())
        : 'this judge';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Judge?'),
        content: Text('Remove $judgeName from ${widget.showName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      await supabase.from('judge_assignments').delete().eq('id', assignmentId);

      await _loadAssigned();
      await _runSearch();

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Judge removed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Remove failed: $e';
      });
    }
  }

  Widget _buildFilterBar() {
    final states = _availableStates();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _search,
            enabled: !_saving && !_isReadOnly,
            decoration: const InputDecoration(
              labelText: 'Search judges to assign',
              hintText: 'Name, ARBA number, type, email, city, state...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _judgeTypeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Judge Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Judges')),
                    DropdownMenuItem(
                      value: 'rabbit',
                      child: Text('Rabbit Judges'),
                    ),
                    DropdownMenuItem(
                      value: 'cavy',
                      child: Text('Cavy Judges'),
                    ),
                    DropdownMenuItem(value: 'dual', child: Text('Dual Judges')),
                  ],
                  onChanged: (_saving || _isReadOnly)
                      ? null
                      : (v) async {
                          setState(() {
                            _judgeTypeFilter = v ?? 'all';
                          });
                          await _runSearch();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _stateFilter,
                  decoration: const InputDecoration(
                    labelText: 'State',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All States'),
                    ),
                    ...states.map(
                      (state) => DropdownMenuItem(
                        value: state,
                        child: Text(state),
                      ),
                    ),
                  ],
                  onChanged: (_saving || _isReadOnly)
                      ? null
                      : (v) async {
                          setState(() {
                            _stateFilter = v ?? 'all';
                          });
                          await _runSearch();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sortBy,
                  decoration: const InputDecoration(
                    labelText: 'Sort By',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Name')),
                    DropdownMenuItem(value: 'state', child: Text('State')),
                  ],
                  onChanged: (_saving || _isReadOnly)
                      ? null
                      : (v) async {
                          setState(() {
                            _sortBy = v ?? 'name';
                          });
                          await _runSearch();
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required int count,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title ($count)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade300),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final success =
        _msg == 'Judge assigned.' || _msg == 'Judge removed.';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF11285A),
            Color(0xFF0B1C43),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/ringmaster_show_logo.png',
                  height: 38,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Judges — ${widget.showName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: _loading || _saving ? null : _loadAll,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Column(
                        children: [
                          if (_isReadOnly) ...[
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Text(
                                _isFinalized
                                    ? 'This show has been finalized. Judge assignments are view-only.'
                                    : 'This show is locked. Judge assignments are view-only.',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                          if (_msg != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: success
                                    ? Colors.green.withOpacity(.08)
                                    : Colors.red.withOpacity(.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: success
                                      ? Colors.green.withOpacity(.25)
                                      : Colors.red.withOpacity(.25),
                                ),
                              ),
                              child: Text(
                                _msg!,
                                style: TextStyle(
                                  color: success ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          _buildFilterBar(),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildPanel(
                                    title: 'Assigned to Show',
                                    count: _assigned.length,
                                    child: _assigned.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No judges assigned to this show yet.',
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: _assigned.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, i) {
                                              final assignment = _assigned[i];
                                              final judge =
                                                  assignment['judges'];
                                              final judgeMap = judge is Map
                                                  ? judge.cast<String, dynamic>()
                                                  : <String, dynamic>{};

                                              return ListTile(
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 6,
                                                ),
                                                title: Text(
                                                  _judgeDisplayName(judgeMap),
                                                ),
                                                subtitle: Text(
                                                  _judgeSubtitle(judgeMap),
                                                ),
                                                trailing: IconButton(
                                                  tooltip: 'Remove from show',
                                                  icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                  ),
                                                  onPressed: (_saving || _isReadOnly)
                                                      ? null
                                                      : () => _removeAssignment(
                                                            assignment,
                                                          ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  color: Theme.of(context).dividerColor,
                                ),
                                Expanded(
                                  child: _buildPanel(
                                    title: 'Available Judges',
                                    count: _searchResults.length,
                                    child: _searchResults.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No matching active judges found.',
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: _searchResults.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, i) {
                                              final judge = _searchResults[i];

                                              return ListTile(
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 6,
                                                ),
                                                title: Text(
                                                  _judgeDisplayName(judge),
                                                ),
                                                subtitle: Text(
                                                  _judgeSubtitle(judge),
                                                ),
                                                trailing: IconButton(
                                                  tooltip: 'Assign to show',
                                                  icon: const Icon(
                                                    Icons.add_circle_outline,
                                                  ),
                                                  onPressed: (_saving || _isReadOnly)
                                                      ? null
                                                      : () => _assignJudge(
                                                            judge,
                                                          ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Spacer(),
                              SizedBox(
                                width: 180,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4A623),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => Navigator.pop(context, true),
                                  child: const Text('Done'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}