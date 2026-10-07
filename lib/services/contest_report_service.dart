import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/contest_settings.dart';
import '../utils/csv_exporter.dart';

class ContestReportService {
  static List<List<String>> rows(
    List<Map<String, dynamic>> entries,
    String type,
  ) {
    final result = type == 'results';
    final teams = type == 'teams';
    return [
      [
        'Contest',
        'Exhibitor #',
        'Entry',
        'Division',
        'Category',
        'Session',
        if (result) ...[
          'Result',
          'Team members',
          'Publication',
        ] else ...[
          'Check-in',
          'Approval',
          'Payment',
        ],
        if (teams) ...['Member', 'Alternate'],
        if (!result) ...['Email'],
      ],
      for (final r in entries) ..._entryRows(r, result, teams),
    ];
  }

  static List<List<String>> _entryRows(
    Map<String, dynamic> r,
    bool result,
    bool teams,
  ) {
    final data = Map<String, dynamic>.from(
      r['registration_data'] as Map? ?? {},
    );
    final members = (data['team']?['members'] as List? ?? []);
    final base = [
      '${r['name']}',
      '${r['exhibitor_number'] ?? ''}',
      contestEntryLabel(r),
      '${r['division'] ?? ''}',
      '${data['category'] ?? ''}',
      '${data['session_name'] ?? ''}',
      if (result)
        contestResultLabel(
          Map<String, dynamic>.from(
            r['result'] as Map? ?? {'status': 'pending'},
          ),
        ),
      if (result)
        members
            .map(
              (m) =>
                  '${m['name']}${m['alternate'] == true ? ' (alternate)' : ''}',
            )
            .join('; '),
      if (result) r['results_published_at'] == null ? 'Draft' : 'Published',
      if (!result) ...[
        r['checked_in'] == true ? 'Yes' : 'No',
        '${r['approval_status'] ?? 'accepted'}',
        '${r['payment_status'] ?? ''}',
      ],
    ];
    if (teams) {
      return [
        for (final m in members)
          [
            ...base,
            '${m['name']}',
            m['alternate'] == true ? 'Yes' : 'No',
            '${r['email'] ?? ''}',
          ],
      ];
    }
    return [
      [...base, if (!result) '${r['email'] ?? ''}'],
    ];
  }

  static List<List<String>> _pdfRows(
    List<Map<String, dynamic>> entries,
    String type,
  ) {
    String joined(List<dynamic> values) =>
        values.where((v) => v != null && v != '').join(' / ');
    final teams = type == 'teams', results = type == 'results';
    final rows = <List<String>>[
      [
        'Exh. #',
        'Contest / Division',
        teams ? 'Team / Session' : 'Entry / Category / Session',
        if (results) ...[
          'Place / Awards',
          'Team members',
          'Status',
        ] else if (teams) ...[
          'Member',
          'Role',
          'Check-in',
          'Email',
        ] else ...[
          'Check-in',
          'Approval / Payment',
          'Email',
        ],
      ],
    ];
    for (final r in entries) {
      final d = Map<String, dynamic>.from(r['registration_data'] as Map? ?? {});
      final members = d['team']?['members'] as List? ?? [];
      final base = [
        '${r['exhibitor_number'] ?? ''}',
        joined([r['name'], r['division']]),
        joined([contestEntryLabel(r), d['category'], d['session_name']]),
      ];
      if (teams) {
        for (final m in members) {
          rows.add([
            ...base,
            '${m['name']}',
            m['alternate'] == true ? 'Alternate' : 'Active',
            r['checked_in'] == true ? 'Yes' : 'No',
            '${r['email'] ?? ''}',
          ]);
        }
      } else if (results) {
        rows.add([
          ...base,
          contestResultLabel(
            Map<String, dynamic>.from(
              r['result'] as Map? ?? {'status': 'pending'},
            ),
          ),
          members
              .map(
                (m) =>
                    '${m['name']}${m['alternate'] == true ? ' (alternate)' : ''}',
              )
              .join('; '),
          r['results_published_at'] == null ? 'Draft' : 'Published',
        ]);
      } else {
        rows.add([
          ...base,
          r['checked_in'] == true ? 'Yes' : 'No',
          joined([r['approval_status'], r['payment_status']]),
          '${r['email'] ?? ''}',
        ]);
      }
    }
    return rows;
  }

  static String csvCell(String value) {
    final safe = RegExp(r'^\s*[=+@\-\t\r]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  static Uint8List csv(List<List<String>> data) => Uint8List.fromList([
    0xef,
    0xbb,
    0xbf,
    ...utf8.encode(data.map((r) => r.map(csvCell).join(',')).join('\r\n')),
  ]);
  static Future<void> download(
    List<Map<String, dynamic>> entries, {
    required String title,
    required String type,
    required bool asCsv,
  }) async {
    final data = rows(entries, type);
    final filename =
        'contest_$type${type == 'results' && entries.any((r) => r['results_published_at'] == null) ? '_draft' : ''}_${DateTime.now().millisecondsSinceEpoch}';
    if (asCsv) {
      await exportCsvBytes(bytes: csv(data), suggestedName: '$filename.csv');
      return;
    }
    await Printing.sharePdf(
      bytes: await pdfBytes(entries, title: title, type: type),
      filename: '$filename.pdf',
    );
  }

  static Future<Uint8List> pdfBytes(
    List<Map<String, dynamic>> entries, {
    required String title,
    required String type,
  }) async {
    final data = _pdfRows(entries, type);
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    if (type == 'labels') {
      doc.addPage(
        pw.MultiPage(
          maxPages: 1000,
          margin: const pw.EdgeInsets.all(32),
          pageFormat: PdfPageFormat.letter,
          build: (_) => [
            pw.Text(
              '$title - Project Labels',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final r in entries)
                  pw.Container(
                    width: 260,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${r['name']}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          '#${r['exhibitor_number']} • ${contestEntryLabel(r)}',
                        ),
                        pw.Text(
                          '${r['division'] ?? ''} / ${r['registration_data']?['category'] ?? ''}',
                        ),
                        pw.Text(
                          'Registration: ${r['id']}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    } else {
      doc.addPage(
        pw.MultiPage(
          maxPages: 1000,
          margin: const pw.EdgeInsets.all(32),
          pageFormat: PdfPageFormat.letter.landscape,
          header: (_) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(
              '$title - ${const {'results': 'Placings & Awards', 'teams': 'Team Roster', 'roster': 'Contest Roster', 'checkin': 'Check-In List'}[type] ?? type}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          footer: (c) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${c.pageNumber} of ${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: data.first,
              data: data.skip(1).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              columnWidths: {
                for (var i = 0; i < data.first.length; i++)
                  i: pw.FlexColumnWidth(
                    (type == 'results'
                        ? [0.55, 1.3, 2.1, 1.25, 1.7, 0.75]
                        : type == 'teams'
                        ? [0.55, 1.3, 1.7, 1.4, 0.8, 0.8, 1.7]
                        : [0.55, 1.3, 2.3, 0.8, 1.2, 1.8])[i],
                  ),
              },
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellPadding: const pw.EdgeInsets.all(5),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      );
    }
    return doc.save();
  }
}
