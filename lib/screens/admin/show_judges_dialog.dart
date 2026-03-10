import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1000,
            maxHeight: 760,
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
    _search.addListener(_runSearch);
    _loadAll();
  }

  @override
  void dispose() {
    _search.removeListener(_runSearch);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
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

      final an = aj is Map ? _judgeDisplayName(aj.cast<String, dynamic>()).toLowerCase() : '';
      final bn = bj is Map ? _judgeDisplayName(bj.cast<String, dynamic>()).toLowerCase() : '';

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
    final judgeId = (judge['id'] ?? '').toString();
    if (judgeId.isEmpty) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.from('judge_assignments').insert({
        'show_id': widget.showId,
        'judge_id': judgeId,
        'assignment_label': _judgeDisplayName(judge),
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
    final assignmentId = (assignment['id'] ?? '').toString();
    if (assignmentId.isEmpty) return;

    final judge = assignment['judges'];
    final judgeName = judge is Map ? _judgeDisplayName(judge.cast<String, dynamic>()) : 'this judge';

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

  Widget _filterBar() {
    final states = _availableStates();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _judgeTypeFilter,
              decoration: const InputDecoration(
                labelText: 'Judge Type',
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Judges')),
                DropdownMenuItem(value: 'rabbit', child: Text('Rabbit Judges')),
                DropdownMenuItem(value: 'cavy', child: Text('Cavy Judges')),
                DropdownMenuItem(value: 'dual', child: Text('Dual Judges')),
              ],
              onChanged: _saving
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
              onChanged: _saving
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
              ),
              items: const [
                DropdownMenuItem(value: 'name', child: Text('Name')),
                DropdownMenuItem(value: 'state', child: Text('State')),
              ],
              onChanged: _saving
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Judges — ${widget.showName}'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading || _saving ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _msg!,
                        style: TextStyle(
                          color: (_msg == 'Judge assigned.' || _msg == 'Judge removed.')
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _search,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Search judges to assign',
                      hintText: 'Name, ARBA number, type, email, city, state...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),

                _filterBar(),

                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Text(
                                'Assigned to Show (${_assigned.length})',
                                style: titleStyle,
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _assigned.isEmpty
                                  ? const Center(
                                      child: Text('No judges assigned to this show yet.'),
                                    )
                                  : ListView.separated(
                                      itemCount: _assigned.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, i) {
                                        final assignment = _assigned[i];
                                        final judge = assignment['judges'];
                                        final judgeMap = judge is Map
                                            ? judge.cast<String, dynamic>()
                                            : <String, dynamic>{};

                                        return ListTile(
                                          title: Text(_judgeDisplayName(judgeMap)),
                                          subtitle: Text(_judgeSubtitle(judgeMap)),
                                          trailing: IconButton(
                                            tooltip: 'Remove from show',
                                            icon: const Icon(Icons.remove_circle_outline),
                                            onPressed: _saving ? null : () => _removeAssignment(assignment),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: Theme.of(context).dividerColor),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Text(
                                'Available Judges (${_searchResults.length})',
                                style: titleStyle,
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _searchResults.isEmpty
                                  ? const Center(
                                      child: Text('No matching active judges found.'),
                                    )
                                  : ListView.separated(
                                      itemCount: _searchResults.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, i) {
                                        final judge = _searchResults[i];

                                        return ListTile(
                                          title: Text(_judgeDisplayName(judge)),
                                          subtitle: Text(_judgeSubtitle(judge)),
                                          trailing: IconButton(
                                            tooltip: 'Assign to show',
                                            icon: const Icon(Icons.add_circle_outline),
                                            onPressed: _saving ? null : () => _assignJudge(judge),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context, true),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}