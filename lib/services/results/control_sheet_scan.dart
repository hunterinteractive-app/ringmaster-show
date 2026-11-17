import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:zxing2/qrcode.dart' as qr;

const scanSheetRowsPerPage = 20;
const scanSheetWidth = 612.0;
const scanSheetHeight = 792.0;
const scanSheetQrLeft = 423.0;
const scanSheetQrTop = 40.0;
const scanSheetQrSize = 142.0;
const scanSheetPlacementsPerPage = 20;
const compactSheetQrLeft = 447.0;
const compactSheetQrTop = 39.0;
const compactSheetQrSize = 120.0;
const compactSheetTableRight = 570.0;
const compactSheetRowHeight = 23.0;
const outcomeSheetRowHeight = 36.0;

enum ControlSheetAwardsLayout { rows, offsetHeader, centeredHeader }

enum ControlSheetOutcome {
  scratch('SCR', 'Scratched'),
  noShow('NS', 'No Show'),
  wrongSex('WS', 'Disqualified - Wrong Sex'),
  wrongVariety('WV', 'Disqualified - Wrong Variety'),
  wrongClass('WC', 'Disqualified - Wrong Class'),
  overweight('OW', 'Disqualified - Overweight'),
  wrongTattoo('WT', 'Disqualified - Wrong Tattoo'),
  otherDq('OTH', 'Disqualified - Other');

  const ControlSheetOutcome(this.code, this.status);
  final String code;
  final String status;

  bool get isDq => this != scratch && this != noShow;
}

const _scanSheetAwardCodes = ['BOV', 'BOSV', 'BOG', 'BOSG', 'BOB', 'BOS'];
const scanSheetCorners = [
  math.Point(29.0, 29.0),
  math.Point(583.0, 29.0),
  math.Point(583.0, 763.0),
  math.Point(29.0, 763.0),
];

/// A versioned snapshot of the entry IDs in printed order. The page remains
/// readable after the roster changes, and repeated tattoos cannot shift results.
class ControlSheetScanPage {
  final String showId;
  final String sectionId;
  final List<String> entryIds;
  final Set<String> awards;
  final int placementCount;
  final int firstPlacement;
  final int? firstRowY;
  final bool includesOutcomes;
  final ControlSheetAwardsLayout awardsLayout;

  const ControlSheetScanPage({
    required this.showId,
    required this.sectionId,
    required this.entryIds,
    required this.awards,
    required this.placementCount,
    this.firstPlacement = 1,
    this.firstRowY,
    this.includesOutcomes = false,
    this.awardsLayout = ControlSheetAwardsLayout.rows,
  });

  static const _prefix = 'RMS2:';
  static const _headerSize = 41;

  int get placementsOnPage =>
      math.min(scanSheetPlacementsPerPage, placementCount - firstPlacement + 1);

  bool get printsNp =>
      includesOutcomes && placementCount > scanSheetPlacementsPerPage;
  int get placementColumns => placementsOnPage + (printsNp ? 1 : 0);
  double get rowHeight =>
      includesOutcomes ? outcomeSheetRowHeight : compactSheetRowHeight;
  bool get headerAwards => awardsLayout != ControlSheetAwardsLayout.rows;

  List<String> get awardColumns => [
    for (final award in _scanSheetAwardCodes)
      if (awards.contains(award)) award,
  ];

  List<String> get columns => [
    for (var i = 0; i < placementsOnPage; i++) '${firstPlacement + i}',
    if (printsNp) 'NP',
    if (!headerAwards) ...awardColumns,
    if (includesOutcomes)
      for (final outcome in ControlSheetOutcome.values) outcome.code,
  ];

  double get awardsWidth =>
      headerAwards || awards.isEmpty ? 0 : math.max(84, awards.length * 20);
  double get awardsLeft => compactSheetTableRight - awardsWidth;
  int get rowAwardCount => headerAwards ? 0 : awards.length;

  double get awardHeaderCenter =>
      awardsLayout == ControlSheetAwardsLayout.centeredHeader
      ? scanSheetWidth / 2
      : 351;

  math.Point<double> awardBubble(int column) => math.Point(
    awardHeaderCenter + (column - (awards.length - 1) / 2) * 23,
    firstRowY! - 67.0,
  );
  double get placementsLeft {
    final left =
        awardsLeft -
        math.max(
          72,
          math.min(includesOutcomes ? 259 : 245, placementColumns * 18),
        );
    return includesOutcomes ? math.min(left, 337) : left;
  }

