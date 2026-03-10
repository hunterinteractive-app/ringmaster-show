// lib/screens/admin/admin_print_packs_screen.dart

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final supabase = Supabase.instance.client;

Future<String?> _savePdfToUserChosenLocation({
  required Uint8List bytes,
  required String suggestedName,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
      ),
    ],
  );

  if (location == null) return null;

  final file = XFile.fromData(
    bytes,
    mimeType: 'application/pdf',
    name: suggestedName,
  );

  await file.saveTo(location.path);
  return location.path;
}

class AdminPrintPacksScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminPrintPacksScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminPrintPacksScreen> createState() => _AdminPrintPacksScreenState();
}

class _AdminPrintPacksScreenState extends State<AdminPrintPacksScreen> {
  bool _loading = true;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  bool _includeScratched = false;
  bool _combineSections = true;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rows = await supabase
          .from('show_sections')
          .select('id,letter,display_name,kind,is_enabled,sort_order')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true)
          ;

      _sections = (rows as List).cast<Map<String, dynamic>>();

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

      if (_sections.isNotEmpty) {
        final currentStillExists = _sections.any(
          (s) => s['id']?.toString() == _selectedSectionId,
        );

        if (!currentStillExists) {
          _selectedSectionId = _sections.first['id']?.toString();
        }
      } else {
        _selectedSectionId = null;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Failed to load sections: $e';
      });
    }
  }

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().toLowerCase();
    final letter = (s['letter'] ?? '').toString().trim().toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = 'Section';
    }

    if (letter.isNotEmpty) return '$kindLabel $letter';
    return kindLabel;
  }

  Map<String, dynamic>? _selectedSection() {
    if (_selectedSectionId == null || _selectedSectionId!.isEmpty) return null;
    for (final s in _sections) {
      if (s['id']?.toString() == _selectedSectionId) return s;
    }
    return null;
  }

  void _openCheckInGenerator() {
    if (!_combineSections && (_selectedSectionId == null || _selectedSectionId!.isEmpty)) {
      setState(() {
        _msg = 'Please select a section for check-in sheets.';
      });
      return;
    }

    final section = _selectedSection();
    final sectionName = _combineSections
        ? 'All Shows (Open/Youth A/B/...)'
        : (section == null ? '' : _sectionLabel(section));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CheckInGeneratorSheet(
        showId: widget.showId,
        showName: widget.showName,
        sections: _sections,
        sectionId: _combineSections ? null : _selectedSectionId,
        sectionLabel: sectionName,
        includeScratched: _includeScratched,
        combineSections: _combineSections,
      ),
    );
  }

  void _openControlSheetsGeneratorForSection(Map<String, dynamic> section) {
    final sectionId = section['id']?.toString();
    final sectionName = _sectionLabel(section);

    if (sectionId == null || sectionId.isEmpty) {
      setState(() {
        _msg = 'That section is missing an ID.';
      });
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ControlSheetsGeneratorSheet(
        showId: widget.showId,
        showName: widget.showName,
        sections: _sections,
        sectionId: sectionId,
        sectionLabel: sectionName,
        includeScratched: _includeScratched,
        combineSections: false, // HARD CODED: never combined
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canOpenCheckIn = !_loading && (_combineSections || (_selectedSectionId != null && _selectedSectionId!.isNotEmpty));
    final hasSections = _sections.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Print Packs — ${widget.showName}'),
        actions: [
          IconButton(
            tooltip: 'Reload sections',
            onPressed: _loading ? null : _loadSections,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _msg!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                // =========================
                // CONTROL SHEETS
                // =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          leading: Icon(Icons.description),
                          title: Text('Control sheets'),
                          subtitle: Text('Generate judge control sheets (PDF)'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Control sheets are generated one show section at a time.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          value: _includeScratched,
                          onChanged: (v) => setState(() => _includeScratched = v),
                          title: const Text('Include scratched entries'),
                        ),
                        const SizedBox(height: 10),
                        if (!hasSections)
                          const Text(
                            'No enabled show sections found.',
                            style: TextStyle(color: Colors.red),
                          )
                        else
                          ..._sections.map(
                            (section) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => _openControlSheetsGeneratorForSection(section),
                                  icon: const Icon(Icons.download),
                                  label: Text('Download Control Sheets — ${_sectionLabel(section)}'),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // CHECK-IN SHEETS
                // =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          leading: Icon(Icons.checklist),
                          title: Text('Check-in sheets'),
                          subtitle: Text('Generate exhibitor check-in sheets (PDF)'),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          value: _combineSections,
                          onChanged: (v) {
                            setState(() {
                              _combineSections = v;
                              if (!v &&
                                  (_selectedSectionId == null || _selectedSectionId!.isEmpty) &&
                                  _sections.isNotEmpty) {
                                _selectedSectionId = _sections.first['id']?.toString();
                              }
                            });
                          },
                          title: const Text('Combine sections'),
                          subtitle: const Text('One sheet per exhibitor (covers Open/Youth A/B/...)'),
                        ),
                        const SizedBox(height: 8),
                        if (!_combineSections) ...[
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: (_selectedSectionId != null &&
                                    _sections.any((s) => s['id']?.toString() == _selectedSectionId))
                                ? _selectedSectionId
                                : null,
                            hint: const Text('Select a section'),
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
                            onChanged: _sections.isEmpty
                                ? null
                                : (v) {
                                    setState(() {
                                      _selectedSectionId = v;
                                    });
                                  },
                          ),
                          const SizedBox(height: 10),
                        ] else ...[
                          Text(
                            'Sections included: ${_sections.isEmpty ? '(none)' : _sections.map(_sectionLabel).join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                        ],
                        SwitchListTile(
                          value: _includeScratched,
                          onChanged: (v) => setState(() => _includeScratched = v),
                          title: const Text('Include scratched entries'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: canOpenCheckIn ? _openCheckInGenerator : null,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: Text(
                            _combineSections
                                ? 'Generate Check-In Sheets (Combined)'
                                : 'Generate Check-In Sheets',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const ListTile(
                  leading: Icon(Icons.sell),
                  title: Text('Coop tags'),
                  subtitle: Text('Optional (coming next)'),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.rate_review),
                  title: Text('Comment cards'),
                  subtitle: Text('Optional (coming next)'),
                ),
              ],
            ),
    );
  }
}

// =======================================================
// CONTROL SHEETS GENERATOR
// =======================================================

class _ControlSheetsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final String? sectionId;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;

  const _ControlSheetsGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
  });

  @override
  State<_ControlSheetsGeneratorSheet> createState() => _ControlSheetsGeneratorSheetState();
}

