import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:ringmaster_show/screens/admin/results/control_sheet_scan_dialog.dart';
import 'package:ringmaster_show/services/results/control_sheet_scan.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:uuid/uuid.dart';
import 'package:zxing2/qrcode.dart' as qr;

const _uuid = Uuid();
final _page = ControlSheetScanPage(
  showId: _uuid.v5(Namespace.url.value, 'show'),
  sectionId: _uuid.v5(Namespace.url.value, 'section'),
  entryIds: List.generate(
    scanSheetRowsPerPage,
    (row) => _uuid.v5(Namespace.url.value, 'entry-$row'),
  ),
  awards: const {'BOV', 'BOSV', 'BOG', 'BOSG', 'BOB', 'BOS'},
  placementCount: 20,
);

image.Image _makeScan({
  List<ControlSheetScanPage>? compactBlocks,
  List<String>? markedRows,
  List<Map<String, int>>? markedSpecials,
}) {
  const scale = 3;
  final paper = image.Image(
    width: (scanSheetWidth * scale).round(),
    height: (scanSheetHeight * scale).round(),
  );
  final white = image.ColorRgb8(250, 250, 250);
  final black = image.ColorRgb8(0, 0, 0);
  image.fill(paper, color: white);
  void rect(double left, double top, double width, image.Color color) {
    image.fillRect(
      paper,
      x1: (left * scale).round(),
      y1: (top * scale).round(),
      x2: ((left + width) * scale).round() - 1,
      y2: ((top + width) * scale).round() - 1,
      color: color,
    );
  }

  for (final center in scanSheetCorners) {
    rect(center.x - 7, center.y - 7, 14, black);
    rect(center.x - 4.5, center.y - 4.5, 9, white);
  }
  final blocks = compactBlocks ?? [_page];
  final payload = compactBlocks == null
      ? _page.encode()
      : CompactControlSheetScanPage(blocks).encode();
  final code = qr.Encoder.encode(payload, qr.ErrorCorrectionLevel.m).matrix!;
  final module =
      (compactBlocks == null ? scanSheetQrSize : compactSheetQrSize) /
      code.width;
  final qrLeft = compactBlocks == null ? scanSheetQrLeft : compactSheetQrLeft;
  final qrTop = compactBlocks == null ? scanSheetQrTop : compactSheetQrTop;
  for (var y = 0; y < code.height; y++) {
    for (var x = 0; x < code.width; x++) {
      if (code.get(x, y) == 1) {
        rect(qrLeft + x * module, qrTop + y * module, module, black);
      }
    }
  }

  void fill(double x, double y, int radius, image.Color color) {
    image.fillCircle(
      paper,
      x: (x * scale).round(),
      y: (y * scale).round(),
      radius: radius,
      color: color,
    );
  }

  void mark(
    ControlSheetScanPage block,
    int row,
    int column,
    int radius,
    image.Color color,
  ) {
    final center = block.bubble(row, column);
    fill(center.x, center.y, radius, color);
  }

  for (final (index, block) in blocks.indexed) {
    if (block.headerAwards) {
      for (final (column, award) in block.awardColumns.indexed) {
        final center = block.awardBubble(column);
        fill(center.x, center.y, 16, black);
        fill(center.x, center.y, 13, white);
        final radius = markedSpecials?[index][award];
        if (radius != null) fill(center.x, center.y, radius, black);
      }
    }
    for (var row = 0; row < block.entryIds.length; row++) {
      for (var col = 0; col < block.columns.length; col++) {
        mark(block, row, col, 16, black);
        mark(block, row, col, 13, white);
      }
    }
  }
  if (compactBlocks == null) {
    mark(_page, 0, 0, 14, black);
    mark(_page, 0, _page.columns.indexOf('BOV'), 14, black);
    mark(_page, 1, 1, 14, black);
    mark(_page, 2, 2, 7, black);
    mark(_page, scanSheetRowsPerPage - 1, 19, 14, black);
  } else {
    for (final block in blocks) {
      if (markedRows == null) {
        mark(block, 0, block.placementsOnPage - 1, 13, black);
      } else {
        for (final (row, key) in markedRows.indexed) {
          mark(block, row, block.columns.indexOf(key), 13, black);
        }
      }
    }
  }
  return paper;
}

