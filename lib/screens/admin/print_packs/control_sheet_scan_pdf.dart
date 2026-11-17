import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/services/results/control_sheet_scan.dart';
import 'package:zxing2/qrcode.dart' as qr;

import 'control_sheet_footer.dart';

const bubbleControlSheetBodyTop = 172;
const bubbleControlSheetBodyBottom = 722;
const bubbleControlSheetBlockHeaderHeight = 90;
const bubbleControlSheetBlockGap = 9;

typedef ControlSheetCount = ({int entries, int exhibitors});
typedef BubbleControlSheetPrintRow = ({
  String coop,
  String ear,
  String exhibitor,
});

class BubbleControlSheetPrintBlock {
  const BubbleControlSheetPrintBlock({
    required this.layout,
    required this.breed,
    required this.variety,
    required this.className,
    required this.sex,
    required this.judge,
    required this.breedCount,
    required this.varietyCount,
    required this.ageCount,
    required this.classCount,
    required this.rows,
  });

  final ControlSheetScanPage layout;
  final String breed;
  final String variety;
  final String className;
  final String sex;
  final String judge;
  final ControlSheetCount breedCount;
  final ControlSheetCount varietyCount;
  final ControlSheetCount ageCount;
  final ControlSheetCount classCount;
  final List<BubbleControlSheetPrintRow> rows;

  int get top =>
      layout.firstRowY! -
      layout.rowHeight.toInt() ~/ 2 -
      bubbleControlSheetBlockHeaderHeight;
}

