// lib/screens/admin/entries_by_breed_section_table.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/utils/csv_exporter.dart';

final supabase = Supabase.instance.client;

class EntriesByBreedSectionTable extends StatefulWidget {
  final String showId;
  final String showName;

  /// If true, scratched entries count too.
  final bool includeScratched;

  const EntriesByBreedSectionTable({
    super.key,
    required this.showId,
    required this.showName,
    this.includeScratched = false,
  });

  @override
  State<EntriesByBreedSectionTable> createState() => _EntriesByBreedSectionTableState();
}

class _EntriesByBreedSectionTableState extends State<EntriesByBreedSectionTable> {
  bool _loading = true;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  List<_BreedGroup> _breedGroups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EntriesByBreedSectionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showId != widget.showId ||
        oldWidget.includeScratched != widget.includeScratched) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final srows = await supabase
          .from('show_sections')
          .select('id,letter,display_name,kind,is_enabled,sort_order')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true);

      _sections = (srows as List).cast<Map<String, dynamic>>();
      _sections.sort((a, b) {
        int kindRank(String k) {
          switch (k) {
            case 'open':
              return 0;
            case 'youth':
              return 1;
            default:
              return 99;
          }
        }

        final ak = (a['kind'] ?? '').toString().toLowerCase();
        final bk = (b['kind'] ?? '').toString().toLowerCase();

        final kr = kindRank(ak).compareTo(kindRank(bk));
        if (kr != 0) return kr;

        final aso = a['sort_order'];
        final bso = b['sort_order'];
        final asoI = (aso is int) ? aso : int.tryParse(aso?.toString() ?? '') ?? 9999;
        final bsoI = (bso is int) ? bso : int.tryParse(bso?.toString() ?? '') ?? 9999;
        final soCmp = asoI.compareTo(bsoI);
        if (soCmp != 0) return soCmp;

        final al = (a['letter'] ?? '').toString().toUpperCase();
        final bl = (b['letter'] ?? '').toString().toUpperCase();
        return al.compareTo(bl);
      });

      var q = supabase
          .from('entries')
          .select('section_id,breed,variety,class_name,sex,exhibitor_id,species,scratched_at')
          .eq('show_id', widget.showId);

      if (!widget.includeScratched) {
        q = q.isFilter('scratched_at', null);
      }

      final rows = await q.order('breed').order('variety').order('class_name').order('sex');
      final entries = (rows as List).cast<Map<String, dynamic>>();

      final groups = _buildGroups(entries);

      if (!mounted) return;
      setState(() {
        _breedGroups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  String _safe(Map<String, dynamic> row, String key) {
    return (row[key] ?? '').toString().trim();
  }

  int _speciesRank(String species) {
    switch (species.toLowerCase()) {
      case 'rabbit':
        return 0;
      case 'cavy':
        return 1;
      default:
        return 99;
    }
  }

  int _ageRank(String age) {
    switch (age.toLowerCase()) {
      case 'junior':
        return 0;
      case 'intermediate':
        return 1;
      case 'senior':
        return 2;
      case 'open':
        return 3;
      default:
        return 99;
    }
  }

  String _ageOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final l = s.toLowerCase();

    if (l.contains('senior') || l.startsWith('sr')) return 'Senior';
    if (l.contains('intermediate') || l.startsWith('int')) return 'Intermediate';
    if (l.contains('junior') || l.startsWith('jr')) return 'Junior';
    if (l.contains('open')) return 'Open';

    return s;
  }

  String _sexOnly(String rawSex, String className) {
    final sex = rawSex.trim();
    if (sex.isNotEmpty) return sex;

    final c = className.toLowerCase();
    if (c.contains('buck')) return 'Buck';
    if (c.contains('doe')) return 'Doe';
    if (c.contains('boar')) return 'Boar';
    if (c.contains('sow')) return 'Sow';

    return '';
  }

  String _sectionHeader(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().toLowerCase();
    final letter = (s['letter'] ?? '').toString().toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = kind.isEmpty ? 'Section' : kind[0].toUpperCase() + kind.substring(1);
    }

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  List<_BreedGroup> _buildGroups(List<Map<String, dynamic>> rows) {
    final breedBuckets = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final breed = _safe(row, 'breed').isEmpty ? '(Unknown Breed)' : _safe(row, 'breed');
      breedBuckets.putIfAbsent(breed, () => <Map<String, dynamic>>[]);
      breedBuckets[breed]!.add(row);
    }

    final groups = breedBuckets.entries.map((breedEntry) {
      final breed = breedEntry.key;
      final breedRows = breedEntry.value;
      final species = breedRows.isEmpty ? '' : _safe(breedRows.first, 'species');

      final breedCounts = <String, int>{};
      final breedExhibitorsBySection = <String, Set<String>>{};
      final breedExhibitors = <String>{};

      for (final row in breedRows) {
        final sid = _safe(row, 'section_id');
        final exhibitorId = _safe(row, 'exhibitor_id');

        if (sid.isNotEmpty) {
          breedCounts[sid] = (breedCounts[sid] ?? 0) + 1;
          breedExhibitorsBySection.putIfAbsent(sid, () => <String>{});
          if (exhibitorId.isNotEmpty) {
            breedExhibitorsBySection[sid]!.add(exhibitorId);
          }
        }

        if (exhibitorId.isNotEmpty) breedExhibitors.add(exhibitorId);
      }

      final varietyBuckets = <String, List<Map<String, dynamic>>>{};
      for (final row in breedRows) {
        final variety = _safe(row, 'variety').isEmpty ? '(No Variety)' : _safe(row, 'variety');
        varietyBuckets.putIfAbsent(variety, () => <Map<String, dynamic>>[]);
        varietyBuckets[variety]!.add(row);
      }

      final varieties = varietyBuckets.entries.map((varietyEntry) {
        final variety = varietyEntry.key;
        final varietyRows = varietyEntry.value;

        final varietyCounts = <String, int>{};
        final varietyExhibitorsBySection = <String, Set<String>>{};
        final varietyExhibitors = <String>{};

        for (final row in varietyRows) {
          final sid = _safe(row, 'section_id');
          final exhibitorId = _safe(row, 'exhibitor_id');

          if (sid.isNotEmpty) {
            varietyCounts[sid] = (varietyCounts[sid] ?? 0) + 1;
            varietyExhibitorsBySection.putIfAbsent(sid, () => <String>{});
            if (exhibitorId.isNotEmpty) {
              varietyExhibitorsBySection[sid]!.add(exhibitorId);
            }
          }

          if (exhibitorId.isNotEmpty) varietyExhibitors.add(exhibitorId);
        }

        final classBuckets = <String, List<Map<String, dynamic>>>{};
        for (final row in varietyRows) {
          final age = _ageOnly(_safe(row, 'class_name'));
          final sex = _sexOnly(_safe(row, 'sex'), _safe(row, 'class_name'));

          final label =
              '${age.isEmpty ? '(No Age)' : age} • ${sex.isEmpty ? '(No Sex)' : sex}';

          classBuckets.putIfAbsent(label, () => <Map<String, dynamic>>[]);
          classBuckets[label]!.add(row);
        }

        final classes = classBuckets.entries.map((classEntry) {
          final classRows = classEntry.value;
          final first = classRows.first;

          final age = _ageOnly(_safe(first, 'class_name'));
          final sex = _sexOnly(_safe(first, 'sex'), _safe(first, 'class_name'));

          final classCounts = <String, int>{};
          final classExhibitorsBySection = <String, Set<String>>{};
          final classExhibitors = <String>{};

          for (final row in classRows) {
            final sid = _safe(row, 'section_id');
            final exhibitorId = _safe(row, 'exhibitor_id');

            if (sid.isNotEmpty) {
              classCounts[sid] = (classCounts[sid] ?? 0) + 1;
              classExhibitorsBySection.putIfAbsent(sid, () => <String>{});
              if (exhibitorId.isNotEmpty) {
                classExhibitorsBySection[sid]!.add(exhibitorId);
              }
            }

            if (exhibitorId.isNotEmpty) classExhibitors.add(exhibitorId);
          }

          return _ClassGroup(
            label: classEntry.key,
            age: age,
            sex: sex,
            countsBySection: classCounts,
            exhibitorsBySection: classExhibitorsBySection,
            rabbitCount: classRows.length,
            exhibitorCount: classExhibitors.length,
          );
        }).toList();

        classes.sort((a, b) {
          final ageCmp = _ageRank(a.age).compareTo(_ageRank(b.age));
          if (ageCmp != 0) return ageCmp;
          return a.sex.toLowerCase().compareTo(b.sex.toLowerCase());
        });

        return _VarietyGroup(
          variety: variety,
          countsBySection: varietyCounts,
          exhibitorsBySection: varietyExhibitorsBySection,
          rabbitCount: varietyRows.length,
          exhibitorCount: varietyExhibitors.length,
          classes: classes,
        );
      }).toList();

      varieties.sort((a, b) => a.variety.toLowerCase().compareTo(b.variety.toLowerCase()));

      return _BreedGroup(
        breed: breed,
        species: species,
        countsBySection: breedCounts,
        exhibitorsBySection: breedExhibitorsBySection,
        rabbitCount: breedRows.length,
        exhibitorCount: breedExhibitors.length,
        varieties: varieties,
      );
    }).toList();

    groups.sort((a, b) {
      final speciesCmp = _speciesRank(a.species).compareTo(_speciesRank(b.species));
      if (speciesCmp != 0) return speciesCmp;
      return a.breed.toLowerCase().compareTo(b.breed.toLowerCase());
    });

    return groups;
  }

  int _countForSection(Map<String, int> countsBySection, String sectionId) {
    return countsBySection[sectionId] ?? 0;
  }

  int _exhibitorsForSection(Map<String, Set<String>> exhibitorsBySection, String sectionId) {
    return exhibitorsBySection[sectionId]?.length ?? 0;
  }

  String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  String _buildCsv() {
    final header = <String>[
      'Breed',
      'Variety',
      'Age / Sex Class',
      ..._sections.map((s) => '${_sectionHeader(s)} (R/E)'),
      'Total Rabbits',
      'Unique Exhibitors',
    ];

    final lines = <List<String>>[];
    lines.add(header);

    for (final breed in _breedGroups) {
      lines.add([
        breed.breed,
        '',
        '',
        ..._sections.map((s) {
          final sid = s['id'].toString();
          final rabbits = _countForSection(breed.countsBySection, sid);
          final exhibitors = _exhibitorsForSection(breed.exhibitorsBySection, sid);
          return '$rabbits/$exhibitors';
        }),
        breed.rabbitCount.toString(),
        breed.exhibitorCount.toString(),
      ]);

      for (final variety in breed.varieties) {
        lines.add([
          breed.breed,
          variety.variety,
          '',
          ..._sections.map((s) {
            final sid = s['id'].toString();
            final rabbits = _countForSection(variety.countsBySection, sid);
            final exhibitors = _exhibitorsForSection(variety.exhibitorsBySection, sid);
            return '$rabbits/$exhibitors';
          }),
          variety.rabbitCount.toString(),
          variety.exhibitorCount.toString(),
        ]);

        for (final c in variety.classes) {
          lines.add([
            breed.breed,
            variety.variety,
            c.label,
            ..._sections.map((s) {
              final sid = s['id'].toString();
              final rabbits = _countForSection(c.countsBySection, sid);
              final exhibitors = _exhibitorsForSection(c.exhibitorsBySection, sid);
              return '$rabbits/$exhibitors';
            }),
            c.rabbitCount.toString(),
            c.exhibitorCount.toString(),
          ]);
        }
      }
    }

    return lines.map((r) => r.map(_csvEscape).join(',')).join('\n');
  }

  Future<void> _exportCsv() async {
    try {
      final csv = _buildCsv();
      final bytes = utf8.encode(csv);

      final suggestedName = 'entries_by_breed_section_${widget.showId}.csv';

      final msg = await exportCsvBytes(
        bytes: bytes,
        suggestedName: suggestedName,
      );

      if (!mounted) return;
      if (msg == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV export failed: $e')),
      );
    }
  }

  Widget _countChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }

  Widget _summaryChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }

  Widget _countsLegendBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'All section counts are shown as Rabbits / Exhibitors (R/E).',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _breedSummaryBar(_BreedGroup breed) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _summaryChip('Section Summary'),
          ..._sections.map((s) {
            final sid = s['id'].toString();
            final rabbits = _countForSection(breed.countsBySection, sid);
            final exhibitors = _exhibitorsForSection(breed.exhibitorsBySection, sid);
            return _summaryChip(
              '${_sectionHeader(s)}: ${rabbits == 0 && exhibitors == 0 ? '-' : '$rabbits/$exhibitors'}',
            );
          }),
        ],
      ),
    );
  }

  Widget _varietySummaryBar(_VarietyGroup variety) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _summaryChip('Variety Summary'),
          ..._sections.map((s) {
            final sid = s['id'].toString();
            final rabbits = _countForSection(variety.countsBySection, sid);
            final exhibitors = _exhibitorsForSection(variety.exhibitorsBySection, sid);
            return _summaryChip(
              '${_sectionHeader(s)}: ${rabbits == 0 && exhibitors == 0 ? '-' : '$rabbits/$exhibitors'}',
            );
          }),
        ],
      ),
    );
  }

  Widget _classTable(_VarietyGroup variety) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 42,
        dataRowMaxHeight: 52,
        columns: [
          const DataColumn(label: Text('Age / Sex Class')),
          ..._sections.map((s) => DataColumn(label: Text('${_sectionHeader(s)} (R/E)'))),
          const DataColumn(label: Text('Rabbits')),
          const DataColumn(label: Text('Exhibitors')),
        ],
        rows: variety.classes.map((c) {
          return DataRow(
            cells: [
              DataCell(Text(c.label)),
              ..._sections.map((s) {
                final sid = s['id'].toString();
                final rabbits = _countForSection(c.countsBySection, sid);
                final exhibitors = _exhibitorsForSection(c.exhibitorsBySection, sid);
                final text =
                    (rabbits == 0 && exhibitors == 0) ? '-' : '$rabbits/$exhibitors';
                return DataCell(Text(text));
              }),
              DataCell(Text(c.rabbitCount.toString())),
              DataCell(Text(c.exhibitorCount.toString())),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_msg != null) return Center(child: Text(_msg!));

    if (_sections.isEmpty) {
      return const Center(child: Text('No enabled sections for this show.'));
    }
    if (_breedGroups.isEmpty) {
      return const Center(child: Text('No entries found for this show.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Text('Entries by Breed / Section', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download),
                label: const Text('Export CSV'),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Reload',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _countsLegendBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _breedGroups.length,
            itemBuilder: (context, index) {
              final breed = _breedGroups[index];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text(breed.breed),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${breed.species.toUpperCase()} • ${breed.varieties.length} varieties'),
                      const SizedBox(height: 8),
                      _breedSummaryBar(breed),
                    ],
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        _countChip('Exhibitors', breed.exhibitorCount),
                        _countChip('Rabbits', breed.rabbitCount),
                      ],
                    ),
                  ),
                  children: [
                    const SizedBox(height: 8),
                    ...breed.varieties.map((variety) {
                      return Card(
                        margin: const EdgeInsets.only(top: 8),
                        color: Colors.black.withOpacity(0.02),
                        child: ExpansionTile(
                          title: Text(variety.variety),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${variety.classes.length} age/sex classes'),
                              const SizedBox(height: 8),
                              _varietySummaryBar(variety),
                            ],
                          ),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                _countChip('Exhibitors', variety.exhibitorCount),
                                _countChip('Rabbits', variety.rabbitCount),
                              ],
                            ),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          children: [
                            const SizedBox(height: 8),
                            _classTable(variety),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BreedGroup {
  final String breed;
  final String species;
  final Map<String, int> countsBySection;
  final Map<String, Set<String>> exhibitorsBySection;
  final int rabbitCount;
  final int exhibitorCount;
  final List<_VarietyGroup> varieties;

  _BreedGroup({
    required this.breed,
    required this.species,
    required this.countsBySection,
    required this.exhibitorsBySection,
    required this.rabbitCount,
    required this.exhibitorCount,
    required this.varieties,
  });
}

class _VarietyGroup {
  final String variety;
  final Map<String, int> countsBySection;
  final Map<String, Set<String>> exhibitorsBySection;
  final int rabbitCount;
  final int exhibitorCount;
  final List<_ClassGroup> classes;

  _VarietyGroup({
    required this.variety,
    required this.countsBySection,
    required this.exhibitorsBySection,
    required this.rabbitCount,
    required this.exhibitorCount,
    required this.classes,
  });
}

class _ClassGroup {
  final String label;
  final String age;
  final String sex;
  final Map<String, int> countsBySection;
  final Map<String, Set<String>> exhibitorsBySection;
  final int rabbitCount;
  final int exhibitorCount;

  _ClassGroup({
    required this.label,
    required this.age,
    required this.sex,
    required this.countsBySection,
    required this.exhibitorsBySection,
    required this.rabbitCount,
    required this.exhibitorCount,
  });
}