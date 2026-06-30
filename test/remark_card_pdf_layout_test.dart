import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Widget _lineField({
  required String label,
  required String value,
  double height = 16,
}) {
  return pw.Container(
    height: height,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(width: 3),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.only(left: 2, bottom: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: .7)),
            ),
            child: pw.Text(
              value,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _checkRow(List<String> labels, Set<String> selectedLabels) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: labels.map((label) {
      final isSelected = selectedLabels
          .map((value) => value.toLowerCase())
          .contains(label.toLowerCase());
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
            pw.Column(
              children: rows
                  .map(
                    (_) => pw.Row(
                      children: headers
                          .map(
                            (_) => pw.Expanded(
                              child: pw.Container(
                                height: 15,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: .55),
                                ),
                              ),
                            ),
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

pw.Widget _remarkCard() {
  const leftRows = [
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

  const rightRows = [
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
    decoration: pw.BoxDecoration(border: pw.Border.all(width: .8)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'RABBIT SHOW REMARK CARD',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'American Rabbit Breeders Association, Inc.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          children: [
            pw.Expanded(
              child: _lineField(label: 'Ear No.', value: 'ABC'),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _lineField(label: 'Coop No.', value: '12'),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _lineField(label: 'Entry No.', value: '2376'),
            ),
          ],
        ),
        _lineField(label: 'Exhibitor', value: 'Jane Doe'),
        pw.Row(
          children: [
            pw.Expanded(
              flex: 3,
              child: _lineField(label: 'Show', value: 'Example Show'),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 2,
              child: _lineField(label: 'Date', value: '06/29/2026'),
            ),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(
              child: _lineField(label: 'Breed', value: 'American'),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _lineField(label: 'Variety', value: 'Blue'),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        _checkRow(
          [
            'Buck',
            'Doe',
            'Sr.',
            '6/8',
            'Jr.',
            'Pre Jr.',
            'Fryer',
            'Meat Pen',
            'Fur',
          ],
          {'Buck', 'Sr.'},
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
        _checkRow([
          'B.O.B.',
          'B.O.S.',
          'B.O.G.',
          'B.O.S.G.',
          'B.O.V.',
          'B.O.S.V.',
        ], {}),
        pw.SizedBox(height: 4),
        _checkRow(['Best Sr.', 'Best 6/8', 'Best Jr.', 'Best Pre-Jr.'], {}),
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

void main() {
  test('remark card pdf layout saves', () async {
    final doc = pw.Document();
    final pageFormat = PdfPageFormat(
      11 * PdfPageFormat.inch,
      8.5 * PdfPageFormat.inch,
    );
    const pageMargin = 20.0;
    const cardGap = 14.0;
    final cardWidth = (pageFormat.width - (pageMargin * 2) - cardGap) / 2;
    final cardHeight = pageFormat.height - (pageMargin * 2);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(pageMargin),
        build: (_) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _remarkCard(),
            ),
            pw.SizedBox(width: cardGap),
            pw.SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _remarkCard(),
            ),
          ],
        ),
      ),
    );

    expect(await doc.save(), isNotEmpty);
  });
}