image.Image _angledPhoto(image.Image paper) {
  final photo = image.Image(
    width: paper.width + 450,
    height: paper.height + 500,
  );
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      final w = 1 + .000045 * y;
      final px = ((x - 205 + .067 * y) / w).round();
      final py = ((y - 120 - .045 * x) / w).round();
      final pixel = paper.getPixelSafe(px, py);
      final brightness = (pixel.r * (1 - .16 * y / photo.height)).round();
      photo.setPixelRgb(x, y, brightness, brightness, brightness);
    }
  }
  return photo;
}

void _expectMarks(ControlSheetScan scan) {
  final block = scan.blocks.single;
  expect(block.page.entryIds, _page.entryIds);
  expect(block.rows[0].marks, {'1', 'BOV'});
  expect(block.rows[1].marks, {'2'});
  expect(block.rows[2].marks, isEmpty);
  expect(block.rows[2].uncertain, {'3'});
  for (final row in block.rows.skip(3).take(scanSheetRowsPerPage - 4)) {
    expect(row.marks, isEmpty);
    expect(row.uncertain, isEmpty);
  }
  expect(block.rows.last.marks, {'20'});
}

void main() {
  late image.Image paper;
  setUpAll(() => paper = _makeScan());

  test('encodes exactly the ranks for classes of 1, 7, and 20', () {
    for (final size in [1, 7, 20]) {
      final page = ControlSheetScanPage(
        showId: _page.showId,
        sectionId: _page.sectionId,
        entryIds: _page.entryIds.take(size).toList(),
        awards: _page.awards,
        placementCount: size,
      );
      final layout = ControlSheetScanPage.decode(page.encode());
      expect(
        layout.columns.takeWhile((code) => int.tryParse(code) != null),
        List.generate(size, (index) => '${index + 1}'),
      );
      expect(layout.entryIds, page.entryIds);
    }
  });

  test('a continuation page can read higher ranks for the earlier entries', () {
    final page = ControlSheetScanPage(
      showId: _page.showId,
      sectionId: _page.sectionId,
      entryIds: _page.entryIds,
      awards: const {},
      placementCount: 27,
      firstPlacement: 21,
    );
    final decoded = ControlSheetScanPage.decode(page.encode());
    expect(decoded.columns, ['21', '22', '23', '24', '25', '26', '27']);
    expect(decoded.entryIds, _page.entryIds);
  });

  test('reads distinct class tables from one compact sheet', () {
    ControlSheetScanPage layout(int start, int size, int y) =>
        ControlSheetScanPage(
          showId: _page.showId,
          sectionId: _page.sectionId,
          entryIds: _page.entryIds.skip(start).take(size).toList(),
          awards: _page.awards,
          placementCount: size,
          firstRowY: y,
        );
    final blocks = [layout(0, 1, 273), layout(1, 7, 395)];
    final scan = readControlSheetScan(
      image.encodePng(_makeScan(compactBlocks: blocks)),
    );
    expect(
      scan.blocks.map((block) => block.page.entryIds),
      blocks.map((block) => block.entryIds),
    );
    expect(scan.blocks.first.rows.single.marks, {'1'});
    expect(scan.blocks.last.rows.first.marks, {'7'});
    expect(
      scan.blocks.last.rows.skip(1).every((row) => row.marks.isEmpty),
      isTrue,
    );
  });

  test('prints NP at 21 and scans it alongside the eight outcome choices', () {
    ControlSheetScanPage layout(int size) => ControlSheetScanPage(
      showId: _page.showId,
      sectionId: _page.sectionId,
      entryIds: _page.entryIds.take(10).toList(),
      awards: _page.awards,
      placementCount: size,
      firstRowY: 280,
      includesOutcomes: true,
    );
    expect(layout(20).columns, isNot(contains('NP')));
    final page = layout(21);
    expect(page.columns.take(21), [
      ...List.generate(20, (index) => '${index + 1}'),
      'NP',
    ]);
    expect(page.columns, isNot(contains('21')));
    final marks = [
      '20',
      'NP',
      ...ControlSheetOutcome.values.map((outcome) => outcome.code),
    ];
    final paper = _makeScan(compactBlocks: [page], markedRows: marks);
    final scan = readControlSheetScan(image.encodePng(paper));
    expect(scan.blocks.single.page.placementCount, 21);
    expect(scan.blocks.single.rows.map((row) => row.marks.single), marks);
    expect(scan.blocks.single.rows.expand((row) => row.uncertain), isEmpty);
  });

  test(
    'reads each header special for the first-place row in its own class',
    () {
      for (final (layout, center, prefix) in [
        (ControlSheetAwardsLayout.offsetHeader, 351, 'RMS5:'),
        (ControlSheetAwardsLayout.centeredHeader, 306, 'RMS6:'),
      ]) {
        ControlSheetScanPage block(int start, int y) => ControlSheetScanPage(
          showId: _page.showId,
          sectionId: _page.sectionId,
          entryIds: _page.entryIds.skip(start).take(3).toList(),
          awards: _page.awards,
          placementCount: 21,
          firstRowY: y,
          includesOutcomes: true,
          awardsLayout: layout,
        );
        final blocks = [block(0, 280), block(3, 505)];
        expect(blocks.first.columns, isNot(contains('BOV')));
        expect(blocks.first.awardHeaderCenter, center);
        expect(
          CompactControlSheetScanPage(blocks).encode(),
          startsWith(prefix),
        );
        final paper = _makeScan(
          compactBlocks: blocks,
          markedRows: ['NP', '1', 'SCR'],
          markedSpecials: [
            {'BOV': 13, 'BOS': 7},
            {'BOG': 13},
          ],
        );
        final scan = readControlSheetScan(image.encodePng(paper));
        expect(scan.blocks.first.page.awardsLayout, layout);
        expect(scan.blocks.first.rows[0].marks, {'NP'});
        expect(scan.blocks.first.rows[1].marks, {'1', 'BOV'});
        expect(scan.blocks.first.rows[1].uncertain, {'BOS'});
        expect(scan.blocks.first.rows[2].marks, {'SCR'});
        expect(scan.blocks.last.rows[1].marks, {'1', 'BOG'});
        expect(scan.blocks.expand((block) => block.unassignedAwards), isEmpty);
      }
    },
  );

  test('flags a header special without a clear first-place mark', () {
    final block = ControlSheetScanPage(
      showId: _page.showId,
      sectionId: _page.sectionId,
      entryIds: _page.entryIds.take(3).toList(),
      awards: _page.awards,
      placementCount: 3,
      firstRowY: 280,
      includesOutcomes: true,
      awardsLayout: ControlSheetAwardsLayout.centeredHeader,
    );
    for (final ranks in [
      ['2', '3'],
      ['1', '1'],
    ]) {
      final paper = _makeScan(
        compactBlocks: [block],
        markedRows: ranks,
        markedSpecials: [
          {'BOB': 13},
        ],
      );
      final scan = readControlSheetScan(image.encodePng(paper));
      expect(scan.blocks.single.unassignedAwards, {'BOB'});
      expect(
        scan.blocks.single.rows.expand((row) => row.marks),
        isNot(contains('BOB')),
      );
    }
  });

  test('reads colored fill and a check while keeping a cross for review', () {
    final layout = ControlSheetScanPage(
      showId: _page.showId,
      sectionId: _page.sectionId,
      entryIds: _page.entryIds.take(1).toList(),
      awards: const {'BOV', 'BOB'},
      placementCount: 1,
      firstRowY: 280,
      includesOutcomes: true,
      awardsLayout: ControlSheetAwardsLayout.centeredHeader,
    );
    final paper = _makeScan(compactBlocks: [layout], markedRows: []);
    final first = layout.bubble(0, 0);
    image.fillCircle(
      paper,
      x: (first.x * 3).round(),
      y: (first.y * 3).round(),
      radius: 12,
      color: image.ColorRgb8(78, 254, 215),
    );
    void stroke(int column, int x1, int y1, int x2, int y2) {
      final center = layout.awardBubble(column);
      final x = (center.x * 3).round();
      final y = (center.y * 3).round();
      image.drawLine(
        paper,
        x1: x + x1,
        y1: y + y1,
        x2: x + x2,
        y2: y + y2,
        thickness: 5,
        color: image.ColorRgb8(15, 15, 15),
      );
    }

    stroke(0, -9, -3, -2, 7);
    stroke(0, -2, 7, 12, -5);
    stroke(1, -9, -8, 9, 8);
    stroke(1, -9, 8, 9, -8);
    final scanned = readControlSheetScan(image.encodeJpg(paper, quality: 82));
    expect(scanned.blocks.single.rows.single.marks, {'1', 'BOV'});
    expect(scanned.blocks.single.rows.single.uncertain, {'BOB'});
    expect(scanned.blocks.single.unassignedAwards, isEmpty);
  });

  test('reads placements and awards, including the final row', () {
    _expectMarks(readControlSheetScan(image.encodePng(paper)));
  });

  test('reads a rotated photo with perspective and uneven lighting', () {
    final photo = image.copyRotate(_angledPhoto(paper), angle: 90);
    _expectMarks(readControlSheetScan(image.encodeJpg(photo, quality: 80)));
  });

  test('reads a complete control sheet with shadow over the far markers', () {
    final layout = ControlSheetScanPage(
      showId: _page.showId,
      sectionId: _page.sectionId,
      entryIds: _page.entryIds.take(12).toList(),
      awards: _page.awards,
      placementCount: 21,
      firstRowY: 280,
      includesOutcomes: true,
      awardsLayout: ControlSheetAwardsLayout.centeredHeader,
    );
    final ranks = [for (var place = 1; place <= 11; place++) '$place', 'NP'];
    final photo = _angledPhoto(
      _makeScan(compactBlocks: [layout], markedRows: ranks),
    );
    for (final pixel in photo) {
      final shade = 1 - .62 * (pixel.y / photo.height);
      final gray = (28 + pixel.r * shade).clamp(0, 255).round();
      pixel.setRgb(gray, gray, gray);
    }
    final scan = readControlSheetScan(image.encodeJpg(photo, quality: 68));
    expect(scan.blocks.single.page.entryIds, layout.entryIds);
    expect(scan.blocks.single.rows.map((row) => row.marks.single), ranks);
    expect(scan.blocks.single.rows.expand((row) => row.uncertain), isEmpty);
  });

  test('aligns the page when the QR alignment point is slightly offset', () {
    final layout = ControlSheetScanPage(
      showId: _page.showId,
      sectionId: _page.sectionId,
      entryIds: _page.entryIds.take(12).toList(),
      awards: _page.awards,
      placementCount: 21,
      firstRowY: 280,
      includesOutcomes: true,
      awardsLayout: ControlSheetAwardsLayout.centeredHeader,
    );
    final ranks = [for (var place = 1; place <= 12; place++) '$place'];
    final paper = image.copyResize(
      _makeScan(compactBlocks: [layout], markedRows: ranks),
      width: 1360,
      interpolation: image.Interpolation.linear,
    );
    final qrCode = qr.QRCodeReader().decode(
      qr.BinaryBitmap(
        qr.HybridBinarizer(
          qr.RGBLuminanceSource(
            paper.width,
            paper.height,
            paper
                .convert(numChannels: 4)
                .getBytes(order: image.ChannelOrder.abgr)
                .buffer
                .asInt32List(),
          ),
        ),
      ),
    );
    expect(qrCode.resultPoints, hasLength(4));
    final center = qrCode.resultPoints.last;
    final module =
        compactSheetQrSize *
        paper.width /
        scanSheetWidth /
        (qrCode.version! * 4 + 17);
    final radius = (module * 2.55).floor();
    final photo = image.Image.from(paper);
    for (
      var y = center.y.round() - radius;
      y <= center.y.round() + radius;
      y++
    ) {
      for (
        var x = center.x.round() - radius;
        x <= center.x.round() + radius;
        x++
      ) {
        photo.setPixel(x - 3, y - 2, paper.getPixel(x, y));
      }
    }
    final scan = readControlSheetScan(image.encodeJpg(photo, quality: 84));
    expect(scan.blocks.single.rows.map((row) => row.marks.single), ranks);
    expect(scan.blocks.single.rows.expand((row) => row.uncertain), isEmpty);
  });

  test('rejects a scan with an erased corner marker', () {
    final incomplete = image.Image.from(paper);
    image.fillRect(
      incomplete,
      x1: 0,
      y1: incomplete.height - 140,
      x2: 140,
      y2: incomplete.height - 1,
      color: image.ColorRgb8(255, 255, 255),
    );
    expect(
      () => readControlSheetScan(image.encodePng(incomplete)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('corner markers could not be aligned'),
        ),
      ),
    );
  });

  testWidgets(
    'requires reviewing faint marks and unassigned specials on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final directory = Directory.systemTemp.createTempSync(
        'control-sheet-scan-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final layout = ControlSheetScanPage(
        showId: _page.showId,
        sectionId: _page.sectionId,
        entryIds: _page.entryIds.take(5).toList(),
        awards: _page.awards,
        placementCount: 21,
        firstRowY: 280,
        includesOutcomes: true,
        awardsLayout: ControlSheetAwardsLayout.centeredHeader,
      );
      final scanImage = _makeScan(
        compactBlocks: [layout],
        markedRows: ['20', 'NP', 'SCR', 'WT'],
        markedSpecials: [
          {'BOB': 13},
        ],
      );
      final faint = layout.bubble(4, 2);
      image.fillCircle(
        scanImage,
        x: (faint.x * 3).round(),
        y: (faint.y * 3).round(),
        radius: 7,
        color: image.ColorRgb8(0, 0, 0),
      );
      final scan = File('${directory.path}/control-sheet.png')
        ..writeAsBytesSync(image.encodePng(scanImage));
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => [scan.path],
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      List<ScanResultChange>? checked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showControlSheetScanDialog(
                  context,
                  showId: _page.showId,
                  loadSection: (_) async => [
                    for (var row = 0; row < 21; row++)
                      {
                        'entry_id': row < 20
                            ? _page.entryIds[row]
                            : 'unprinted-entry',
                        'section_id': _page.sectionId,
                        'tattoo': 'TEST$row',
                        'breed': 'Mini Rex',
                        'variety': 'Broken',
                        'class_name': 'Senior',
                        'sex': 'Buck',
                      },
                  ],
                  validate: (results) async {
                    checked = results;
                    return results.length;
                  },
                ),
                child: const Text('Import from Results Entry'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Import from Results Entry'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Choose scans'));
        for (var i = 0; i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
          if (find.text('5 marked rows · 2 to review').evaluate().isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('5 marked rows · 2 to review'), findsOneWidget);
      expect(find.textContaining('no clear first-place mark'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check results'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Mark specials reviewed'));
      await tester.tap(find.text('Mark specials reviewed'));
      await tester.pumpAndSettle();
      expect(find.text('5 marked rows · 1 to review'), findsOneWidget);
      await tester.ensureVisible(find.text('Mark reviewed'));
      await tester.tap(find.text('Mark reviewed'));
      await tester.pumpAndSettle();
      expect(find.text('5 marked rows · 0 to review'), findsOneWidget);
      await tester.tap(find.text('Check results'));
      await tester.pumpAndSettle();
      expect(checked?.map((change) => change.placement), [
        '20',
        '0',
        null,
        null,
        '3',
      ]);
      expect(checked?.map((change) => change.outcome), [
        null,
        null,
        ControlSheetOutcome.scratch,
        ControlSheetOutcome.wrongTattoo,
        null,
      ]);

      expect(tester.takeException(), isNull);
    },
  );
}
