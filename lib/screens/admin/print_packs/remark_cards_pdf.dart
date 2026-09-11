import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared by the print dialog and PDF layout regression tests.
class RemarkCardsPdfBuilder {
  final String showName;
  final bool includeRunnerCards;
  final bool useCoopNumberInsteadOfName;
  const RemarkCardsPdfBuilder({
    required this.showName,
    this.includeRunnerCards = true,
    this.useCoopNumberInsteadOfName = false,
  });
  static const double _runnerCardHeight = 2 * PdfPageFormat.inch;
  String _safe(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim();
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

    if (useCoopNumberInsteadOfName) {
      return coop.isEmpty ? 'Coop No.' : 'Coop No. $coop';
    }

    return exhibitor;
  }

  String _entryNumber(Map<String, dynamic> row) {
    for (final key in const [
      'entry_number',
      'entry_no',
      'catalog_number',
      'show_entry_number',
      'entry_index',
      'exhibitor_number',
    ]) {
      final value = _safe(row, key);
      if (value.isNotEmpty) return value;
    }
    return '';
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
                border: pw.Border(bottom: pw.BorderSide(width: .7)),
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

  pw.Widget _runnerCard(
    Map<String, dynamic> row, {
    required String sex,
    required String cls,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Container(height: .7, color: PdfColors.grey700),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6),
              child: pw.Text(
                'DETACHABLE RUNNER CARD',
                style: pw.TextStyle(
                  fontSize: 6.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Container(height: .7, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'RUNNER CARD',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Expanded(
              child: _lineField(
                label: 'Ear No.',
                value: _safe(row, 'tattoo'),
                height: 13,
                labelSize: 6.5,
                valueSize: 7,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _lineField(
                label: 'Coop No.',
                value: _safe(row, 'coop_number'),
                height: 13,
                labelSize: 6.5,
                valueSize: 7,
              ),
            ),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(
              child: _lineField(
                label: 'Breed',
                value: _safe(row, 'breed'),
                height: 13,
                labelSize: 6.5,
                valueSize: 7,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _lineField(
                label: 'Variety',
                value: _groupVarietyLabel(row),
                height: 13,
                labelSize: 6.5,
                valueSize: 7,
              ),
            ),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(
              child: _lineField(
                label: 'Class',
                value: cls,
                height: 13,
                labelSize: 6.5,
                valueSize: 7,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _lineField(
                label: 'Sex',
                value: sex,
                height: 13,
                labelSize: 6.5,
                valueSize: 7,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _remarkCard(
    Map<String, dynamic> row, {
    required String showDateLabel,
    required bool includeRunnerCard,
  }) {
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
      padding: pw.EdgeInsets.fromLTRB(14, 10, 14, includeRunnerCard ? 0 : 8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: .8)),
      child: pw.LayoutBuilder(
        builder: (context, constraints) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Reserve the detachable area before sizing the remark content.
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(
                  width: constraints!.maxWidth,
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
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
                            child: _lineField(
                              label: 'Ear No.',
                              value: _safe(row, 'tattoo'),
                            ),
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
                              value: _entryNumber(row),
                            ),
                          ),
                        ],
                      ),

                      _lineField(
                        label: 'Exhibitor',
                        value: _exhibitorDisplay(row),
                      ),

                      pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: _lineField(label: 'Show', value: showName),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            flex: 2,
                            child: _lineField(
                              label: 'Date',
                              value: showDateLabel,
                            ),
                          ),
                        ],
                      ),

                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: _lineField(
                              label: 'Breed',
                              value: _safe(row, 'breed'),
                            ),
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
                        {if (sex.isNotEmpty) sex, if (cls.isNotEmpty) cls},
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
                            child: _lineField(
                              label: 'No. Exhibitors',
                              value: '',
                            ),
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
                      _checkRow([
                        'Best Sr.',
                        'Best 6/8',
                        'Best Jr.',
                        'Best Pre-Jr.',
                      ], {}),

                      pw.SizedBox(height: 4),
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: _scoreGrid(leftRows, fourCols: true),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Expanded(
                            child: _scoreGrid(rightRows, fourCols: false),
                          ),
                        ],
                      ),

                      pw.SizedBox(height: 5),
                      _lineField(label: 'Remarks', value: '', height: 15),
                      _lineField(label: '', value: '', height: 13),
                      _lineField(label: 'Judge', value: '', height: 15),
                    ],
                  ),
                ),
              ),
            ),
            if (includeRunnerCard) ...[
              pw.SizedBox(
                height: _runnerCardHeight,
                child: _runnerCard(row, sex: sex, cls: cls),
              ),
            ],
          ],
        ),
      ),
    );
  }

  pw.Document build({
    required List<Map<String, dynamic>> entries,
    required pw.ThemeData theme,
    required String showDateLabel,
  }) {
    final doc = pw.Document(theme: theme);
    final pageFormat = PdfPageFormat(
      11 * PdfPageFormat.inch,
      8.5 * PdfPageFormat.inch,
    );
    const pageMargin = 20.0;
    const cardGap = 14.0;
    final cardWidth = (pageFormat.width - (pageMargin * 2) - cardGap) / 2;
    final cardHeight = pageFormat.height - (pageMargin * 2);

    for (var i = 0; i < entries.length; i += 2) {
      final first = entries[i];
      final second = i + 1 < entries.length ? entries[i + 1] : null;

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
                child: _remarkCard(
                  first,
                  showDateLabel: showDateLabel,
                  includeRunnerCard: includeRunnerCards,
                ),
              ),
              pw.SizedBox(width: cardGap),
              pw.SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: second == null
                    ? pw.Container()
                    : _remarkCard(
                        second,
                        showDateLabel: showDateLabel,
                        includeRunnerCard: includeRunnerCards,
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return doc;
  }
}
