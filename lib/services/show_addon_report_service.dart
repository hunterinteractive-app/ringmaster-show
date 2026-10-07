import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/contest_settings.dart';
import '../screens/admin/closeout/csv/report_csv.dart';
import '../screens/admin/closeout/models/base/report_file_result.dart';
import 'show_addon_service.dart';

/// On-demand, whole-show reports. The existing authenticated RPC returns only
/// submitted orders and retains snapshots for offerings removed from sale.
class ShowAddonReportService {
  ShowAddonReportService({ShowAddonService? service})
    : _service = service ?? ShowAddonService();
  final ShowAddonService _service;

  static const purchases = 'show_addon_purchases_report';
  static const registrations = 'contest_registrations_report';
  static const reportNames = {purchases, registrations};
  static String title(String reportName) => switch (reportName) {
    purchases => 'Add-On Purchases',
    registrations => 'Contest Registrations',
    _ => throw ArgumentError('Unknown add-on report: $reportName'),
  };

  Future<ReportFileResult> build({
    required String showId,
    required String showName,
    required String reportName,
    required bool asCsv,
  }) async {
    title(reportName); // Validate before making any request.
    final rows = await _service.registrations(showId: showId);
    final data = ShowAddonReportData(
      showName: showName,
      reportName: reportName,
      entries: rows,
    );
    return asCsv ? data.csv() : data.pdf();
  }
}

class ShowAddonReportData {
  ShowAddonReportData({
    required this.showName,
    required this.reportName,
    required List<Map<String, dynamic>> entries,
    DateTime? generatedAt,
  }) : generatedAt = (generatedAt ?? DateTime.now()).toUtc(),
       entries = entries
           .where(
             (r) =>
                 r['kind'] ==
                 (reportName == ShowAddonReportService.purchases
                     ? 'extra'
                     : 'contest'),
           )
           .toList() {
    ShowAddonReportService.title(reportName);
    this.entries.sort((a, b) {
      for (final field in ['name', 'division', 'exhibitor_name', 'id']) {
        final comparison = _text(
          a[field],
        ).toLowerCase().compareTo(_text(b[field]).toLowerCase());
        if (comparison != 0) return comparison;
      }
      return 0;
    });
  }

  final String showName, reportName;
  final List<Map<String, dynamic>> entries;
  final DateTime generatedAt;
  bool get isContest => reportName == ShowAddonReportService.registrations;
  String get title => ShowAddonReportService.title(reportName);
  String get generatedLabel =>
      '${generatedAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC';
  int get quantity => entries.fold(0, (total, r) => total + _quantity(r));
  int get exhibitorCount => entries
      .map((r) => r['exhibitor_id'] ?? r['exhibitor_number'])
      .toSet()
      .length;
  Map<String, int> get totalsCents {
    final totals = <String, int>{};
    for (final r in entries) {
      final currency = _currency(r);
      totals[currency] = (totals[currency] ?? 0) + _total(r);
    }
    return totals;
  }

  String get summary {
    final exhibitors =
        '$exhibitorCount exhibitor${exhibitorCount == 1 ? '' : 's'}';
    return isContest
        ? '${entries.length} registration${entries.length == 1 ? '' : 's'} | $exhibitors'
        : '$quantity item${quantity == 1 ? '' : 's'} ordered | $exhibitors';
  }

  String get explanation => isContest
      ? 'Submitted contest registrations across the full show. Includes unpaid registrations; drafts are excluded.'
      : 'Submitted add-on orders across the full show. Includes pay-at-show orders and items removed from sale; drafts are excluded.';

  ReportFileResult csv() => ReportCsvTable(
    [
      isContest ? 'Contest' : 'Add-on',
      'Exhibitor #',
      'Exhibitor',
      'Email',
      if (isContest) ...[
        'Entry / Team / Project',
        'Division',
        'Category',
        'Session',
        'Animals',
        'Team members',
        'Approval',
        'Checked in',
      ],
      'Quantity',
      'Unit price',
      'Item total',
      'Currency',
      'Order payment status',
      'Registration / Purchase ID',
      'Generated (UTC)',
    ],
    [
      for (final r in entries)
        [
          _text(r['name']),
          _text(r['exhibitor_number']),
          _text(r['exhibitor_name']),
          _text(r['email']),
          if (isContest) ...[
            contestEntryLabel(r),
            _text(r['division']),
            _text(_data(r)['category']),
            _text(_data(r)['session_name']),
            _animals(r).join('; '),
            _members(r).join('; '),
            _status(r['approval_status'] ?? 'accepted'),
            r['checked_in'] == true ? 'Yes' : 'No',
          ],
          _quantity(r),
          (_price(r) / 100).toStringAsFixed(2),
          (_total(r) / 100).toStringAsFixed(2),
          _currency(r),
          _status(r['payment_status']),
          _text(r['id']),
          generatedLabel,
        ],
    ],
  ).toFile(title: title, showName: showName);

