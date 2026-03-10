// lib/screens/my_entries_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'my_animals_screen.dart';

final supabase = Supabase.instance.client;

class MyEntriesScreen extends StatefulWidget {
  const MyEntriesScreen({super.key});

  @override
  State<MyEntriesScreen> createState() => _MyEntriesScreenState();
}

class _MyEntriesScreenState extends State<MyEntriesScreen> {
  bool _loading = true;
  String? _msg;

  // show_id -> show row
  final Map<String, Map<String, dynamic>> _showsById = {};

  // section_id -> section row
  final Map<String, Map<String, dynamic>> _sectionsById = {};

  // exhibitor_id -> exhibitor row
  final Map<String, Map<String, dynamic>> _exhibitorsById = {};

  // Raw entries
  List<Map<String, dynamic>> _entries = [];

  // Show expansion state
  final Set<String> _expandedShowIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ------------------------------
  // Load
  // ------------------------------
  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _msg = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rows = await supabase
          .from('entries')
          .select(
            'id,show_id,exhibitor_id,animal_id,species,tattoo,breed,variety,sex,'
            'class_name,status,section_id,created_at,exhibitor_user_id',
          )
          .eq('exhibitor_user_id', user.id)
          .order('created_at', ascending: true);

      _entries = (rows as List).cast<Map<String, dynamic>>();

      final showIds =
          _entries.map((e) => (e['show_id'] ?? '').toString()).where((s) => s.isNotEmpty).toSet();

      if (showIds.isNotEmpty) {
        final shows = await supabase
            .from('shows')
            .select('id,name,start_date,entry_close_at')
            .inFilter('id', showIds.toList());

        _showsById
          ..clear()
          ..addAll({
            for (final s in (shows as List).cast<Map<String, dynamic>>()) s['id'].toString(): s,
          });

        final sections = await supabase
            .from('show_sections')
            .select('id,show_id,display_name,kind,letter,sort_order')
            .inFilter('show_id', showIds.toList());

        _sectionsById
          ..clear()
          ..addAll({
            for (final s in (sections as List).cast<Map<String, dynamic>>()) s['id'].toString(): s,
          });
      }

      final exhibitorIds =
          _entries.map((e) => (e['exhibitor_id'] ?? '').toString()).where((s) => s.isNotEmpty).toSet();

      if (exhibitorIds.isNotEmpty) {
        final exRows = await supabase
            .from('exhibitors')
            .select('id,showing_name,display_name')
            .inFilter('id', exhibitorIds.toList());

        _exhibitorsById
          ..clear()
          ..addAll({
            for (final e in (exRows as List).cast<Map<String, dynamic>>()) e['id'].toString(): e,
          });
      }

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

  // ------------------------------
  // Helpers
  // ------------------------------
  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  DateTime? _showStartDate(String showId) {
    return _parseTs(_showsById[showId]?['start_date']);
  }

  String _showTitle(String showId) {
    final s = _showsById[showId];
    if (s == null) return 'Show';
    final name = (s['name'] ?? 'Show').toString();
    final sd = _parseTs(s['start_date']);
    final date = sd == null ? '' : ' (${sd.toIso8601String().substring(0, 10)})';
    return '$name$date';
  }

  bool _deadlinePassedForShow(String showId) {
    final closeAt = _parseTs(_showsById[showId]?['entry_close_at']);
    if (closeAt == null) return false;
    return DateTime.now().isAfter(closeAt.toLocal());
  }

  /// ✅ Hide the entire show after 48 hours past show start_date.
  bool _hideShowAfter48h(String showId) {
    final sd = _showStartDate(showId);
    if (sd == null) return false; // if missing show date, don't hide
    final cutoff = sd.toLocal().add(const Duration(hours: 48));
    return DateTime.now().isAfter(cutoff);
  }

