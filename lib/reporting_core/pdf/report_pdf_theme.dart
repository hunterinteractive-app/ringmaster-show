import 'package:pdf/widgets.dart' as pw;

import '../assets/report_asset_loader.dart';

Future<pw.ThemeData> buildReportPdfTheme(
  ReportAssetLoader assets, {
  bool includeItalic = true,
}) async {
  final regular = pw.Font.ttf(
    await assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
  );
  if (!includeItalic) {
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }
  final italic = pw.Font.ttf(
    await assets.loadByteData('assets/fonts/NotoSans-Italic.ttf'),
  );
  final boldItalic = pw.Font.ttf(
    await assets.loadByteData('assets/fonts/NotoSans-BoldItalic.ttf'),
  );
  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
    boldItalic: boldItalic,
  );
}
