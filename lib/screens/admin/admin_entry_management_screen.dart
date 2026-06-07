// lib/screens/admin/admin_entry_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';
import 'package:ringmaster_show/services/app_session.dart';
import 'package:ringmaster_show/widgets/animal_editor/open_animal_editor_dialog.dart';

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

  Future<void> _openEditExhibitor(Map<String, dynamic> entry) async {

    final exhibitorRaw = entry['exhibitors'];
    if (exhibitorRaw is! Map) {
      setState(() => _msg = 'Could not load exhibitor details for editing.');
      return;
    }

    final exhibitor = Map<String, dynamic>.from(exhibitorRaw);
    final ownerUserId = (exhibitor['owner_user_id'] ?? '').toString().trim();
    final readOnly = ownerUserId.isNotEmpty;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _EditExhibitorSheet(
          exhibitor: exhibitor,
          showId: widget.showId,
          readOnly: readOnly,
        ),
      ),
    );

    if (saved == true) {
      await _loadEntries();
      if (!mounted) return;
      setState(() => _msg = 'Exhibitor updated.');
    } else if (readOnly && mounted) {
      setState(() => _msg = null);
    }
  }

  Future<void> _loadEntries() async {
    var q = supabase
        .from('entries')
        .select(
          'id,show_id,section_id,exhibitor_id,exhibitor_user_id,animal_id,species,'
          'tattoo,animal_name,breed,variety,fur_variety,sex,class_name,notes,status,created_at,updated_at,scratched_at,'
          'is_fur,fur_placement,fur_notes,'
          'show_sections(id,letter,display_name,kind),'
          'exhibitors!entries_exhibitor_id_fkey(id,display_name,showing_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,owner_user_id,is_local_only,type,is_merged,merged_into_exhibitor_id)',
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
      (e['animal_name'] ?? '').toString(),
      (e['tattoo'] ?? '').toString(),
      (e['breed'] ?? '').toString(),
      (e['variety'] ?? '').toString(),
      (e['fur_variety'] ?? '').toString(), 
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
      await ShowLockService.assertShowUnlocked(widget.showId);

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

    // Entry Management should edit the show entry snapshot, not the saved
    // animal master profile. Saved animal profiles may belong to an exhibitor
    // account, and RLS correctly prevents show staff from editing those rows.
    // Updating the entries row keeps the current show entry correct without
    // changing the exhibitor's saved animal profile.
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
    if (AppSession.isSupportMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: const Text(
            'Support Mode — You are managing entries as an admin while viewing another user.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    if (_msg == null) return const SizedBox.shrink();

    final successMessages = {
      'Entry updated.',
      'Animal updated.',
      'Exhibitor updated.',
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

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Entry Mgmt — ${widget.showName}',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: AppSession.isSupportMode
              ? 'Add entry while viewing as another user'
              : 'Add Entry',
          icon: const Icon(Icons.add),
          onPressed: (_loading || _sections.isEmpty)
            ? null
            : _openAddEntry,
        ),
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : _loadAll,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                        onChanged: _sections.isEmpty ? null : _onChangeSection,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: 'Search entries (includes exhibitor name)',
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
                          child: Text('No entries found for this filter.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: exhibitorKeys.length,
                          itemBuilder: (context, idx) {
                            final exKey = exhibitorKeys[idx];
                            final exEntries = grouped[exKey] ?? [];
                            if (exEntries.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final exhibitorName =
                                _exhibitorDisplayName(exEntries.first);
                            final firstExhibitor = exEntries.first['exhibitors'];
                            final hasExhibitor = firstExhibitor is Map;
                            final exhibitorHasAccount = hasExhibitor &&
                                ((firstExhibitor['owner_user_id'] ?? '').toString().trim().isNotEmpty);
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
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        exhibitorName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (hasExhibitor)
                                      TextButton.icon(
                                        onPressed: () => _openEditExhibitor(exEntries.first),
                                        icon: Icon(
                                          exhibitorHasAccount ? Icons.visibility : Icons.edit,
                                          size: 18,
                                        ),
                                        label: Text(
                                          exhibitorHasAccount
                                              ? 'View Exhibitor'
                                              : 'Edit Exhibitor',
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${exEntries.length} entr${exEntries.length == 1 ? 'y' : 'ies'}',
                                ),
                                children: [
                                  const Divider(height: 1),
                                  ...exEntries.map((e) {
                                    final tattoo = (e['tattoo'] ?? '')
                                        .toString()
                                        .trim()
                                        .toUpperCase();
                                    final animalName = (e['animal_name'] ?? '').toString().trim();
                                    final breed = (e['breed'] ?? '').toString();
                                    final variety =
                                        (e['variety'] ?? '').toString();
                                    final furVariety =
                                        (e['fur_variety'] ?? '').toString();
                                    final notes = (e['notes'] ?? '').toString();
                                    final scratchedAt =
                                        e['scratched_at']?.toString();
                                    final isScratched = scratchedAt != null &&
                                        scratchedAt.isNotEmpty;

                                    final section = e['show_sections'];
                                    final letter = (section is Map
                                            ? (section['letter'] ?? '')
                                            : '')
                                        .toString();

                                    final titleLeft = animalName.isNotEmpty && tattoo.isNotEmpty
                                        ? '$animalName • $tattoo'
                                        : animalName.isNotEmpty
                                            ? animalName
                                            : tattoo.isEmpty
                                                ? '(no tattoo)'
                                                : tattoo;

                                    final isFur = e['is_fur'] == true;

                                    final subtitle = [
                                      if (breed.isNotEmpty) 'Breed: $breed',
                                      if (variety.isNotEmpty) 'Variety: $variety',
                                      if (isFur)
                                        furVariety.isNotEmpty
                                            ? 'Fur/Wool: $furVariety'
                                            : 'Fur/Wool',
                                      if (letter.isNotEmpty) 'Show: $letter',
                                      if (isScratched)
                                        'SCRATCHED: ${_dateOnly(scratchedAt)}',
                                      if (notes.isNotEmpty) 'Notes: $notes',
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
                                      subtitle:
                                          subtitle.isEmpty ? null : Text(subtitle),
                                      isThreeLine: subtitle.length > 80,
                                      trailing: PopupMenuButton<String>(
                                        tooltip: AppSession.isSupportMode
                                            ? 'Actions while viewing as another user'
                                            : 'Actions',
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
                                            child: Text(
                                              isScratched
                                                  ? 'Un-scratch'
                                                  : 'Scratch',
                                            ),
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

  late final TextEditingController _animalName;
  late final TextEditingController _tattoo;
  late final TextEditingController _breed;
  late final TextEditingController _variety;
  late final TextEditingController _sex;
  late final TextEditingController _className;
  late final TextEditingController _notes;
  bool _isFur = false;
  late final TextEditingController _furNotes;
  late final TextEditingController _furVariety;

  String _species = 'rabbit';
  String? _breedId;
  String? _sexValue;
  String? _classValue;
  String? _furVarietyValue;

  List<Map<String, dynamic>> _breedOptions = [];
  List<Map<String, dynamic>> _varietyOptions = [];

  bool _loadingBreeds = false;
  bool _loadingVarieties = false;
  bool _isLopBreedName(String breedName) {
    return breedName.trim().toLowerCase().endsWith('lop');
  }

  List<String> get _sexOptions =>
      _species == 'rabbit' ? const ['Buck', 'Doe'] : const ['Boar', 'Sow'];

  Future<void> _loadBreedsForSpecies({String? initialBreedName}) async {
    if (!mounted) return;
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

      final showId = (widget.entry['show_id'] ?? '').toString();
      final showBreedRes = await supabase
          .from('show_breeds')
          .select('breed_id,is_enabled')
          .eq('show_id', showId);

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

      final currentBreedName = (initialBreedName ?? _breed.text).trim().toLowerCase();
      final matchedBreed = effective.firstWhere(
        (b) => (b['name'] ?? '').toString().trim().toLowerCase() == currentBreedName,
        orElse: () => <String, dynamic>{},
      );

      if (!mounted) return;
      setState(() {
        _breedOptions = effective;
        _loadingBreeds = false;
        _breedId = matchedBreed.isEmpty ? null : matchedBreed['id']?.toString();
      });

      if (_breedId != null && _breedId!.isNotEmpty) {
        await _loadVarietiesForBreed(_breedId!, initialVarietyName: _variety.text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBreeds = false;
        _msg = 'Failed to load breeds: $e';
      });
    }
  }

  Future<void> _loadVarietiesForBreed(
    String breedId, {
    String? initialVarietyName,
  }) async {
    if (!mounted) return;
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

      if (_species == 'cavy') {
        final cavyRowsRes = await supabase
            .from('cavy_sop_variety_order')
            .select('variety_name,variety_sort_order')
            .eq('breed_name', breedName)
            .order('variety_sort_order', ascending: true)
            .order('variety_name', ascending: true);

        final cavyRows = (cavyRowsRes as List).cast<Map<String, dynamic>>();

        final effective = <Map<String, dynamic>>[];
        final seen = <String>{};

        for (final row in cavyRows) {
          final varietyName = (row['variety_name'] ?? '').toString().trim();
          if (varietyName.isEmpty) continue;

          final key = varietyName.toLowerCase();
          if (seen.contains(key)) continue;
          seen.add(key);

          effective.add({
            'id': 'cavy_$key',
            'name': varietyName,
          });
        }

        final currentVariety =
            (initialVarietyName ?? _variety.text).trim().toLowerCase();
        final matchedVariety = effective.firstWhere(
          (v) => (v['name'] ?? '').toString().trim().toLowerCase() == currentVariety,
          orElse: () => <String, dynamic>{},
        );

        if (!mounted) return;
        setState(() {
          _varietyOptions = effective;
          _loadingVarieties = false;

          if (matchedVariety.isNotEmpty) {
            _variety.text = (matchedVariety['name'] ?? '').toString();
          } else if (effective.length == 1) {
            _variety.text = (effective.first['name'] ?? '').toString();
          } else {
            _variety.clear();
          }
        });
        return;
      }

      if (_isLopBreedName(breedName)) {
        const lopOptions = [
          {'id': 'lop_broken', 'name': 'Broken'},
          {'id': 'lop_solid', 'name': 'Solid'},
        ];

        final currentVariety =
            (initialVarietyName ?? _variety.text).trim().toLowerCase();
        final matchedVariety = lopOptions.firstWhere(
          (v) => (v['name'] ?? '').toString().trim().toLowerCase() == currentVariety,
          orElse: () => <String, String>{},
        );

        if (!mounted) return;
        setState(() {
          _loadingVarieties = false;
          _varietyOptions = lopOptions;
          if (matchedVariety.isNotEmpty) {
            _variety.text = (matchedVariety['name'] ?? '').toString();
          } else if (lopOptions.length == 1) {
            _variety.text = (lopOptions.first['name'] ?? '').toString();
          } else {
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

      final showId = (widget.entry['show_id'] ?? '').toString();
      final showVarietiesRes = await supabase
          .from('show_varieties')
          .select('id,variety_id,custom_name,is_enabled')
          .eq('show_id', showId)
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

      final currentVariety =
          (initialVarietyName ?? _variety.text).trim().toLowerCase();
      final matchedVariety = effective.firstWhere(
        (v) => (v['name'] ?? '').toString().trim().toLowerCase() == currentVariety,
        orElse: () => <String, dynamic>{},
      );

      if (!mounted) return;
      setState(() {
        _varietyOptions = effective;
        _loadingVarieties = false;

        if (matchedVariety.isNotEmpty) {
          _variety.text = (matchedVariety['name'] ?? '').toString();
        } else if (effective.length == 1) {
          _variety.text = (effective.first['name'] ?? '').toString();
        } else {
          _variety.clear();
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

  @override
  void initState() {
    super.initState();
    _animalName = TextEditingController(
        text: (widget.entry['animal_name'] ?? '').toString().trim(),
      );
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
    _furVariety = TextEditingController(
      text: (widget.entry['fur_variety'] ?? '').toString(),
    );

    _species = (widget.entry['species'] ?? 'rabbit').toString().trim().toLowerCase();
    if (_species != 'cavy') _species = 'rabbit';

    final initialSex = _sex.text.trim();
    _sexValue = _sexOptions.contains(initialSex) ? initialSex : _sexOptions.first;
    _sex.text = _sexValue ?? '';

    final initialClass = _className.text.trim();
    const classOptions = ['Senior', 'Intermediate', 'Junior', 'Pre-Junior'];
    _classValue = classOptions.contains(initialClass) ? initialClass : null;

    final initialFurVariety = _furVariety.text.trim();
    _furVarietyValue = ['White', 'Colored'].contains(initialFurVariety)
        ? initialFurVariety
        : null;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBreedsForSpecies(initialBreedName: _breed.text);
    });
  }

  @override
  void dispose() {
    _animalName.dispose();
    _tattoo.dispose();
    _breed.dispose();
    _variety.dispose();
    _sex.dispose();
    _className.dispose();
    _notes.dispose();
    _furNotes.dispose();
    _furVariety.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final id = widget.entry['id'].toString();

      await ShowLockService.assertShowUnlocked(
        (widget.entry['show_id'] ?? '').toString(),
      );

      final updatePayload = <String, dynamic>{
        'animal_name': _animalName.text.trim().isEmpty
            ? null
            : _animalName.text.trim(),
        'tattoo': _tattoo.text.trim().isEmpty
            ? null
            : _tattoo.text.trim().toUpperCase(),
        'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(),
        'variety': _variety.text.trim().isEmpty ? null : _variety.text.trim(),
        'sex': _sexValue == null || _sexValue!.trim().isEmpty
            ? null
            : _sexValue!.trim(),
        'class_name': _classValue == null || _classValue!.trim().isEmpty
            ? null
            : _classValue!.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'is_fur': _isFur,
        'fur_variety': _isFur && (_furVarietyValue?.trim().isNotEmpty == true)
            ? _furVarietyValue!.trim()
            : null,
        'fur_notes': _isFur && _furNotes.text.trim().isNotEmpty
            ? _furNotes.text.trim()
            : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint('Updating entry $id with: $updatePayload');

      final updatedRows = await supabase
          .from('entries')
          .update(updatePayload)
          .eq('id', id)
          .select('id, animal_name, tattoo, breed, variety, sex, class_name, updated_at');

      final updatedList = (updatedRows as List).cast<Map<String, dynamic>>();
      if (updatedList.isEmpty) {
        throw Exception(
          'No entry row was updated. This usually means RLS blocked the update or the entry ID was not visible to this user.',
        );
      }

      debugPrint('Entry update succeeded: ${updatedList.first}');

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
                controller: _animalName,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Animal Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
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
              onChanged: (_saving || _breedId == null)
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
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fur / Wool Entry'),
              value: _isFur,
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                        _isFur = v;
                        if (!v) {
                          _furVarietyValue = null;
                          _furVariety.clear();
                          _furNotes.clear();
                        }
                        _msg = null;
                      }),
            ),
            if (_isFur) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _furVarietyValue,
                decoration: const InputDecoration(
                  labelText: 'Fur / Wool Class',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'White', child: Text('White')),
                  DropdownMenuItem(value: 'Colored', child: Text('Colored')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _furVarietyValue = value;
                          _furVariety.text = value ?? '';
                          _msg = null;
                        });
                      },
              ),
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

class _EditExhibitorSheet extends StatefulWidget {
  final Map<String, dynamic> exhibitor;
  final String showId;
  final bool readOnly;

  const _EditExhibitorSheet({
    required this.exhibitor,
    required this.showId,
    this.readOnly = false,
  });

  @override
  State<_EditExhibitorSheet> createState() => _EditExhibitorSheetState();
}

class _EditExhibitorSheetState extends State<_EditExhibitorSheet> {
  bool _saving = false;
  String? _msg;

  late final TextEditingController _showingName;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _addressLine1;
  late final TextEditingController _addressLine2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _zip;
  late final TextEditingController _arbaNumber;

  @override
  void initState() {
    super.initState();

    _showingName = TextEditingController(
      text: (widget.exhibitor['showing_name'] ??
              widget.exhibitor['display_name'] ??
              '')
          .toString()
          .trim(),
    );
    _firstName = TextEditingController(
      text: (widget.exhibitor['first_name'] ?? '').toString().trim(),
    );
    _lastName = TextEditingController(
      text: (widget.exhibitor['last_name'] ?? '').toString().trim(),
    );
    _email = TextEditingController(
      text: (widget.exhibitor['email'] ?? '').toString().trim(),
    );
    _phone = TextEditingController(
      text: (widget.exhibitor['phone'] ?? '').toString().trim(),
    );
    _addressLine1 = TextEditingController(
      text: (widget.exhibitor['address_line1'] ?? '').toString().trim(),
    );
    _addressLine2 = TextEditingController(
      text: (widget.exhibitor['address_line2'] ?? '').toString().trim(),
    );
    _city = TextEditingController(
      text: (widget.exhibitor['city'] ?? '').toString().trim(),
    );
    _state = TextEditingController(
      text: (widget.exhibitor['state'] ?? '').toString().trim().toUpperCase(),
    );
    _zip = TextEditingController(
      text: (widget.exhibitor['zip'] ?? '').toString().trim(),
    );
    _arbaNumber = TextEditingController(
      text: (widget.exhibitor['arba_number'] ?? '').toString().trim(),
    );
  }

  @override
  void dispose() {
    _showingName.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    _arbaNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {

    final ownerUserId =
        (widget.exhibitor['owner_user_id'] ?? '').toString().trim();
    if (ownerUserId.isNotEmpty) {
      setState(() => _msg = 'This exhibitor already has an account and cannot be edited here.');
      return;
    }

    final exhibitorId = (widget.exhibitor['id'] ?? '').toString().trim();
    if (exhibitorId.isEmpty) {
      setState(() => _msg = 'Missing exhibitor ID.');
      return;
    }

    final showing = _showingName.text.trim();
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final addressLine1 = _addressLine1.text.trim();
    final addressLine2 = _addressLine2.text.trim();
    final city = _city.text.trim();
    final state = _state.text.trim().toUpperCase();
    final zip = _zip.text.trim();
    final arbaNumber = _arbaNumber.text.trim();

    if (showing.isEmpty && first.isEmpty && last.isEmpty) {
      setState(() => _msg = 'Enter at least a showing name or first/last name.');
      return;
    }
    if (addressLine1.isEmpty) {
      setState(() => _msg = 'Enter address line 1.');
      return;
    }
    if (city.isEmpty) {
      setState(() => _msg = 'Enter city.');
      return;
    }
    if (state.isEmpty) {
      setState(() => _msg = 'Enter state.');
      return;
    }
    if (zip.isEmpty) {
      setState(() => _msg = 'Enter ZIP code.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);

      await supabase
          .from('exhibitors')
          .update({
            'showing_name': showing.isEmpty ? null : showing,
            'display_name': showing.isEmpty ? null : showing,
            'first_name': first.isEmpty ? null : first,
            'last_name': last.isEmpty ? null : last,
            'email': email.isEmpty ? null : email.toLowerCase(),
            'phone': phone.isEmpty ? null : phone,
            'address_line1': addressLine1,
            'address_line2': addressLine2.isEmpty ? null : addressLine2,
            'city': city,
            'state': state,
            'zip': zip,
            'arba_number': arbaNumber.isEmpty ? null : arbaNumber,
          })
          .eq('id', exhibitorId)
          .filter('owner_user_id', 'is', 'null');

      await supabase
          .from('entries')
          .update({
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('show_id', widget.showId)
          .eq('exhibitor_id', exhibitorId)
          .limit(1);

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
            Text(
              widget.readOnly ? 'View Exhibitor' : 'Edit Exhibitor',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.readOnly) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(.25)),
                ),
                child: const Text(
                  'This exhibitor has an account. Show secretaries can view the contact information here, but profile changes must be made by the exhibitor from their account.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
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
              controller: _showingName,
              enabled: !_saving && !widget.readOnly,
              textCapitalization: TextCapitalization.words,
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
                    enabled: !_saving && !widget.readOnly,
                    textCapitalization: TextCapitalization.words,
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
                    enabled: !_saving && !widget.readOnly,
                    textCapitalization: TextCapitalization.words,
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
              enabled: !_saving && !widget.readOnly,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              enabled: !_saving && !widget.readOnly,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _arbaNumber,
              enabled: !_saving && !widget.readOnly,
              decoration: const InputDecoration(
                labelText: 'ARBA Number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressLine1,
              enabled: !_saving && !widget.readOnly,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Address Line 1 *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressLine2,
              enabled: !_saving && !widget.readOnly,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Address Line 2',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _city,
              enabled: !_saving && !widget.readOnly,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'City *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _state,
                    enabled: !_saving && !widget.readOnly,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'State *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _zip,
                    enabled: !_saving && !widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'ZIP Code *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (widget.readOnly)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Close'),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A623),
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save Exhibitor'),
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

    if (_sectionId == null || _sectionId!.isEmpty) {
      setState(() => _msg = 'Select a section.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await ShowLockService.assertShowUnlocked(
        (widget.entry['show_id'] ?? '').toString(),
      );
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
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _sectionId = v),
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
              onPressed: _saving
                  ? null
                  : _save,
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
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _arbaNumber = TextEditingController();
  final _exhibitorSearch = TextEditingController();
  final _exhibitorSearchFocus = FocusNode();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();

  String _exhibitorType = 'adult';
  String _species = 'rabbit';

  final _animalName = TextEditingController();
  final _tattoo = TextEditingController();
  final _breed = TextEditingController();
  final _variety = TextEditingController();
  final _sex = TextEditingController();

  String? _breedId;
  String? _sexValue;
  String? _classValue;
  String? _furVarietyValue;

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
    if (_sectionId != null && _sectionId!.isNotEmpty) {
      _selectedSectionIds.add(_sectionId!);
    }
    _sexValue = _sexOptions.first;
    _sex.text = _sexValue ?? '';
    _className.text = _classValue ?? '';
    _loadExhibitors();
    _firstName.addListener(_autoFillShowingName);
    _lastName.addListener(_autoFillShowingName);
    _exhibitorSearch.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBreedsForSpecies();
    });
  }

  @override
  void dispose() {
    _showingName.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _arbaNumber.dispose();
    _exhibitorSearch.dispose();
    _exhibitorSearchFocus.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    _animalName.dispose();
    _tattoo.dispose();
    _breed.dispose();
    _variety.dispose();
    _sex.dispose();
    _className.dispose();
    _notes.dispose();
    _furNotes.dispose();
    super.dispose();
  }
  List<Map<String, dynamic>> _filteredExhibitors([String? searchText]) {
    final query = (searchText ?? _exhibitorSearch.text).trim().toLowerCase();
    if (query.isEmpty) return _exhibitors;

    return _exhibitors.where((e) {
      final haystack = [
        _exhibitorName(e),
        _exhibitorLabel(e),
        e['first_name'],
        e['last_name'],
        e['showing_name'],
        e['display_name'],
        e['email'],
        e['phone'],
        e['arba_number'],
        e['city'],
        e['state'],
        e['zip'],
      ].where((v) => v != null).map((v) => v.toString().toLowerCase()).join(' ');

      return haystack.contains(query);
    }).toList();
  }
  void _selectExhibitor(Map<String, dynamic> exhibitor) {
    final id = (exhibitor['id'] ?? '').toString();
    if (id.isEmpty) return;

    setState(() {
      _exhibitorId = id;
      _exhibitorSearch.text = _exhibitorLabel(exhibitor);
      _animal = null;
      _animals = [];
      _msg = null;
    });

    _loadAnimalsForSelectedExhibitor();
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

Future<void> _openSharedAnimalEditorForAdd() async {
  final exhibitor = _selectedExhibitor();
  if (exhibitor == null) {
    setState(() => _msg = 'Select an exhibitor before adding an animal.');
    return;
  }

  // Do not open the shared animal editor here. That editor runs as the
  // logged-in show secretary, so it saves the animal under the secretary's
  // account. This admin flow needs to collect the animal details inline and
  // let _save() attach the animal to the selected exhibitor account.
  setState(() {
    _useLocalAnimal = true;
    _animal = null;
    _msg = 'Enter the animal details below, then save the entry.';
  });
}

  Future<Map<String, dynamic>?> _findExistingShowExhibitor() async {
    final showing = _showingName.text.trim();
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();

    if (showing.isEmpty && first.isEmpty && last.isEmpty) return null;

    dynamic existing;

    if (showing.isNotEmpty) {
      existing = await supabase
          .from('exhibitors')
          .select(
            'id,showing_name,display_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,type,owner_user_id,is_active,is_local_only,created_for_show_id,is_merged,merged_into_exhibitor_id',
          )
          .eq('created_for_show_id', widget.showId)
          .eq('is_active', true)
          .or('is_merged.is.null,is_merged.eq.false')
          .eq('showing_name', showing)
          .maybeSingle();
    }

    if (existing == null && first.isNotEmpty && last.isNotEmpty) {
      existing = await supabase
          .from('exhibitors')
          .select(
            'id,showing_name,display_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,type,owner_user_id,is_active,is_local_only,created_for_show_id,is_merged,merged_into_exhibitor_id',
          )
          .eq('created_for_show_id', widget.showId)
          .eq('is_active', true)
          .or('is_merged.is.null,is_merged.eq.false')
          .eq('first_name', first)
          .eq('last_name', last)
          .maybeSingle();
    }

    if (existing == null) return null;
    return Map<String, dynamic>.from(existing as Map);
  }

  Future<void> _loadExhibitors() async {
    try {
      final res = await supabase
          .from('exhibitors')
          .select(
            'id,showing_name,display_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,type,owner_user_id,is_active,is_local_only,created_for_show_id,is_merged,merged_into_exhibitor_id',
          )
          .eq('is_active', true)
          .or('is_merged.is.null,is_merged.eq.false')
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

  String _exhibitorName(Map<String, dynamic> e) {
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

  String _exhibitorLabel(Map<String, dynamic> e) {
    final name = _exhibitorName(e);
    final city = (e['city'] ?? '').toString().trim();
    final state = (e['state'] ?? '').toString().trim().toUpperCase();
    final location = [city, state].where((s) => s.isNotEmpty).join(', ');

    if (location.isEmpty) return name;
    return '$name — $location';
  }

  Map<String, dynamic>? _selectedExhibitor() {
    final id = _exhibitorId;
    if (id == null || id.isEmpty) return null;

    for (final exhibitor in _exhibitors) {
      if ((exhibitor['id'] ?? '').toString() == id) {
        return exhibitor;
      }
    }

    return null;
  }

  Widget _selectedExhibitorContactCard() {
    final exhibitor = _selectedExhibitor();
    if (exhibitor == null) return const SizedBox.shrink();

    final name = _exhibitorName(exhibitor);
    final email = (exhibitor['email'] ?? '').toString().trim();
    final phone = (exhibitor['phone'] ?? '').toString().trim();
    final addressLine1 = (exhibitor['address_line1'] ?? '').toString().trim();
    final addressLine2 = (exhibitor['address_line2'] ?? '').toString().trim();
    final city = (exhibitor['city'] ?? '').toString().trim();
    final state = (exhibitor['state'] ?? '').toString().trim().toUpperCase();
    final zip = (exhibitor['zip'] ?? '').toString().trim();
    final arbaNumber = (exhibitor['arba_number'] ?? '').toString().trim();
    final type = (exhibitor['type'] ?? '').toString().trim();

    final cityStateZip = [
      [city, state].where((s) => s.isNotEmpty).join(', '),
      zip,
    ].where((s) => s.isNotEmpty).join(' ');

    final rows = <Widget>[
      _contactLine('Name', name),
      if (type.isNotEmpty) _contactLine('Type', type),
      if (email.isNotEmpty) _contactLine('Email', email),
      if (phone.isNotEmpty) _contactLine('Phone', phone),
      if (arbaNumber.isNotEmpty) _contactLine('ARBA #', arbaNumber),
      if (addressLine1.isNotEmpty) _contactLine('Address', addressLine1),
      if (addressLine2.isNotEmpty) _contactLine('Address 2', addressLine2),
      if (cityStateZip.isNotEmpty) _contactLine('City/State/ZIP', cityStateZip),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selected Exhibitor Contact',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _contactLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _animalLabel(Map<String, dynamic> a) {
    final tattoo = (a['tattoo'] ?? '').toString().trim().toUpperCase();
    final breed = (a['breed'] ?? '').toString().trim();
    final variety = (a['variety'] ?? '').toString().trim();
    final sex = (a['sex'] ?? '').toString().trim();
    final name = (a['name'] ?? '').toString().trim();

    final parts = <String>[];
    if (tattoo.isNotEmpty) parts.add(tattoo);
    if (breed.isNotEmpty) parts.add(breed);
    if (variety.isNotEmpty) parts.add(variety);
    if (sex.isNotEmpty) parts.add(sex);

    if (parts.isNotEmpty) return parts.join(' • ');
    if (name.isNotEmpty) return name;
    return '(Unnamed Animal)';
  }

  Widget _selectedAnimalSummaryCard() {
    final animal = _animal;
    if (animal == null) return const SizedBox.shrink();

    final name = (animal['name'] ?? '').toString().trim();
    final tattoo = (animal['tattoo'] ?? '').toString().trim().toUpperCase();
    final breed = (animal['breed'] ?? '').toString().trim();
    final variety = (animal['variety'] ?? '').toString().trim();
    final sex = (animal['sex'] ?? '').toString().trim();
    final birthDate = (animal['birth_date'] ?? '').toString().trim();
    final dobUnknown = animal['is_dob_unknown'] == true;
    final selectedClass = (_classValue ?? _className.text).trim();

    final rows = <Widget>[
      if (name.isNotEmpty) _contactLine('Name', name),
      if (tattoo.isNotEmpty) _contactLine('Tattoo', tattoo),
      if (breed.isNotEmpty) _contactLine('Breed', breed),
      if (variety.isNotEmpty) _contactLine('Variety', variety),
      if (sex.isNotEmpty) _contactLine('Saved Sex', sex),
      if (birthDate.isNotEmpty) _contactLine('DOB', birthDate),
      if (dobUnknown) _contactLine('DOB', 'Unknown'),
      _contactLine(
        'Entry Class',
        selectedClass.isEmpty ? 'Select class below' : selectedClass,
      ),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selected Animal Details',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
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

      // Cavy-specific loader
      if (_species == 'cavy') {
        final cavyRowsRes = await supabase
            .from('cavy_sop_variety_order')
            .select('variety_name,variety_sort_order')
            .eq('breed_name', breedName)
            .order('variety_sort_order')
            .order('variety_name');

        final cavyRows = (cavyRowsRes as List).cast<Map<String, dynamic>>();

        final effective = <Map<String, dynamic>>[];
        final seenNames = <String>{};

        for (final row in cavyRows) {
          final name = (row['variety_name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final key = name.toLowerCase();
          if (seenNames.contains(key)) continue;
          seenNames.add(key);

          effective.add({
            'id': 'cavy_$key',
            'name': name,
          });
        }

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
    final exhibitorId = (exhibitor['id'] ?? '').toString().trim();

    if (ownerUserId.isEmpty && exhibitorId.isEmpty) {
      if (mounted) {
        setState(() {
          _animals = [];
          _animal = null;
        });
      }
      return;
    }

    try {
      var query = supabase
          .from('animals')
          .select('id,owner_user_id,exhibitor_id,name,tattoo,breed,variety,sex,species,birth_date,is_dob_unknown');

      if (ownerUserId.isNotEmpty) {
        query = query.eq('owner_user_id', ownerUserId);
      } else {
        query = query.eq('exhibitor_id', exhibitorId);
      }

      final res = await query.order('created_at', ascending: false);

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
    if (AppSession.isSupportMode) {
      throw Exception('Creating exhibitors is disabled while viewing in support mode.');
    }
    final showing = _showingName.text.trim();
    final display = showing;
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final arbaNumber = _arbaNumber.text.trim();
    final addressLine1 = _addressLine1.text.trim();
    final addressLine2 = _addressLine2.text.trim();
    final city = _city.text.trim();
    final state = _state.text.trim().toUpperCase();
    final zip = _zip.text.trim();

    if (showing.isEmpty &&
        display.isEmpty &&
        first.isEmpty &&
        last.isEmpty) {
      throw Exception(
        'Enter at least a showing name, display name, or first/last name.',
      );
    }

    if (addressLine1.isEmpty) {
      throw Exception('Enter address line 1.');
    }
    if (city.isEmpty) {
      throw Exception('Enter city.');
    }
    if (state.isEmpty) {
      throw Exception('Enter state.');
    }
    if (zip.isEmpty) {
      throw Exception('Enter ZIP code.');
    }

    final existing = await supabase
        .from('exhibitors')
        .select(
          'id,showing_name,display_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,type,owner_user_id,is_active,is_local_only,created_for_show_id',
        )
        .eq('showing_name', showing)
        .eq('created_for_show_id', widget.showId)
        .maybeSingle();

    if (existing != null) {
      final existingType =
          (existing['type'] ?? '').toString().trim().toLowerCase();
      final wantedType = _exhibitorType.trim().toLowerCase();

      if (existingType == wantedType) {
        final row = Map<String, dynamic>.from(existing);
        final alreadyLoaded = _exhibitors.any(
          (e) => (e['id'] ?? '').toString() == (row['id'] ?? '').toString(),
        );
        if (!alreadyLoaded) {
          _exhibitors.add(row);
        }
        return row['id'].toString();
      }

      throw Exception(
        'An exhibitor named "$showing" already exists for this show as '
        '${existingType.isEmpty ? 'a different type' : existingType}. '
        'Please use the existing exhibitor or change the showing name.',
      );
    }

    final inserted = await supabase
        .from('exhibitors')
        .insert({
          'showing_name': showing.isEmpty ? null : showing,
          'display_name': showing.isEmpty ? null : showing,
          'first_name': first.isEmpty ? null : first,
          'last_name': last.isEmpty ? null : last,
          'phone': phone.isEmpty ? null : phone,
          'arba_number': arbaNumber.isEmpty ? null : arbaNumber,
          'address_line1': addressLine1,
          'address_line2': addressLine2.isEmpty ? null : addressLine2,
          'city': city,
          'state': state,
          'zip': zip,
          'type': _exhibitorType,
          'is_active': true,
          'is_local_only': true,
          'created_for_show_id': widget.showId,
          'owner_user_id': null,
          'email': email.isEmpty ? null : email.toLowerCase(),
        })
        .select(
          'id,showing_name,display_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,arba_number,type,owner_user_id,is_active,is_local_only,created_for_show_id',
        )
        .single();

    final row = Map<String, dynamic>.from(inserted);
    _exhibitors.add(row);

    return row['id'].toString();
  }

  Future<void> _save({bool reset = false}) async {
    if (AppSession.isSupportMode) {
      setState(() => _msg = 'Adding entries is disabled while viewing in support mode.');
      return;
    }
    if (_selectedSectionIds.isEmpty) {
      setState(() => _msg = 'Select at least one section.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
    await ShowLockService.assertShowUnlocked(widget.showId);
    
    String resolvedExhibitorId;

    if (_addNewExhibitor) {
      final existing = await _findExistingShowExhibitor();

      if (existing != null) {
        final existingId = (existing['id'] ?? '').toString();
        final existingType =
            (existing['type'] ?? '').toString().trim().toLowerCase();

        final hasYouthSection = _selectedSectionIds.any(
          (sectionId) => _sectionKindById(sectionId) == 'youth',
        );

        if (hasYouthSection && existingType != 'youth') {
          setState(() {
            _saving = false;
            _msg =
                'This exhibitor already exists as an open exhibitor. Select that exhibitor or create a separate youth exhibitor record.';
          });
          return;
        }

        final alreadyLoaded = _exhibitors.any(
          (e) => (e['id'] ?? '').toString() == existingId,
        );
        if (!alreadyLoaded) {
          _exhibitors.add(existing);
        }

        setState(() {
          _addNewExhibitor = false;
          _exhibitorId = existingId;
          _msg =
              'Existing exhibitor found. Select one of their animals below or turn on "Add New Animal".';
        });

        await _loadAnimalsForSelectedExhibitor();
        return;
      }

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

      final exhibitorOwnerUserId =
          (exhibitor['owner_user_id'] ?? '').toString().trim();
      final type = (exhibitor['type'] ?? '').toString().toLowerCase();

      final hasYouthSection = _selectedSectionIds.any(
        (sectionId) => _sectionKindById(sectionId) == 'youth',
      );

      if (hasYouthSection && type != 'youth') {
        setState(() {
          _saving = false;
          _msg = 'Only youth exhibitors can be used when any youth section is selected.';
        });
        return;
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
        if (_sexValue == null || _sexValue!.trim().isEmpty) {
          throw Exception('Select sex');
        }
      }

      final selectedClass = (_classValue ?? _className.text).trim();
      if (selectedClass.isEmpty) {
        throw Exception('Select class');
      }

      String? animalId;

      if (_useLocalAnimal) {
        final normalizedTattoo = _tattoo.text.trim().toUpperCase();
        final now = DateTime.now().toUtc().toIso8601String();

        var existingAnimalQuery = supabase
            .from('animals')
            .select('id')
            .eq('tattoo', normalizedTattoo)
            .eq('breed', _breed.text.trim())
            .eq('species', _species);

        if (exhibitorOwnerUserId.isNotEmpty) {
          existingAnimalQuery =
              existingAnimalQuery.eq('owner_user_id', exhibitorOwnerUserId);
        } else {
          existingAnimalQuery = existingAnimalQuery.eq('exhibitor_id', resolvedExhibitorId);
        }

        final existingAnimal = await existingAnimalQuery.maybeSingle();

        if (existingAnimal != null) {
          animalId = (existingAnimal['id'] ?? '').toString();
        } else {
          final insertedAnimal = await supabase
              .from('animals')
              .insert({
                'owner_user_id': exhibitorOwnerUserId.isEmpty ? null : exhibitorOwnerUserId,
                'exhibitor_id': resolvedExhibitorId,
                'species': _species,
                'name': _animalName.text.trim().isEmpty
                    ? null
                    : _animalName.text.trim(),
                'tattoo': normalizedTattoo,
                'breed': _breed.text.trim(),
                'variety': _variety.text.trim().isEmpty
                    ? null
                    : _variety.text.trim(),
                'sex': _sexValue,
                'created_at': now,
                'updated_at': now,
              })
              .select('id')
              .single();

          animalId = (insertedAnimal['id'] ?? '').toString();
        }
      } else {
        animalId = (_animal!['id'] ?? '').toString();
      }

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

      final rows = <Map<String, dynamic>>[];

      for (final sectionId in _selectedSectionIds) {
        final baseRow = {
          'show_id': widget.showId,
          'section_id': sectionId,
          'exhibitor_id': resolvedExhibitorId,
          'exhibitor_user_id':
              exhibitorOwnerUserId.isEmpty ? null : exhibitorOwnerUserId,
          'animal_id': animalId,
          'species': _useLocalAnimal ? _species : _animal!['species'],
          'tattoo': _useLocalAnimal
              ? _tattoo.text.trim().toUpperCase()
              : (_animal!['tattoo'] ?? '').toString().trim().toUpperCase(),
          'animal_name': _useLocalAnimal
              ? (_animalName.text.trim().isEmpty ? null : _animalName.text.trim())
              : ((_animal!['name'] ?? '').toString().trim().isEmpty
                  ? null
                  : (_animal!['name'] ?? '').toString().trim()),
          'breed': _useLocalAnimal ? _breed.text.trim() : _animal!['breed'],
          'variety': _useLocalAnimal ? _variety.text.trim() : _animal!['variety'],
          'sex': _useLocalAnimal ? _sexValue : _animal!['sex'],
          'class_name': selectedClass,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'status': 'entered',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };

        // Main class entry (always non-fur)
        rows.add({
          ...baseRow,
          'is_fur': false,
          'fur_variety': null,
          'fur_notes': null,
        });

        // Separate fur/wool entry
        if (_isFur) {
          rows.add({
            ...baseRow,
            'is_fur': true,
            'fur_variety': _furVarietyValue?.trim().isNotEmpty == true
                ? _furVarietyValue!.trim()
                : null,
            'fur_notes': _furNotes.text.trim().isNotEmpty
                ? _furNotes.text.trim()
                : null,
          });
        }
      }

      await supabase.from('entries').insert(rows);

      if (!mounted) return;

      if (!reset) {
        Navigator.pop(context, true);
        return;
      }

      setState(() {
        _animal = null;
        if (!_addNewExhibitor && _exhibitorId != null) {
          _loadAnimalsForSelectedExhibitor();
        } else {
          _animals = _addNewExhibitor ? [] : _animals;
        }
        _species = 'rabbit';
        _breedId = null;
        _breedOptions = [];
        _varietyOptions = [];
        _sexValue = _sexOptions.first;
        _sex.text = _sexValue ?? '';
        _classValue = null;
        _furVarietyValue = null;
        _className.clear();
        _animalName.clear();
        _tattoo.clear();
        _breed.clear();
        _variety.clear();
        _notes.clear();
        _furNotes.clear();
        if (_addNewExhibitor) {
          _arbaNumber.clear();
          _addressLine1.clear();
          _addressLine2.clear();
          _city.clear();
          _state.clear();
          _zip.clear();
        }
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
                            onChanged: (_saving || AppSession.isSupportMode)
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
                    onChanged: (_saving || AppSession.isSupportMode)
                        ? null
                        : (v) {
                            setState(() {
                              _addNewExhibitor = v;
                              _exhibitorId = null;
                              _animal = null;
                              _animals = [];
                              _exhibitorSearch.clear();
                              _msg = null;
                            });
                          },
                  ),
                  if (_addNewExhibitor) ...[
                    TextField(
                      controller: _showingName,
                      enabled: !_saving && !AppSession.isSupportMode,
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
                            enabled: !_saving && !AppSession.isSupportMode,
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
                            enabled: !_saving && !AppSession.isSupportMode,
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
                      enabled: !_saving && !AppSession.isSupportMode,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      enabled: !_saving && !AppSession.isSupportMode,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: _arbaNumber,
                      enabled: !_saving && !AppSession.isSupportMode,
                      decoration: const InputDecoration(
                        labelText: 'ARBA Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressLine1,
                      enabled: !_saving && !AppSession.isSupportMode,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Address Line 1 *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressLine2,
                      enabled: !_saving && !AppSession.isSupportMode,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Address Line 2',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _city,
                      enabled: !_saving && !AppSession.isSupportMode,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'City *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _state,
                            enabled: !_saving && !AppSession.isSupportMode,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [UpperCaseTextFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'State *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _zip,
                            enabled: !_saving && !AppSession.isSupportMode,
                            decoration: const InputDecoration(
                              labelText: 'ZIP Code *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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
                      onChanged: (_saving || AppSession.isSupportMode)
                          ? null
                          : (v) => setState(() => _exhibitorType = v ?? 'adult'),
                    ),
                  ] else ...[
                    RawAutocomplete<Map<String, dynamic>>(
                      textEditingController: _exhibitorSearch,
                      focusNode: _exhibitorSearchFocus,
                      displayStringForOption: _exhibitorLabel,
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        return _filteredExhibitors(textEditingValue.text);
                      },
                      onSelected: _selectExhibitor,
                      fieldViewBuilder: (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          enabled: !_saving && !AppSession.isSupportMode,
                          decoration: InputDecoration(
                            labelText: 'Exhibitor',
                            hintText: 'Search by name, city, state, email, phone, or ARBA #',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: textEditingController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear exhibitor',
                                    icon: const Icon(Icons.clear),
                                    onPressed: (_saving || AppSession.isSupportMode)
                                        ? null
                                        : () {
                                            setState(() {
                                              textEditingController.clear();
                                              _exhibitorId = null;
                                              _animal = null;
                                              _animals = [];
                                              _msg = null;
                                            });
                                          },
                                  ),
                            helperText: textEditingController.text.trim().isEmpty
                                ? 'Start typing to search exhibitors'
                                : '${_filteredExhibitors(textEditingController.text).length} match${_filteredExhibitors(textEditingController.text).length == 1 ? '' : 'es'} found',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            final selected = _selectedExhibitor();
                            if (selected != null && value != _exhibitorLabel(selected)) {
                              setState(() {
                                _exhibitorId = null;
                                _animal = null;
                                _animals = [];
                                _msg = null;
                              });
                            } else {
                              setState(() {});
                            }
                          },
                          onSubmitted: (_) => onFieldSubmitted(),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        final optionList = options.toList();
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 280,
                                maxWidth: 620,
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: optionList.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final option = optionList[index];
                                  final email = (option['email'] ?? '').toString().trim();
                                  final phone = (option['phone'] ?? '').toString().trim();
                                  final subtitle = [email, phone]
                                      .where((s) => s.isNotEmpty)
                                      .join(' • ');

                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      _exhibitorLabel(option),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: subtitle.isEmpty
                                        ? null
                                        : Text(
                                            subtitle,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    _selectedExhibitorContactCard(),
                  ],
                  const SizedBox(height: 14),
                  if (!_addNewExhibitor && !_useLocalAnimal) ...[
                    if (_exhibitorId == null)
                      const Text(
                        'Select an exhibitor first to load their animals.',
                      )
                    else if (_animals.isEmpty)
                      const Text(
                        'No saved animals found for this exhibitor. Use "Add New Animal" to add one.',
                      )
                    else
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: _animal,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Saved Animal',
                          border: OutlineInputBorder(),
                        ),
                        items: _animals
                            .map(
                              (a) => DropdownMenuItem<Map<String, dynamic>>(
                                value: a,
                                child: Text(
                                  _animalLabel(a),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (_saving || AppSession.isSupportMode)
                            ? null
                            : (v) => setState(() {
                                  _animal = v;
                                  final savedSex = (v?['sex'] ?? '').toString().trim();
                                  if (savedSex.isNotEmpty) {
                                    _sexValue = savedSex;
                                    _sex.text = savedSex;
                                  }
                                  _msg = null;
                                }),
                      ),
                      _selectedAnimalSummaryCard(),
                    const SizedBox(height: 14),
                  ],
                  if (!_addNewExhibitor) ...[
                    OutlinedButton.icon(
                      onPressed: (_saving || AppSession.isSupportMode || _exhibitorId == null)
                          ? null
                          : _openSharedAnimalEditorForAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add New Animal'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _exhibitorId == null
                          ? 'Select an exhibitor before adding an animal.'
                          : 'Use this to add a new animal for the selected exhibitor. Account exhibitors will have it saved to their account.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Add New Animal'),
                      subtitle: const Text(
                        'Enter animal details for this new walk-in/local exhibitor',
                      ),
                      value: _useLocalAnimal,
                      onChanged: (_saving || AppSession.isSupportMode)
                          ? null
                          : (v) {
                              setState(() {
                                _useLocalAnimal = v;
                                _animal = null;
                                _msg = null;
                              });
                            },
                    ),
                  ],
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
                      onChanged: (_saving || AppSession.isSupportMode)
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
                      controller: _animalName,
                      enabled: !_saving && !AppSession.isSupportMode,
                      decoration: const InputDecoration(
                        labelText: 'Animal Name (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tattoo,
                      enabled: !_saving && !AppSession.isSupportMode,
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
                      onChanged: (_saving || AppSession.isSupportMode)
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
                      onChanged: (_saving || AppSession.isSupportMode || _breedId == null)
                          ? null
                          : (value) {
                              setState(() {
                                _variety.text = value ?? '';
                                _msg = null;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
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
                      onChanged: (_saving || AppSession.isSupportMode)
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
                    else if (_addNewExhibitor) ...[
                      const Text(
                        'Select "Add New Animal" for a new walk-in exhibitor, or switch back to an existing exhibitor to load saved animals.',
                      ),
                    ],

                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _classValue,
                    decoration: const InputDecoration(
                      labelText: 'Class / Age Override',
                      helperText: 'Use this when DOB is missing or when the show secretary needs to override the calculated class.',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Senior', child: Text('Senior')),
                      DropdownMenuItem(value: 'Intermediate', child: Text('Intermediate')),
                      DropdownMenuItem(value: 'Junior', child: Text('Junior')),
                      DropdownMenuItem(value: 'Pre-Junior', child: Text('Pre-Junior')),
                    ],
                    onChanged: (_saving || AppSession.isSupportMode)
                        ? null
                        : (value) {
                            setState(() {
                              _classValue = value;
                              _className.text = value ?? '';
                              _msg = null;
                            });
                          },
                  ),

                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fur / Wool Entry'),
                    subtitle: const Text(
                      'Mark this animal as entered in Fur/Wool for this section',
                    ),
                    value: _isFur,
                    onChanged: (_saving || AppSession.isSupportMode)
                        ? null
                        : (v) => setState(() {
                              _isFur = v;
                              if (!_isFur) _furVarietyValue = null;
                              _msg = null;
                            }),
                  ),
                  if (_isFur) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _furNotes,
                      enabled: !_saving && !AppSession.isSupportMode,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Fur / Wool Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _furVarietyValue,
                      decoration: const InputDecoration(
                        labelText: 'Fur / Wool Class',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'White', child: Text('White')),
                        DropdownMenuItem(value: 'Colored', child: Text('Colored')),
                      ],
                      onChanged: (_saving || AppSession.isSupportMode)
                          ? null
                          : (value) {
                              setState(() {
                                _furVarietyValue = value;
                                _msg = null;
                              });
                            },
                    ),
                  ],

                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    enabled: !_saving && !AppSession.isSupportMode,
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