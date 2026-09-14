import '../../data/loaders/breed_awards_overview_loader.dart';
import '../../data/loaders/exhibitor_mailing_labels_loader.dart';
import '../../models/exhibitor/entered_exhibitors_contact_report_data.dart';
import '../../models/exhibitor/entered_exhibitors_list_report_data.dart';
import '../../models/exhibitor/exhibitor_report_data.dart';
import '../../models/exhibitor/payback_report_data.dart';
import '../../models/exhibitor/ribbon_payout_report_data.dart';
import '../../models/judge/breed_judged_totals_report_data.dart';
import '../../models/judge/judge_report_data.dart';
import '../../models/legs/legs_certificate_data.dart';
import '../../models/paid/paid_exhibitor_report_data.dart';
import '../../models/unpaid/unpaid_balances_report_data.dart';
import '../report_csv.dart';

class OtherReportsCsvBuilder {
  static const reportNames = {
    'breed_awards_overview',
    'breed_judged_totals_report',
    'entered_exhibitors_contact_report',
    'exhibitor_mailing_labels',
    'entered_exhibitors_list_report',
    'exhibitor_print_pack',
    'judge_report',
    'paid_exhibitor_report',
    'payback_report',
    'ribbon_payout_report',
    'unpaid_balances_report',
    'michelles_special_report',
  };

