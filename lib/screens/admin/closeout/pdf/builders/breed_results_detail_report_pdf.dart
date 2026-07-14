// lib/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/breed_results_detail_report_data.dart';
import '../../utils/breed_results_detail_order.dart';

class BreedResultsDetailReportPdf {
  final Uint8List? logoBytes;
  final ReportAssetLoader assets;

  BreedResultsDetailReportPdf({required this.assets, this.logoBytes});

  Future<pw.ThemeData> _buildTheme() async {
    final regular = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
    );
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

  Future<ReportFileResult> buildFile(
    BreedResultsDetailReportData data,
    ReportRequest request,
  ) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);

    final showName = (request.showName ?? '').trim().isEmpty
        ? 'Unknown Show'
        : request.showName!.trim();

    final showDate = (request.showDate ?? '').trim().isEmpty
        ? 'Unknown Date'
        : request.showDate!.trim();

    final sections = data.sections.isNotEmpty
        ? data.sections
        : [
            BreedResultsDetailSection(
              showLetter: data.showLetter,
              judgeName: data.judgeName,
              breedAwards: data.breedAwards,
              varieties: data.varieties,
              noResultsFound: data.noResultsFound,
            ),
          ];

    for (final section in sections) {
      final isNoResults =
          section.noResultsFound ||
          (section.breedAwards.isEmpty && section.varieties.isEmpty);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(24),
          theme: theme,
          footer: (context) => _footer(context),
          build: (context) => [
            _buildHeader(
              breedName: data.breedName,
              scope: data.scope,
              showLetter: section.showLetter,
              judgeName: section.judgeName,
              showName: showName,
              showDate: showDate,
              arbaSanctionNumber: data.arbaSanction,
              breedSanctionNumber: data.breedSanctionNumber,
              breedClubName: data.breedClubName,
              hostClubName: data.hostClubName,
              showLocation: data.showLocation,
              secretaryName: data.secretaryName,
              secretaryEmail: data.secretaryEmail,
              secretaryPhone: data.secretaryPhone,
            ),
            pw.SizedBox(height: 12),
            if (isNoResults)
              _buildNoResultsBox(
                'No breed result details were found for this breed/show section.',
              )
            else
              ..._buildSections(
                breedAwards: section.breedAwards,
                varieties: section.varieties,
                isRabbit: breedResultsDetailUsesRabbitClassLayout(data.species),
              ),
          ],
        ),
      );
    }

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: _buildFileName(
        breedName: data.breedName,
        scope: data.scope,
        showLetter: data.showLetter,
        showName: showName,
      ),
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  String _buildFileName({
    required String breedName,
    required String scope,
    required String showLetter,
    required String showName,
  }) {
    String clean(String input) {
      return input
          // remove UUID / long id-like fragments
          .replaceAll(RegExp(r'\b[0-9a-fA-F\-]{8,}\b'), '')
          // remove non filename-safe chars
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          // collapse spaces to underscores
          .replaceAll(RegExp(r'\s+'), '_')
          // collapse multiple underscores
          .replaceAll(RegExp(r'_+'), '_')
          // trim leading/trailing underscores
          .replaceAll(RegExp(r'^_|_$'), '');
    }

    return '${clean(showName)}_${clean(breedName)}_Breed_Results_Detail_Report_${clean(scope.toUpperCase())}_${clean(showLetter.toUpperCase())}.pdf';
  }

  pw.Widget _buildHeader({
    required String breedName,
    required String scope,
    required String showLetter,
    required String judgeName,
    required String showName,
    required String showDate,
    required String arbaSanctionNumber,
    required String breedSanctionNumber,
    required String breedClubName,
    required String hostClubName,
    required String showLocation,
    required String secretaryName,
    required String secretaryEmail,
    required String secretaryPhone,
  }) {
    pw.Widget infoCell(String label, String value) {
      if (label.trim().isEmpty && value.trim().isEmpty) {
        return pw.SizedBox();
      }

      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 78,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 8.5)),
            ),
          ],
        ),
      );
    }

    pw.Widget infoRow2(
      String leftLabel,
      String leftValue,
      String rightLabel,
      String rightValue,
    ) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: infoCell(leftLabel, leftValue)),
          pw.SizedBox(width: 12),
          pw.Expanded(child: infoCell(rightLabel, rightValue)),
        ],
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Container(
            width: 85,
            height: 65,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(pw.MemoryImage(logoBytes!), fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Breed Results Detail Report',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(9),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    infoRow2('Show Name', showName, 'Show Date', showDate),
                    infoRow2(
                      'Host Club',
                      hostClubName,
                      'Location',
                      showLocation,
                    ),
                    infoRow2(
                      'Breed',
                      breedName,
                      'Show',
                      '$scope - $showLetter',
                    ),
                    if (breedClubName.trim().isNotEmpty)
                      infoRow2('Breed Club', breedClubName, '', ''),
                    infoRow2(
                      'Judge',
                      judgeName.isEmpty ? 'Judge Not Listed' : judgeName,
                      '',
                      '',
                    ),
                    infoRow2(
                      'ARBA Sanction',
                      arbaSanctionNumber,
                      'Breed Sanction',
                      breedSanctionNumber,
                    ),
                    infoRow2('Secretary', secretaryName, '', ''),
                    infoRow2(
                      'Contact',
                      [
                        if (secretaryEmail.trim().isNotEmpty)
                          secretaryEmail.trim(),
                        if (secretaryPhone.trim().isNotEmpty)
                          secretaryPhone.trim(),
                      ].join(' / '),
                      '',
                      '',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildNoResultsBox(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.grey100,
      ),
      child: pw.Text(message, style: const pw.TextStyle(fontSize: 10)),
    );
  }

  List<pw.Widget> _buildSections({
    required List<BreedAward> breedAwards,
    required List<VarietySection> varieties,
    required bool isRabbit,
  }) {
    final widgets = <pw.Widget>[];

    final overallAwards = breedAwards
        .where((a) => _isOverallAward(a.award))
        .toList();
    final breedOnlyAwards = breedAwards
        .where((a) => !_isOverallAward(a.award))
        .toList();

    if (overallAwards.isNotEmpty) {
      widgets.add(_sectionTitle('Overall Show Awards'));
      widgets.add(_buildAwardTable(overallAwards, includeBreed: true));
      widgets.add(pw.SizedBox(height: 12));
    }

    if (breedOnlyAwards.isNotEmpty) {
      widgets.add(_sectionTitle('Show Awards'));
      widgets.add(_buildAwardTable(breedOnlyAwards, includeBreed: true));
      widgets.add(pw.SizedBox(height: 12));
    }

    final regularVarieties = varieties
        .map(_regularOnlyVarietySection)
        .where((v) => _hasPrintableVarietyContent(v))
        .toList();
    final furWoolVarieties = varieties
        .map(_furWoolOnlyVarietySection)
        .where((v) => _hasPrintableVarietyContent(v))
        .toList();

    for (final variety in regularVarieties) {
      widgets.addAll(_buildVarietySection(variety, isRabbit: isRabbit));
    }

    if (furWoolVarieties.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(_sectionTitle('Fur / Wool Placements'));
      widgets.addAll(_buildFurWoolPlacementSections(furWoolVarieties));
    }

    return widgets;
  }

  List<pw.Widget> _buildVarietySection(
    VarietySection variety, {
    required bool isRabbit,
  }) {
    final widgets = <pw.Widget>[];

    widgets.add(_varietyHeader(variety.varietyName));

    if (variety.awards.isNotEmpty) {
      widgets.add(_buildAwardTable(variety.awards));
      widgets.add(pw.SizedBox(height: 8));
    }

    if (isRabbit) {
      for (final block in rabbitBreedResultsClassBlocks(variety)) {
        final classGroup = block.classSection;
        widgets.add(
          pw.Text(
            '${block.heading} — ${classGroup.animalsJudged} animals / ${classGroup.exhibitorsJudged} exhibitors judged',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        );
        widgets.add(pw.SizedBox(height: 4));

        if (classGroup.rows.isEmpty) {
          widgets.add(
            pw.Text(
              'No top 5 placements recorded.',
              style: const pw.TextStyle(fontSize: 8),
            ),
          );
        } else {
          widgets.add(_buildPlacementTable(classGroup.rows));
        }

        widgets.add(pw.SizedBox(height: 8));
      }
    } else {
      for (final sexSection in variety.sexSections) {
        widgets.add(_sexHeader(sexSection.sexLabel));

        for (final classGroup in sexSection.classes) {
          widgets.add(
            pw.Text(
              '${classGroup.className} — ${classGroup.animalsJudged} animals / ${classGroup.exhibitorsJudged} exhibitors judged',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          );
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(
            classGroup.rows.isEmpty
                ? pw.Text(
                    'No top 5 placements recorded.',
                    style: const pw.TextStyle(fontSize: 8),
                  )
                : _buildPlacementTable(classGroup.rows),
          );
          widgets.add(pw.SizedBox(height: 8));
        }

        widgets.add(pw.SizedBox(height: 6));
      }
    }

    widgets.add(pw.SizedBox(height: 8));
    return widgets;
  }

  VarietySection _regularOnlyVarietySection(VarietySection variety) {
    return VarietySection(
      varietyName: variety.varietyName,
      awards: variety.awards
          .where((award) => !_isFurWoolAward(award, variety))
          .toList(),
      sexSections: variety.sexSections
          .map((sexSection) {
            final classes = sexSection.classes
                .map((classGroup) {
                  final rows = classGroup.rows
                      .where(
                        (row) =>
                            !_isFurWoolPlacementRow(row, classGroup, variety),
                      )
                      .toList();

                  return ClassSection(
                    className: classGroup.className,
                    entryCount: classGroup.entryCount,
                    placedCount: classGroup.placedCount,
                    animalsJudged: classGroup.animalsJudged,
                    exhibitorsJudged: classGroup.exhibitorsJudged,
                    rows: rows,
                  );
                })
                .where((classGroup) => classGroup.rows.isNotEmpty)
                .toList(growable: false);

            return SexSection(
              sexLabel: sexSection.sexLabel,
              classes: classes.cast<ClassSection>(),
            );
          })
          .where((sexSection) => sexSection.classes.isNotEmpty)
          .toList(),
    );
  }

  VarietySection _furWoolOnlyVarietySection(VarietySection variety) {
    return VarietySection(
      varietyName: variety.varietyName,
      awards: variety.awards
          .where((award) => _isFurWoolAward(award, variety))
          .toList(),
      sexSections: variety.sexSections
          .map((sexSection) {
            final classes = sexSection.classes
                .map((classGroup) {
                  final rows = classGroup.rows
                      .where(
                        (row) =>
                            _isFurWoolPlacementRow(row, classGroup, variety),
                      )
                      .toList();

                  return ClassSection(
                    className: classGroup.className,
                    entryCount: classGroup.entryCount,
                    placedCount: classGroup.placedCount,
                    animalsJudged: classGroup.animalsJudged,
                    exhibitorsJudged: classGroup.exhibitorsJudged,
                    rows: rows,
                  );
                })
                .where((classGroup) => classGroup.rows.isNotEmpty)
                .toList(growable: false);

            return SexSection(
              sexLabel: sexSection.sexLabel,
              classes: classes.cast<ClassSection>(),
            );
          })
          .where((sexSection) => sexSection.classes.isNotEmpty)
          .toList(),
    );
  }

  bool _hasPrintableVarietyContent(VarietySection variety) {
    if (variety.awards.isNotEmpty) return true;
    for (final sexSection in variety.sexSections) {
      for (final classGroup in sexSection.classes) {
        if (classGroup.rows.isNotEmpty) return true;
      }
    }
    return false;
  }

  bool _isFurWoolAward(BreedAward award, VarietySection variety) {
    if (award.pointsCategory.trim().isNotEmpty) return true;
    return _isFurWoolTextMatch([
      award.variety,
      award.className,
      variety.varietyName,
    ]);
  }

  bool _isFurWoolPlacementRow(
    ClassEntry row,
    ClassSection classGroup,
    VarietySection variety,
  ) {
    if (row.pointsCategory.trim().isNotEmpty) return true;
    return _isFurWoolTextMatch([
      row.variety,
      classGroup.className,
      variety.varietyName,
    ]);
  }

  bool _isFurWoolTextMatch(List<String> values) {
    for (final value in values) {
      final normalized = value.toLowerCase().trim();
      if (normalized.contains('fur') || normalized.contains('wool')) {
        return true;
      }
    }
    return false;
  }

  List<pw.Widget> _buildFurWoolPlacementSections(
    List<VarietySection> varieties,
  ) {
    final widgets = <pw.Widget>[];
    final categoryOrder = <String>['White', 'Colored', 'Uncategorized'];
    final awardsByCategory = <String, List<BreedAward>>{};
    final rowsByCategory = <String, List<ClassEntry>>{};
    final animalsJudgedByCategory = <String, int>{};
    final exhibitorsJudgedByCategory = <String, int>{};

    String categoryForAward(BreedAward award, VarietySection variety) {
      final category = _categoryLabelFromValues([
        award.pointsCategory,
        award.variety,
        award.className,
        variety.varietyName,
      ]);
      return category.isEmpty ? 'Uncategorized' : category;
    }

    String categoryForRow(
      ClassEntry row,
      ClassSection classGroup,
      VarietySection variety,
    ) {
      final category = _categoryLabelFromValues([
        row.pointsCategory,
        row.variety,
        classGroup.className,
        variety.varietyName,
      ]);
      return category.isEmpty ? 'Uncategorized' : category;
    }

    for (final variety in varieties) {
      for (final award in variety.awards) {
        final category = categoryForAward(award, variety);
        awardsByCategory.putIfAbsent(category, () => <BreedAward>[]).add(award);
        if (!categoryOrder.contains(category)) categoryOrder.add(category);
      }

      for (final sexSection in variety.sexSections) {
        for (final classGroup in sexSection.classes) {
          final classCategories = classGroup.rows
              .map((row) => categoryForRow(row, classGroup, variety))
              .where((category) => category.isNotEmpty)
              .toSet();

          for (final category in classCategories) {
            final currentAnimals = animalsJudgedByCategory[category];
            final currentExhibitors = exhibitorsJudgedByCategory[category];
            if (currentAnimals == null ||
                classGroup.animalsJudged > currentAnimals) {
              animalsJudgedByCategory[category] = classGroup.animalsJudged;
            }
            if (currentExhibitors == null ||
                classGroup.exhibitorsJudged > currentExhibitors) {
              exhibitorsJudgedByCategory[category] =
                  classGroup.exhibitorsJudged;
            }
          }

          for (final row in classGroup.rows) {
            final category = categoryForRow(row, classGroup, variety);
            rowsByCategory.putIfAbsent(category, () => <ClassEntry>[]).add(row);
            if (!categoryOrder.contains(category)) categoryOrder.add(category);
          }
        }
      }
    }

    for (final category in categoryOrder) {
      final awards = awardsByCategory[category] ?? const <BreedAward>[];
      final rows = [...(rowsByCategory[category] ?? const <ClassEntry>[])]
        ..sort((a, b) {
          final aPlace = int.tryParse(a.place) ?? 9999;
          final bPlace = int.tryParse(b.place) ?? 9999;
          final placeCompare = aPlace.compareTo(bPlace);
          if (placeCompare != 0) return placeCompare;
          return a.exhibitorName.compareTo(b.exhibitorName);
        });

      if (awards.isEmpty && rows.isEmpty) continue;

      widgets.add(_varietyHeader(category));

      // Display the full judged class size supplied by the loader, not merely
      // the number of top-five placement rows printed in the table.
      final animalsJudged = animalsJudgedByCategory[category] ?? rows.length;
      final exhibitorsJudged =
          exhibitorsJudgedByCategory[category] ??
          rows
              .map((row) => row.exhibitorName.trim().toLowerCase())
              .where((name) => name.isNotEmpty)
              .toSet()
              .length;

      widgets.add(
        pw.Text(
          '$animalsJudged ${animalsJudged == 1 ? 'animal' : 'animals'} / '
          '$exhibitorsJudged ${exhibitorsJudged == 1 ? 'exhibitor' : 'exhibitors'} judged',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      );
      widgets.add(pw.SizedBox(height: 4));

      if (awards.isNotEmpty) {
        widgets.add(_buildAwardTable(awards));
        widgets.add(pw.SizedBox(height: 8));
      }

      if (rows.isEmpty) {
        widgets.add(
          pw.Text(
            'No top 5 wool placements recorded.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        );
      } else {
        widgets.add(_buildFurWoolPlacementTable(rows));
      }

      widgets.add(pw.SizedBox(height: 10));
    }

    return widgets;
  }

  pw.Widget _buildFurWoolPlacementTable(List<ClassEntry> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Place', 'Animal', 'Category', 'Exhibitor', 'Points'],
      data: rows
          .map(
            (row) => [
              row.place,
              row.animal,
              row.pointsCategory.trim().isNotEmpty
                  ? row.pointsCategory
                  : row.variety,
              row.exhibitorName,
              _points(row.pointsEarned),
            ],
          )
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      columnWidths: {
        0: const pw.FixedColumnWidth(32),
        1: const pw.FlexColumnWidth(1.35),
        2: const pw.FixedColumnWidth(58),
        3: const pw.FlexColumnWidth(1.65),
      },
    );
  }

  String _categoryLabelFromValues(List<String> values) {
    for (final value in values) {
      final normalized = value
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('_', ' ')
          .trim();

      if (normalized.contains('white')) return 'White';
      if (normalized.contains('colored') || normalized.contains('colour')) {
        return 'Colored';
      }
      if (normalized.contains('color') && !normalized.contains('white')) {
        return 'Colored';
      }
    }

    return '';
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _varietyHeader(String title) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _sexHeader(String title) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 5, top: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      child: pw.Text(
        title.toUpperCase(),
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  String _awardLabel(String code) {
    switch (code.toUpperCase().trim()) {
      case 'BJV':
        return 'Best Junior Variety';
      case 'BIV':
        return 'Best Intermediate Variety';
      case 'BSV':
        return 'Best Senior Variety';
      case 'BJB':
        return 'Best Junior of Breed';
      case 'BIB':
        return 'Best Intermediate of Breed';
      case 'BSB':
        return 'Best Senior of Breed';
      case 'BOV':
        return 'Best of Variety';
      case 'BOSV':
        return 'Best Opposite Sex of Variety';
      case 'BOB':
        return 'Best of Breed';
      case 'BOSB':
        return 'Best Opposite Sex of Breed';
      case 'BIS':
        return 'Best in Show';
      case 'RIS':
      case 'RBIS':
        return 'Reserve in Show';
      case 'B4C':
        return 'Best 4-Class';
      case 'B6C':
        return 'Best 6-Class';
      case 'BOG':
        return 'Best of Group';
      case 'BOSG':
        return 'Best Opposite Sex of Group';
      case 'HM':
        return 'Honorable Mention';
      default:
        return code;
    }
  }

  bool _isOverallAward(String code) {
    switch (code.toUpperCase().trim()) {
      case 'BIS':
      case 'RIS':
      case 'RBIS':
      case 'B4C':
      case 'B6C':
      case 'HM':
        return true;
      default:
        return false;
    }
  }

  pw.Widget _buildAwardTable(
    List<BreedAward> rows, {
    bool includeBreed = false,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: includeBreed
          ? const [
              'Award',
              'Animal',
              'Breed',
              'Variety',
              'Class',
              'Sex',
              'Judged',
              'Points',
            ]
          : const [
              'Award',
              'Animal',
              'Variety',
              'Class',
              'Sex',
              'Judged',
              'Points',
            ],
      data: rows
          .map(
            (r) => includeBreed
                ? [
                    _awardLabel(r.award),
                    r.animal,
                    r.breedName,
                    r.variety,
                    r.className,
                    r.sex,
                    r.animalsJudged > 0
                        ? '${r.animalsJudged}/${r.exhibitorsJudged}'
                        : '',
                    _points(r.pointsEarned),
                  ]
                : [
                    _awardLabel(r.award),
                    r.animal,
                    r.variety,
                    r.className,
                    r.sex,
                    r.animalsJudged > 0
                        ? '${r.animalsJudged}/${r.exhibitorsJudged}'
                        : '',
                    _points(r.pointsEarned),
                  ],
          )
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      columnWidths: includeBreed
          ? {
              0: const pw.FixedColumnWidth(86),
              1: const pw.FlexColumnWidth(1.05),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(0.9),
              5: const pw.FixedColumnWidth(30),
              6: const pw.FixedColumnWidth(40),
              7: const pw.FixedColumnWidth(36),
            }
          : {
              0: const pw.FixedColumnWidth(86),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(0.9),
              4: const pw.FixedColumnWidth(30),
              5: const pw.FixedColumnWidth(40),
              6: const pw.FixedColumnWidth(36),
            },
    );
  }

  pw.Widget _buildPlacementTable(List<ClassEntry> rows) {
    final includeCategory = rows.any((r) => r.pointsCategory.trim().isNotEmpty);

    return pw.TableHelper.fromTextArray(
      headers: includeCategory
          ? const [
              'Place',
              'Animal',
              'Sex',
              'Variety',
              'Category',
              'Exhibitor',
              'Points',
            ]
          : const ['Place', 'Animal', 'Sex', 'Variety', 'Exhibitor', 'Points'],
      data: rows
          .map(
            (r) => includeCategory
                ? [
                    r.place,
                    r.animal,
                    r.sex,
                    r.variety,
                    r.pointsCategory,
                    r.exhibitorName,
                    _points(r.pointsEarned),
                  ]
                : [
                    r.place,
                    r.animal,
                    r.sex,
                    r.variety,
                    r.exhibitorName,
                    _points(r.pointsEarned),
                  ],
          )
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      columnWidths: includeCategory
          ? {
              0: const pw.FixedColumnWidth(32),
              1: const pw.FlexColumnWidth(1.25),
              2: const pw.FixedColumnWidth(30),
              3: const pw.FlexColumnWidth(1.05),
              4: const pw.FixedColumnWidth(48),
              5: const pw.FlexColumnWidth(1.5),
              6: const pw.FixedColumnWidth(36),
            }
          : {
              0: const pw.FixedColumnWidth(32),
              1: const pw.FlexColumnWidth(1.3),
              2: const pw.FixedColumnWidth(30),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.6),
              5: const pw.FixedColumnWidth(36),
            },
    );
  }

  String _points(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by RingMaster Show',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
