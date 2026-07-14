import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/pdf/report_pdf_theme.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/check_in_sheet_report_data.dart';

class CheckInSheetReportPdfBuilder {
  CheckInSheetReportPdfBuilder({required this.assets});

  final ReportAssetLoader assets;

  Future<ReportFileResult> buildFile(
    CheckInSheetReportData data,
    ReportRequest request,
  ) async {
    final theme = await buildReportPdfTheme(assets);
    final doc = pw.Document(theme: theme);
    final entries = data.entries;

    if (entries.isEmpty) {
      throw StateError('No check-in entries found.');
    }

    final exhibitorName = _exhibitorName(entries.first);
    final exhibitorNumber = _exhibitorNumber(entries.first);
    final exhibitorLabel = exhibitorNumber.isEmpty
        ? exhibitorName
        : '$exhibitorName    Exhibitor #: $exhibitorNumber';
    final balanceDue = _checkInBalanceDue(entries);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      data.showName,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      data.sectionLabel,
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Exhibitor Check-In Sheet',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Text('Page 1 of 1', style: pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 8),
          _grayBar(
            left: exhibitorLabel,
            right: 'Number Entered  ${entries.length}',
            trailing: 'Balance Due: $balanceDue',
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _exhibitorContact(entries.first)),
              pw.SizedBox(width: 24),
              pw.Container(width: 190, child: _showSecretary(data.showContact)),
            ],
          ),
          _instructions(),
          ..._entrySections(entries),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Text('RingMaster One Show', style: pw.TextStyle(fontSize: 9)),
              pw.Spacer(),
              pw.Text(
                DateTime.now().toLocal().toString(),
                style: pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final fileName =
        'check_in_${_safeFileName(data.showName)}_${_safeFileName(exhibitorName)}.pdf';

    return ReportFileResult(
      fileName: fileName,
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  List<pw.Widget> _entrySections(List<Map<String, dynamic>> entries) {
    final bySection = <String, List<Map<String, dynamic>>>{};
    for (final entry in entries) {
      final key = [
        _safe(entry, 'section_kind'),
        _safe(entry, 'section_letter'),
        _safe(entry, 'section_display_name'),
      ].join('|');
      bySection.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(entry);
    }

    return bySection.entries.expand((entry) {
      final rows = entry.value;
      final first = rows.first;
      return <pw.Widget>[
        pw.SizedBox(height: 10),
        pw.Text(
          _sectionHeader(first),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        _entriesTable(rows),
      ];
    }).toList();
  }

  pw.Widget _grayBar({
    required String left,
    required String right,
    required String trailing,
  }) {
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
            flex: 2,
            child: pw.Text(
              left,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(right, style: pw.TextStyle(fontSize: 11)),
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Text(
            trailing,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _exhibitorContact(Map<String, dynamic> entry) {
    final city = _safe(entry, 'exhibitor_city');
    final state = _safe(entry, 'exhibitor_state');
    final zip = _safe(entry, 'exhibitor_zip');
    final lines = <String>[
      if (_safe(entry, 'exhibitor_address_line1').isNotEmpty)
        _safe(entry, 'exhibitor_address_line1'),
      if (_safe(entry, 'exhibitor_address_line2').isNotEmpty)
        _safe(entry, 'exhibitor_address_line2'),
      if (city.isNotEmpty || state.isNotEmpty || zip.isNotEmpty)
        '${city.isEmpty ? '' : city}${city.isNotEmpty && state.isNotEmpty ? ', ' : ''}${state.isEmpty ? '' : state} ${zip.isEmpty ? '' : zip}'
            .trim(),
      if (_safe(entry, 'exhibitor_phone').isNotEmpty)
        'Phone: ${_safe(entry, 'exhibitor_phone')}',
      if (_safe(entry, 'exhibitor_email').isNotEmpty)
        'Email: ${_safe(entry, 'exhibitor_email')}',
    ];

    if (lines.isEmpty) {
      return pw.Text(
        '(No address/contact on file)',
        style: pw.TextStyle(fontSize: 9),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: lines
          .map((line) => pw.Text(line, style: pw.TextStyle(fontSize: 9)))
          .toList(),
    );
  }

  pw.Widget _showSecretary(Map<String, dynamic> showContact) {
    final lines = <pw.Widget>[
      pw.Text(
        'Show Secretary:',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ];

    final name = _safe(showContact, 'secretary_name');
    final phone = _safe(showContact, 'secretary_phone');
    final email = _safe(showContact, 'secretary_email');

    if (name.isNotEmpty) {
      lines.add(pw.Text(name, style: pw.TextStyle(fontSize: 9)));
    }
    if (phone.isNotEmpty) {
      lines.add(pw.Text('Phone: $phone', style: pw.TextStyle(fontSize: 9)));
    }
    if (email.isNotEmpty) {
      lines.add(pw.Text('Email: $email', style: pw.TextStyle(fontSize: 9)));
    }
    if (lines.length == 1) {
      lines.add(
        pw.Text('(Not set for this show)', style: pw.TextStyle(fontSize: 9)),
      );
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
            '»  Fur column: X = entered in fur.',
            style: pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _entriesTable(List<Map<String, dynamic>> entries) {
    final header = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
    final cell = pw.TextStyle(fontSize: 10);

    return pw.Table(
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
            _tableCell('Ear #', header),
            _tableCell('Coop #', header),
            _tableCell('Breed', header),
            _tableCell('Group / Variety', header),
            _tableCell('Class', header),
            _tableCell('Sex', header),
            _tableCell('Fur', header),
          ],
        ),
        ...entries.map((entry) {
          final className = _safe(entry, 'class_name');
          final classNameLower = className.toLowerCase();
          final furMark =
              _truthy(entry['is_fur']) ||
                  classNameLower.contains('fur') ||
                  classNameLower.contains('wool')
              ? 'X'
              : '';

          return pw.TableRow(
            children: [
              _tableCell(_safe(entry, 'tattoo'), cell),
              _tableCell(_safe(entry, 'coop_number'), cell),
              _tableCell(_safe(entry, 'breed'), cell),
              _tableCell(_groupVarietyLabel(entry), cell),
              _tableCell(_displayAgeClassOnly(className), cell),
              _tableCell(_safe(entry, 'sex'), cell),
              _tableCell(furMark, cell),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _tableCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: style),
    );
  }

  String _sectionHeader(Map<String, dynamic> entry) {
    final display = _safe(entry, 'section_display_name');
    if (display.isNotEmpty) return display;

    final kind = _safe(entry, 'section_kind').toLowerCase();
    final letter = _safe(entry, 'section_letter').toUpperCase();
    final kindLabel = switch (kind) {
      'open' => 'Open',
      'youth' => 'Youth',
      _ =>
        kind.isEmpty
            ? 'Section'
            : '${kind[0].toUpperCase()}${kind.substring(1)}',
    };

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  String _checkInBalanceDue(List<Map<String, dynamic>> entries) {
    const centKeys = [
      'balance_due_all_shows_cents',
      'all_shows_balance_due_cents',
      'total_balance_due_cents',
      'exhibitor_balance_due_cents',
      'balance_due_cents',
      'balance_due_this_show_cents',
    ];
    for (final key in centKeys) {
      for (final entry in entries) {
        final value = entry[key];
        if (_hasValue(value)) return _moneyFromCents(value);
      }
    }

    const dollarKeys = [
      'balance_due_all_shows',
      'all_shows_balance_due',
      'total_balance_due',
      'exhibitor_balance_due',
      'balance_due_this_show',
      'this_show_balance_due',
    ];
    for (final key in dollarKeys) {
      for (final entry in entries) {
        final value = entry[key];
        if (_hasValue(value)) return _money(value);
      }
    }

    return r'$—';
  }

  String _exhibitorName(Map<String, dynamic> entry) {
    final label = _safe(entry, 'exhibitor_label');
    return label.isEmpty ? 'Exhibitor' : label;
  }

  String _exhibitorNumber(Map<String, dynamic> entry) {
    const keys = [
      'exhibitor_number',
      'show_exhibitor_number',
      'show_exhibitor_no',
      'exhibitor_no',
      'entry_exhibitor_number',
    ];
    for (final key in keys) {
      final value = _safe(entry, key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _groupVarietyLabel(Map<String, dynamic> entry) {
    final group = _safe(entry, 'group_name');
    final variety = _safe(entry, 'variety');
    if (group.isNotEmpty && variety.isNotEmpty) return '$group / $variety';
    return group.isNotEmpty ? group : variety;
  }

  String _displayAgeClassOnly(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('senior')) return 'Senior';
    if (lower.contains('intermediate')) return 'Intermediate';
    if (lower.contains('junior')) return 'Junior';
    return value;
  }

  String _safe(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim();

  bool _hasValue(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

  bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    return text == 'true' ||
        text == 't' ||
        text == 'yes' ||
        text == 'y' ||
        text == '1' ||
        text == 'x';
  }

  String _money(dynamic value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (number == null) return r'$—';
    return '\$${number.toStringAsFixed(2)}';
  }

  String _moneyFromCents(dynamic value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (number == null) return r'$—';
    return '\$${(number / 100).toStringAsFixed(2)}';
  }

  String _safeFileName(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