  math.Point<double> bubble(int row, int column) {
    final rowY = firstRowY;
    if (rowY != null) {
      final y = rowY + row * rowHeight;
      final outcomesStart = placementColumns + rowAwardCount;
      if (column >= outcomesStart) {
        final slotWidth =
            (compactSheetTableRight - placementsLeft) /
            ControlSheetOutcome.values.length;
        return math.Point(
          placementsLeft + 8 + slotWidth * (column - outcomesStart),
          y + 9,
        );
      }
      final x = column < placementColumns
          ? placementsLeft +
                (awardsLeft - placementsLeft) * (column + .5) / placementColumns
          : awardsLeft +
                awardsWidth * (column - placementColumns + .5) / awards.length;
      return math.Point(x, includesOutcomes ? y - 8 : y);
    }
    if (column >= placementsOnPage) {
      return math.Point(
        453.0 + 20 * (column - placementsOnPage),
        222.0 + row * 25,
      );
    }
    final spacing = placementsOnPage == 1
        ? 36.0
        : math.min(36.0, 252.0 / (placementsOnPage - 1));
    return math.Point(179.0 + spacing * column, 222.0 + row * 25);
  }

  bool get _validRange =>
      firstPlacement >= 1 &&
      firstPlacement <= placementCount &&
      (firstPlacement - 1) % scanSheetPlacementsPerPage == 0 &&
      placementCount <= 0xffffffff;

  String encode() {
    if (entryIds.isEmpty ||
        entryIds.length > scanSheetRowsPerPage ||
        entryIds.length > placementCount ||
        !_validRange ||
        entryIds.toSet().length != entryIds.length) {
      throw const FormatException(
        'Invalid rows or placement range on the control sheet.',
      );
    }
    final bytes = BytesBuilder();
    bytes.add(_uuidBytes(showId));
    bytes.add(_uuidBytes(sectionId));
    var mask = 0;
    for (var i = 0; i < _scanSheetAwardCodes.length; i++) {
      if (awards.contains(_scanSheetAwardCodes[i])) mask |= 1 << i;
    }
    bytes.addByte(mask);
    final range = ByteData(8)
      ..setUint32(0, placementCount)
      ..setUint32(4, firstPlacement);
    bytes.add(range.buffer.asUint8List());
    for (final id in entryIds) {
      bytes.add(_uuidBytes(id));
    }
    return '$_prefix${base64UrlEncode(bytes.takeBytes())}';
  }

  factory ControlSheetScanPage.decode(String code) {
    if (!code.startsWith(_prefix)) {
      throw const FormatException(
        'Use a bubble control sheet printed from the current pilot.',
      );
    }
    final bytes = base64Url.decode(code.substring(_prefix.length));
    if (bytes.length < _headerSize + 16 ||
        bytes.length > _headerSize + scanSheetRowsPerPage * 16 ||
        (bytes.length - _headerSize) % 16 != 0 ||
        bytes[32] >= (1 << _scanSheetAwardCodes.length)) {
      throw const FormatException('The control sheet code is damaged.');
    }
    final ids = [
      for (var at = _headerSize; at < bytes.length; at += 16)
        _uuidString(bytes, at),
    ];
    if (ids.toSet().length != ids.length) {
      throw const FormatException('The control sheet has duplicate rows.');
    }
    final range = ByteData.sublistView(bytes, 33, _headerSize);
    final page = ControlSheetScanPage(
      showId: _uuidString(bytes, 0),
      sectionId: _uuidString(bytes, 16),
      entryIds: ids,
      placementCount: range.getUint32(0),
      firstPlacement: range.getUint32(4),
      awards: {
        for (var i = 0; i < _scanSheetAwardCodes.length; i++)
          if (bytes[32] & (1 << i) != 0) _scanSheetAwardCodes[i],
      },
    );
    if (!page._validRange || ids.length > page.placementCount) {
      throw const FormatException(
        'The placement range on the control sheet is invalid.',
      );
    }
    return page;
  }