  String _exhibitorLabelById(String? exhibitorId) {
    final id = (exhibitorId ?? '').toString();
    if (id.isEmpty) return '(Unknown Exhibitor)';
    final e = _exhibitorsById[id];
    if (e == null) return '(Unknown Exhibitor)';
    final sn = (e['showing_name'] ?? '').toString().trim();
    if (sn.isNotEmpty) return sn;
    final dn = (e['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    return '(Unknown Exhibitor)';
  }

  String _sectionLabel(String? sectionId) {
    final id = (sectionId ?? '').toString();
    final s = _sectionsById[id];
    if (s == null) return 'Section';
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().trim();
    final letter = (s['letter'] ?? '').toString().trim();
    if (kind.isNotEmpty && letter.isNotEmpty) {
      return '${kind[0].toUpperCase()}${kind.substring(1)} $letter';
    }
    return 'Section';
  }

  // ------------------------------
  // Actions: Scratch/Edit
  // ------------------------------
  Future<void> _scratchEntry(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString() ?? '';
    if (id.isEmpty) return;

    try {
      await supabase.from('entries').update({'status': 'scratched'}).eq('id', id);
      await _load();
    } catch (e) {
      setState(() => _msg = 'Scratch failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadMyAnimals() async {
    final rows = await supabase
        .from('animals')
        .select('id,species,name,tattoo,breed,variety,sex,birth_date')
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final showId = entry['show_id']?.toString() ?? '';
    if (showId.isEmpty) return;

    if (_deadlinePassedForShow(showId)) {
      setState(() => _msg = 'Entry deadline passed. Editing is locked. You can still scratch entries.');
      return;
    }

    final animals = await _loadMyAnimals();

    final result = await showDialog<_EditEntryResult>(
      context: context,
      builder: (_) => _EditEntryDialogV2(
        initialClassName: (entry['class_name'] ?? '').toString(),
        initialAnimalId: (entry['animal_id'] ?? '').toString(),
        animals: animals,
        onAddNewAnimal: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
          );
        },
        reloadAnimals: _loadMyAnimals,
      ),
    );

    if (result == null) return;

    final newClass = result.className.trim();
    if (newClass.isEmpty) {
      setState(() => _msg = 'Class is required.');
      return;
    }

    final picked = animals.where((a) => (a['id'] ?? '').toString() == result.animalId).toList();
    if (picked.isEmpty) {
      setState(() => _msg = 'Selected animal not found.');
      return;
    }
    final a = picked.first;

    final rawSpecies = (a['species'] ?? '').toString().trim().toLowerCase();
    final species = (rawSpecies == 'rabbit' || rawSpecies == 'cavy') ? rawSpecies : null;
    if (species == null) {
      setState(() => _msg = 'Animal species must be rabbit or cavy.');
      return;
    }

    try {
      await supabase.from('entries').update({
        'animal_id': a['id'],
        'species': species,
        'tattoo': a['tattoo'],
        'breed': a['breed'],
        'variety': a['variety'],
        'sex': a['sex'],
        'class_name': newClass,
      }).eq('id', entry['id']);

      await _load();
    } catch (e) {
      setState(() => _msg = 'Edit failed: $e');
    }
  }

  // ------------------------------
  // Grouping: Show -> Exhibitor -> Entries
  // ------------------------------
  Map<String, Map<String, List<Map<String, dynamic>>>> _grouped() {
    final Map<String, Map<String, List<Map<String, dynamic>>>> out = {};
    for (final e in _entries) {
      final showId = (e['show_id'] ?? '').toString();
      final exhibitorId = (e['exhibitor_id'] ?? '').toString();

      if (showId.isEmpty) continue;
      out.putIfAbsent(showId, () => {});
      out[showId]!.putIfAbsent(exhibitorId, () => []);
      out[showId]![exhibitorId]!.add(e);
    }

    // sort entries in each exhibitor bucket
    for (final showBuckets in out.values) {
      for (final list in showBuckets.values) {
        list.sort((a, b) {
          final sa = _sectionLabel(a['section_id']);
          final sb = _sectionLabel(b['section_id']);
          final c1 = sa.compareTo(sb);
          if (c1 != 0) return c1;
          final ta = (a['tattoo'] ?? '').toString();
          final tb = (b['tattoo'] ?? '').toString();
          return ta.compareTo(tb);
        });
      }
    }

    return out;
  }

  // ------------------------------
  // UI
  // ------------------------------
  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();

    // ✅ Filter out shows older than 48 hours after show date
    final visibleShowIds = grouped.keys.where((showId) => !_hideShowAfter48h(showId)).toList()
      ..sort((a, b) => _showTitle(a).compareTo(_showTitle(b)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Entries'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visibleShowIds.isEmpty
              ? const Center(
                  child: Text(
                    'No recent entries.\n(Shows disappear here 48 hours after their show date.)',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_msg!, style: const TextStyle(color: Colors.red)),
                      ),

                    for (final showId in visibleShowIds) ...[
                      _ShowExpansionCard(
                        title: _showTitle(showId),
                        deadlinePassed: _deadlinePassedForShow(showId),
                        closeAt: _parseTs(_showsById[showId]?['entry_close_at']),
                        exhibitorBuckets: grouped[showId] ?? const {},
                        exhibitorLabel: _exhibitorLabelById,
                        sectionLabel: _sectionLabel,
                        onEdit: _editEntry,
                        onScratch: _scratchEntry,
                        initiallyExpanded: _expandedShowIds.contains(showId),
                        onExpandedChanged: (expanded) {
                          setState(() {
                            if (expanded) {
                              _expandedShowIds.add(showId);
                            } else {
                              _expandedShowIds.remove(showId);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
    );
  }
}

class _ShowExpansionCard extends StatelessWidget {
  final String title;
  final bool deadlinePassed;
  final DateTime? closeAt;

  // exhibitorId -> entries
  final Map<String, List<Map<String, dynamic>>> exhibitorBuckets;

  final String Function(String? exhibitorId) exhibitorLabel;
  final String Function(String? sectionId) sectionLabel;

  final Future<void> Function(Map<String, dynamic> entry) onEdit;
  final Future<void> Function(Map<String, dynamic> entry) onScratch;

  final bool initiallyExpanded;
  final ValueChanged<bool> onExpandedChanged;

  const _ShowExpansionCard({
    required this.title,
    required this.deadlinePassed,
    required this.closeAt,
    required this.exhibitorBuckets,
    required this.exhibitorLabel,
    required this.sectionLabel,
    required this.onEdit,
    required this.onScratch,
    required this.initiallyExpanded,
    required this.onExpandedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final exhibitorIds = exhibitorBuckets.keys.toList()
      ..sort((a, b) => exhibitorLabel(a).compareTo(exhibitorLabel(b)));

    final deadlineText = closeAt == null ? '(deadline not set)' : closeAt!.toLocal().toString();
    final totalEntries = exhibitorBuckets.values.fold<int>(0, (sum, list) => sum + list.length);

    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpandedChanged,
        title: Text(title),
        subtitle: Text('$totalEntries entries'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              deadlinePassed ? 'Entry deadline: PASSED' : 'Entry deadline: $deadlineText',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 24),

          for (final exId in exhibitorIds) ...[
            Text(exhibitorLabel(exId), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),

            ...exhibitorBuckets[exId]!.map((e) {
              final section = sectionLabel(e['section_id']);
              final tattoo = (e['tattoo'] ?? '').toString();
              final breed = (e['breed'] ?? '').toString();
              final variety = (e['variety'] ?? '').toString();
              final sex = (e['sex'] ?? '').toString();
              final cls = (e['class_name'] ?? '').toString();
              final status = (e['status'] ?? '').toString();
              final scratched = status.toLowerCase() == 'scratched';

              final canEdit = !deadlinePassed && !scratched;
              final canScratch = !scratched;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('$tattoo'),
                subtitle: Text('$breed • $variety • $sex\nClass: $cls\nStatus: $status\nSection: $section'),
                isThreeLine: true,
                trailing: (canEdit || canScratch)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canEdit)
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit),
                              onPressed: () => onEdit(e),
                            ),
                          if (canScratch)
                            IconButton(
                              tooltip: 'Scratch',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => onScratch(e),
                            ),
                        ],
                      )
                    : null,
              );
            }).toList(),

            const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _EditEntryResult {
  final String animalId;
  final String className;
  _EditEntryResult({required this.animalId, required this.className});
}

class _EditEntryDialogV2 extends StatefulWidget {
  final String initialAnimalId;
  final String initialClassName;
  final List<Map<String, dynamic>> animals;

  final Future<void> Function() onAddNewAnimal;
  final Future<List<Map<String, dynamic>>> Function() reloadAnimals;

  const _EditEntryDialogV2({
    required this.initialAnimalId,
    required this.initialClassName,
    required this.animals,
    required this.onAddNewAnimal,
    required this.reloadAnimals,
  });

  @override
  State<_EditEntryDialogV2> createState() => _EditEntryDialogV2State();
}

class _EditEntryDialogV2State extends State<_EditEntryDialogV2> {
  late List<Map<String, dynamic>> _animals;
  late String _animalId;
  late TextEditingController _classCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _animals = widget.animals;
    _animalId = widget.initialAnimalId;
    _classCtrl = TextEditingController(text: widget.initialClassName);
  }

  @override
  void dispose() {
    _classCtrl.dispose();
    super.dispose();
  }

  String _animalLabel(Map<String, dynamic> a) {
    final tattoo = (a['tattoo'] ?? '').toString().trim();
    final name = (a['name'] ?? '').toString().trim();
    final breed = (a['breed'] ?? '').toString().trim();
    final variety = (a['variety'] ?? '').toString().trim();
    final sex = (a['sex'] ?? '').toString().trim();
    final top = tattoo.isNotEmpty ? tattoo : (name.isNotEmpty ? name : (a['id'] ?? '').toString());
    return '$top — $breed • $variety • $sex';
  }

  Future<void> _addNewAnimal() async {
    setState(() => _busy = true);
    try {
      await widget.onAddNewAnimal();
      final refreshed = await widget.reloadAnimals();
      if (!mounted) return;

      setState(() {
        _animals = refreshed;
        final exists = _animals.any((a) => (a['id'] ?? '').toString() == _animalId);
        if (!exists && _animals.isNotEmpty) _animalId = (_animals.first['id'] ?? '').toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _animals.any((a) => (a['id'] ?? '').toString() == _animalId);

    return AlertDialog(
      title: const Text('Edit Entry'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: hasSelected ? _animalId : null,
                items: _animals.map((a) {
                  final id = (a['id'] ?? '').toString();
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(_animalLabel(a), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _busy ? null : (v) => setState(() => _animalId = v ?? _animalId),
                decoration: const InputDecoration(
                  labelText: 'Animal',
                  helperText: 'Swap to an existing animal from My Animals.',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addNewAnimal,
                  icon: const Icon(Icons.add),
                  label: const Text('Add new animal'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _classCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Class (required)',
                  hintText: 'Example: Jr Buck, Sr Doe, Int Buck, Open Sow',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _EditEntryResult(animalId: _animalId, className: _classCtrl.text),
                  );
                },
          child: Text(_busy ? 'Working…' : 'Save'),
        ),
      ],
    );
  }
}