  ReportCsvTable build(
    Object data, {
    MailingLabelMode labelMode = MailingLabelMode.address,
    MailingLabelSort labelSort = MailingLabelSort.lastName,
  }) {
    switch (data) {
      case BreedAwardsOverviewData():
        return ReportCsvTable(
          [
            'Section',
            'Species',
            'Award',
            'Ear #',
            'Coop #',
            'Breed',
            'Variety',
            'Class',
            'Sex',
            'Exhibitor',
          ],
          [
            for (final r in data.rows)
              [
                r.sectionLabel,
                r.species,
                r.award,
                r.tattoo,
                r.coop,
                r.breed,
                r.variety,
                r.className,
                r.sex,
                r.exhibitor,
              ],
          ],
        );
      case BreedJudgedTotalsReportData():
        return ReportCsvTable(
          ['Section', 'Judged As', 'Breed', 'Species', 'Total Judged'],
          [
            if (data.showBreakdowns.isNotEmpty)
              for (final section in data.showBreakdowns) ...[
                for (final r in section.breedRows)
                  [section.label, 'Breed', r.breed, r.species, r.totalJudged],
                for (final r in section.furRows)
                  [section.label, 'Fur', r.breed, r.species, r.totalJudged],
              ]
            else ...[
              for (final r in data.breedRows)
                [data.scopeLabel, 'Breed', r.breed, r.species, r.totalJudged],
              for (final r in data.furRows)
                [data.scopeLabel, 'Fur', r.breed, r.species, r.totalJudged],
            ],
          ],
        );
      case EnteredExhibitorsContactReportData():
        return ReportCsvTable(
          ['Exhibitor', 'Address', 'Email', 'Phone'],
          [
            for (final r in data.rows)
              [r.exhibitorName, r.address, r.email, r.phone],
          ],
        );
      case EnteredExhibitorsListReportData():
        return ReportCsvTable(
          ['Exhibitor Number', 'Last Name', 'First Name', 'Display Name'],
          [
            for (final r in data.rows)
              [r.exhibitorNumber, r.lastName, r.firstName, r.displayName],
          ],
        );
      case List<ExhibitorMailingLabel>():
        final eligible = data
            .where(
              (r) =>
                  r.name.isNotEmpty &&
                  (labelMode == MailingLabelMode.address
                      ? r.hasMailingAddress && r.address.isNotEmpty
                      : r.number.isNotEmpty),
            )
            .toList();
        final labels = sortExhibitorMailingLabels(eligible, labelSort);
        return labelMode == MailingLabelMode.address
            ? ReportCsvTable(
                ['Exhibitor', 'Mailing Address'],
                [
                  for (final r in labels) [r.name, r.address.join('\n')],
                ],
              )
            : ReportCsvTable(
                ['Exhibitor', 'Exhibitor Number'],
                [
                  for (final r in labels) [r.name, r.number],
                ],
              );
      case JudgeReportData():
        return ReportCsvTable(
          [
            'Judge',
            'ARBA Number',
            'Judge Email',
            'Judge Phone',
            'Section',
            'Species',
            'Judged As',
            'Breed',
            'Variety',
            'Class',
            'Sex',
            'Ear #',
            'Animal',
            'Exhibitor',
            'Placement',
            'Awards',
            'Notes',
          ],
          [
            for (final judge in data.judges)
              for (final r in judge.rows)
                [
                  judge.displayName,
                  judge.arbaNumber,
                  judge.email,
                  judge.phone,
                  r.sectionLabel,
                  r.species,
                  r.judgedAsLabel,
                  r.breed,
                  r.varietyLabel,
                  r.className,
                  r.sex,
                  r.tattoo,
                  r.animalName,
                  r.exhibitorName,
                  r.placementLabel,
                  r.awardsLabel,
                  r.notes,
                ],
          ],
        );
      case RibbonPayoutReportData():
        List<Object?> row(RibbonPayoutRow r, String scope, String letter) => [
          scope,
          letter,
          r.exhibitorNumber,
          r.exhibitorName,
          r.first,
          r.second,
          r.third,
          r.fourth,
          r.fifth,
        ];
        return ReportCsvTable(
          [
            'Classification',
            'Show Letter',
            'Exhibitor Number',
            'Exhibitor',
            '1st',
            '2nd',
            '3rd',
            '4th',
            '5th',
          ],
          [
            if (data.sections.isNotEmpty)
              for (final s in data.sections)
                for (final r in s.rows) row(r, s.classification, s.showLetter)
            else
              for (final r in data.rows)
                row(r, data.classification, data.showLetter),
          ],
        );
      case PaybackReportData():
        return ReportCsvTable(
          [
            'Exhibitor Number',
            'Exhibitor',
            'Email',
            'Mailing Address',
            'Section',
            'Source',
            'Award',
            'Ear #',
            'Breed',
            'Variety',
            'Group',
            'Class',
            'Sex',
            'Placement',
            'Eligible Count',
            'Amount',
            'Note',
          ],
          [
            for (final ex in data.exhibitors)
              for (final r in ex.rows)
                [
                  ex.exhibitorNumber,
                  ex.exhibitorName,
                  ex.email,
                  ex.mailingAddress,
                  r.sectionLabel,
                  r.sourceLabel,
                  r.awardLabel,
                  r.tattoo,
                  r.breedName,
                  r.varietyName,
                  r.groupName,
                  r.className,
                  r.sex,
                  r.placementLabel ?? r.placement,
                  r.eligibleCount,
                  r.amountCents / 100,
                  r.paybackNote,
                ],
          ],
        );
      case PaidExhibitorReportData():
        return ReportCsvTable(_balanceHeaders, [
          for (final r in data.rows)
            [
              r.exhibitorName,
              r.exhibitorType,
              r.email,
              r.phone,
              r.addressLine1,
              r.addressLine2,
              r.city,
              r.state,
              r.zip,
              r.arbaNumber,
              r.paymentStatus,
              r.source,
              r.sections
                  .map(
                    (s) => '${s.label}: ${s.count} entries, ${s.furCount} fur',
                  )
                  .join('; '),
              r.entryCount,
              r.furCount,
              r.entriesSubtotal,
              r.furSubtotal,
              r.subtotal,
              r.showFee,
              r.discount,
              r.calculatedTotal,
              r.paidOnline,
              r.paidManual,
              r.refunded,
              r.amountPaid,
              r.balanceDue,
              data.currency,
            ],
        ]);
      case UnpaidBalancesReportData():
        return ReportCsvTable(_balanceHeaders, [
          for (final r in data.rows)
            [
              r.exhibitorName,
              r.exhibitorType,
              r.email,
              r.phone,
              r.addressLine1,
              r.addressLine2,
              r.city,
              r.state,
              r.zip,
              r.arbaNumber,
              r.paymentStatus,
              r.source,
              r.sections
                  .map(
                    (s) => '${s.label}: ${s.count} entries, ${s.furCount} fur',
                  )
                  .join('; '),
              r.entryCount,
              r.furCount,
              r.entriesSubtotal,
              r.furSubtotal,
              r.subtotal,
              r.showFee,
              r.discount,
              r.calculatedTotal,
              r.paidOnline,
              r.paidManual,
              r.refunded,
              r.paidOnline + r.paidManual - r.refunded,
              r.totalDue,
              data.currency,
            ],
        ]);
      case ExhibitorPrintPackCsvData():
        return ReportCsvTable(_printPackHeaders, data.rows);
      default:
        throw ArgumentError('Unsupported CSV report data: ${data.runtimeType}');
    }
  }

