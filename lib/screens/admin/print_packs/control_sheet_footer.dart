import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared by populated and blank sheets. Keep this in MultiPage.footer so the
/// key also appears when a large class table continues onto another page.
pw.Widget controlSheetFooter({required pw.Widget details}) => pw.Column(
  mainAxisSize: pw.MainAxisSize.min,
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    pw.SizedBox(height: 6),
    pw.Text(
      'BOV = Best of Variety   |   BOG = Best of Group   |   BOB = Best of Breed',
      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
    ),
    pw.Text(
      'BOSV = Best Opposite Sex Variety   |   BOSG = Best Opposite Sex Group   |   BOS = Best Opposite Sex Breed',
      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
    ),
    pw.SizedBox(height: 3),
    details,
  ],
);
