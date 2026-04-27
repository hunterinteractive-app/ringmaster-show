// lib/screens/my_entries_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'my_animals_screen.dart';
import 'account_settings_screen.dart';
import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import '../widgets/rm_widgets.dart';

final supabase = Supabase.instance.client;

class MyEntriesScreen extends StatefulWidget {
  const MyEntriesScreen({super.key});

  @override
  State<MyEntriesScreen> createState() => _MyEntriesScreenState();
}

class _MyEntriesScreenState extends State<MyEntriesScreen> {
  bool _loading = true;
  String? _msg;

  final Map<String, Map<String, dynamic>> _showsById = {};
  final Map<String, Map<String, dynamic>> _sectionsById = {};
  final Map<String, Map<String, dynamic>> _exhibitorsById = {};

  List<Map<String, dynamic>> _entries = [];
  final Set<String> _expandedShowIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

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

      final showIds = _entries
          .map((e) => (e['show_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();

      if (showIds.isNotEmpty) {
        final shows = await supabase
            .from('shows')
            .select('id,name,start_date,entry_close_at')
            .inFilter('id', showIds.toList());

        _showsById
          ..clear()
          ..addAll({
            for (final s in (shows as List).cast<Map<String, dynamic>>())
              s['id'].toString(): s,
          });

        final sections = await supabase
            .from('show_sections')
            .select('id,show_id,display_name,kind,letter,sort_order')
            .inFilter('show_id', showIds.toList());

        _sectionsById
          ..clear()
          ..addAll({
            for (final s in (sections as List).cast<Map<String, dynamic>>())
              s['id'].toString(): s,
          });
      }

      final exhibitorIds = _entries
          .map((e) => (e['exhibitor_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();

      if (exhibitorIds.isNotEmpty) {
        final exRows = await supabase
            .from('exhibitors')
            .select('id,showing_name,display_name')
            .inFilter('id', exhibitorIds.toList());

        _exhibitorsById
          ..clear()
          ..addAll({
            for (final e in (exRows as List).cast<Map<String, dynamic>>())
              e['id'].toString(): e,
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

  bool _hideShowAfter48h(String showId) {
    final sd = _showStartDate(showId);
    if (sd == null) return false;
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

  Future<void> _scratchEntry(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scratch Entry'),
        content: const Text(
          'This will mark the entry as scratched. You can restore it again before the entry deadline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Scratch'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('entries')
          .update({'status': 'scratched'})
          .eq('id', id);

      await _load();

      if (!mounted) return;
      setState(() {
        _msg = 'Entry scratched.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Scratch failed: $e');
    }
  }

  Future<void> _restoreEntry(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final showId = entry['show_id']?.toString() ?? '';
    if (showId.isEmpty) return;

    if (_deadlinePassedForShow(showId)) {
      setState(() {
        _msg = 'Entry deadline passed. Scratched entries can no longer be restored.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Entry'),
        content: const Text(
          'This will restore the scratched entry back into the show.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('entries')
          .update({'status': 'entered'})
          .eq('id', id);

      await _load();

      if (!mounted) return;
      setState(() {
        _msg = 'Entry restored.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Restore failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadMyAnimals() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final rows = await supabase
        .from('animals')
        .select('id,species,name,tattoo,breed,variety,sex,birth_date')
        .eq('owner_user_id', user.id)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final showId = entry['show_id']?.toString() ?? '';
    if (showId.isEmpty) return;

    if (_deadlinePassedForShow(showId)) {
      setState(() => _msg =
          'Entry deadline passed. Editing is locked. You can still scratch entries.');
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

    final picked = animals
        .where((a) => (a['id'] ?? '').toString() == result.animalId)
        .toList();
    if (picked.isEmpty) {
      setState(() => _msg = 'Selected animal not found.');
      return;
    }

    final a = picked.first;
    final rawSpecies = (a['species'] ?? '').toString().trim().toLowerCase();
    final species =
        (rawSpecies == 'rabbit' || rawSpecies == 'cavy') ? rawSpecies : null;

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

    return out;
  }

  void _openAnimals(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
    );
  }

  void _openAccount(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();

    final visibleShowIds = grouped.keys
        .where((showId) => !_hideShowAfter48h(showId))
        .toList()
      ..sort((a, b) {
        final aDate = _showStartDate(a);
        final bDate = _showStartDate(b);

        if (aDate != null && bDate != null) {
          return aDate.compareTo(bDate);
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }

        return _showTitle(a).compareTo(_showTitle(b));
      });

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'My Entries',
      showBackButton: true,
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Animals',
          icon: const Icon(Icons.pets),
          onPressed: () => _openAnimals(context),
        ),
        IconButton(
          tooltip: 'Account',
          icon: const Icon(Icons.manage_accounts),
          onPressed: () => _openAccount(context),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visibleShowIds.isEmpty
              ? const RMEmptyState(
                  title: 'No recent entries',
                  subtitle: 'Shows disappear here 48 hours after their show date.',
                  icon: Icons.receipt_long_outlined,
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: RMCard(
                          child: Text(
                            _msg!,
                            style: TextStyle(
                              color: _msg!.toLowerCase().contains('failed') ||
                                      _msg!.toLowerCase().contains('error') ||
                                      _msg!.toLowerCase().contains('required')
                                  ? AppColors.danger
                                  : AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
                        onRestore: _restoreEntry,
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
                      const SizedBox(height: AppSpacing.md),
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
  final Map<String, List<Map<String, dynamic>>> exhibitorBuckets;
  final String Function(String? exhibitorId) exhibitorLabel;
  final String Function(String? sectionId) sectionLabel;
  final Future<void> Function(Map<String, dynamic> entry) onEdit;
  final Future<void> Function(Map<String, dynamic> entry) onScratch;
  final Future<void> Function(Map<String, dynamic> entry) onRestore;
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
    required this.onRestore,
    required this.initiallyExpanded,
    required this.onExpandedChanged,
  });

  String _safeLower(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  String _safeLabel(dynamic value, String fallback) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Map<String, Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>>
      _groupEntriesForDisplay(List<Map<String, dynamic>> entries) {
    final grouped =
        <String, Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>>{};

    final sorted = List<Map<String, dynamic>>.from(entries)
      ..sort((a, b) {
        final breedCmp = _safeLower(a['breed']).compareTo(_safeLower(b['breed']));
        if (breedCmp != 0) return breedCmp;

        final varietyCmp =
            _safeLower(a['variety']).compareTo(_safeLower(b['variety']));
        if (varietyCmp != 0) return varietyCmp;

        final classCmp =
            _safeLower(a['class_name']).compareTo(_safeLower(b['class_name']));
        if (classCmp != 0) return classCmp;

        final sexCmp = _safeLower(a['sex']).compareTo(_safeLower(b['sex']));
        if (sexCmp != 0) return sexCmp;

        return _safeLower(a['tattoo']).compareTo(_safeLower(b['tattoo']));
      });

    for (final e in sorted) {
      final breed = _safeLabel(e['breed'], '(No Breed)');
      final variety = _safeLabel(e['variety'], '(No Variety)');
      final className = _safeLabel(e['class_name'], '(No Class)');
      final sex = _safeLabel(e['sex'], '(No Sex)');

      grouped.putIfAbsent(breed, () => {});
      grouped[breed]!.putIfAbsent(variety, () => {});
      grouped[breed]![variety]!.putIfAbsent(className, () => {});
      grouped[breed]![variety]![className]!.putIfAbsent(sex, () => []);
      grouped[breed]![variety]![className]![sex]!.add(e);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final exhibitorIds = exhibitorBuckets.keys.toList()
      ..sort((a, b) => exhibitorLabel(a).compareTo(exhibitorLabel(b)));

    final deadlineText = closeAt == null
        ? '(deadline not set)'
        : formatLocalDateTime(closeAt!.toIso8601String());

    final totalEntries =
        exhibitorBuckets.values.fold<int>(0, (sum, list) => sum + list.length);

    return RMCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpandedChanged,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          title: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                RMBadge(
                  text: '$totalEntries entr${totalEntries == 1 ? 'y' : 'ies'}',
                  icon: Icons.receipt_long,
                ),
                RMBadge(
                  text: deadlinePassed
                      ? 'Deadline Passed'
                      : 'Deadline: $deadlineText',
                  icon: Icons.event_available,
                  danger: deadlinePassed,
                  success: !deadlinePassed,
                ),
              ],
            ),
          ),
          children: [
            const SizedBox(height: AppSpacing.md),
            for (final exId in exhibitorIds) ...[
              Builder(
                builder: (context) {
                  final groupedEntries =
                      _groupEntriesForDisplay(exhibitorBuckets[exId]!);

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exhibitorLabel(exId),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...groupedEntries.entries.map((breedEntry) {
                          final breed = breedEntry.key;
                          final varieties = breedEntry.value;

                          final varietyKeys = varieties.keys.toList()
                            ..sort((a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()));

                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  breed,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ...varietyKeys.map((variety) {
                                  final classes = varieties[variety]!;
                                  final classKeys = classes.keys.toList()
                                    ..sort((a, b) => a.toLowerCase()
                                        .compareTo(b.toLowerCase()));

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      bottom: AppSpacing.sm,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          variety,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        ...classKeys.map((className) {
                                          final sexes = classes[className]!;
                                          final sexKeys = sexes.keys.toList()
                                            ..sort((a, b) => a.toLowerCase()
                                                .compareTo(b.toLowerCase()));

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 12,
                                              bottom: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  className,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                ...sexKeys.map((sex) {
                                                  final entries = sexes[sex]!;
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      left: 12,
                                                      bottom: 8,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          sex,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium,
                                                        ),
                                                        const SizedBox(height: 6),
                                                        ...entries.map((e) {
                                                          final section =
                                                              sectionLabel(
                                                                  e['section_id']);
                                                          final tattoo =
                                                              (e['tattoo'] ?? '')
                                                                  .toString()
                                                                  .trim();
                                                          final rawStatus =
                                                              (e['status'] ?? '')
                                                                  .toString()
                                                                  .trim();
                                                          final normalizedStatus =
                                                              rawStatus.isEmpty
                                                                  ? 'entered'
                                                                  : rawStatus;
                                                          final scratched =
                                                              normalizedStatus
                                                                      .toLowerCase() ==
                                                                  'scratched';

                                                          final canEdit =
                                                              !deadlinePassed &&
                                                                  !scratched;
                                                          final canScratch =
                                                              !scratched;
                                                          final canRestore =
                                                              scratched &&
                                                                  !deadlinePassed;

                                                          return Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              bottom: AppSpacing
                                                                  .sm,
                                                            ),
                                                            child: Container(
                                                              decoration:
                                                                  BoxDecoration(
                                                                color:
                                                                    Colors.white,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  AppRadius.sm,
                                                                ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .grey
                                                                      .shade200,
                                                                ),
                                                              ),
                                                              child: ListTile(
                                                                title: Text(
                                                                  tattoo.isEmpty
                                                                      ? '(No tattoo)'
                                                                      : tattoo,
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    decoration:
                                                                        scratched
                                                                            ? TextDecoration.lineThrough
                                                                            : null,
                                                                  ),
                                                                ),
                                                                subtitle:
                                                                    Padding(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .only(
                                                                    top: 6,
                                                                  ),
                                                                  child: Text(
                                                                    'Status: $normalizedStatus\nSection: $section',
                                                                  ),
                                                                ),
                                                                trailing:
                                                                    (canEdit ||
                                                                            canScratch ||
                                                                            canRestore)
                                                                        ? Wrap(
                                                                            spacing:
                                                                                4,
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
                                                                              if (canRestore)
                                                                                IconButton(
                                                                                  tooltip: 'Restore',
                                                                                  icon: const Icon(Icons.undo),
                                                                                  onPressed: () => onRestore(e),
                                                                                ),
                                                                            ],
                                                                          )
                                                                        : null,
                                                              ),
                                                            ),
                                                          );
                                                        }),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditEntryResult {
  final String animalId;
  final String className;

  _EditEntryResult({
    required this.animalId,
    required this.className,
  });
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
    final top = tattoo.isNotEmpty
        ? tattoo
        : (name.isNotEmpty ? name : (a['id'] ?? '').toString());
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
        final exists =
            _animals.any((a) => (a['id'] ?? '').toString() == _animalId);
        if (!exists && _animals.isNotEmpty) {
          _animalId = (_animals.first['id'] ?? '').toString();
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected =
        _animals.any((a) => (a['id'] ?? '').toString() == _animalId);

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
                    child: Text(
                      _animalLabel(a),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _animalId = v ?? _animalId),
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
                    _EditEntryResult(
                      animalId: _animalId,
                      className: _classCtrl.text,
                    ),
                  );
                },
          child: Text(_busy ? 'Working…' : 'Save'),
        ),
      ],
    );
  }
}