  static List<int> _uuidBytes(String uuid) {
    final hex = uuid.toLowerCase().replaceAll('-', '');
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) {
      throw const FormatException(
        'A control sheet row is missing its entry ID.',
      );
    }
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }

  static String _uuidString(List<int> bytes, int start) {
    final hex = bytes
        .skip(start)
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// All class tables on one compact physical page share a section and QR code.
class CompactControlSheetScanPage {
  final List<ControlSheetScanPage> blocks;

  const CompactControlSheetScanPage(this.blocks);

  static const prefix = 'RMS6:';
  static const _offsetHeaderPrefix = 'RMS5:';
  static const outcomePrefix = 'RMS4:';
  static const legacyPrefix = 'RMS3:';

  static bool recognizes(String code) =>
      code.startsWith(prefix) ||
      code.startsWith(_offsetHeaderPrefix) ||
      code.startsWith(outcomePrefix) ||
      code.startsWith(legacyPrefix);

  String encode() {
    if (blocks.isEmpty ||
        blocks.fold<int>(0, (count, block) => count + block.entryIds.length) >
            scanSheetRowsPerPage) {
      throw const FormatException(
        'Invalid number of rows on the control sheet.',
      );
    }
    final first = blocks.first;
    final includesOutcomes = first.includesOutcomes;
    final headerAwards = first.headerAwards;
    final bytes = BytesBuilder()
      ..add(ControlSheetScanPage._uuidBytes(first.showId))
      ..add(ControlSheetScanPage._uuidBytes(first.sectionId));
    var previousBottom = 165.0;
    final minimumGap = headerAwards ? 108 : 12;
    for (final block in blocks) {
      final y = block.firstRowY;
      if (block.showId != first.showId ||
          block.sectionId != first.sectionId ||
          block.includesOutcomes != includesOutcomes ||
          block.awardsLayout != first.awardsLayout ||
          (headerAwards && !includesOutcomes) ||
          (includesOutcomes && block.firstPlacement != 1) ||
          y == null ||
          y < previousBottom + minimumGap) {
        throw const FormatException(
          'Invalid class layout on the control sheet.',
        );
      }
      previousBottom = y + (block.entryIds.length - .5) * block.rowHeight;
      if (previousBottom > 726) {
        throw const FormatException(
          'A class table exceeds the printable page.',
        );
      }
      final encoded = base64Url.decode(
        block.encode().substring(ControlSheetScanPage._prefix.length),
      );
      final header = ByteData(3)
        ..setUint16(0, y)
        ..setUint8(2, block.entryIds.length);
      bytes
        ..add(header.buffer.asUint8List())
        ..add(encoded.sublist(32));
    }
    final version = switch (first.awardsLayout) {
      ControlSheetAwardsLayout.centeredHeader => prefix,
      ControlSheetAwardsLayout.offsetHeader => _offsetHeaderPrefix,
      ControlSheetAwardsLayout.rows =>
        includesOutcomes ? outcomePrefix : legacyPrefix,
    };
    return '$version${base64UrlEncode(bytes.takeBytes())}';
  }

  factory CompactControlSheetScanPage.decode(String code) {
    final awardsLayout = switch (code.substring(0, prefix.length)) {
      prefix => ControlSheetAwardsLayout.centeredHeader,
      _offsetHeaderPrefix => ControlSheetAwardsLayout.offsetHeader,
      _ => ControlSheetAwardsLayout.rows,
    };
    final includesOutcomes =
        awardsLayout != ControlSheetAwardsLayout.rows ||
        code.startsWith(outcomePrefix);
    final bytes = base64Url.decode(code.substring(prefix.length));
    if (bytes.length < 60) {
      throw const FormatException('The compact control sheet code is damaged.');
    }
    final blocks = <ControlSheetScanPage>[];
    for (var offset = 32; offset < bytes.length;) {
      if (bytes.length - offset < 3) {
        throw const FormatException(
          'The compact control sheet code is damaged.',
        );
      }
      final header = ByteData.sublistView(bytes, offset, offset + 3);
      final end = offset + 3 + 9 + header.getUint8(2) * 16;
      if (end > bytes.length) {
        throw const FormatException(
          'The compact control sheet code is damaged.',
        );
      }
      final plain = BytesBuilder()
        ..add(bytes.sublist(0, 32))
        ..add(bytes.sublist(offset + 3, end));
      final old = ControlSheetScanPage.decode(
        '${ControlSheetScanPage._prefix}${base64UrlEncode(plain.takeBytes())}',
      );
      blocks.add(
        ControlSheetScanPage(
          showId: old.showId,
          sectionId: old.sectionId,
          entryIds: old.entryIds,
          awards: old.awards,
          placementCount: old.placementCount,
          firstPlacement: old.firstPlacement,
          firstRowY: header.getUint16(0),
          includesOutcomes: includesOutcomes,
          awardsLayout: awardsLayout,
        ),
      );
      offset = end;
    }
    final page = CompactControlSheetScanPage(blocks);
    page.encode(); // Validate that every decoded table fits on the sheet.
    return page;
  }
}

class ControlSheetScanRow {
  final String entryId;
  final Set<String> marks;
  final Set<String> uncertain;

  const ControlSheetScanRow(this.entryId, this.marks, this.uncertain);
}

typedef ControlSheetScanBlock = ({
  ControlSheetScanPage page,
  List<ControlSheetScanRow> rows,
  Set<String> unassignedAwards,
});

class ControlSheetScan {
  final List<ControlSheetScanBlock> blocks;
  final Uint8List preview;

  const ControlSheetScan(this.blocks, this.preview);
}

const _unreadableCode = FormatException(
  'The page code could not be read. Retake the photo with the entire page in focus.',
);
const _unreadableCorners = FormatException(
  'The four corner markers could not be aligned. Take the photo straight above '
  'the page in even light, with a little space around all four edges.',
);

/// Call on a background isolate where Flutter supports it.
ControlSheetScan readControlSheetScan(Uint8List bytes) {
  var source = image.decodeImage(bytes);
  if (source == null) {
    throw const FormatException('Use a JPG or PNG photo, or a scanned PDF.');
  }
  source = image.bakeOrientation(source);
  if (math.max(source.width, source.height) > 2400) {
    source = image.copyResize(
      source,
      width: source.width >= source.height ? 2400 : null,
      height: source.height > source.width ? 2400 : null,
      interpolation: image.Interpolation.linear,
    );
  }

  final luminance = qr.RGBLuminanceSource(
    source.width,
    source.height,
    source
        .convert(numChannels: 4)
        .getBytes(order: image.ChannelOrder.abgr)
        .buffer
        .asInt32List(),
  );
  final bitmap = qr.BinaryBitmap(qr.HybridBinarizer(luminance));
  late final qr.Result code;
  try {
    final hints = qr.DecodeHints()..put(qr.DecodeHintType.tryHarder);
    code = qr.QRCodeReader().decode(bitmap, hints: hints);
  } on qr.ReaderException {
    throw _unreadableCode;
  } on ArgumentError {
    // The QR detector can report an impossible version for non-QR patterns.
    throw _unreadableCode;
  }
  final compact = CompactControlSheetScanPage.recognizes(code.text);
  final blocks = compact
      ? CompactControlSheetScanPage.decode(code.text).blocks
      : [ControlSheetScanPage.decode(code.text)];
  final qrLeft = compact ? compactSheetQrLeft : scanSheetQrLeft;
  final qrTop = compact ? compactSheetQrTop : scanSheetQrTop;
  final qrSize = compact ? compactSheetQrSize : scanSheetQrSize;
  final points = code.resultPoints;
  final dimension = code.version! * 4 + 17;
  final module = qrSize / dimension;
  final first = 3.5 * module;
  final last = qrSize - first;
  final hasAlignment = points.length == 4;
  final alignment = last - (hasAlignment ? 3 * module : 0);
  math.Point<double> point(int i) => math.Point(points[i].x, points[i].y);
  final qrTopLeft = math.Point(qrLeft + first, qrTop + first);
  final qrTopRight = math.Point(qrLeft + last, qrTop + first);
  final qrBottomLeft = math.Point(qrLeft + first, qrTop + last);
  final qrAnchors = [
    (qrTopLeft, point(1)),
    (qrTopRight, point(2)),
    (qrBottomLeft, point(0)),
  ];

  final approximate = _PageTransform(
    [
      qrTopLeft,
      qrTopRight,
      math.Point(qrLeft + alignment, qrTop + alignment),
      qrBottomLeft,
    ],
    [
      point(1),
      point(2),
      hasAlignment ? point(3) : point(0) + point(2) - point(1),
      point(0),
    ],
  );

  final pixels = _ScanPixels(
    Uint8List.sublistView(luminance.getMatrix()),
    source.width,
    source.height,
  );
  final transform = _alignScanPage(pixels, bitmap, approximate, qrAnchors);

  return ControlSheetScan(
    [for (final page in blocks) _readBlock(pixels, transform, page)],
    image.encodeJpg(
      image.copyResize(source, width: math.min(source.width, 980)),
      quality: 85,
    ),
  );
}

_PageTransform _alignScanPage(
  _ScanPixels pixels,
  qr.BinaryBitmap bitmap,
  _PageTransform approximate,
  List<(math.Point<double>, math.Point<double>)> anchors,
) {
  final qrWidth = anchors[0].$2.distanceTo(anchors[1].$2);
  final maxError = qrWidth * .055;

  double qrError(_PageTransform transform) => anchors.fold<double>(
    0,
    (error, anchor) =>
        math.max(error, transform.map(anchor.$1).distanceTo(anchor.$2)),
  );
  bool hasFourSquares(_PageTransform transform) => scanSheetCorners.every(
    (corner) => pixels.isHollowSquare(transform, corner),
  );

  final estimatedCorners = [
    for (final corner in scanSheetCorners)
      pixels.findMarker(approximate, corner),
  ];
  if (estimatedCorners.every((corner) => corner != null)) {
    final transform = _PageTransform(
      scanSheetCorners,
      estimatedCorners.nonNulls.toList(),
    );
    if (qrError(transform) <= maxError && hasFourSquares(transform)) {
      return transform;
    }
  }

  // A subpixel error inside the QR code can move the estimated bottom corners
  // by many pixels. Look for the hollow squares in the whole photo instead.
  final approximatePaper = _PageTransform(
    [
      anchors[0].$2,
      anchors[1].$2,
      anchors[1].$2 + anchors[2].$2 - anchors[0].$2,
      anchors[2].$2,
    ],
    [
      anchors[0].$1,
      anchors[1].$1,
      anchors[1].$1 + anchors[2].$1 - anchors[0].$1,
      anchors[2].$1,
    ],
  );
  final nominalMarkerWidth =
      qrWidth / anchors[0].$1.distanceTo(anchors[1].$1) * 14;
  final candidates = pixels.hollowSquares(
    bitmap.getBlackMatrix().get,
    minSpan: math.max(5, (nominalMarkerWidth * .35).floor()),
    maxSpan: (nominalMarkerWidth * 3).ceil(),
  );
  final located = [
    for (final point in candidates) (point, approximatePaper.map(point)),
  ];
  final choices = [
    for (final expected in scanSheetCorners)
      (located
              .where(
                (candidate) =>
                    (candidate.$2.x - expected.x).abs() < 250 &&
                    (candidate.$2.y - expected.y).abs() < 330,
              )
              .toList()
            ..sort(
              (a, b) => a.$2
                  .distanceTo(expected)
                  .compareTo(b.$2.distanceTo(expected)),
            ))
          .take(5)
          .map((candidate) => candidate.$1)
          .toList(),
  ];

  _PageTransform? best;
  var bestError = maxError;
  final selected = <math.Point<double>>[];
  void matchCorners(int index) {
    if (index == choices.length) {
      // The corners must describe a convex page in the same order as the PDF.
      for (var i = 0; i < selected.length; i++) {
        final a = selected[(i + 1) % 4] - selected[i];
        final b = selected[(i + 2) % 4] - selected[(i + 1) % 4];
        if (a.x * b.y - a.y * b.x <= 0) return;
      }
      final transform = _PageTransform(scanSheetCorners, selected);
      final error = qrError(transform);
      if (error < bestError && hasFourSquares(transform)) {
        best = transform;
        bestError = error;
      }
      return;
    }
    for (final corner in choices[index]) {
      if (selected.contains(corner)) continue;
      selected.add(corner);
      matchCorners(index + 1);
      selected.removeLast();
    }
  }

  matchCorners(0);
  return best ?? (throw _unreadableCorners);
}

ControlSheetScanBlock _readBlock(
  _ScanPixels pixels,
  _PageTransform transform,
  ControlSheetScanPage page,
) {
  final rows = [
    for (var row = 0; row < page.entryIds.length; row++)
      _readRow(pixels, transform, page, row),
  ];
  final unassignedAwards = <String>{};
  if (page.headerAwards && page.awards.isNotEmpty) {
    final firstPlaces = rows.where((row) => row.marks.contains('1'));
    final winner = firstPlaces.length == 1 ? firstPlaces.single : null;
    final clear =
        winner != null &&
        winner.marks.length == 1 &&
        winner.uncertain.isEmpty &&
        !rows.any((row) => row.uncertain.contains('1'));
    for (final (column, award) in page.awardColumns.indexed) {
      final darkness = pixels.bubbleDarkness(
        transform,
        page.awardBubble(column),
      );
      if (darkness >= .22) {
        if (!clear) {
          unassignedAwards.add(award);
        } else if (darkness >= .62) {
          winner.marks.add(award);
        } else {
          winner.uncertain.add(award);
        }
      }
    }
  }
  return (page: page, rows: rows, unassignedAwards: unassignedAwards);
}

ControlSheetScanRow _readRow(
  _ScanPixels pixels,
  _PageTransform transform,
  ControlSheetScanPage page,
  int row,
) {
  final marks = <String>{};
  final uncertain = <String>{};
  final columns = page.columns;
  for (var col = 0; col < columns.length; col++) {
    final label = columns[col];
    final center = page.bubble(row, col);
    final darkness = pixels.bubbleDarkness(transform, center);
    if (darkness >= .62) {
      marks.add(label);
    } else if (darkness >= .22) {
      uncertain.add(label);
    }
  }
  return ControlSheetScanRow(page.entryIds[row], marks, uncertain);
}

class _ScanPixels {
  final Uint8List values;
  final int width;
  final int height;

  _ScanPixels(this.values, this.width, this.height);

  double _sample(math.Point<double> point) {
    if (!point.x.isFinite || !point.y.isFinite) return 255;
    final x = point.x.round();
    final y = point.y.round();
    if (x < 0 || y < 0 || x >= width || y >= height) return 255;
    return values[y * width + x].toDouble();
  }

  // The hollow marker avoids being mistaken for a QR finder pattern.
  // Searching in PDF coordinates preserves the template's shape on angled scans.
  math.Point<double>? findMarker(
    _PageTransform transform,
    math.Point<double> expected,
  ) {
    const axes = [
      math.Point(1.0, 0.0),
      math.Point(0.0, 1.0),
      math.Point(-1.0, 0.0),
      math.Point(0.0, -1.0),
    ];
    double score(math.Point<double> center) {
      double at(math.Point<double> offset) =>
          _sample(transform.map(center + offset));
      var dark = 0.0;
      var light = at(const math.Point(0.0, 0.0));
      for (final axis in axes) {
        dark += at(axis * 5.5);
        light += at(axis * 3.5) + at(axis * 9);
      }
      return light / 9 - dark / 4;
    }

    var best = expected;
    var bestScore = -255.0;
    for (var y = -72; y <= 72; y += 2) {
      for (var x = -72; x <= 72; x += 2) {
        final sample = expected + math.Point(x.toDouble(), y.toDouble());
        final confidence = score(sample) - math.sqrt(x * x + y * y) * .35;
        if (confidence > bestScore) {
          best = sample;
          bestScore = confidence;
        }
      }
    }
    var refined = best;
    bestScore = score(best);
    for (var y = -2; y <= 2; y++) {
      for (var x = -2; x <= 2; x++) {
        final sample = best + math.Point(x.toDouble(), y.toDouble());
        final confidence = score(sample);
        if (confidence > bestScore) {
          refined = sample;
          bestScore = confidence;
        }
      }
    }
    return bestScore >= 45 ? transform.map(refined) : null;
  }

  List<math.Point<double>> hollowSquares(
    bool Function(int x, int y) isBlack, {
    required int minSpan,
    required int maxSpan,
  }) {
    final seen = Uint8List(width * height);
    final pending = <int>[];
    final candidates = <math.Point<double>>[];

    void visit(int x, int y) {
      final offset = y * width + x;
      if (seen[offset] != 0 || !isBlack(x, y)) return;
      seen[offset] = 1;
      pending.add(offset);
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        visit(x, y);
        if (pending.isEmpty) continue;
        var left = x, right = x, top = y, bottom = y, area = 0;
        while (pending.isNotEmpty) {
          final offset = pending.removeLast();
          final col = offset % width;
          final row = offset ~/ width;
          left = math.min(left, col);
          right = math.max(right, col);
          top = math.min(top, row);
          bottom = math.max(bottom, row);
          area++;
          if (col > 0) visit(col - 1, row);
          if (col + 1 < width) visit(col + 1, row);
          if (row > 0) visit(col, row - 1);
          if (row + 1 < height) visit(col, row + 1);
        }
        final spanX = right - left + 1;
        final spanY = bottom - top + 1;
        final density = area / (spanX * spanY);
        final center = math.Point((left + right) / 2, (top + bottom) / 2);
        if (spanX >= minSpan &&
            spanY >= minSpan &&
            spanX <= maxSpan &&
            spanY <= maxSpan &&
            spanX / spanY >= .45 &&
            spanX / spanY <= 2.2 &&
            density >= .18 &&
            density <= .78 &&
            !isBlack(center.x.round(), center.y.round())) {
          candidates.add(center);
        }
      }
    }
    return candidates;
  }

  bool isHollowSquare(_PageTransform transform, math.Point<double> center) {
    double at(double x, double y) =>
        _sample(transform.map(center + math.Point(x, y)));
    final interior = [at(0, 0), at(2, 0), at(-2, 0), at(0, 2), at(0, -2)]
      ..sort();
    final cutoff = interior[2] * .78;
    final sides = [at(5.5, 0), at(-5.5, 0), at(0, 5.5), at(0, -5.5)];
    final corners = [
      at(5.5, 5.5),
      at(-5.5, 5.5),
      at(5.5, -5.5),
      at(-5.5, -5.5),
    ];
    return sides.where((value) => value < cutoff).length >= 3 &&
        corners.where((value) => value < cutoff).length >= 3;
  }

  double bubbleDarkness(_PageTransform transform, math.Point<double> center) {
    double at(double x, double y) =>
        _sample(transform.map(center + math.Point(x, y)));
    final paper = [at(0, 8), at(0, -8), at(2, 8), at(-2, -8)]..sort();
    final cutoff = paper[2] * .75;
    var dark = 0;
    var total = 0;
    for (var y = -3; y <= 3; y++) {
      for (var x = -3; x <= 3; x++) {
        if (x * x + y * y > 12) continue;
        total++;
        if (at(x.toDouble(), y.toDouble()) < cutoff) dark++;
      }
    }
    return dark / total;
  }
}

