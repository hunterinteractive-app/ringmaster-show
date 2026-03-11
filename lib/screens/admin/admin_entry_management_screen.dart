// lib/screens/admin/admin_entry_management_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AdminEntryManagementScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminEntryManagementScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminEntryManagementScreen> createState() => _AdminEntryManagementScreenState();
}

class _AdminEntryManagementScreenState extends State<AdminEntryManagementScreen> {
  bool _loading = true;
  String? _msg;

  // Sections (Show letters)
  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  // Entries
  List<Map<String, dynamic>> _entries = [];

  // Search
  final _search = TextEditingController();

  // Expand/collapse memory per exhibitor
  final Set<String> _expandedExhibitorIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadAll();
    _search.addListener(() => setState(() {}));
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
      await _loadSections();
      await _loadEntries();
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

  Future<void> _loadSections() async {
    final rows = await supabase
        .from('show_sections')
        .select('id,letter,display_name,is_enabled,sort_order')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true)
        .order('sort_order', ascending: true);

    _sections = (rows as List).cast<Map<String, dynamic>>();

    if (_selectedSectionId == null && _sections.isNotEmpty) {
      _selectedSectionId = _sections.first['id']?.toString();
    }
  }

  Future<void> _loadEntries() async {
    var q = supabase
        .from('entries')
        .select(
          'id,show_id,section_id,exhibitor_id,exhibitor_user_id,animal_id,species,'
          'tattoo,breed,variety,sex,class_name,notes,status,created_at,updated_at,scratched_at,'
          'show_sections(id,letter,display_name),'
          // IMPORTANT: disambiguate embed relationship (you have multiple FKs)
          'exhibitors!entries_exhibitor_id_fkey(id,display_name,first_name,last_name)',
        )
        .eq('show_id', widget.showId);

    if (_selectedSectionId != null) {
      q = q.eq('section_id', _selectedSectionId!);
    }

    final res = await q.order('created_at', ascending: true);
    _entries = (res as List).cast<Map<String, dynamic>>();
  }

  String _sectionLabel(Map<String, dynamic> s) {
    final letter = (s['letter'] ?? '').toString();
    final dn = (s['display_name'] ?? '').toString();
    if (dn.isEmpty) return 'Show $letter';
    return '$dn ($letter)';
  }

  String _dateOnly(String? ts) {
    if (ts == null || ts.trim().isEmpty) return '';
    final dt = DateTime.tryParse(ts);
    if (dt == null) return '';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _exhibitorId(Map<String, dynamic> e) {
    final id = e['exhibitor_id'];
    return (id ?? '').toString();
  }

  String _exhibitorDisplayName(Map<String, dynamic> e) {
    final label = (e['exhibitor_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;

    final ex = e['exhibitors'];
    if (ex is Map<String, dynamic>) {
      final dn = (ex['display_name'] ?? '').toString().trim();
      if (dn.isNotEmpty) return dn;

      final first = (ex['first_name'] ?? '').toString().trim();
      final last = (ex['last_name'] ?? '').toString().trim();
      final combined = '$first $last'.trim();
      if (combined.isNotEmpty) return combined;
    }

    return '(Unknown exhibitor)';
  }

  bool _matchesSearch(Map<String, dynamic> e, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();

    final exhibitorName = _exhibitorDisplayName(e).toLowerCase();

    final fields = <String>[
      exhibitorName,
      (e['tattoo'] ?? '').toString(),
      (e['breed'] ?? '').toString(),
      (e['variety'] ?? '').toString(),
      (e['sex'] ?? '').toString(),
      (e['class_name'] ?? '').toString(),
      (e['notes'] ?? '').toString(),
      (e['species'] ?? '').toString(),
    ].join(' ').toLowerCase();

    return fields.contains(q);
  }

  Future<void> _toggleScratch(Map<String, dynamic> entry) async {
    final id = entry['id'].toString();
    final scratchedAt = entry['scratched_at']?.toString();
    final willScratch = scratchedAt == null || scratchedAt.isEmpty;

    try {
      await supabase.from('entries').update({
        'scratched_at': willScratch ? DateTime.now().toUtc().toIso8601String() : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      await _loadEntries();
      if (!mounted) return;
      setState(() => _msg = willScratch ? 'Scratched.' : 'Unscratched.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Scratch update failed: $e');
    }
  }

  Future<void> _openEdit(Map<String, dynamic> entry) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditEntrySheet(entry: entry),
    );

    if (saved == true) {
      await _loadEntries();
      if (!mounted) return;
      setState(() => _msg = 'Entry updated.');
    }
  }

  Future<void> _openMove(Map<String, dynamic> entry) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MoveEntrySheet(
        entry: entry,
        sections: _sections,
      ),
    );

    if (saved == true) {
      await _loadEntries();
      if (!mounted) return;
      setState(() => _msg = 'Animal moved.');
    }
  }

  Future<void> _onChangeSection(String? v) async {
    setState(() {
      _selectedSectionId = v;
      _loading = true;
      _msg = null;
      _expandedExhibitorIds.clear();
    });

    try {
      await _loadEntries();
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

  Map<String, List<Map<String, dynamic>>> _groupByExhibitor(List<Map<String, dynamic>> items) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in items) {
      final exId = _exhibitorId(e);
      final key = exId.isEmpty ? '_unknown' : exId;
      map.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      map[key]!.add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final searchText = _search.text.trim();

    final filtered = _entries.where((e) => _matchesSearch(e, searchText)).toList();

    final grouped = _groupByExhibitor(filtered);
    final exhibitorKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aName = grouped[a]!.isEmpty ? '' : _exhibitorDisplayName(grouped[a]!.first).toLowerCase();
        final bName = grouped[b]!.isEmpty ? '' : _exhibitorDisplayName(grouped[b]!.first).toLowerCase();
        return aName.compareTo(bName);
      });

    final sectionTitle = () {
      if (_selectedSectionId == null) return '';
      final s = _sections.firstWhere(
        (x) => x['id']?.toString() == _selectedSectionId,
        orElse: () => const <String, dynamic>{},
      );
      if (s.isEmpty) return '';
      return _sectionLabel(s);
    }();

    return Scaffold(
      appBar: AppBar(
        title: Text('Entry Mgmt — ${widget.showName}'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _msg!,
                          style: TextStyle(
                            color: (_msg == 'Entry updated.' || _msg == 'Scratched.' || _msg == 'Unscratched.' || _msg == 'Animal moved.')
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedSectionId,
                                decoration: const InputDecoration(
                                  labelText: 'Show Letter / Section',
                                ),
                                items: _sections
                                    .map(
                                      (s) => DropdownMenuItem<String>(
                                        value: s['id']?.toString(),
                                        child: Text(_sectionLabel(s)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _sections.isEmpty ? null : _onChangeSection,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            labelText: 'Search entries (includes exhibitor name)',
                            hintText: 'Exhibitor, tattoo, breed, variety, sex, class, notes…',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            sectionTitle.isEmpty
                                ? 'Showing: ${filtered.length} entries • ${grouped.length} exhibitors'
                                : 'Showing: ${filtered.length} entries • ${grouped.length} exhibitors • $sectionTitle',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No entries found for this filter.'))
                        : ListView.builder(
                            itemCount: exhibitorKeys.length,
                            itemBuilder: (context, idx) {
                              final exKey = exhibitorKeys[idx];
                              final exEntries = grouped[exKey] ?? [];
                              if (exEntries.isEmpty) return const SizedBox.shrink();

                              final exhibitorName = _exhibitorDisplayName(exEntries.first);
                              final isExpanded = _expandedExhibitorIds.contains(exKey);

                              return Card(
                                margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                                child: ExpansionTile(
                                  initiallyExpanded: isExpanded,
                                  onExpansionChanged: (v) {
                                    setState(() {
                                      if (v) {
                                        _expandedExhibitorIds.add(exKey);
                                      } else {
                                        _expandedExhibitorIds.remove(exKey);
                                      }
                                    });
                                  },
                                  title: Text(exhibitorName),
                                  subtitle: Text('${exEntries.length} entr${exEntries.length == 1 ? 'y' : 'ies'}'),
                                  children: [
                                    const Divider(height: 1),
                                    ...exEntries.map((e) {
                                      final tattoo = (e['tattoo'] ?? '').toString();
                                      final breed = (e['breed'] ?? '').toString();
                                      final variety = (e['variety'] ?? '').toString();
                                      final sex = (e['sex'] ?? '').toString();
                                      final cls = (e['class_name'] ?? '').toString();
                                      final notes = (e['notes'] ?? '').toString();
                                      final scratchedAt = e['scratched_at']?.toString();
                                      final isScratched = scratchedAt != null && scratchedAt.isNotEmpty;

                                      final section = e['show_sections'];
                                      final letter = (section is Map ? (section['letter'] ?? '') : '').toString();

                                      final titleLeft = tattoo.isEmpty ? '(no tattoo)' : tattoo;

                                      final subtitle = [
                                        if (breed.isNotEmpty) 'Breed: $breed',
                                        if (variety.isNotEmpty) 'Variety: $variety',
                                        if (sex.isNotEmpty) 'Sex: $sex',
                                        if (cls.isNotEmpty) 'Class: $cls',
                                        if (letter.isNotEmpty) 'Show: $letter',
                                        if (isScratched) 'SCRATCHED: ${_dateOnly(scratchedAt)}',
                                        if (notes.isNotEmpty) 'Notes: $notes',
                                      ].join(' • ');

                                      return ListTile(
                                        title: Text(
                                          titleLeft,
                                          style: TextStyle(
                                            decoration: isScratched ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                                        isThreeLine: subtitle.length > 80,
                                        trailing: PopupMenuButton<String>(
                                          tooltip: 'Actions',
                                          onSelected: (v) {
                                            if (v == 'edit') _openEdit(e);
                                            if (v == 'move') _openMove(e);
                                            if (v == 'scratch') _toggleScratch(e);
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                            const PopupMenuItem(value: 'move', child: Text('Move Animal')),
                                            PopupMenuItem(
                                              value: 'scratch',
                                              child: Text(isScratched ? 'Un-scratch' : 'Scratch'),
                                            ),
                                          ],
                                        ),
                                        onTap: () => _openEdit(e),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EditEntrySheet extends StatefulWidget {
  final Map<String, dynamic> entry;

  const _EditEntrySheet({required this.entry});

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  bool _saving = false;
  String? _msg;

  late final TextEditingController _tattoo;
  late final TextEditingController _breed;
  late final TextEditingController _variety;
  late final TextEditingController _sex;
  late final TextEditingController _className;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _tattoo = TextEditingController(text: (widget.entry['tattoo'] ?? '').toString());
    _breed = TextEditingController(text: (widget.entry['breed'] ?? '').toString());
    _variety = TextEditingController(text: (widget.entry['variety'] ?? '').toString());
    _sex = TextEditingController(text: (widget.entry['sex'] ?? '').toString());
    _className = TextEditingController(text: (widget.entry['class_name'] ?? '').toString());
    _notes = TextEditingController(text: (widget.entry['notes'] ?? '').toString());
  }

  @override
  void dispose() {
    _tattoo.dispose();
    _breed.dispose();
    _variety.dispose();
    _sex.dispose();
    _className.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final id = widget.entry['id'].toString();

      await supabase.from('entries').update({
        'tattoo': _tattoo.text.trim().isEmpty ? null : _tattoo.text.trim(),
        'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(),
        'variety': _variety.text.trim().isEmpty ? null : _variety.text.trim(),
        'sex': _sex.text.trim().isEmpty ? null : _sex.text.trim(),
        'class_name': _className.text.trim().isEmpty ? null : _className.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Entry', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_msg!, style: const TextStyle(color: Colors.red)),
              ),

            TextField(
              controller: _tattoo,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Tattoo / Ear #'),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _breed,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Breed'),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _variety,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Variety'),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _sex,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Sex'),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _className,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Class'),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _notes,
              enabled: !_saving,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 14),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveEntrySheet extends StatefulWidget {
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> sections;

  const _MoveEntrySheet({
    required this.entry,
    required this.sections,
  });

  @override
  State<_MoveEntrySheet> createState() => _MoveEntrySheetState();
}

class _MoveEntrySheetState extends State<_MoveEntrySheet> {
  bool _saving = false;
  String? _msg;

  String? _sectionId;
  late final TextEditingController _className;

  @override
  void initState() {
    super.initState();
    _sectionId = widget.entry['section_id']?.toString();
    _className = TextEditingController(text: (widget.entry['class_name'] ?? '').toString());
  }

  @override
  void dispose() {
    _className.dispose();
    super.dispose();
  }

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final letter = (s['letter'] ?? '').toString().toUpperCase();
    return letter.isEmpty ? 'Section' : 'Show $letter';
  }

  Future<void> _save() async {
    final entryId = widget.entry['id']?.toString() ?? '';
    if (entryId.isEmpty) return;

    if (_sectionId == null || _sectionId!.isEmpty) {
      setState(() => _msg = 'Select a section.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.from('entries').update({
        'section_id': _sectionId,
        // Optional: allow changing class at same time (per-entry)
        'class_name': _className.text.trim().isEmpty ? null : _className.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', entryId);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Move failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Move Animal', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_msg!, style: const TextStyle(color: Colors.red)),
              ),

            DropdownButtonFormField<String>(
              value: _sectionId,
              decoration: const InputDecoration(labelText: 'Move to section'),
              items: widget.sections
                  .map((s) => DropdownMenuItem<String>(
                        value: s['id']?.toString(),
                        child: Text(_sectionLabel(s)),
                      ))
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _sectionId = v),
            ),
            const SizedBox(height: 12),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Moving…' : 'Save Move'),
            ),
          ],
        ),
      ),
    );
  }
}