class _ControlSheetsGeneratorSheetState extends State<_ControlSheetsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  String _safe(Map<String, dynamic> e, String k) => (e[k] ?? '').toString().trim();

  String _ageOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final l = s.toLowerCase();
    if (l.contains('senior')) return 'Senior';
    if (l.contains('intermediate')) return 'Intermediate';
    if (l.contains('junior')) return 'Junior';
    return s;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    final rows = await supabase.rpc(
      'report_control_sheet_entries',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.combineSections ? null : widget.sectionId,
        'p_include_scratched': widget.includeScratched,
      },
    );

    return (rows as List).cast<Map<String, dynamic>>();
  }

  String _sectionTitleFromRow(Map<String, dynamic> row) {
    final label = _safe(row, 'section_label');
    if (label.isNotEmpty) return label;

    final kind = _safe(row, 'section_kind').toLowerCase();
    final letter = _safe(row, 'section_letter').toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = 'Section';
    }

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  String _colorLabel(Map<String, dynamic> row) {
    final groupName = _safe(row, 'group_name');
    final variety = _safe(row, 'variety');

    if (groupName.isNotEmpty && variety.isNotEmpty) return '$groupName / $variety';
    if (groupName.isNotEmpty) return groupName;
    return variety;
  }

  List<String> _specialsForRow(Map<String, dynamic> row) {
    final usesGroupAwards = row['uses_group_awards'] == true;
    final usesVarietyAwards = row['uses_variety_awards'] == true;

    final out = <String>[];

    if (usesVarietyAwards) {
      out.addAll([
        'BOV',
        'BOSV',
      ]);
    }

    if (usesGroupAwards) {
      out.addAll([
        'BOG',
        'BOSG',
      ]);
    }

    out.addAll([
      'BOB',
      'BOS',
    ]);

    return out;
  }

  pw.Document _buildPdf(List<Map<String, dynamic>> rows) {
    final doc = pw.Document();

    final bySection = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sid = _safe(row, 'section_id');
      bySection.putIfAbsent(sid, () => <Map<String, dynamic>>[]);
      bySection[sid]!.add(row);
    }

    final sectionRows = widget.combineSections
        ? bySection.entries.toList()
        : <MapEntry<String, List<Map<String, dynamic>>>>[
            MapEntry(widget.sectionId ?? '', rows),
          ];

    final allPages = <Map<String, dynamic>>[];

    for (final sectionEntry in sectionRows) {
      final sectionEntries = sectionEntry.value;
      if (sectionEntries.isEmpty) continue;

      final grouped = <String, List<Map<String, dynamic>>>{};

      for (final row in sectionEntries) {
        final breed = _safe(row, 'breed');
        final color = _colorLabel(row);
        final cls = _ageOnly(_safe(row, 'class_name'));
        final sex = _safe(row, 'sex');

        final key = [
          breed.toLowerCase(),
          color.toLowerCase(),
          cls.toLowerCase(),
          sex.toLowerCase(),
        ].join('|');

        grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]);
        grouped[key]!.add(row);
      }

      final keys = grouped.keys.toList()..sort();

      for (final key in keys) {
        final groupRows = grouped[key]!;
        if (groupRows.isEmpty) continue;

        final first = groupRows.first;
        final exhibitorIds = <String>{};
        for (final row in groupRows) {
          final exId = _safe(row, 'exhibitor_id');
          if (exId.isNotEmpty) exhibitorIds.add(exId);
        }

        allPages.add({
          'sectionTitle': widget.combineSections ? _sectionTitleFromRow(first) : widget.sectionLabel,
          'breed': _safe(first, 'breed'),
          'color': _colorLabel(first),
          'class': _ageOnly(_safe(first, 'class_name')),
          'sex': _safe(first, 'sex'),
          'rabbitCount': groupRows.length,
          'exhibitorCount': exhibitorIds.length,
          'rows': groupRows,
          'specials': _specialsForRow(first),
        });
      }
    }

    final totalPages = allPages.length;

    pw.Widget _topHeader({
      required String showHeader,
      required String pageText,
    }) {
      final titleStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
      final pageStyle = pw.TextStyle(fontSize: 10);

      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(showHeader, style: titleStyle, textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Judging Sheet - Breed Class',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, top: 2),
            child: pw.Text(pageText, style: pageStyle),
          ),
        ],
      );
    }

    pw.Widget _underlinedValue(String label, String value) {
      final textStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('$label: ', style: textStyle),
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(width: 0.8),
              ),
            ),
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(value, style: textStyle),
          ),
        ],
      );
    }

    pw.Widget _classHeaderBlock({
      required String breed,
      required String color,
      required String cls,
      required String sex,
      required int rabbitCount,
      required int exhibitorCount,
    }) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _underlinedValue('Breed', breed),
                    pw.SizedBox(height: 10),
                    _underlinedValue('Color', color),
                  ],
                ),
              ),
              pw.SizedBox(width: 18),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      _underlinedValue('Class', cls),
                      pw.SizedBox(width: 20),
                      _underlinedValue('Sex', sex),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    children: [
                      _underlinedValue('No. in Class', rabbitCount.toString()),
                      pw.SizedBox(width: 20),
                      _underlinedValue('No. Exhibitors', exhibitorCount.toString()),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    pw.Widget _judgingTable({
      required List<Map<String, dynamic>> groupEntries,
      required List<String> specialsList,
    }) {
      final h = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
      final c = pw.TextStyle(fontSize: 9);
      final specialsText = specialsList.join(', ');

      return pw.Table(
        border: pw.TableBorder.all(width: 0.8),
        columnWidths: {
          0: const pw.FixedColumnWidth(80),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FixedColumnWidth(150),
          3: const pw.FixedColumnWidth(140),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Ear #', style: h),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Exhibitor', style: h),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Place / DQ', style: h),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Specials', style: h),
              ),
            ],
          ),
          ...groupEntries.map((row) {
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(_safe(row, 'tattoo'), style: c),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('', style: c),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    specialsText,
                    style: c,
                  ),
                ),
              ],
            );
          }),
        ],
      );
    }

    for (var i = 0; i < allPages.length; i++) {
      final p = allPages[i];

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
          build: (_) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _topHeader(
                  showHeader: '${widget.showName}   ${(p['sectionTitle'] ?? '').toString()}',
                  pageText: 'Page ${i + 1} of $totalPages',
                ),
                pw.SizedBox(height: 18),
                _classHeaderBlock(
                  breed: (p['breed'] ?? '').toString(),
                  color: (p['color'] ?? '').toString(),
                  cls: (p['class'] ?? '').toString(),
                  sex: (p['sex'] ?? '').toString(),
                  rabbitCount: (p['rabbitCount'] as int?) ?? 0,
                  exhibitorCount: (p['exhibitorCount'] as int?) ?? 0,
                ),
                pw.SizedBox(height: 14),
                _judgingTable(
                  groupEntries: (p['rows'] as List).cast<Map<String, dynamic>>(),
                  specialsList: (p['specials'] as List).map((x) => x.toString()).toList(),
                ),
              ],
            );
          },
        ),
      );
    }

    return doc;
  }

  Future<void> _generatePdf() async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      final rows = await _fetchEntries();

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this selection.';
        });
        return;
      }

      final doc = _buildPdf(rows);
      final bytes = await doc.save();

      final name = widget.combineSections
          ? 'control_${widget.showName}_ALL_SECTIONS.pdf'
          : 'control_${widget.showName}_${widget.sectionLabel}.pdf';

      final savedPath = await _savePdfToUserChosenLocation(
        bytes: Uint8List.fromList(bytes),
        suggestedName: name,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = savedPath == null ? 'Save canceled.' : 'PDF saved to: $savedPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = 'PDF build failed: $e';
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
            Text('Generate Control Sheets', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              '${widget.showName} • ${widget.sectionLabel}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.includeScratched ? 'Including scratched entries' : 'Excluding scratched entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.combineSections ? 'Mode: Combined (pages grouped by class)' : 'Mode: Single section',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_msg != null) ...[
              Text(
                _msg!,
                style: TextStyle(
                  color: _msg == 'Save canceled.' || _msg!.startsWith('PDF saved to:')
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: _building ? null : _generatePdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building PDF…' : 'Generate PDF'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _building ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// CHECK-IN GENERATOR
// =======================================================

class _CheckInGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final String? sectionId;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;

  const _CheckInGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
  });

  @override
  State<_CheckInGeneratorSheet> createState() => _CheckInGeneratorSheetState();
}

class _CheckInGeneratorSheetState extends State<_CheckInGeneratorSheet> {
  bool _building = false;
  String? _msg;
  Map<String, dynamic>? _showRow;

  Future<void> _loadShowContact() async {
    final row = await supabase
        .from('shows')
        .select('id, secretary_name, secretary_phone, secretary_email')
        .eq('id', widget.showId)
        .single();

    _showRow = row as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    final rows = await supabase.rpc(
      'report_checkin_entries',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.combineSections ? null : widget.sectionId,
        'p_include_scratched': widget.includeScratched,
      },
    );

    return (rows as List).cast<Map<String, dynamic>>();
  }

  String _safe(Map<String, dynamic> e, String k) => (e[k] ?? '').toString().trim();

  String _displayAgeClassOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.contains('senior')) return 'Senior';
    if (lower.contains('intermediate')) return 'Intermediate';
    if (lower.contains('junior')) return 'Junior';
    return s;
  }

  String _exhibitorNameFromEntry(Map<String, dynamic> entry) {
    final dn = _safe(entry, 'exhibitor_label');
    return dn.isEmpty ? '(Unknown Exhibitor)' : dn;
  }

  String _groupVarietyLabel(Map<String, dynamic> row) {
    final groupName = _safe(row, 'group_name');
    final variety = _safe(row, 'variety');

    if (groupName.isNotEmpty && variety.isNotEmpty) return '$groupName / $variety';
    if (groupName.isNotEmpty) return groupName;
    return variety;
  }

  Map<String, List<Map<String, dynamic>>> _groupByExhibitor(List<Map<String, dynamic>> entries) {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final e in entries) {
      final exId = (e['exhibitor_id'] ?? '').toString();
      final key = exId.isEmpty ? '_unknown' : exId;
      map.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      map[key]!.add(e);
    }

    for (final k in map.keys) {
      map[k]!.sort((a, b) {
        final at = _safe(a, 'tattoo').toLowerCase();
        final bt = _safe(b, 'tattoo').toLowerCase();
        final c1 = at.compareTo(bt);
        if (c1 != 0) return c1;

        final breedCmp = _safe(a, 'breed').toLowerCase().compareTo(_safe(b, 'breed').toLowerCase());
        if (breedCmp != 0) return breedCmp;

        return _groupVarietyLabel(a).toLowerCase().compareTo(_groupVarietyLabel(b).toLowerCase());
      });
    }

    return map;
  }

  bool _isMultiSection(List<Map<String, dynamic>> exEntries) {
    final set = <String>{};
    for (final e in exEntries) {
      set.add((e['section_id'] ?? '').toString());
    }
    return set.length > 1;
  }

  Map<String, List<Map<String, dynamic>>> _groupEntriesBySection(List<Map<String, dynamic>> exEntries) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in exEntries) {
      final sid = (e['section_id'] ?? '').toString();
      map.putIfAbsent(sid, () => <Map<String, dynamic>>[]);
      map[sid]!.add(e);
    }
    return map;
  }

  List<Map<String, dynamic>> _sortedSectionsForExhibitor(List<Map<String, dynamic>> exEntries) {
    final map = <String, Map<String, dynamic>>{};
    for (final e in exEntries) {
      final sid = (e['section_id'] ?? '').toString();
      map[sid] = {
        'id': sid,
        'display_name': (e['section_label'] ?? '').toString(),
        'kind': (e['section_kind'] ?? '').toString(),
        'letter': (e['section_letter'] ?? '').toString(),
        'sort_order': e['section_sort_order'],
      };
    }

    final list = map.values.toList();

    list.sort((a, b) {
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

    return list;
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

  pw.Document _buildPdf({
    required List<Map<String, dynamic>> entries,
  }) {
    final doc = pw.Document();

    final grouped = _groupByExhibitor(entries);
    final exhibitorKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aList = grouped[a]!;
        final bList = grouped[b]!;
        final aName = aList.isEmpty ? '' : _exhibitorNameFromEntry(aList.first).toLowerCase();
        final bName = bList.isEmpty ? '' : _exhibitorNameFromEntry(bList.first).toLowerCase();
        return aName.compareTo(bName);
      });

    final totalPages = exhibitorKeys.length;

    pw.Widget _grayBar({required String left, required String right}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey300,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(width: 0.8),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(left, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(right, style: pw.TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget _balanceBox({required String allShows, required String thisShow}) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Balance Due',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('All Shows: $allShows', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('This Show: $thisShow', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
    }

    pw.Widget _infoBlockLeft(Map<String, dynamic> ex) {
      final a1 = _safe(ex, 'address_line1');
      final a2 = _safe(ex, 'address_line2');
      final city = _safe(ex, 'city');
      final st = _safe(ex, 'state');
      final zip = _safe(ex, 'zip');
      final phone = _safe(ex, 'phone');
      final email = _safe(ex, 'email');

      final lines = <String>[
        if (a1.isNotEmpty) a1,
        if (a2.isNotEmpty) a2,
        if (city.isNotEmpty || st.isNotEmpty || zip.isNotEmpty)
          '${city.isEmpty ? '' : city}${city.isNotEmpty && st.isNotEmpty ? ', ' : ''}${st.isEmpty ? '' : st} ${zip.isEmpty ? '' : zip}'.trim(),
        if (phone.isNotEmpty) 'Phone: $phone',
        if (email.isNotEmpty) 'Email: $email',
      ];

      if (lines.isEmpty) {
        return pw.Text('(No address/contact on file)', style: pw.TextStyle(fontSize: 9));
      }

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines.map((x) => pw.Text(x, style: pw.TextStyle(fontSize: 9))).toList(),
      );
    }

    pw.Widget _infoBlockRight() {
      String s2(Map<String, dynamic>? m, String k) => (m == null) ? '' : (m[k] ?? '').toString().trim();

      final name = s2(_showRow, 'secretary_name');
      final phone = s2(_showRow, 'secretary_phone');
      final email = s2(_showRow, 'secretary_email');

      final lines = <pw.Widget>[
        pw.Text('Show Secretary:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ];

      if (name.isNotEmpty) lines.add(pw.Text(name, style: pw.TextStyle(fontSize: 9)));
      if (phone.isNotEmpty) lines.add(pw.Text(phone, style: pw.TextStyle(fontSize: 9)));
      if (email.isNotEmpty) lines.add(pw.Text(email, style: pw.TextStyle(fontSize: 9)));

      if (lines.length == 1) {
        lines.add(pw.Text('(Not set for this show)', style: pw.TextStyle(fontSize: 9)));
      }

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines,
      );
    }

    pw.Widget _instructions() {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '»  If there are any problems with your entry as shown below please see the show secretary.',
              style: pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '    No corrections or changes can be made at the judging table or after the show starts.',
              style: pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '»  Fur column: B = entered in breed fur, C = entered in commercial fur.',
              style: pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '»  A ? in any column indicates the correct information is not known.',
              style: pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );
    }

    pw.Widget _entriesTable(List<Map<String, dynamic>> exEntries) {
      final h = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
      final c = pw.TextStyle(fontSize: 10);

      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          columnWidths: {
            0: const pw.FixedColumnWidth(60),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FixedColumnWidth(110),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FixedColumnWidth(70),
            5: const pw.FixedColumnWidth(50),
            6: const pw.FixedColumnWidth(40),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Ear #', style: h)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Coop #', style: h)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Breed', style: h)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Group / Variety', style: h)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Class', style: h)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sex', style: h)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Fur', style: h)),
              ],
            ),
            ...exEntries.map((e) {
              final scratchedAt = _safe(e, 'scratched_at');
              final isScratched = scratchedAt.isNotEmpty;

              final style = isScratched
                  ? pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                      decoration: pw.TextDecoration.lineThrough,
                    )
                  : c;

              final ageClass = _displayAgeClassOnly(_safe(e, 'class_name'));

              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_safe(e, 'tattoo'), style: style)),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('', style: style)),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_safe(e, 'breed'), style: style)),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_groupVarietyLabel(e), style: style),
                  ),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(ageClass, style: style)),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_safe(e, 'sex'), style: style)),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('', style: style)),
                ],
              );
            }),
          ],
        ),
      );
    }

    for (var i = 0; i < exhibitorKeys.length; i++) {
      final exKey = exhibitorKeys[i];
      final exEntries = grouped[exKey]!;
      if (exEntries.isEmpty) continue;

      final exMap = exEntries.first;
      final exName = _exhibitorNameFromEntry(exMap);
      final numberEntered = exEntries.length;
      const allShows = r'$—';
      const thisShow = r'$—';
      final multi = _isMultiSection(exEntries);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
          build: (_) {
            final widgets = <pw.Widget>[];

            widgets.add(
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(widget.showName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text(widget.sectionLabel, style: pw.TextStyle(fontSize: 12)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Exhibitor Check-In Sheet',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.Text('Page ${i + 1} of $totalPages', style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              pw.Row(
                children: [
                  pw.Spacer(),
                  _balanceBox(allShows: allShows, thisShow: thisShow),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              _grayBar(
                left: exName,
                right: 'Number Entered  $numberEntered',
              ),
            );

            widgets.add(pw.SizedBox(height: 6));
            widgets.add(
              pw.Row(
                children: [
                  pw.Text(
                    '${multi ? '☑' : '☐'} Entered in multiple shows',
                    style: pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: _infoBlockLeft(exMap)),
                  pw.SizedBox(width: 24),
                  pw.Container(width: 190, child: _infoBlockRight()),
                ],
              ),
            );

            widgets.add(_instructions());

            if (widget.combineSections) {
              final bySection = _groupEntriesBySection(exEntries);
              final sList = _sortedSectionsForExhibitor(exEntries);

              for (final s in sList) {
                final sid = (s['id'] ?? '').toString();
                final blockEntries = bySection[sid] ?? const <Map<String, dynamic>>[];
                if (blockEntries.isEmpty) continue;

                widgets.add(pw.SizedBox(height: 10));
                widgets.add(
                  pw.Text(
                    _sectionHeader(s),
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                );
                widgets.add(pw.SizedBox(height: 4));
                widgets.add(_entriesTable(blockEntries));
              }
            } else {
              widgets.add(_entriesTable(exEntries));
            }

            widgets.add(pw.SizedBox(height: 12));
            widgets.add(
              pw.Row(
                children: [
                  pw.Text('RingMaster Show', style: pw.TextStyle(fontSize: 9)),
                  pw.Spacer(),
                  pw.Text('${DateTime.now().toLocal()}', style: pw.TextStyle(fontSize: 9)),
                ],
              ),
            );

            return widgets;
          },
        ),
      );
    }

    return doc;
  }

  Future<void> _generatePdf() async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      await _loadShowContact();

      final entries = await _fetchEntries();

      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this selection.';
        });
        return;
      }

      final doc = _buildPdf(entries: entries);
      final bytes = await doc.save();

      final name = widget.combineSections
          ? 'check_in_${widget.showName}_ALL_SECTIONS.pdf'
          : 'check_in_${widget.showName}_${widget.sectionLabel}.pdf';

      final savedPath = await _savePdfToUserChosenLocation(
        bytes: Uint8List.fromList(bytes),
        suggestedName: name,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = savedPath == null ? 'Save canceled.' : 'PDF saved to: $savedPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = 'PDF build failed: $e';
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
            Text('Generate Check-In Sheets', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              '${widget.showName} • ${widget.sectionLabel}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.includeScratched ? 'Including scratched entries' : 'Excluding scratched entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.combineSections ? 'Mode: Combined (one sheet per exhibitor)' : 'Mode: Single section',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_msg != null) ...[
              Text(
                _msg!,
                style: TextStyle(
                  color: _msg == 'Save canceled.' || _msg!.startsWith('PDF saved to:')
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: _building ? null : _generatePdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building PDF…' : 'Generate PDF'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _building ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}