// lib/screens/admin/print_packs/remark_cards_generator_sheet.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_pack_pdf_helpers.dart';

final supabase = Supabase.instance.client;

class RemarkCardsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final bool includeScratched;

  const RemarkCardsGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.includeScratched,
  });

  @override
  State<RemarkCardsGeneratorSheet> createState() =>
      _RemarkCardsGeneratorSheetState();
}

class _RemarkCardsGeneratorSheetState extends State<RemarkCardsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  String? _selectedSectionId;
  bool _useCoopNumberInsteadOfName = false;

  @override
  void initState() {
    super.initState();
    if (widget.sections.isNotEmpty) {
      _selectedSectionId = widget.sections.first['id']?.toString();
    }
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().toLowerCase();
    final letter = (s['letter'] ?? '').toString().trim().toUpperCase();

    final kindLabel = switch (kind) {
      'open' => 'Open',
      'youth' => 'Youth',
      _ => 'Section',
    };

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  String _groupVarietyLabel(Map<String, dynamic> row) {
    final groupName = _safe(row, 'group_name');
    final variety = _safe(row, 'variety');

    if (groupName.isNotEmpty && variety.isNotEmpty) {
      return '$groupName / $variety';
    }
    if (groupName.isNotEmpty) return groupName;
    return variety;
  }

  String _displayClass(Map<String, dynamic> row) {
    final raw = _safe(row, 'class_name');
    final lower = raw.toLowerCase();

    if (lower.contains('pre')) return 'Pre Jr.';
    if (lower.contains('senior')) return 'Sr.';
    if (lower.contains('intermediate')) return '6/8';
    if (lower.contains('junior')) return 'Jr.';
    if (lower.contains('fryer')) return 'Fryer';
    if (lower.contains('meat')) return 'Meat Pen';
    if (lower.contains('fur')) return 'Fur';
    if (lower.contains('wool')) return 'Fur';

    return raw;
  }

  String _displaySex(Map<String, dynamic> row) {
    final sex = _safe(row, 'sex').toLowerCase();
    if (sex.startsWith('buck')) return 'Buck';
    if (sex.startsWith('doe')) return 'Doe';
    return _safe(row, 'sex');
  }

  String _exhibitorDisplay(Map<String, dynamic> row) {
    final coop = _safe(row, 'coop_number');
    final exhibitor = _safe(row, 'exhibitor_label');

    if (_useCoopNumberInsteadOfName) {
      return coop.isEmpty ? 'Coop No.' : 'Coop No. $coop';
    }

    return exhibitor;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    const pageSize = 1000;
    final out = <Map<String, dynamic>>[];

    for (var from = 0;; from += pageSize) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc(
            'report_checkin_entries',
            params: {
              'p_show_id': widget.showId,
              'p_section_id': _selectedSectionId,
              'p_include_scratched': widget.includeScratched,
            },
          )
          .range(from, to);

      final page = (rows as List).cast<Map<String, dynamic>>();
      out.addAll(page);

      if (page.length < pageSize) break;
    }

    int toInt(dynamic value, [int fallback = 9999]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    int cmpText(String ak, String bk) =>
        ak.toLowerCase().compareTo(bk.toLowerCase());

    out.sort((a, b) {
      final sectionSortCmp = toInt(a['section_sort_order'])
          .compareTo(toInt(b['section_sort_order']));
      if (sectionSortCmp != 0) return sectionSortCmp;

      final sectionLetterCmp = cmpText(
        _safe(a, 'section_letter'),
        _safe(b, 'section_letter'),
      );
      if (sectionLetterCmp != 0) return sectionLetterCmp;

      final breedSortCmp = toInt(a['breed_sort_order'])
          .compareTo(toInt(b['breed_sort_order']));
      if (breedSortCmp != 0) return breedSortCmp;

      final breedCmp = cmpText(_safe(a, 'breed'), _safe(b, 'breed'));
      if (breedCmp != 0) return breedCmp;

      final groupSortCmp = toInt(a['group_sort_order'])
          .compareTo(toInt(b['group_sort_order']));
      if (groupSortCmp != 0) return groupSortCmp;

      final varietySortCmp = toInt(a['variety_sort_order'])
          .compareTo(toInt(b['variety_sort_order']));
      if (varietySortCmp != 0) return varietySortCmp;

      final varietyCmp = cmpText(_groupVarietyLabel(a), _groupVarietyLabel(b));
      if (varietyCmp != 0) return varietyCmp;

      final classSortCmp = toInt(a['class_sort_order'])
          .compareTo(toInt(b['class_sort_order']));
      if (classSortCmp != 0) return classSortCmp;

      final classCmp = cmpText(_safe(a, 'class_name'), _safe(b, 'class_name'));
      if (classCmp != 0) return classCmp;

      final sexSortCmp = toInt(a['sex_sort_order'])
          .compareTo(toInt(b['sex_sort_order']));
      if (sexSortCmp != 0) return sexSortCmp;

      final sexCmp = cmpText(_safe(a, 'sex'), _safe(b, 'sex'));
      if (sexCmp != 0) return sexCmp;

      final coopCmp = cmpText(_safe(a, 'coop_number'), _safe(b, 'coop_number'));
      if (coopCmp != 0) return coopCmp;

      return cmpText(_safe(a, 'tattoo'), _safe(b, 'tattoo'));
    });

    return out;
  }

  pw.Widget _lineField({
    required String label,
    required String value,
    double labelSize = 8,
    double valueSize = 8,
    double height = 16,
    double? width,
  }) {
    return pw.Container(
      width: width,
      height: height,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: labelSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(left: 2, bottom: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: .7),
                ),
              ),
              child: pw.Text(
                value,
                maxLines: 1,
                style: pw.TextStyle(fontSize: valueSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _checkRow(List<String> labels, String selected) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: labels.map((label) {
        final isSelected = selected.toLowerCase() == label.toLowerCase();
        return pw.Text(
          isSelected ? '[$label]' : label,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: isSelected ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _scoreGrid(List<String> rows, {bool fourCols = true}) {
    final headers = fourCols ? ['VG', 'G', 'F', 'P'] : ['VG', 'G', 'F'];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 72,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 12),
              ...rows.map(
                (r) => pw.Container(
                  height: 15,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    r,
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Row(
                children: headers
                    .map(
                      (h) => pw.Expanded(
                        child: pw.Center(
                          child: pw.Text(
                            h,
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              pw.Table(
                border: pw.TableBorder.all(width: .55),
                children: rows
                    .map(
                      (_) => pw.TableRow(
                        children: headers
                            .map(
                              (_) => pw.Container(height: 15),
                            )
                            .toList(),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _remarkCard(Map<String, dynamic> row) {
    final sex = _displaySex(row);
    final cls = _displayClass(row);

    final leftRows = [
      'Head',
      'Ears',
      'Crown',
      'Bone',
      'Type',
      'Shoulders',
      'Midsection',
      'Hindquarters',
      'Fur/Wool',
      'Sheen',
      'Density',
      'Texture',
      'Color',
    ];

    final rightRows = [
      'Condition',
      'Butterfly',
      'Eye Circles',
      'Cheek Spots',
      'Ear Base',
      'Side Markings',
      'Spine/Herringbone',
      'Blaze',
      'Cheeks',
      'Neck',
      'Saddle',
      'Undercut',
      'Stops',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: .8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'RABBIT SHOW REMARK CARD',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'American Rabbit Breeders Association, Inc.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 7),

          pw.Row(
            children: [
              pw.Expanded(
                child: _lineField(label: 'Ear No.', value: _safe(row, 'tattoo')),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(
                  label: 'Coop No.',
                  value: _safe(row, 'coop_number'),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(
                  label: 'Entry No.',
                  value: _safe(row, 'entry_number'),
                ),
              ),
            ],
          ),

          _lineField(label: 'Exhibitor', value: _exhibitorDisplay(row)),
          _lineField(label: 'Address', value: _safe(row, 'exhibitor_address_line1')),

          pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: _lineField(label: 'Show', value: widget.showName),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                flex: 2,
                child: _lineField(label: 'Date', value: ''),
              ),
            ],
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: _lineField(label: 'Breed', value: _safe(row, 'breed')),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(
                  label: 'Variety',
                  value: _groupVarietyLabel(row),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 5),
          _checkRow(
            ['Buck', 'Doe', 'Sr.', '6/8', 'Jr.', 'Pre Jr.', 'Fryer', 'Meat Pen', 'Fur'],
            sex.isNotEmpty ? sex : cls,
          ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 3, bottom: 5),
            height: .8,
            color: PdfColors.black,
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: _lineField(label: 'No. in Class', value: ''),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(label: 'Award', value: ''),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(label: 'No. Exhibitors', value: ''),
              ),
            ],
          ),

          pw.SizedBox(height: 4),
          _checkRow(['B.O.B.', 'B.O.S.', 'B.O.G.', 'B.O.S.G.', 'B.O.V.', 'B.O.S.V.'], ''),
          pw.SizedBox(height: 4),
          _checkRow(['Best Sr.', 'Best 6/8', 'Best Jr.', 'Best Pre-Jr.'], ''),

          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _scoreGrid(leftRows, fourCols: true)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _scoreGrid(rightRows, fourCols: false)),
            ],
          ),

          pw.SizedBox(height: 5),
          _lineField(label: 'Remarks', value: '', height: 15),
          _lineField(label: '', value: '', height: 13),
          _lineField(label: 'Judge', value: '', height: 15),
        ],
      ),
    );
  }

  pw.Document _buildPdf({
    required List<Map<String, dynamic>> entries,
    required pw.ThemeData theme,
  }) {
    final doc = pw.Document(theme: theme);

    for (var i = 0; i < entries.length; i += 2) {
      final first = entries[i];
      final second = i + 1 < entries.length ? entries[i + 1] : null;

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(20, 20, 20, 20),
          build: (_) {
            return [
              pw.Column(
              children: [
                pw.Expanded(child: _remarkCard(first)),
                pw.SizedBox(height: 14),
                pw.Expanded(
                  child: second == null
                      ? pw.Container()
                      : _remarkCard(second),
                ),
              ],
            ),
            ];
          },
        )
      );
    }

    return doc;
  }

  Future<void> _generatePdf() async {
    if (_building) return;

    if (_selectedSectionId == null || _selectedSectionId!.isEmpty) {
      setState(() => _msg = 'Please select a section.');
      return;
    }

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      final entries = await _fetchEntries();

      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this section.';
        });
        return;
      }

      final theme = await buildPrintPackPdfTheme();
      final doc = _buildPdf(entries: entries, theme: theme);
      final bytes = await doc.save();

      final section = widget.sections.firstWhere(
        (s) => s['id']?.toString() == _selectedSectionId,
        orElse: () => <String, dynamic>{},
      );

      final sectionName =
          section.isEmpty ? 'SECTION' : _sectionLabel(section);

      final name = 'remark_cards_${widget.showName}_$sectionName.pdf';

      final savedPath = await savePdfToUserChosenLocation(
        bytes: Uint8List.fromList(bytes),
        suggestedName: name,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = savedPath == null
            ? 'Save canceled.'
            : 'PDF saved to: $savedPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = 'Remark card PDF failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isSuccess = _msg != null &&
        (_msg == 'Save canceled.' || _msg!.startsWith('PDF saved to:'));

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
              'Generate Remark Cards',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.showName} • 2 cards per letter-size sheet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              isExpanded: true,
              value: (_selectedSectionId != null &&
                      widget.sections.any(
                        (s) => s['id']?.toString() == _selectedSectionId,
                      ))
                  ? _selectedSectionId
                  : null,
              hint: const Text('Select a section'),
              decoration: const InputDecoration(
                labelText: 'Show Letter / Section',
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
              onChanged: widget.sections.isEmpty
                  ? null
                  : (v) => setState(() => _selectedSectionId = v),
            ),

            const SizedBox(height: 8),

            SwitchListTile(
              value: _useCoopNumberInsteadOfName,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) =>
                  setState(() => _useCoopNumberInsteadOfName = v),
              title: const Text('Use coop numbers instead of exhibitor names'),
              subtitle: const Text(
                'Keeps exhibitor data saved, but hides names on printed cards.',
              ),
            ),

            const SizedBox(height: 6),

            Text(
              widget.includeScratched
                  ? 'Including scratched entries'
                  : 'Excluding scratched entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 12),

            if (_msg != null) ...[
              Container(
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
              const SizedBox(height: 10),
            ],

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _building ? null : _generatePdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building PDF…' : 'Generate PDF'),
            ),

            const SizedBox(height: 8),

            OutlinedButton(
              onPressed: _building ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