  static const _balanceHeaders = [
    'Exhibitor',
    'Exhibitor Type',
    'Email',
    'Phone',
    'Address Line 1',
    'Address Line 2',
    'City',
    'State',
    'ZIP',
    'ARBA Number',
    'Payment Status',
    'Source',
    'Sections',
    'Entries',
    'Fur Entries',
    'Entry Fees',
    'Fur Fees',
    'Subtotal',
    'Show Fees',
    'Discount',
    'Total Charges',
    'Paid Online',
    'Paid Manual',
    'Refunded',
    'Net Paid',
    'Balance Due',
    'Currency',
  ];
  static const _printPackHeaders = [
    'Record Type',
    'Exhibitor',
    'Exhibitor Number',
    'Address',
    'Scope',
    'Species',
    'Section',
    'Ear #',
    'Breed',
    'Variety',
    'Class',
    'Sex',
    'Placement',
    'Animals Count',
    'Exhibitors Count',
    'Awards / Win',
    'Judge',
    'Earned Leg',
    'Specialty Points',
    'Total Points',
    'Certificate ID',
    'Leg Rule',
    'Leg Rule Description',
    'Sanction Number',
    'Show Date',
  ];
}

class ExhibitorPrintPackCsvData {
  final List<List<Object?>> rows = [];

  void addReport(
    ExhibitorReportData data, {
    required String number,
    required String scope,
    required String species,
  }) {
    for (final r in data.entries) {
      rows.add([
        'Result',
        data.exhibitorName,
        number,
        '${data.exhibitorAddress}\n${data.exhibitorCityStateZip}',
        scope,
        species,
        r.showSection,
        r.tattoo,
        r.breed,
        r.variety,
        r.className,
        r.sex,
        r.placing,
        r.classCount,
        r.exhibitorCount,
        r.awardsText,
        r.judgeName,
        r.earnedLeg ? 'Yes' : 'No',
        r.specialtyPoints,
        r.totalPoints,
        '',
        '',
        '',
        '',
        data.showDate,
      ]);
    }
  }

  void addLegs(
    List<LegsCertificateData> legs, {
    required String scope,
    required String species,
  }) {
    for (final r in legs) {
      rows.add([
        'Leg',
        r.exhibitorName,
        r.exhibitorNumber,
        r.ownerAddress,
        scope,
        species,
        '',
        r.earNumber,
        r.breed,
        r.variety,
        r.className,
        r.sex,
        '',
        r.animalsCount,
        r.exhibitorsCount,
        r.winCode,
        r.judgeName,
        'Yes',
        '',
        '',
        r.certificateId,
        r.legRule,
        r.legRuleDescription,
        r.sanctionNumber,
        r.showDate?.toIso8601String().split('T').first,
      ]);
    }
  }
}