  Future<ReportFileResult> pdf() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final document = pw.Document(
      title: '$showName - $title',
      author: 'RingMaster Show',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final widths = isContest
        ? [1.3, 0.55, 2.1, 1.2, 1.8, 1.3, 0.85]
        : [1.8, 0.6, 2.4, 0.45, 0.85, 0.85, 1.15];
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 1000,
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(showName, style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Entire show | Generated $generatedLabel',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
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
          pw.Text(
            summary,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(explanation, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            'Totals show ordered amounts. Payment status applies to the exhibitor’s order.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 12),
          if (entries.isEmpty)
            pw.Text(
              isContest
                  ? 'No contest registrations yet.'
                  : 'No add-on purchases yet.',
            )
          else ...[
            pw.TableHelper.fromTextArray(
              headers: isContest
                  ? [
                      'Contest',
                      'Exh. #',
                      'Exhibitor / Entry / Email',
                      'Division / Category / Session',
                      'Animals / Team members',
                      'Approval / Check-in / Payment',
                      'Entry fee',
                    ]
                  : [
                      'Add-on',
                      'Exh. #',
                      'Exhibitor / Email',
                      'Qty',
                      'Unit price',
                      'Item total',
                      'Order payment',
                    ],
              data: _pdfRows(),
              columnWidths: {
                for (var i = 0; i < widths.length; i++)
                  i: pw.FlexColumnWidth(widths[i]),
              },
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellPadding: const pw.EdgeInsets.all(5),
              cellAlignment: pw.Alignment.topLeft,
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Total ordered: ${totalsCents.entries.map((e) => '${e.key} ${(e.value / 100).toStringAsFixed(2)}').join(' | ')}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ],
      ),
    );
    return ReportFileResult(
      fileName: csv().fileName.replaceFirst(RegExp(r'\.csv$'), '.pdf'),
      mimeType: 'application/pdf',
      bytes: await document.save(),
      metadata: {'row_count': entries.length},
    );
  }

  List<List<String>> _pdfRows() => [
    for (final r in entries)
      if (!isContest)
        [
          _text(r['name']),
          _text(r['exhibitor_number']),
          _joined([r['exhibitor_name'], r['email']]),
          '${_quantity(r)}',
          _money(r, _price(r)),
          _money(r, _total(r)),
          _status(r['payment_status']),
        ]
      else
        ..._contestPdfRows(r),
  ];

  List<List<String>> _contestPdfRows(Map<String, dynamic> r) {
    final details = [..._animals(r), ..._members(r)];
    return [
      [
        _text(r['name']),
        _text(r['exhibitor_number']),
        _joined([
          r['exhibitor_name'],
          if (contestEntryLabel(r) != r['exhibitor_name']) contestEntryLabel(r),
          r['email'],
        ]),
        _joined([
          r['division'],
          _data(r)['category'],
          _data(r)['session_name'],
        ]),
        details.isEmpty ? '' : details.first,
        _joined([
          _status(r['approval_status'] ?? 'accepted'),
          r['checked_in'] == true ? 'Checked in' : 'Not checked in',
          _status(r['payment_status']),
        ]),
        _money(r, _total(r)),
      ],
      // One detail per row lets long team rosters continue onto another page.
      for (final detail in details.skip(1))
        [
          _text(r['name']),
          _text(r['exhibitor_number']),
          '${contestEntryLabel(r)} (continued)',
          '',
          detail,
          '',
          '',
        ],
    ];
  }

  static List<String> _animals(Map<String, dynamic> r) {
    final animals = (_data(r)['animals'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (animals.isEmpty && r['animal_snapshot'] is Map) {
      animals.add(r['animal_snapshot'] as Map);
    }
    return [
      for (final a in animals)
        [
          if (_text(a['role']).isNotEmpty) _text(a['role']),
          _text(a['label']).isNotEmpty
              ? _text(a['label'])
              : [
                  a['species'],
                  a['breed'],
                  a['tattoo'],
                ].map(_text).where((s) => s.isNotEmpty).join(' / '),
        ].where((s) => s.isNotEmpty).join(': '),
    ];
  }

  static List<String> _members(Map<String, dynamic> r) => [
    for (final m
        in (_data(r)['team']?['members'] as List? ?? []).whereType<Map>())
      '${_text(m['name'])}${m['alternate'] == true ? ' (alternate)' : ''}',
  ];
  static Map _data(Map r) => r['registration_data'] as Map? ?? {};
  static String _text(Object? v) => v?.toString().trim() ?? '';
  static String _joined(List<Object?> values) =>
      values.map(_text).where((v) => v.isNotEmpty).join('\n');
  static int _quantity(Map r) => (r['quantity'] as num?)?.toInt() ?? 1;
  static int _price(Map r) => (r['unit_price_cents'] as num?)?.toInt() ?? 0;
  static int _total(Map r) => _quantity(r) * _price(r);
  static String _currency(Map r) =>
      _text(r['currency']).isEmpty ? 'USD' : _text(r['currency']).toUpperCase();
  static String _money(Map r, int cents) =>
      '${_currency(r)} ${(cents / 100).toStringAsFixed(2)}';
  static String _status(Object? v) {
    final text = _text(v).replaceAll('_', ' ');
    return text.isEmpty
        ? 'Unknown'
        : '${text[0].toUpperCase()}${text.substring(1)}';
  }
}
