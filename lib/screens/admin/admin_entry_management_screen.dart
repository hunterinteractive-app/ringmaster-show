// lib/screens/admin/admin_entry_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  State<AdminEntryManagementScreen> createState() =>
      _AdminEntryManagementScreenState();
}

class _AdminEntryManagementScreenState
    extends State<AdminEntryManagementScreen> {
  bool _loading = true;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  List<Map<String, dynamic>> _entries = [];

  final _search = TextEditingController();

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
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _AdminAddEntrySheet(
          showId: widget.showId,
          sections: _sections,
          initialSectionId: _selectedSectionId,
        ),
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
          'is_fur,fur_placement,fur_notes,'
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
      ((e['is_fur'] == true) ? 'fur wool fur/wool' : ''),
    ].join(' ').toLowerCase();

    return fields.contains(q);
  }

  Future<void> _toggleScratch(Map<String, dynamic> entry) async {
    final id = entry['id'].toString();
    final scratchedAt = entry['scratched_at']?.toString();
    final willScratch = scratchedAt == null || scratchedAt.isEmpty;

    try {
      await supabase.from('entries').update({
        'scratched_at':
            willScratch ? DateTime.now().toUtc().toIso8601String() : null,
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
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _EditEntrySheet(entry: entry),
      ),
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
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _MoveEntrySheet(
          entry: entry,
          sections: _sections,
        ),
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

  Map<String, List<Map<String, dynamic>>> _groupByExhibitor(
      List<Map<String, dynamic>> items) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in items) {
      final exId = _exhibitorId(e);
      final key = exId.isEmpty ? '_unknown' : exId;
      map.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      map[key]!.add(e);
    }
    return map;
  }

  Widget _messageBanner() {
    if (_msg == null) return const SizedBox.shrink();

    final successMessages = {
      'Entry updated.',
      'Scratched.',
      'Unscratched.',
      'Animal moved.',
      'Entry added.',
    };

    final isSuccess = successMessages.contains(_msg);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSuccess
              ? Colors.green.withOpacity(.08)
              : Colors.red.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSuccess
                ? Colors.green.withOpacity(.25)
                : Colors.red.withOpacity(.25),
          ),
        ),
        child: Text(
          _msg!,
          style: TextStyle(
            color: isSuccess ? Colors.green.shade700 : Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchText = _search.text.trim();

    final filtered =
        _entries.where((e) => _matchesSearch(e, searchText)).toList();

    final grouped = _groupByExhibitor(filtered);
    final exhibitorKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aName = grouped[a]!.isEmpty
            ? ''
            : _exhibitorDisplayName(grouped[a]!.first).toLowerCase();
        final bName = grouped[b]!.isEmpty
            ? ''
            : _exhibitorDisplayName(grouped[b]!.first).toLowerCase();
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
                'Entry Mgmt — ${widget.showName}',
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Entry'),
              onPressed: _loading || _sections.isEmpty ? null : _openAddEntry,
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAll,
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
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      _messageBanner(),
                      _summaryCard(
                        title: 'Filters',
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: _selectedSectionId,
                              decoration: const InputDecoration(
                                labelText: 'Show Letter / Section',
                                border: OutlineInputBorder(),
                              ),
                              items: _sections
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value: s['id']?.toString(),
                                      child: Text(_sectionLabel(s)),
                                    ),
                                  )
                                  .toList(),
                              onChanged:
                                  _sections.isEmpty ? null : _onChangeSection,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _search,
                              decoration: const InputDecoration(
                                labelText:
                                    'Search entries (includes exhibitor name)',
                                hintText:
                                    'Exhibitor, tattoo, breed, variety, sex, class, notes…',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
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
                      const SizedBox(height: 16),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child:
                                    Text('No entries found for this filter.'),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: exhibitorKeys.length,
                                itemBuilder: (context, idx) {
                                  final exKey = exhibitorKeys[idx];
                                  final exEntries = grouped[exKey] ?? [];
                                  if (exEntries.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final exhibitorName =
                                      _exhibitorDisplayName(exEntries.first);
                                  final isExpanded =
                                      _expandedExhibitorIds.contains(exKey);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
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
                                      title: Text(
                                        exhibitorName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${exEntries.length} entr${exEntries.length == 1 ? 'y' : 'ies'}',
                                      ),
                                      children: [
                                        const Divider(height: 1),
                                        ...exEntries.map((e) {
                                          final tattoo =
                                              (e['tattoo'] ?? '').toString().trim().toUpperCase();
                                          final breed =
                                              (e['breed'] ?? '').toString();
                                          final variety =
                                              (e['variety'] ?? '').toString();
                                          final sex =
                                              (e['sex'] ?? '').toString();
                                          final cls =
                                              (e['class_name'] ?? '').toString();
                                          final notes =
                                              (e['notes'] ?? '').toString();
                                          final scratchedAt =
                                              e['scratched_at']?.toString();
                                          final isScratched = scratchedAt !=
                                                  null &&
                                              scratchedAt.isNotEmpty;

                                          final section = e['show_sections'];
                                          final letter = (section is Map
                                                  ? (section['letter'] ?? '')
                                                  : '')
                                              .toString();

                                          final titleLeft = tattoo.isEmpty
                                              ? '(no tattoo)'
                                              : tattoo;

                                          final isFur = e['is_fur'] == true;

                                          final subtitle = [
                                            if (breed.isNotEmpty)
                                              'Breed: $breed',
                                            if (variety.isNotEmpty)
                                              'Variety: $variety',
                                            if (sex.isNotEmpty) 'Sex: $sex',
                                            if (cls.isNotEmpty) 'Class: $cls',
                                            if (isFur) 'Fur/Wool',
                                            if (letter.isNotEmpty)
                                              'Show: $letter',
                                            if (isScratched)
                                              'SCRATCHED: ${_dateOnly(scratchedAt)}',
                                            if (notes.isNotEmpty)
                                              'Notes: $notes',
                                          ].join(' • ');

                                          return ListTile(
                                            title: Text(
                                              titleLeft,
                                              style: TextStyle(
                                                decoration: isScratched
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            ),
                                            subtitle: subtitle.isEmpty
                                                ? null
                                                : Text(subtitle),
                                            isThreeLine: subtitle.length > 80,
                                            trailing:
                                                PopupMenuButton<String>(
                                              tooltip: 'Actions',
                                              onSelected: (v) {
                                                if (v == 'edit') _openEdit(e);
                                                if (v == 'move') _openMove(e);
                                                if (v == 'scratch') {
                                                  _toggleScratch(e);
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'move',
                                                  child: Text('Move Animal'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'scratch',
                                                  child: Text(isScratched
                                                      ? 'Un-scratch'
                                                      : 'Scratch'),
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
              ),
      ),
    );
  }
}

Widget _themedBottomSheetShell(BuildContext context, {required Widget child}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFF11285A),
          Color(0xFF0B1C43),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
          color: Color(0xFFF4F6FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: child,
      ),
    ),
  );
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
  bool _isFur = false;
  late final TextEditingController _furNotes;

  @override
  void initState() {
    super.initState();
    _tattoo = TextEditingController(
        text: (widget.entry['tattoo'] ?? '').toString().trim().toUpperCase(),
      );
    _breed =
        TextEditingController(text: (widget.entry['breed'] ?? '').toString());
    _variety = TextEditingController(
        text: (widget.entry['variety'] ?? '').toString());
    _sex = TextEditingController(text: (widget.entry['sex'] ?? '').toString());
    _className = TextEditingController(
        text: (widget.entry['class_name'] ?? '').toString());
    _notes =
        TextEditingController(text: (widget.entry['notes'] ?? '').toString());
    _isFur = widget.entry['is_fur'] == true;
    _furNotes = TextEditingController(
      text: (widget.entry['fur_notes'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _tattoo.dispose();
    _breed.dispose();
    _variety.dispose();
    _sex.dispose();
    _className.dispose();
    _notes.dispose();
    _furNotes.dispose();
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
        'tattoo': _tattoo.text.trim().isEmpty
            ? null
            : _tattoo.text.trim().toUpperCase(),
        'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(),
        'variety': _variety.text.trim().isEmpty ? null : _variety.text.trim(),
        'sex': _sex.text.trim().isEmpty ? null : _sex.text.trim(),
        'class_name':
            _className.text.trim().isEmpty ? null : _className.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'is_fur': _isFur,
        'fur_notes': _isFur && _furNotes.text.trim().isNotEmpty
            ? _furNotes.text.trim()
            : null,
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
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Entry', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_msg != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(.25)),
                ),
                child: Text(
                  _msg!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            TextField(
              controller: _tattoo,
              enabled: !_saving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Tattoo / Ear #',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _breed,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Breed',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _variety,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Variety',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sex,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Sex',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _className,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fur / Wool Entry'),
              value: _isFur,
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                        _isFur = v;
                      }),
            ),
            if (_isFur) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _furNotes,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Fur / Wool Notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              enabled: !_saving,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
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
  final Set<String> _selectedSectionIds = <String>{};
  late final TextEditingController _className;

  @override
  void initState() {
    super.initState();
    _sectionId = widget.entry['section_id']?.toString();
    _className = TextEditingController(
      text: (widget.entry['class_name'] ?? '').toString(),
    );
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

    if (_selectedSectionIds.isEmpty) {
      setState(() => _msg = 'Select at least one section.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.from('entries').update({
        'section_id': _sectionId,
        'class_name':
            _className.text.trim().isEmpty ? null : _className.text.trim(),
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
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Move Animal', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_msg != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(.25)),
                ),
                child: Text(
                  _msg!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            DropdownButtonFormField<String>(
              value: _sectionId,
              decoration: const InputDecoration(
                labelText: 'Move to section',
                border: OutlineInputBorder(),
              ),
              items: widget.sections
                  .map(
                    (s) => DropdownMenuItem<String>(
                      value: s['id']?.toString(),
                      child: Text(_sectionLabel(s)),
                    ),
                  )
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _sectionId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _className,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
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
  final Set<String> _selectedSectionIds = <String>{};
  Map<String, dynamic>? _animal;

  bool _addNewExhibitor = false;
  bool _useLocalAnimal = false;

  final _showingName = TextEditingController();
  final _displayName = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  String _exhibitorType = 'adult';
  String _species = 'rabbit';

  final _tattoo = TextEditingController();
  final _breed = TextEditingController();
  final _variety = TextEditingController();
  final _sex = TextEditingController();

  String? _breedId;
  String? _sexValue;
  String? _classValue;

  List<Map<String, dynamic>> _breedOptions = [];
  List<Map<String, dynamic>> _varietyOptions = [];

  bool _loadingBreeds = false;
  bool _loadingVarieties = false;

  final _className = TextEditingController();
  final _notes = TextEditingController();
  final _furNotes = TextEditingController();

  bool _isFur = false;

  Map<String, dynamic> _sectionById(String id) {
    return widget.sections.firstWhere(
      (x) => x['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
  }

  String _sectionKindById(String id) {
    final s = _sectionById(id);
    return (s['kind'] ?? '').toString().toLowerCase();
  }

  String _sectionDisplayLabelById(String id) {
    final s = _sectionById(id);
    final dn = (s['display_name'] ?? '').toString().trim();
    final letter = (s['letter'] ?? '').toString().trim();
    if (dn.isNotEmpty && letter.isNotEmpty) return '$dn ($letter)';
    if (dn.isNotEmpty) return dn;
    if (letter.isNotEmpty) return 'Show $letter';
    return 'Section';
  }

  @override
  void initState() {
    super.initState();
    _sectionId = widget.initialSectionId;
    _sectionId = widget.initialSectionId;
    if (_sectionId != null && _sectionId!.isNotEmpty) {
      _selectedSectionIds.add(_sectionId!);
    }
    _sexValue = _sexOptions.first;
    _sex.text = _sexValue ?? '';
    _className.text = _classValue ?? '';
    _loadExhibitors();
    _firstName.addListener(_autoFillShowingName);
    _lastName.addListener(_autoFillShowingName);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBreedsForSpecies();
    });
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
    _furNotes.dispose();
    super.dispose();
  }

  void _autoFillShowingName() {
    // Don't overwrite if user already typed something custom
    if (_showingName.text.trim().isNotEmpty) return;

    final first = _firstName.text.trim();
    final last = _lastName.text.trim();

    final combined = [first, last].where((s) => s.isNotEmpty).join(' ');

    if (combined.isNotEmpty) {
      _showingName.text = combined;
    }
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
    final tattoo = (a['tattoo'] ?? '').toString().trim().toUpperCase();
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

  bool _isLopBreedName(String breedName) {
    return breedName.trim().toLowerCase().endsWith('lop');
  }

  List<String> get _sexOptions =>
      _species == 'rabbit' ? const ['Buck', 'Doe'] : const ['Boar', 'Sow'];

  Future<void> _loadBreedsForSpecies() async {
    setState(() => _loadingBreeds = true);

    try {
      final globalBreedsRes = await supabase
          .from('breeds')
          .select('id,name,species,is_active')
          .eq('species', _species)
          .eq('is_active', true)
          .order('name');

      final globalBreeds =
          (globalBreedsRes as List).cast<Map<String, dynamic>>();

      final showBreedRes = await supabase
          .from('show_breeds')
          .select('breed_id,is_enabled')
          .eq('show_id', widget.showId);

      final showBreedRows =
          (showBreedRes as List).cast<Map<String, dynamic>>();

      final showBreedMap = <String, bool>{};
      for (final row in showBreedRows) {
        final breedId = (row['breed_id'] ?? '').toString();
        if (breedId.isEmpty) continue;
        showBreedMap[breedId] = row['is_enabled'] == true;
      }

      final effective = globalBreeds.where((b) {
        final id = (b['id'] ?? '').toString();

        if (showBreedMap.containsKey(id)) {
          return showBreedMap[id] == true;
        }

        return true;
      }).toList()
        ..sort(
          (a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase()),
        );

      if (!mounted) return;
      setState(() {
        _breedOptions = effective;
        _loadingBreeds = false;

        final stillValidBreed = _breedId != null &&
            _breedOptions.any((b) => (b['id'] ?? '').toString() == _breedId);

        if (!stillValidBreed) {
          _breedId = null;
          _breed.clear();
          _variety.clear();
          _varietyOptions = [];
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBreeds = false;
        _msg = 'Failed to load breeds: $e';
      });
    }
  }

  Future<void> _loadVarietiesForBreed(String breedId) async {
    setState(() {
      _loadingVarieties = true;
      _varietyOptions = [];
    });

    try {
      final matchedBreed = _breedOptions.firstWhere(
        (b) => (b['id'] ?? '').toString() == breedId,
        orElse: () => <String, dynamic>{},
      );

      final breedName = (matchedBreed['name'] ?? '').toString().trim();

      if (_isLopBreedName(breedName)) {
        const lopOptions = [
          {'id': 'lop_broken', 'name': 'Broken'},
          {'id': 'lop_solid', 'name': 'Solid'},
        ];

        if (!mounted) return;
        setState(() {
          _loadingVarieties = false;
          _varietyOptions = lopOptions;

          final currentVariety = _variety.text.trim().toLowerCase();
          final stillValidVariety = currentVariety.isNotEmpty &&
              _varietyOptions.any(
                (v) => (v['name'] ?? '').toString().trim().toLowerCase() ==
                    currentVariety,
              );

          if (!stillValidVariety) {
            _variety.clear();
          }
        });
        return;
      }

      final globalVarietiesRes = await supabase
          .from('varieties')
          .select('id,name,breed_id,is_active')
          .eq('breed_id', breedId)
          .eq('is_active', true)
          .order('name');

      final globalVarieties =
          (globalVarietiesRes as List).cast<Map<String, dynamic>>();

      final showVarietiesRes = await supabase
          .from('show_varieties')
          .select('id,variety_id,custom_name,is_enabled')
          .eq('show_id', widget.showId)
          .eq('breed_id', breedId);

      final showVarietyRows =
          (showVarietiesRes as List).cast<Map<String, dynamic>>();

      final showVarietyByGlobalId = <String, Map<String, dynamic>>{};
      final customRows = <Map<String, dynamic>>[];

      for (final row in showVarietyRows) {
        final varietyId = row['variety_id']?.toString();
        final customName = (row['custom_name'] ?? '').toString().trim();

        if (varietyId != null && varietyId.isNotEmpty) {
          showVarietyByGlobalId[varietyId] = row;
        } else if (customName.isNotEmpty) {
          customRows.add(row);
        }
      }

      final effective = <Map<String, dynamic>>[];

      for (final global in globalVarieties) {
        final globalId = (global['id'] ?? '').toString();
        if (globalId.isEmpty) continue;

        final override = showVarietyByGlobalId[globalId];

        if (override != null) {
          if (override['is_enabled'] == true) {
            effective.add({
              'id': globalId,
              'name': (global['name'] ?? '').toString(),
            });
          }
        } else {
          effective.add({
            'id': globalId,
            'name': (global['name'] ?? '').toString(),
          });
        }
      }

      for (final row in customRows) {
        if (row['is_enabled'] == true) {
          final customName = (row['custom_name'] ?? '').toString().trim();
          if (customName.isNotEmpty) {
            effective.add({
              'id': 'custom_$customName',
              'name': customName,
            });
          }
        }
      }

      effective.sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _varietyOptions = effective;
        _loadingVarieties = false;

        if (effective.length == 1) {
          _variety.text = (effective.first['name'] ?? '').toString();
        } else {
          final currentVariety = _variety.text.trim().toLowerCase();
          final stillValidVariety = currentVariety.isNotEmpty &&
              _varietyOptions.any(
                (v) => (v['name'] ?? '').toString().trim().toLowerCase() ==
                    currentVariety,
              );

          if (!stillValidVariety) {
            _variety.clear();
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVarieties = false;
        _msg = 'Failed to load varieties: $e';
      });
    }
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
    final display = showing;
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();

    if (showing.isEmpty &&
        display.isEmpty &&
        first.isEmpty &&
        last.isEmpty) {
      throw Exception(
        'Enter at least a showing name, display name, or first/last name.',
      );
    }

    final existing = await supabase
        .from('exhibitors')
        .select('id')
        .eq('showing_name', showing)
        .eq('created_for_show_id', widget.showId)
        .maybeSingle();

    if (existing != null) {
      return existing['id'].toString();
    }

    final inserted = await supabase
        .from('exhibitors')
        .insert({
          'showing_name': showing.isEmpty ? null : showing,
          'display_name': showing.isEmpty ? null : showing,
          'first_name': first.isEmpty ? null : first,
          'last_name': last.isEmpty ? null : last,
          'email': email.isEmpty ? null : email,
          'phone': phone.isEmpty ? null : phone,
          'type': _exhibitorType,
          'is_active': true,
          'is_local_only': true,
          'created_for_show_id': widget.showId,
          'owner_user_id': null,
          'email': email.isEmpty ? null : email.toLowerCase(),
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

      for (final sectionId in _selectedSectionIds) {
        final kind = _sectionKindById(sectionId);

        if (kind == 'youth' && type != 'youth') {
          setState(() {
            _saving = false;
            _msg =
                'Open exhibitors cannot enter youth show sections. Remove ${_sectionDisplayLabelById(sectionId)}.';
          });
          return;
        }

        if (kind == 'open' && type == 'youth') {
          setState(() {
            _saving = false;
            _msg =
                'Youth exhibitors cannot enter open show sections. Remove ${_sectionDisplayLabelById(sectionId)}.';
          });
          return;
        }
      }

      if (!_useLocalAnimal && _animal == null) {
        throw Exception('Select an animal');
      }

      if (_useLocalAnimal) {
        if (_tattoo.text.trim().isEmpty) {
          throw Exception('Enter tattoo');
        }
        if (_breedId == null || _breed.text.trim().isEmpty) {
          throw Exception('Select breed');
        }
        if (_variety.text.trim().isEmpty) {
          throw Exception('Select variety');
        }
        if (_classValue == null || _classValue!.trim().isEmpty) {
          throw Exception('Select class');
        }
        if (_sexValue == null || _sexValue!.trim().isEmpty) {
          throw Exception('Select sex');
        }
      }

      final animalId = _useLocalAnimal ? null : _animal!['id'];

      if (animalId != null) {
        for (final sectionId in _selectedSectionIds) {
          final dup = await supabase
              .from('entries')
              .select('id')
              .eq('show_id', widget.showId)
              .eq('section_id', sectionId)
              .eq('animal_id', animalId)
              .maybeSingle();

          if (dup != null) {
            throw Exception(
              'Animal already entered in ${_sectionDisplayLabelById(sectionId)}',
            );
          }
        }
      }

      final rows = _selectedSectionIds.map((sectionId) {
        return {
          'show_id': widget.showId,
          'section_id': sectionId,
          'exhibitor_id': resolvedExhibitorId,
          'animal_id': animalId,
          'species': _useLocalAnimal ? _species : _animal!['species'],
          'tattoo': _useLocalAnimal
              ? _tattoo.text.trim().toUpperCase()
              : (_animal!['tattoo'] ?? '').toString().trim().toUpperCase(),
          'breed': _useLocalAnimal ? _breed.text.trim() : _animal!['breed'],
          'variety': _useLocalAnimal ? _variety.text.trim() : _animal!['variety'],
          'sex': _useLocalAnimal ? _sexValue : _animal!['sex'],
          'class_name': _useLocalAnimal
              ? _classValue
              : (_className.text.trim().isEmpty ? null : _className.text.trim()),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'is_fur': _isFur,
          'fur_notes': _isFur && _furNotes.text.trim().isNotEmpty
              ? _furNotes.text.trim()
              : null,
          'status': 'entered',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
      }).toList();

      await supabase.from('entries').insert(rows);

      if (!mounted) return;

      if (!reset) {
        Navigator.pop(context, true);
        return;
      }

      setState(() {
        _animal = null;
        _animals = _addNewExhibitor ? [] : _animals;
        _species = 'rabbit';
        _breedId = null;
        _breedOptions = [];
        _varietyOptions = [];
        _sexValue = _sexOptions.first;
        _sex.text = _sexValue ?? '';
        _classValue = null;
        _className.clear();
        _tattoo.clear();
        _breed.clear();
        _variety.clear();
        _notes.clear();
        _furNotes.clear();
        _isFur = false;
        _saving = false;
        _msg = 'Saved. Add another.';
      });

      await _loadBreedsForSpecies();
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
    final isSuccess = _msg == 'Saved. Add another.';

    return Padding(
      padding:
          EdgeInsets.only(bottom: inset + 16, left: 16, right: 16, top: 10),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add Entry',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_msg != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? Colors.green.withOpacity(.08)
                            : Colors.red.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSuccess
                              ? Colors.green.withOpacity(.25)
                              : Colors.red.withOpacity(.25),
                        ),
                      ),
                      child: Text(
                        _msg!,
                        style: TextStyle(
                          color:
                              isSuccess ? Colors.green.shade700 : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    'Show Letters / Sections',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      children: [
                        ...widget.sections.map((s) {
                          final id = s['id'].toString();
                          final checked = _selectedSectionIds.contains(id);

                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: checked,
                            title: Text((s['display_name'] ?? s['letter']).toString()),
                            onChanged: _saving
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedSectionIds.add(id);
                                        _sectionId = id;
                                      } else {
                                        _selectedSectionIds.remove(id);
                                        if (_sectionId == id) {
                                          _sectionId = _selectedSectionIds.isEmpty
                                              ? null
                                              : _selectedSectionIds.first;
                                        }
                                      }
                                      _msg = null;
                                    });
                                  },
                          );
                        }),
                        if (_selectedSectionIds.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Select at least one section.',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add New Exhibitor'),
                    subtitle: const Text(
                      'Create a show/local exhibitor with contact info',
                    ),
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
                      decoration: const InputDecoration(
                        labelText: 'Showing Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstName,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'First Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _lastName,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Last Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _email,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _exhibitorType,
                      decoration: const InputDecoration(
                        labelText: 'Exhibitor Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'adult', child: Text('Open')),
                        DropdownMenuItem(value: 'youth', child: Text('Youth')),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _exhibitorType = v ?? 'adult'),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: _exhibitorId,
                      decoration: const InputDecoration(
                        labelText: 'Exhibitor',
                        border: OutlineInputBorder(),
                      ),
                      items: _exhibitors
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e['id'].toString(),
                              child: Text(_exhibitorLabel(e)),
                            ),
                          )
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
                    subtitle: const Text(
                      'Use when the animal is not already in the system',
                    ),
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
                    DropdownButtonFormField<String>(
                      value: _species,
                      decoration: const InputDecoration(
                        labelText: 'Species',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                        DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) async {
                              final newSpecies = v ?? 'rabbit';
                              setState(() {
                                _species = newSpecies;
                                _sexValue = _sexOptions.first;
                                _sex.text = _sexValue ?? '';
                                _breedId = null;
                                _breedOptions = [];
                                _varietyOptions = [];
                                _breed.clear();
                                _variety.clear();
                                _msg = null;
                              });

                              await _loadBreedsForSpecies();
                            },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tattoo,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Tattoo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loadingBreeds) const LinearProgressIndicator(),
                    DropdownButtonFormField<String>(
                      value: _breedId,
                      decoration: const InputDecoration(
                        labelText: 'Breed',
                        border: OutlineInputBorder(),
                      ),
                      items: _breedOptions
                          .map(
                            (b) => DropdownMenuItem<String>(
                              value: (b['id'] ?? '').toString(),
                              child: Text((b['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) async {
                              final selected = _breedOptions.firstWhere(
                                (b) => (b['id'] ?? '').toString() == value,
                                orElse: () => <String, dynamic>{},
                              );

                              setState(() {
                                _breedId = value;
                                _breed.text = (selected['name'] ?? '').toString();
                                _variety.clear();
                                _varietyOptions = [];
                                _msg = null;
                              });

                              if (value != null && value.isNotEmpty) {
                                await _loadVarietiesForBreed(value);
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                    if (_breedId != null && _loadingVarieties) const LinearProgressIndicator(),
                    DropdownButtonFormField<String>(
                      value: _variety.text.trim().isEmpty ? null : _variety.text.trim(),
                      decoration: const InputDecoration(
                        labelText: 'Variety',
                        border: OutlineInputBorder(),
                      ),
                      items: _varietyOptions
                          .map(
                            (v) => DropdownMenuItem<String>(
                              value: (v['name'] ?? '').toString(),
                              child: Text((v['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: _saving || _breedId == null
                          ? null
                          : (value) {
                              setState(() {
                                _variety.text = value ?? '';
                                _msg = null;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _classValue,
                      decoration: const InputDecoration(
                        labelText: 'Class',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Senior', child: Text('Senior')),
                        DropdownMenuItem(value: 'Intermediate', child: Text('Intermediate')),
                        DropdownMenuItem(value: 'Junior', child: Text('Junior')),
                        DropdownMenuItem(value: 'Pre-Junior', child: Text('Pre-Junior')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _classValue = value ?? '';
                                _className.text = _classValue ?? '';
                                _msg = null;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _sexValue,
                      decoration: const InputDecoration(
                        labelText: 'Sex',
                        border: OutlineInputBorder(),
                      ),
                      items: _sexOptions
                          .map(
                            (sex) => DropdownMenuItem<String>(
                              value: sex,
                              child: Text(sex),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _sexValue = value;
                                _sex.text = value ?? '';
                                _msg = null;
                              });
                            },
                    ),
                    ] 
                    else ...[
                      if (_addNewExhibitor)
                        const Text(
                          'Select "Add New Animal" for a new walk-in exhibitor, or switch back to an existing exhibitor to load saved animals.',
                        )
                      else if (_exhibitorId == null)
                        const Text(
                          'Select an exhibitor first to load their animals.',
                        )
                      else if (_animals.isEmpty)
                        const Text(
                          'No saved animals found for this exhibitor. Use "Add New Animal" to enter one locally.',
                        )
                      else
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _animal,
                          decoration: const InputDecoration(
                            labelText: 'Animal',
                            border: OutlineInputBorder(),
                          ),
                          items: _animals
                              .map(
                                (a) => DropdownMenuItem<Map<String, dynamic>>(
                                  value: a,
                                  child: Text(_animalLabel(a)),
                                ),
                              )
                              .toList(),
                          onChanged:
                              _saving ? null : (v) => setState(() => _animal = v),
                        ),
                    ],

                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fur / Wool Entry'),
                    subtitle: const Text(
                      'Mark this animal as entered in Fur/Wool for this section',
                    ),
                    value: _isFur,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                              _isFur = v;
                              _msg = null;
                            }),
                  ),
                  if (_isFur) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _furNotes,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Fur / Wool Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _save(),
                          child: Text(_saving ? 'Saving…' : 'Save'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _save(reset: true),
                          child: const Text('Save & Add Another'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
    );
  }
}
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}