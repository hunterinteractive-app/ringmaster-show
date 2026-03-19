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
        .select('id,letter,display_name,kind,is_enabled,sort_order')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true)
        .order('sort_order', ascending: true);

    _sections = (rows as List).cast<Map<String, dynamic>>();

    if (_selectedSectionId == null && _sections.isNotEmpty) {
      _selectedSectionId = _sections.first['id']?.toString();
    }
  }

  Future<void> _openAddEntry() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdminAddEntrySheet(
        showId: widget.showId,
        sections: _sections,
        initialSectionId: _selectedSectionId,
      ),
    );

    if (saved == true) {
      await _loadEntries();
      if (!mounted) return;
      setState(() => _msg = 'Entry added.');
    }
  }

  Future<void> _loadEntries() async {
    var q = supabase
        .from('entries')
        .select(
          'id,show_id,section_id,exhibitor_id,exhibitor_user_id,animal_id,species,'
          'tattoo,breed,variety,sex,class_name,notes,status,created_at,updated_at,scratched_at,'
          'show_sections(id,letter,display_name,kind),'
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
            tooltip: 'Add Entry',
            icon: const Icon(Icons.add),
            onPressed: _loading || _sections.isEmpty ? null : _openAddEntry,
          ),
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
                            color: (_msg == 'Entry updated.' ||
                                    _msg == 'Scratched.' ||
                                    _msg == 'Unscratched.' ||
                                    _msg == 'Animal moved.' ||
                                    _msg == 'Entry added.')
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
                                    }),
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

class _AdminAddEntrySheet extends StatefulWidget {
  final String showId;
  final List<Map<String, dynamic>> sections;
  final String? initialSectionId;

  const _AdminAddEntrySheet({
    required this.showId,
    required this.sections,
    required this.initialSectionId,
  });

  @override
  State<_AdminAddEntrySheet> createState() => _AdminAddEntrySheetState();
}

