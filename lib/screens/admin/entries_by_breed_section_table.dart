// lib/screens/admin/entries_by_breed_section_table.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/utils/csv_exporter.dart';
import 'package:ringmaster_show/services/app_session.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

final supabase = Supabase.instance.client;

class EntriesByBreedSectionTable extends StatefulWidget {
  final String showId;
  final String showName;

  /// If true, scratched entries count too.
  final bool includeScratched;

  /// If false, hides the CSV export button.
  final bool showExportButton;

  /// If false, hides exhibitor counts and only shows showing entry counts.
  final bool showExhibitorCounts;

  /// Screen/table title.
  final String title;

  const EntriesByBreedSectionTable({
    super.key,
    required this.showId,
    required this.showName,
    this.includeScratched = false,
    this.showExportButton = true,
    this.showExhibitorCounts = true,
    this.title = 'Entries by Breed / Section',
  });

  @override
  State<EntriesByBreedSectionTable> createState() =>
      _EntriesByBreedSectionTableState();
}

class _EntriesByBreedSectionTableState
    extends State<EntriesByBreedSectionTable> {
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
      final resp = await supabase.rpc(
        'report_entries_by_breed_section_bundle',
        params: {
          'p_show_id': widget.showId,
          'p_include_scratched': widget.includeScratched,
        },
      );

      final json = Map<String, dynamic>.from(resp as Map);

      final sectionRows = (json['sections'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final entryRows = (json['rows'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      _sections = sectionRows;

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
        final asoI = (aso is int)
            ? aso
            : int.tryParse(aso?.toString() ?? '') ?? 9999;
        final bsoI = (bso is int)
            ? bso
            : int.tryParse(bso?.toString() ?? '') ?? 9999;
        final soCmp = asoI.compareTo(bsoI);
        if (soCmp != 0) return soCmp;

        final al = (a['letter'] ?? '').toString().toUpperCase();
        final bl = (b['letter'] ?? '').toString().toUpperCase();
        return al.compareTo(bl);
      });

      entryRows.sort((a, b) {
        int cmp(String key) =>
            ((a[key] ?? '').toString()).compareTo((b[key] ?? '').toString());

        final breedCmp = cmp('breed');
        if (breedCmp != 0) return breedCmp;

        final varietyCmp = cmp('variety');
        if (varietyCmp != 0) return varietyCmp;

        final classCmp = cmp('class_name');
        if (classCmp != 0) return classCmp;

        return cmp('sex');
      });

      final groups = _buildGroups(entryRows);

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
    if (l.contains('intermediate') || l.startsWith('int')) {
      return 'Intermediate';
    }
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
        kindLabel = kind.isEmpty
            ? 'Section'
            : kind[0].toUpperCase() + kind.substring(1);
    }

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  List<_BreedGroup> _buildGroups(List<Map<String, dynamic>> rows) {
    final breedBuckets = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final breed = _safe(row, 'breed').isEmpty
          ? '(Unknown Breed)'
          : _safe(row, 'breed');
      breedBuckets.putIfAbsent(breed, () => <Map<String, dynamic>>[]);
      breedBuckets[breed]!.add(row);
    }

    final groups = breedBuckets.entries.map((breedEntry) {
      final breed = breedEntry.key;
      final breedRows = breedEntry.value;
      final species = breedRows.isEmpty
          ? ''
          : _safe(breedRows.first, 'species');

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
        final variety = _safe(row, 'variety').isEmpty
            ? '(No Variety)'
            : _safe(row, 'variety');
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
              '${age.isEmpty ? '(No Age)' : age} / ${sex.isEmpty ? '(No Sex)' : sex}';

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
      final speciesCmp = _speciesRank(
        a.species,
      ).compareTo(_speciesRank(b.species));
      if (speciesCmp != 0) return speciesCmp;
      return a.breed.toLowerCase().compareTo(b.breed.toLowerCase());
    });

    return groups;
  }

  int _countForSection(Map<String, int> countsBySection, String sectionId) {
    return countsBySection[sectionId] ?? 0;
  }

  int _exhibitorsForSection(
    Map<String, Set<String>> exhibitorsBySection,
    String sectionId,
  ) {
    return exhibitorsBySection[sectionId]?.length ?? 0;
  }

  String _csvEscape(String v) {
    if (v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  String _buildCsv() {
    final header = <String>[
      'Breed',
      'Variety',
      'Age / Sex Class',
      ..._sections.map((s) => '${_sectionHeader(s)} Showing'),
      'Total Showing',
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
          return rabbits.toString();
        }),
        breed.rabbitCount.toString(),
      ]);
    }

    return lines.map((r) => r.map(_csvEscape).join(',')).join('\n');
  }

  List<List<String>> _pdfRows() {
    final rows = <List<String>>[];

    for (final breed in _breedGroups) {
      rows.add([
        breed.breed,
        '',
        '',
        ..._sections.map((s) {
          final sid = s['id'].toString();
          final rabbits = _countForSection(breed.countsBySection, sid);
          return rabbits.toString();
        }),
        breed.rabbitCount.toString(),
      ]);

      for (final variety in breed.varieties) {
        rows.add([
          breed.breed,
          variety.variety,
          '',
          ..._sections.map((s) {
            final sid = s['id'].toString();
            final rabbits = _countForSection(variety.countsBySection, sid);
            return rabbits.toString();
          }),
          variety.rabbitCount.toString(),
        ]);

        for (final c in variety.classes) {
          rows.add([
            breed.breed,
            variety.variety,
            c.label,
            ..._sections.map((s) {
              final sid = s['id'].toString();
              final rabbits = _countForSection(c.countsBySection, sid);
              return rabbits == 0 ? '-' : rabbits.toString();
            }),
            c.rabbitCount.toString(),
          ]);
        }
      }
    }

    return rows;
  }

  Future<void> _exportPdf() async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                widget.title,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(widget.showName),
              pw.SizedBox(height: 8),
              pw.Text(
                'Export counts shown as entries currently showing only.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
          footer: (context) => pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: [
                'Breed',
                'Variety',
                'Age / Sex Class',
                ..._sections.map((s) => '${_sectionHeader(s)} Showing'),
                'Total Showing',
              ],
              data: _pdfRows(),
              headerStyle: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              cellPadding: const pw.EdgeInsets.all(3),
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'entries_by_breed_section_${widget.showId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
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

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }

  Widget _countChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.10)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _overallTotalsHeader() {
    final totalShowing = _breedGroups.fold<int>(
      0,
      (sum, breed) => sum + breed.rabbitCount,
    );

    final totalExhibitors = <String>{};
    for (final breed in _breedGroups) {
      for (final exhibitors in breed.exhibitorsBySection.values) {
        totalExhibitors.addAll(exhibitors);
      }
    }

    return AppTheme.surfaceTextScope(
      context,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entry Totals',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._sections.map((s) {
                    final sid = s['id'].toString();
                    var showing = 0;
                    final exhibitors = <String>{};

                    for (final breed in _breedGroups) {
                      showing += _countForSection(breed.countsBySection, sid);
                      exhibitors.addAll(
                        breed.exhibitorsBySection[sid] ?? const <String>{},
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _summaryChip(
                        widget.showExhibitorCounts
                            ? '${_sectionHeader(s)}: $showing/${exhibitors.length}'
                            : '${_sectionHeader(s)}: $showing',
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _summaryChip(
                      widget.showExhibitorCounts
                          ? 'Overall: $totalShowing/${totalExhibitors.length}'
                          : 'Overall: $totalShowing',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
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
            final exhibitors = _exhibitorsForSection(
              breed.exhibitorsBySection,
              sid,
            );
            return _summaryChip(
              widget.showExhibitorCounts
                  ? '${_sectionHeader(s)}: ${rabbits == 0 && exhibitors == 0 ? '-' : '$rabbits/$exhibitors'}'
                  : '${_sectionHeader(s)}: ${rabbits == 0 ? '-' : rabbits}',
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
            final exhibitors = _exhibitorsForSection(
              variety.exhibitorsBySection,
              sid,
            );
            return _summaryChip(
              widget.showExhibitorCounts
                  ? '${_sectionHeader(s)}: ${rabbits == 0 && exhibitors == 0 ? '-' : '$rabbits/$exhibitors'}'
                  : '${_sectionHeader(s)}: ${rabbits == 0 ? '-' : rabbits}',
            );
          }),
        ],
      ),
    );
  }

  Widget _countsLegendBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        widget.showExhibitorCounts
            ? 'All section counts are shown as Rabbit/Cavy / Exhibitors (R/E).'
            : 'All section counts are shown as entries currently showing.',
        style: const TextStyle(
          color: AppColors.headerForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _classTable(_VarietyGroup variety) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 46,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 54,
          columnSpacing: 18,
          headingRowColor: WidgetStatePropertyAll(
            AppColors.navy.withValues(alpha: 0.06),
          ),
          columns: [
            const DataColumn(
              label: Text(
                'Age / Sex Class',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ..._sections.map(
              (s) => DataColumn(
                label: Text(
                  widget.showExhibitorCounts
                      ? '${_sectionHeader(s)} (R/E)'
                      : '${_sectionHeader(s)} Showing',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const DataColumn(
              label: Text(
                'Rabbit/Cavy',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (widget.showExhibitorCounts)
              const DataColumn(
                label: Text(
                  'Exhibitors',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
          rows: variety.classes.map((c) {
            return DataRow(
              cells: [
                DataCell(Text(c.label)),
                ..._sections.map((s) {
                  final sid = s['id'].toString();
                  final rabbits = _countForSection(c.countsBySection, sid);
                  final exhibitors = _exhibitorsForSection(
                    c.exhibitorsBySection,
                    sid,
                  );
                  final text = widget.showExhibitorCounts
                      ? ((rabbits == 0 && exhibitors == 0)
                            ? '-'
                            : '$rabbits/$exhibitors')
                      : (rabbits == 0 ? '-' : rabbits.toString());
                  return DataCell(Text(text));
                }),
                DataCell(Text(c.rabbitCount.toString())),
                if (widget.showExhibitorCounts)
                  DataCell(Text(c.exhibitorCount.toString())),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_msg != null) {
      return Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _msg!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_sections.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: const Center(
          child: Text(
            'No enabled sections for this show.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (_breedGroups.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: const Center(
          child: Text(
            'No entries found for this show.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.page),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: AppTheme.gradientTextScope(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (widget.showExportButton) ...[
                        TextButton.icon(
                          onPressed: _exportCsv,
                          icon: const Icon(Icons.download),
                          label: const Text('CSV'),
                        ),
                        TextButton.icon(
                          onPressed: _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IconButton(
                        tooltip: 'Reload',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                if (AppSession.isSupportMode)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.support_agent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Support Mode — Viewing entry counts as an admin while viewing another user.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                _countsLegendBar(),
                _overallTotalsHeader(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _breedGroups.length,
                    itemBuilder: (context, index) {
                      final breed = _breedGroups[index];

                      return AppTheme.surfaceTextScope(
                        context,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              12,
                              0,
                              12,
                              12,
                            ),
                            title: Text(
                              breed.breed,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${breed.species.toUpperCase()} • ${breed.varieties.length} varieties',
                                ),
                                const SizedBox(height: 8),
                                _breedSummaryBar(breed),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (widget.showExhibitorCounts)
                                      _countChip(
                                        'Exhibitors',
                                        breed.exhibitorCount,
                                      ),
                                    _countChip('Showing', breed.rabbitCount),
                                  ],
                                ),
                              ],
                            ),
                            children: [
                              const SizedBox(height: 8),
                              ...breed.varieties.map((variety) {
                                return Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                    ),
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    title: Text(
                                      variety.variety,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${variety.classes.length} age/sex classes',
                                        ),
                                        const SizedBox(height: 8),
                                        _varietySummaryBar(variety),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            if (widget.showExhibitorCounts)
                                              _countChip(
                                                'Exhibitors',
                                                variety.exhibitorCount,
                                              ),
                                            _countChip(
                                              'Showing',
                                              variety.rabbitCount,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    children: [
                                      const SizedBox(height: 8),
                                      _classTable(variety),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
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
