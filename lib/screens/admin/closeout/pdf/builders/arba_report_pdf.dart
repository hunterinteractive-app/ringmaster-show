import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/arba/arba_report_data.dart';
import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';

class ArbaReportPdfBuilder {
  Future<ReportFileResult> buildFile(
    ArbaReportData data,
    ReportRequest request,
  ) async {
    final pdf = pw.Document();
    final dynamic d = data;

    final sanctionNumber = _str(_tryGet(() => d.sanctionNumber));
    final printedDate =
        _fmtDate(_tryGet(() => d.reportDate)) ?? _fmtDate(DateTime.now()) ?? '';

    final rabbitsShown = _str(_tryGet(() => d.rabbitsShown));
    final caviesShown = _str(_tryGet(() => d.caviesShown));

    final showName = _str(_tryGet(() => d.showName));
    final sponsoringShow =
        _str(_tryGet(() => d.clubName), fallback: showName);

    final showDate = _fmtDate(_tryGet(() => d.showDate)) ?? '';
    final location = _str(_tryGet(() => d.showLocation));

    final secretaryName = _str(_tryGet(() => d.secretaryName));
    final secretaryEmail = _str(_tryGet(() => d.secretaryEmail));
    final secretaryPhone = _str(_tryGet(() => d.secretaryPhone));
    final secretaryAddress = _str(_tryGet(() => d.secretaryAddress));

    final superintendentName = _str(_tryGet(() => d.superintendentName));
    final superintendentArbaNumber =
        _str(_tryGet(() => d.superintendentArbaNumber));

    final superintendent = [
      superintendentName,
      superintendentArbaNumber,
    ].where((e) => e.isNotEmpty).join('\n');

    final troubleReceivingSanctions =
        _str(_tryGet(() => d.troubleReceivingSanctions), fallback: 'No');

    final troubleReceivingSanctionClubs =
        _str(_tryGet(() => d.troubleReceivingSanctionClubs), fallback: 'N/A');

    final protestFiled =
        _str(_tryGet(() => d.protestFiled), fallback: 'No');

    final protestReportFiled =
        _str(_tryGet(() => d.protestReportFiled), fallback: 'N/A');

    final ribbonsMailed =
        _fmtDate(_tryGet(() => d.ribbonsReportsMailedAt)) ?? '';

    final sweepstakesFiled =
        _fmtDate(_tryGet(() => d.sweepstakesReportsFiledAt)) ?? '';

    final judges = _normalizeJudges(_tryGet(() => d.judges));

    final filedDate =
        _fmtDate(_tryGet(() => d.filedDate)) ?? printedDate;

    final signedBy = _str(_tryGet(() => d.signedBy));

    final bisRabbitOwner = _str(_tryGet(() => d.bisRabbitOwner));
    final bisRabbitCityState = _str(_tryGet(() => d.bisRabbitCityState));
    final bisRabbitBreed = _str(_tryGet(() => d.bisRabbitBreed));
    final bisRabbitEarNumber = _str(_tryGet(() => d.bisRabbitEarNumber));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(26, 22, 26, 22),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _topPrintLine(
                printedDate: printedDate,
                sanctionNumber: sanctionNumber,
              ),

              pw.SizedBox(height: 6),

              _titleBlock(),

              pw.SizedBox(height: 8),

              _instructionBlock(),

              pw.SizedBox(height: 8),

              _simpleLabeledLine(
                'Number of Rabbits Exhibited:',
                rabbitsShown,
                trailingText: caviesShown == '0'
                    ? ''
                    : 'Number of Cavies Exhibited: $caviesShown',
              ),

              pw.SizedBox(height: 8),

              _showInfoGrid(
                sponsoringShow: sponsoringShow,
                showDate: showDate,
                location: location,
                secretaryName: secretaryName,
                secretaryAddress: secretaryAddress,
                superintendent: superintendent,
                ribbonsMailed: ribbonsMailed,
                sweepstakesFiled: sweepstakesFiled,
              ),

              pw.SizedBox(height: 6),

              _contactBlock(
                secretaryEmail: secretaryEmail,
                secretaryPhone: secretaryPhone,
              ),

              pw.SizedBox(height: 8),

              _judgesSection(judges),

              pw.SizedBox(height: 8),

              _twoQuestionBlock(
                question1:
                    'ANY TROUBLE RECEIVING SWEEPSTAKES SANCTIONS FROM NATIONAL SPECIALTY CLUBS?',
                answer1: troubleReceivingSanctions,
                question2: 'IF YES, WHICH ONE/S?',
                answer2: troubleReceivingSanctionClubs,
              ),

              pw.SizedBox(height: 8),

              _sectionHeader('BEST IN SHOW RABBIT'),

              _bisRabbitTable(
                owner: bisRabbitOwner,
                cityState: bisRabbitCityState,
                breed: bisRabbitBreed,
                earNumber: bisRabbitEarNumber,
              ),

              pw.SizedBox(height: 8),

              _signatureBlock(
                filedDate: filedDate,
                signedBy: signedBy,
                secretaryPhone: secretaryPhone,
                secretaryEmail: secretaryEmail,
              ),

              pw.SizedBox(height: 8),

              _twoQuestionBlock(
                question1: 'Was there an official protest filed at this show?',
                answer1: protestFiled,
                question2:
                    'If so, has a report been filed with the ARBA office at this time?',
                answer2: protestReportFiled,
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: 'arba_report.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  pw.Widget _topPrintLine({
    required String printedDate,
    required String sanctionNumber,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Printed: $printedDate',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.Text(
          'ARBA Sanction Number ${sanctionNumber.isEmpty ? "________" : sanctionNumber}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }

  pw.Widget _titleBlock() {
    return pw.Column(
      children: [
        pw.Text(
          'AMERICAN RABBIT BREEDERS ASSOCIATION, INC.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'OFFICIAL SANCTIONED SHOW REPORT',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _instructionBlock() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        'THIS FORM MUST BE COMPLETED BY THE SHOW SECRETARY AND RETURNED TO THE ARBA OFFICE WITHIN THIRTY (30) DAYS AFTER THE CLOSE OF THE SHOW.',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  pw.Widget _simpleLabeledLine(
    String label,
    String value, {
    String? trailingText,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '$label ${value.isEmpty ? "________" : value}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          if (trailingText != null && trailingText.trim().isNotEmpty)
            pw.Text(
              trailingText,
              style: const pw.TextStyle(fontSize: 9),
            ),
        ],
      ),
    );
  }

  pw.Widget _contactBlock({
    required String secretaryEmail,
    required String secretaryPhone,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      children: [
        pw.TableRow(
          children: [
            _valueCell(
              secretaryEmail.isEmpty ? 'SECRETARY EMAIL' : secretaryEmail,
            ),
            _valueCell(
              secretaryPhone.isEmpty ? 'SECRETARY PHONE' : secretaryPhone,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _signatureBlock({
    required String filedDate,
    required String signedBy,
    required String secretaryPhone,
    required String secretaryEmail,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      children: [
        pw.TableRow(
          children: [
            _valueCell(
              'DATE FILED  ${filedDate.isEmpty ? "________" : filedDate}',
            ),
            _valueCell(
              'SIGNED (SHOW SEC.)  ${signedBy.isEmpty ? "________" : signedBy}',
            ),
          ],
        ),
        pw.TableRow(
          children: [
            _valueCell(secretaryPhone.isEmpty ? 'Phone number' : secretaryPhone),
            _valueCell(secretaryEmail.isEmpty ? 'Email address' : secretaryEmail),
          ],
        ),
      ],
    );
  }

  pw.Widget _valueCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text.isEmpty ? ' ' : text,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  dynamic _tryGet(dynamic Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  String _str(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String? _fmtDate(dynamic value) {
    if (value == null) return null;

    try {
      if (value is DateTime) {
        return '${value.month}/${value.day}/${value.year}';
      }

      final parsed = DateTime.tryParse(value.toString());
      if (parsed == null) return value.toString();

      return '${parsed.month}/${parsed.day}/${parsed.year}';
    } catch (_) {
      return value.toString();
    }
  }

    List<String> _normalizeJudges(dynamic raw) {
      if (raw == null) return const [];

      if (raw is List) {
        return raw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }

      return [raw.toString()];
    }
pw.Widget _showInfoGrid({
  required String sponsoringShow,
  required String showDate,
  required String location,
  required String secretaryName,
  required String secretaryAddress,
  required String superintendent,
  required String ribbonsMailed,
  required String sweepstakesFiled,
}) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.4),
      1: pw.FlexColumnWidth(1.4),
    },
    children: [
      _row2(
        'ASSOC. SPONSORING SHOW',
        'DATE OF SHOW                            LOCATION',
        value1: sponsoringShow,
        value2:
            '${showDate.isEmpty ? "" : showDate}    ${location.isEmpty ? "" : location}',
      ),
      _row2(
        'SHOW SECRETARY',
        'SUPERINTENDENT',
        value1: secretaryName,
        value2: superintendent,
      ),
      _singleRow('ADDRESS', secretaryAddress),
      _row2(
        'DATE RIBBONS, PREMIUMS, AND REPORTS WERE MAILED TO EXHIBITORS',
        'DATE SWEEPSTAKES REPORTS FILED WITH NATIONAL SPECIALTY CLUBS',
        value1: ribbonsMailed,
        value2: sweepstakesFiled,
      ),
    ],
  );
}

pw.TableRow _row2(
  String label1,
  String label2, {
  required String value1,
  required String value2,
}) {
  return pw.TableRow(
    children: [
      _cellBlock(label1, value1),
      _cellBlock(label2, value2),
    ],
  );
}

pw.TableRow _singleRow(String label, String value) {
  return pw.TableRow(
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value.isEmpty ? ' ' : value,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
      pw.Container(),
    ],
  );
}

pw.Widget _cellBlock(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value.isEmpty ? ' ' : value,
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
}

pw.Widget _judgesSection(List<String> judges) {
  final left = <String>[];
  final right = <String>[];

  for (var i = 0; i < judges.length; i++) {
    final numbered = '${i + 1}. ${judges[i]}';
    if (i.isEven) {
      left.add(numbered);
    } else {
      right.add(numbered);
    }
  }

  while (left.length < 6) {
    left.add('${left.length * 2 + 1}. ');
  }
  while (right.length < 6) {
    right.add('${right.length * 2 + 2}. ');
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _headerCell('JUDGE/S & LICENSE NUMBER'),
          _headerCell('JUDGE/S & LICENSE NUMBER'),
        ],
      ),
      for (var i = 0; i < 6; i++)
        pw.TableRow(
          children: [
            _valueCell(left[i]),
            _valueCell(right[i]),
          ],
        ),
    ],
  );
}

pw.Widget _sectionHeader(String text) {
  return pw.Container(
    width: double.infinity,
    color: PdfColors.grey300,
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _bisRabbitTable({
  required String owner,
  required String cityState,
  required String breed,
  required String earNumber,
}) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.4),
      1: pw.FlexColumnWidth(1.4),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(0.9),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _headerCell('OWNER'),
          _headerCell('CITY & STATE'),
          _headerCell('BREED'),
          _headerCell('EAR NUMBER'),
        ],
      ),
      pw.TableRow(
        children: [
          _valueCell(owner),
          _valueCell(cityState),
          _valueCell(breed),
          _valueCell(earNumber),
        ],
      ),
    ],
  );
}

pw.Widget _twoQuestionBlock({
  required String question1,
  required String answer1,
  required String question2,
  required String answer2,
}) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 0.6),
    ),
    padding: const pw.EdgeInsets.all(6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          question1,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(answer1.isEmpty ? ' ' : answer1, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text(
          question2,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(answer2.isEmpty ? ' ' : answer2, style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );
}

pw.Widget _headerCell(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(4),
    alignment: pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
    ),
  );
}
}