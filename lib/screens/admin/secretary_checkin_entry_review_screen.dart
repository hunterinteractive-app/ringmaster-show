import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/species_sex.dart';
import 'admin_entry_management_screen.dart';

/// Staff-facing entry review used while completing an exhibitor's check-in.
/// It intentionally mirrors the public check-in review instead of opening the
/// broader Entry Management area.
class SecretaryCheckinEntryReviewScreen extends StatefulWidget {
  const SecretaryCheckinEntryReviewScreen({
    super.key,
    required this.showId,
    required this.exhibitorId,
    required this.exhibitorName,
    required this.exhibitorNumber,
  });

  final String showId;
  final String exhibitorId;
  final String exhibitorName;
  final String exhibitorNumber;

  @override
  State<SecretaryCheckinEntryReviewScreen> createState() =>
      _SecretaryCheckinEntryReviewScreenState();
}

class _SecretaryCheckinEntryReviewScreenState
    extends State<SecretaryCheckinEntryReviewScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _entries = const [];
  String? _error;
  bool _loading = true;

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
      final rows = await _db
          .from('entries')
          .select(
            'id,show_id,section_id,exhibitor_id,exhibitor_user_id,animal_id,'
            'species,tattoo,animal_name,breed,variety,fur_variety,sex,'
            'class_name,notes,status,created_at,updated_at,scratched_at,is_fur,'
            'fur_placement,fur_notes,show_sections(id,letter,display_name,kind)',
          )
          .eq('show_id', widget.showId)
          .eq('exhibitor_id', widget.exhibitorId)
          .order('created_at');
      if (!mounted) return;
      setState(() => _entries = (rows as List).cast<Map<String, dynamic>>());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not load this exhibitor’s entries.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sectionLabel(Map<String, dynamic> entry) {
    final section = entry['show_sections'];
    if (section is! Map) return 'Show entries';
    final displayName = (section['display_name'] ?? '').toString().trim();
    final letter = (section['letter'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;
    return letter.isEmpty ? 'Show entries' : 'Show $letter';
  }

  String _entryTitle(Map<String, dynamic> entry) {
    final tattoo = (entry['tattoo'] ?? '').toString().trim();
    if (tattoo.isNotEmpty) return tattoo;
    final name = (entry['animal_name'] ?? '').toString().trim();
    return name.isEmpty ? 'Entry' : name;
  }

  String _entryDetails(Map<String, dynamic> entry) {
    final values =
        [
              entry['breed'],
              entry['variety'],
              displayClassNameForSpecies(
                species: entry['species'],
                className: entry['class_name'],
              ),
              displaySexForSpecies(
                species: entry['species'],
                sex: entry['sex'],
                className: entry['class_name'],
              ),
              if (entry['is_fur'] == true) 'Fur / Wool',
            ]
            .map((value) => (value ?? '').toString().trim())
            .where((value) => value.isNotEmpty);
    return values.join(' • ');
  }

  bool _isScratched(Map<String, dynamic> entry) {
    final scratchedAt = entry['scratched_at']?.toString().trim();
    return (scratchedAt != null && scratchedAt.isNotEmpty) ||
        (entry['status'] ?? '').toString().toLowerCase() == 'scratched';
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final saved = await showAdminEntryEditSheet(context, entry: entry);
    if (saved == true) await _load();
  }

  Future<void> _setScratch(Map<String, dynamic> entry, bool scratch) async {
    try {
      await _db.rpc(
        'set_entry_scratch_state',
        params: {'p_entry_id': entry['id'], 'p_is_scratched': scratch},
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this entry.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final entry in _entries) {
      grouped.putIfAbsent(_sectionLabel(entry), () => []).add(entry);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Entries'),
        actions: [
          IconButton(
            tooltip: 'Refresh entries',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: AppTheme.gradientTextScope(
          context,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Text(
                  widget.exhibitorName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.headerForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Exhibitor #${widget.exhibitorNumber}'),
                const SizedBox(height: 24),
                Text(
                  'Review entries',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.headerForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'These are the entries currently on file. Use Edit to make corrections before completing check-in.',
                  style: TextStyle(
                    color: AppColors.headerForeground.withValues(alpha: .86),
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  Center(child: Text(_error!))
                else if (grouped.isEmpty)
                  const Center(
                    child: Text('No entries are on file for this exhibitor.'),
                  )
                else
                  for (final group in grouped.entries) ...[
                    Text(
                      group.key,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.headerForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final entry in group.value) ...[
                      AppTheme.surfaceTextScope(
                        context,
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(_entryTitle(entry)),
                            subtitle: Text(_entryDetails(entry)),
                            trailing: Wrap(
                              spacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (_isScratched(entry))
                                  const Chip(label: Text('Scratched')),
                                OutlinedButton(
                                  onPressed: () => _editEntry(entry),
                                  child: const Text('Edit'),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Entry actions',
                                  onSelected: (action) =>
                                      _setScratch(entry, action == 'scratch'),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: _isScratched(entry)
                                          ? 'unscratch'
                                          : 'scratch',
                                      child: Text(
                                        _isScratched(entry)
                                            ? 'Un-scratch entry'
                                            : 'Scratch entry',
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
                    const SizedBox(height: 14),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