void addBubbleControlSheetPage({
  required pw.Document document,
  required List<BubbleControlSheetPrintBlock> blocks,
  required String showName,
  required String section,
  required String judge,
  required DateTime printedAt,
  bool byVariety = false,
}) {
  final layout = CompactControlSheetScanPage(
    blocks.map((block) => block.layout).toList(),
  );
  final matrix = qr.Encoder.encode(
    layout.encode(),
    qr.ErrorCorrectionLevel.m,
  ).matrix!;
  final module = compactSheetQrSize / matrix.width;
  const tableLeft = 42.0;
  const earLeft = 86.0;
  const exhibitorLeft = 140.0;
  const tableRight = compactSheetTableRight;
  const headerHeight = 25.0;
  const headerColumnWidth = (tableRight - tableLeft) / 3;
  const headerInset = 4.0;
  final centeredHeader =
      blocks.first.layout.awardsLayout ==
      ControlSheetAwardsLayout.centeredHeader;
  final detailsLeft = centeredHeader ? tableLeft + headerInset : tableLeft;
  final countLeft = centeredHeader
      ? tableRight - headerColumnWidth + headerInset
      : 350.0;
  final countWidth = centeredHeader
      ? headerColumnWidth - headerInset * 2
      : 220.0;

  pw.Widget label(
    String text,
    double left,
    double top,
    double width,
    double size, {
    bool bold = true,
    int lines = 1,
    double? height,
    bool fit = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    final content = pw.Text(
      text,
      maxLines: lines,
      textAlign: align,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    );
    return pw.Positioned(
      left: left,
      top: top,
      right: scanSheetWidth - left - width,
      bottom: height == null ? null : scanSheetHeight - top - height,
      child: fit
          ? pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: align == pw.TextAlign.center
                  ? pw.Alignment.topCenter
                  : pw.Alignment.topLeft,
              child: content,
            )
          : content,
    );
  }

  String countLabel(String title, ControlSheetCount count) =>
      '$title: ${count.entries}   Exhibitors: ${count.exhibitors}';

  pw.Widget classDetail(
    BubbleControlSheetPrintBlock block,
    String text,
    double offset,
    double size,
    double height,
    double legacyWidth,
  ) => label(
    text,
    detailsLeft,
    block.top + offset,
    centeredHeader
        ? headerColumnWidth - headerInset * 2
        : block.layout.headerAwards
        ? 227
        : legacyWidth,
    size,
    height: block.layout.headerAwards ? height : null,
    fit: block.layout.headerAwards,
    align: centeredHeader ? pw.TextAlign.center : pw.TextAlign.left,
  );

  pw.Widget classCount(
    String title,
    ControlSheetCount count,
    double top,
    double size,
  ) => label(
    countLabel(title, count),
    countLeft,
    top,
    countWidth,
    size,
    height: centeredHeader ? size + 3 : null,
    fit: centeredHeader,
    align: centeredHeader ? pw.TextAlign.center : pw.TextAlign.right,
  );

  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.CustomPaint(
            size: const PdfPoint(scanSheetWidth, scanSheetHeight),
            painter: (canvas, size) {
              void box(
                double x,
                double y,
                double width,
                double height,
                PdfColor color,
              ) {
                canvas
                  ..setFillColor(color)
                  ..drawRect(x, size.y - y - height, width, height)
                  ..fillPath();
              }

              for (final corner in scanSheetCorners) {
                for (final (extent, color) in const [
                  (14.0, PdfColors.black),
                  (9.0, PdfColors.white),
                ]) {
                  box(
                    corner.x - extent / 2,
                    corner.y - extent / 2,
                    extent,
                    extent,
                    color,
                  );
                }
              }
              canvas.setFillColor(PdfColors.black);
              for (var row = 0; row < matrix.height; row++) {
                for (var column = 0; column < matrix.width; column++) {
                  if (matrix.get(column, row) == 1) {
                    canvas.drawRect(
                      compactSheetQrLeft + column * module,
                      size.y - compactSheetQrTop - (row + 1) * module,
                      module,
                      module,
                    );
                  }
                }
              }
              canvas.fillPath();

              for (final block in blocks) {
                final page = block.layout;
                final bodyTop = page.firstRowY! - page.rowHeight / 2;
                final headerTop = bodyTop - headerHeight;
                final bodyBottom = bodyTop + block.rows.length * page.rowHeight;
                box(
                  tableLeft,
                  headerTop,
                  tableRight - tableLeft,
                  headerHeight,
                  PdfColors.grey300,
                );
                canvas
                  ..setStrokeColor(PdfColors.grey600)
                  ..setLineWidth(.45);
                for (final x in [
                  tableLeft,
                  earLeft,
                  exhibitorLeft,
                  page.placementsLeft,
                  if (page.rowAwardCount > 0 && !page.includesOutcomes)
                    page.awardsLeft,
                  tableRight,
                ]) {
                  canvas.drawLine(
                    x,
                    size.y - headerTop,
                    x,
                    size.y - bodyBottom,
                  );
                }
                if (page.rowAwardCount > 0 && page.includesOutcomes) {
                  final x = page.awardsLeft;
                  canvas.drawLine(x, size.y - headerTop, x, size.y - bodyTop);
                  for (var row = 0; row < block.rows.length; row++) {
                    final y = bodyTop + row * page.rowHeight;
                    canvas.drawLine(
                      x,
                      size.y - y,
                      x,
                      size.y - y - page.rowHeight / 2,
                    );
                  }
                }
                for (final y in [
                  headerTop,
                  for (var row = 0; row <= block.rows.length; row++)
                    bodyTop + row * page.rowHeight,
                ]) {
                  canvas.drawLine(
                    tableLeft,
                    size.y - y,
                    tableRight,
                    size.y - y,
                  );
                }
                canvas.strokePath();
                canvas
                  ..setStrokeColor(PdfColors.black)
                  ..setLineWidth(.85);
                if (page.headerAwards) {
                  for (var column = 0; column < page.awards.length; column++) {
                    final center = page.awardBubble(column);
                    canvas.drawEllipse(center.x, size.y - center.y, 5, 5);
                  }
                }
                final columns = page.columns.length;
                for (var row = 0; row < block.rows.length; row++) {
                  for (var column = 0; column < columns; column++) {
                    final center = page.bubble(row, column);
                    canvas.drawEllipse(center.x, size.y - center.y, 5, 5);
                  }
                }
                canvas.strokePath();
              }
            },
          ),
          label(
            '$showName   $section',
            42,
            42,
            391,
            12,
            lines: 2,
            align: pw.TextAlign.center,
          ),
          label(
            'Judging Sheet - Breed Class - ${byVariety ? 'By Variety' : 'Compact'}',
            42,
            75,
            391,
            12,
            align: pw.TextAlign.center,
          ),
          pw.Positioned(
            left: 42,
            right: 179,
            top: 98,
            child: pw.Row(
              children: [
                _writeInLine(judge.isEmpty ? 'Judge: ' : 'Judge: $judge '),
                pw.SizedBox(width: 18),
                _writeInLine('Writer: '),
              ],
            ),
          ),
          label(
            'Fill the bubbles completely.',
            42,
            125,
            391,
            8.5,
            bold: false,
          ),
          if (blocks.first.layout.includesOutcomes) ...[
            label(
              'SCR Scratch   NS No Show   NP No Placing (classes of 21 or more)',
              42,
              139,
              391,
              8,
              bold: false,
            ),
            label(
              'DQ: WS Wrong Sex   WV Wrong Variety   WC Wrong Class',
              42,
              150,
              391,
              8,
              bold: false,
            ),
            label(
              'OW Overweight   WT Wrong Tattoo   OTH Other',
              42,
              161,
              391,
              8,
              bold: false,
            ),
          ],
          for (final block in blocks) ...[
            classDetail(block, 'Breed: ${block.breed}', 0, 16, 20, 340),
            classCount('No. In Breed', block.breedCount, block.top + 4.0, 9),
            classDetail(
              block,
              'Variety: ${block.variety.isEmpty ? 'Standard' : block.variety}',
              21,
              13,
              16,
              340,
            ),
            classCount(
              'No. In Variety',
              block.varietyCount,
              block.top + 23.0,
              9,
            ),
            classDetail(
              block,
              'Class: ${block.className}${block.sex.isEmpty ? '' : '     Sex: ${block.sex}'}',
              39,
              14,
              16,
              325,
            ),
            if (block.layout.headerAwards &&
                block.layout.awards.isNotEmpty) ...[
              label(
                'Specials',
                block.layout.awardHeaderCenter - 72,
                block.top.toDouble(),
                144,
                16,
                height: 20,
                fit: true,
                align: pw.TextAlign.center,
              ),
              for (final (index, award) in block.layout.awardColumns.indexed)
                label(
                  award == 'BOS' ? 'BOSB' : award,
                  block.layout.awardBubble(index).x - 11.5,
                  block.top + 22.0,
                  23,
                  8.5,
                  align: pw.TextAlign.center,
                ),
              label(
                'For 1st place on this page',
                block.layout.awardHeaderCenter - 72,
                block.top + 53.0,
                144,
                7.5,
                bold: false,
                align: pw.TextAlign.center,
              ),
            ],
            if (block.sex.isNotEmpty)
              classCount(
                'Age Group Total',
                block.ageCount,
                block.top + 35.0,
                8,
              ),
            classCount(
              'Class Total',
              block.classCount,
              block.top + (block.sex.isEmpty ? 42.0 : 46.0),
              9,
            ),
            if (block.judge.isNotEmpty && block.judge != judge)
              classDetail(block, 'Judge: ${block.judge}', 54, 8, 10, 300),
            label(
              'Coop #',
              tableLeft + 4,
              block.top + 69.0,
              earLeft - tableLeft - 8,
              10,
            ),
            label(
              'Ear #',
              earLeft + 4,
              block.top + 69.0,
              exhibitorLeft - earLeft - 8,
              10,
            ),
            label(
              'Exhibitor',
              exhibitorLeft + 4,
              block.top + 69.0,
              block.layout.placementsLeft - exhibitorLeft - 6,
              10,
            ),
            label(
              block.layout.firstPlacement == 1
                  ? 'Place'
                  : 'Places ${block.layout.firstPlacement}-${block.layout.firstPlacement + block.layout.placementsOnPage - 1}',
              block.layout.placementsLeft,
              block.top + 66.0,
              block.layout.awardsLeft - block.layout.placementsLeft,
              9,
              align: pw.TextAlign.center,
            ),
            if (block.layout.rowAwardCount > 0)
              label(
                'Specials',
                block.layout.awardsLeft,
                block.top + 66.0,
                block.layout.awardsWidth,
                9,
                align: pw.TextAlign.center,
              ),
            for (final (index, column)
                in block.layout.columns
                    .take(
                      block.layout.placementColumns +
                          block.layout.rowAwardCount,
                    )
                    .indexed)
              label(
                column,
                block.layout.bubble(0, index).x - 12,
                block.top + 76.0,
                24,
                index < block.layout.placementColumns ? 7.5 : 6.7,
                align: pw.TextAlign.center,
              ),
            for (final (index, row) in block.rows.indexed) ...[
              label(
                row.coop,
                tableLeft + 4,
                block.layout.bubble(index, 0).y - 6,
                earLeft - tableLeft - 8,
                10.5,
              ),
              label(
                row.ear,
                earLeft + 4,
                block.layout.bubble(index, 0).y - 6,
                exhibitorLeft - earLeft - 8,
                10.5,
              ),
              label(
                row.exhibitor,
                exhibitorLeft + 4,
                block.layout.bubble(index, 0).y - 6,
                block.layout.placementsLeft - exhibitorLeft - 8,
                block.layout.placementsLeft - exhibitorLeft < 64 ? 8 : 9.5,
                bold: block.layout.placementsLeft - exhibitorLeft >= 64,
                lines: block.layout.includesOutcomes ? 3 : 2,
                height: block.layout.includesOutcomes
                    ? block.layout.rowHeight - 7
                    : null,
              ),
              if (block.layout.includesOutcomes)
                for (final (position, outcome)
                    in ControlSheetOutcome.values.indexed)
                  label(
                    outcome.code,
                    block.layout
                            .bubble(
                              index,
                              block.layout.placementColumns +
                                  block.layout.rowAwardCount +
                                  position,
                            )
                            .x +
                        7,
                    block.layout.bubble(index, 0).y + 13,
                    18,
                    6.8,
                  ),
            ],
          ],
          label(
            'Include all four corner marks in the scan.',
            tableLeft,
            bubbleControlSheetBodyBottom + 3.0,
            tableRight - tableLeft,
            8.5,
            bold: false,
            align: pw.TextAlign.center,
          ),
          pw.Positioned(
            left: 42,
            right: 42,
            top: 733,
            child: controlSheetFooter(
              oppositeBreedCode: blocks.first.layout.headerAwards
                  ? 'BOSB'
                  : 'BOS',
              details: pw.Row(
                children: [
                  pw.Text(
                    'RingMaster One Show',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    printedAt.toLocal().toString().split('.').first,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _writeInLine(String text) => pw.Expanded(
  child: pw.Row(
    children: [
      pw.Flexible(
        child: pw.Text(
          text,
          maxLines: 1,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Expanded(
        child: pw.Container(
          height: 10,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: .6)),
          ),
        ),
      ),
    ],
  ),
);
