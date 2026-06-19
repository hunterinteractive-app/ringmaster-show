// lib/screens/admin/print_packs/print_pack_pdf_helpers.dart

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

const String kQrResultsEntryBaseUrl =
    'https://show.ringmasterone.com/#/qr-results-entry';

Future<pw.ThemeData> buildPrintPackPdfTheme() async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final italic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
  );
  final boldItalic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-BoldItalic.ttf'),
  );

  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
    boldItalic: boldItalic,
  );
}

Future<String?> savePdfToUserChosenLocation({
  required Uint8List bytes,
  required String suggestedName,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
      ),
    ],
  );

  if (location == null) return null;

  final file = XFile.fromData(
    bytes,
    mimeType: 'application/pdf',
    name: suggestedName,
  );

  await file.saveTo(location.path);
  return location.path;
}