class _AdminAddEntrySheetState extends State<_AdminAddEntrySheet> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  List<Map<String, dynamic>> _exhibitors = [];
  List<Map<String, dynamic>> _animals = [];

  String? _exhibitorId;
  String? _sectionId;
  Map<String, dynamic>? _animal;

  bool _addNewExhibitor = false;
  bool _useLocalAnimal = false;

  final _showingName = TextEditingController();
  final _displayName = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  String _exhibitorType = 'open';

  final _tattoo = TextEditingController();
  final _breed = TextEditingController();
  final _variety = TextEditingController();
  final _sex = TextEditingController();

  final _className = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sectionId = widget.initialSectionId;
    _loadExhibitors();
  }

  @override
  void dispose() {
    _showingName.dispose();
    _displayName.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _tattoo.dispose();
    _breed.dispose();
    _variety.dispose();
    _sex.dispose();
    _className.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadExhibitors() async {
    try {
      final res = await supabase
          .from('exhibitors')
          .select(
            'id,showing_name,display_name,first_name,last_name,email,phone,type,owner_user_id,is_active,is_local_only,created_for_show_id',
          )
          .eq('is_active', true)
          .order('display_name', ascending: true);

      _exhibitors = (res as List).cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Failed to load exhibitors: $e';
      });
    }
  }

  String _exhibitorLabel(Map<String, dynamic> e) {
    final showing = (e['showing_name'] ?? '').toString().trim();
    if (showing.isNotEmpty) return showing;

    final display = (e['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;

    final first = (e['first_name'] ?? '').toString().trim();
    final last = (e['last_name'] ?? '').toString().trim();
    final combined = '$first $last'.trim();
    if (combined.isNotEmpty) return combined;

    return '(Unnamed Exhibitor)';
  }

  String _animalLabel(Map<String, dynamic> a) {
    final tattoo = (a['tattoo'] ?? '').toString().trim();
    final breed = (a['breed'] ?? '').toString().trim();
    final variety = (a['variety'] ?? '').toString().trim();
    final name = (a['name'] ?? '').toString().trim();

    if (tattoo.isNotEmpty && breed.isNotEmpty) {
      return '$tattoo • $breed${variety.isNotEmpty ? " • $variety" : ""}';
    }
    if (name.isNotEmpty) return name;
    if (tattoo.isNotEmpty) return tattoo;
    return '(Unnamed Animal)';
  }

  String _sectionKind() {
    final s = widget.sections.firstWhere(
      (x) => x['id'].toString() == _sectionId,
      orElse: () => <String, dynamic>{},
    );
    return (s['kind'] ?? '').toString().toLowerCase();
  }

  Future<void> _loadAnimalsForSelectedExhibitor() async {
    _animals = [];
    _animal = null;

    if (_exhibitorId == null || _exhibitorId!.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final exhibitor = _exhibitors.firstWhere(
      (e) => e['id'].toString() == _exhibitorId,
      orElse: () => <String, dynamic>{},
    );

    final ownerUserId = (exhibitor['owner_user_id'] ?? '').toString().trim();

    // Walk-in / local exhibitors may not have an owner_user_id
    if (ownerUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _animals = [];
          _animal = null;
        });
      }
      return;
    }

    try {
      final res = await supabase
          .from('animals')
          .select('id,owner_user_id,name,tattoo,breed,variety,sex,species')
          .eq('owner_user_id', ownerUserId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _animals = (res as List).cast<Map<String, dynamic>>();
        _animal = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _animals = [];
        _animal = null;
        _msg = 'Failed to load animals: $e';
      });
    }
  }

  Future<String> _createNewExhibitor() async {
    final showing = _showingName.text.trim();
    final display = _displayName.text.trim();
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();

    if (showing.isEmpty &&
        display.isEmpty &&
        first.isEmpty &&
        last.isEmpty) {
      throw Exception('Enter at least a showing name, display name, or first/last name.');
    }

    final inserted = await supabase
        .from('exhibitors')
        .insert({
          'showing_name': showing.isEmpty ? null : showing,
          'display_name': display.isEmpty ? null : display,
          'first_name': first.isEmpty ? null : first,
          'last_name': last.isEmpty ? null : last,
          'email': email.isEmpty ? null : email,
          'phone': phone.isEmpty ? null : phone,
          'type': _exhibitorType,
          'is_active': true,
          'is_local_only': true,
          'created_for_show_id': widget.showId,
          'owner_user_id': null,
        })
        .select(
          'id,showing_name,display_name,first_name,last_name,email,phone,type,owner_user_id,is_active,is_local_only,created_for_show_id',
        )
        .single();

    final row = Map<String, dynamic>.from(inserted);
    _exhibitors.add(row);

    return row['id'].toString();
  }

  Future<void> _save({bool reset = false}) async {
    if (_sectionId == null || _sectionId!.isEmpty) {
      setState(() => _msg = 'Select section');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      String resolvedExhibitorId;

      if (_addNewExhibitor) {
        resolvedExhibitorId = await _createNewExhibitor();
      } else {
        if (_exhibitorId == null || _exhibitorId!.isEmpty) {
          throw Exception('Select exhibitor');
        }
        resolvedExhibitorId = _exhibitorId!;
      }

      final exhibitor = _exhibitors.firstWhere(
        (e) => e['id'].toString() == resolvedExhibitorId,
        orElse: () => <String, dynamic>{},
      );

      final type = (exhibitor['type'] ?? '').toString().toLowerCase();
      if (_sectionKind() == 'youth' && type != 'youth') {
        throw Exception('Youth section requires youth exhibitor');
      }

      if (!_useLocalAnimal && _animal == null) {
        throw Exception('Select an animal');
      }

      if (_useLocalAnimal) {
        if (_tattoo.text.trim().isEmpty) {
          throw Exception('Enter tattoo');
        }
        if (_breed.text.trim().isEmpty) {
          throw Exception('Enter breed');
        }
      }

      final animalId = _useLocalAnimal ? null : _animal!['id'];

      if (animalId != null) {
        final dup = await supabase
            .from('entries')
            .select('id')
            .eq('show_id', widget.showId)
            .eq('section_id', _sectionId!)
            .eq('animal_id', animalId)
            .maybeSingle();

        if (dup != null) {
          throw Exception('Animal already entered in this section');
        }
      }

      await supabase.from('entries').insert({
        'show_id': widget.showId,
        'section_id': _sectionId,
        'exhibitor_id': resolvedExhibitorId,
        'animal_id': animalId,
        'species': _useLocalAnimal ? null : _animal!['species'],
        'tattoo': _useLocalAnimal ? _tattoo.text.trim() : _animal!['tattoo'],
        'breed': _useLocalAnimal ? _breed.text.trim() : _animal!['breed'],
        'variety': _useLocalAnimal ? _variety.text.trim() : _animal!['variety'],
        'sex': _useLocalAnimal ? _sex.text.trim() : _animal!['sex'],
        'class_name': _className.text.trim().isEmpty ? null : _className.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'status': 'entered',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (!mounted) return;

      if (!reset) {
        Navigator.pop(context, true);
        return;
      }

      setState(() {
        _animal = null;
        _animals = _addNewExhibitor ? [] : _animals;
        _tattoo.clear();
        _breed.clear();
        _variety.clear();
        _sex.clear();
        _className.clear();
        _notes.clear();
        _saving = false;
        _msg = 'Saved. Add another.';
      });
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
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset + 16, left: 16, right: 16, top: 10),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add Entry', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_msg != null)
                    Text(_msg!, style: const TextStyle(color: Colors.red)),

                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    value: _sectionId,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: widget.sections
                        .map((s) => DropdownMenuItem<String>(
                              value: s['id'].toString(),
                              child: Text((s['display_name'] ?? s['letter']).toString()),
                            ))
                        .toList(),
                    onChanged: _saving ? null : (v) => setState(() => _sectionId = v),
                  ),

                  const SizedBox(height: 14),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add New Exhibitor'),
                    subtitle: const Text('Create a show/local exhibitor with contact info'),
                    value: _addNewExhibitor,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() {
                              _addNewExhibitor = v;
                              _exhibitorId = null;
                              _animal = null;
                              _animals = [];
                              _msg = null;
                            });
                          },
                  ),

                  if (_addNewExhibitor) ...[
                    TextField(
                      controller: _showingName,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Showing Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _displayName,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Display Name'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstName,
                            enabled: !_saving,
                            decoration: const InputDecoration(labelText: 'First Name'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _lastName,
                            enabled: !_saving,
                            decoration: const InputDecoration(labelText: 'Last Name'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _email,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _exhibitorType,
                      decoration: const InputDecoration(labelText: 'Exhibitor Type'),
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('Open')),
                        DropdownMenuItem(value: 'youth', child: Text('Youth')),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _exhibitorType = v ?? 'open'),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: _exhibitorId,
                      decoration: const InputDecoration(labelText: 'Exhibitor'),
                      items: _exhibitors
                          .map((e) => DropdownMenuItem<String>(
                                value: e['id'].toString(),
                                child: Text(_exhibitorLabel(e)),
                              ))
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) async {
                              setState(() {
                                _exhibitorId = v;
                                _animal = null;
                                _animals = [];
                                _msg = null;
                              });
                              await _loadAnimalsForSelectedExhibitor();
                            },
                    ),
                  ],

                  const SizedBox(height: 14),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add New Animal (Local Only)'),
                    subtitle: const Text('Use when the animal is not already in the system'),
                    value: _useLocalAnimal,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() {
                              _useLocalAnimal = v;
                              _animal = null;
                              _msg = null;
                            });
                          },
                  ),

                  if (_useLocalAnimal) ...[
                    TextField(
                      controller: _tattoo,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Tattoo'),
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
                  ] else ...[
                    if (_addNewExhibitor)
                      const Text(
                        'Select "Add New Animal" for a new walk-in exhibitor, or switch back to an existing exhibitor to load saved animals.',
                      )
                    else if (_exhibitorId == null)
                      const Text('Select an exhibitor first to load their animals.')
                    else if (_animals.isEmpty)
                      const Text('No saved animals found for this exhibitor. Use "Add New Animal" to enter one locally.')
                    else
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: _animal,
                        decoration: const InputDecoration(labelText: 'Animal'),
                        items: _animals
                            .map((a) => DropdownMenuItem<Map<String, dynamic>>(
                                  value: a,
                                  child: Text(_animalLabel(a)),
                                ))
                            .toList(),
                        onChanged: _saving ? null : (v) => setState(() => _animal = v),
                      ),
                  ],

                  const SizedBox(height: 12),

                  TextField(
                    controller: _className,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Class'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _save(),
                          child: Text(_saving ? 'Saving…' : 'Save'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _save(reset: true),
                          child: const Text('Save & Add Another'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}