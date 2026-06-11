// lib/screens/admin/closeout/models/exhibitor/payback_report_data.dart

class PaybackReportData {
  final String showId;
  final String showName;
  final String? showDate;
  final String? showLocation;

  final List<PaybackExhibitorSummary> exhibitors;
  final int grandTotalCents;

  const PaybackReportData({
    required this.showId,
    required this.showName,
    required this.showDate,
    required this.showLocation,
    required this.exhibitors,
    required this.grandTotalCents,
  });

  bool get hasPaybacks => exhibitors.isNotEmpty;

  int get totalExhibitors => exhibitors.length;
}

class PaybackExhibitorSummary {
  final String exhibitorId;
  final String exhibitorNumber;
  final String exhibitorName;
  final String mailingAddress;
  final int totalCents;
  final List<PaybackBreakdownRow> rows;

  const PaybackExhibitorSummary({
    required this.exhibitorId,
    required this.exhibitorNumber,
    required this.exhibitorName,
    required this.mailingAddress,
    required this.totalCents,
    required this.rows,
  });
}

class PaybackBreakdownRow {
  final String? sectionId;
  final String sectionLabel;
  final String? sectionKind;
  final String? showLetter;

  final String sourceType;
  final String? awardCode;
  final String awardLabel;

  final String entryId;
  final String? animalId;

  final String breedName;
  final String? varietyName;
  final String? groupName;
  final String? className;
  final String? sex;
  final String? tattoo;

  final int? placement;
  final String? placementLabel;
  final int? eligibleCount;
  final int amountCents;
  final String? paybackNote;

  const PaybackBreakdownRow({
    required this.sectionId,
    required this.sectionLabel,
    required this.sectionKind,
    required this.showLetter,
    required this.sourceType,
    required this.awardCode,
    required this.awardLabel,
    required this.entryId,
    required this.animalId,
    required this.breedName,
    required this.varietyName,
    required this.groupName,
    required this.className,
    required this.sex,
    required this.tattoo,
    required this.placement,
    required this.placementLabel,
    required this.eligibleCount,
    required this.amountCents,
    required this.paybackNote,
  });

  bool get isClassPlacement => sourceType == 'class_placement';
  bool get isSpecialMoney => sourceType == 'special_money';

  String get sourceLabel {
    if (isClassPlacement) return 'Class';
    if (isSpecialMoney) return 'Special';
    return sourceType;
  }

  String get animalDescription {
    final parts = <String>[
      breedName,
      if ((varietyName ?? '').trim().isNotEmpty) varietyName!.trim(),
      if ((groupName ?? '').trim().isNotEmpty) groupName!.trim(),
      if ((className ?? '').trim().isNotEmpty) className!.trim(),
      if ((sex ?? '').trim().isNotEmpty) sex!.trim(),
    ];

    return parts.where((p) => p.trim().isNotEmpty).join(' • ');
  }

  String get tattooDisplay {
    final value = tattoo?.trim() ?? '';
    return value.isEmpty ? '—' : value;
  }

  factory PaybackBreakdownRow.fromJson(Map<String, dynamic> json) {
    return PaybackBreakdownRow(
      sectionId: json['section_id']?.toString(),
      sectionLabel: (json['section_label'] ?? '').toString(),
      sectionKind: json['section_kind']?.toString(),
      showLetter: json['show_letter']?.toString(),
      sourceType: (json['source_type'] ?? '').toString(),
      awardCode: json['award_code']?.toString(),
      awardLabel: (json['award_label'] ?? '').toString(),
      entryId: (json['entry_id'] ?? '').toString(),
      animalId: json['animal_id']?.toString(),
      breedName: (json['breed_name'] ?? '').toString(),
      varietyName: json['variety_name']?.toString(),
      groupName: json['group_name']?.toString(),
      className: json['class_name']?.toString(),
      sex: json['sex']?.toString(),
      tattoo: json['tattoo']?.toString(),
      placement: _intOrNull(json['placement']),
      placementLabel: json['placement_label']?.toString(),
      eligibleCount: _intOrNull(json['eligible_count']),
      amountCents: _intOrZero(json['amount_cents']),
      paybackNote: json['payback_note']?.toString(),
    );
  }
}

int _intOrZero(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

int? _intOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}