/// Maps a quadrilateral to another using projective, rather than affine,
/// coordinates. Photos taken at an angle distort spacing across the page.
class _PageTransform {
  final List<double> _matrix;

  _PageTransform(List<math.Point<double>> from, List<math.Point<double>> to)
    : _matrix = _multiply(_squareTo(to), _inverse(_squareTo(from)));

  math.Point<double> map(math.Point<double> point) {
    final m = _matrix;
    final x = point.x;
    final y = point.y;
    final w = m[6] * x + m[7] * y + m[8];
    return math.Point(
      (m[0] * x + m[1] * y + m[2]) / w,
      (m[3] * x + m[4] * y + m[5]) / w,
    );
  }

  static List<double> _squareTo(List<math.Point<double>> p) {
    final right = p[1] - p[2];
    final bottom = p[3] - p[2];
    final offset = p[0] - p[1] + p[2] - p[3];
    final denominator = right.x * bottom.y - bottom.x * right.y;
    final g = (offset.x * bottom.y - bottom.x * offset.y) / denominator;
    final h = (right.x * offset.y - offset.x * right.y) / denominator;
    return [
      p[1].x - p[0].x + g * p[1].x,
      p[3].x - p[0].x + h * p[3].x,
      p[0].x,
      p[1].y - p[0].y + g * p[1].y,
      p[3].y - p[0].y + h * p[3].y,
      p[0].y,
      g,
      h,
      1,
    ];
  }

  static List<double> _inverse(List<double> m) => [
    m[4] * m[8] - m[5] * m[7],
    m[2] * m[7] - m[1] * m[8],
    m[1] * m[5] - m[2] * m[4],
    m[5] * m[6] - m[3] * m[8],
    m[0] * m[8] - m[2] * m[6],
    m[2] * m[3] - m[0] * m[5],
    m[3] * m[7] - m[4] * m[6],
    m[1] * m[6] - m[0] * m[7],
    m[0] * m[4] - m[1] * m[3],
  ];

  static List<double> _multiply(List<double> a, List<double> b) => [
    for (var row = 0; row < 3; row++)
      for (var col = 0; col < 3; col++)
        a[row * 3] * b[col] +
            a[row * 3 + 1] * b[col + 3] +
            a[row * 3 + 2] * b[col + 6],
  ];
}
