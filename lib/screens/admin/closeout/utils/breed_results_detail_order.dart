import '../models/clubs/breed_results_detail_report_data.dart';

bool breedResultsDetailUsesRabbitClassLayout(String species) =>
    species.trim().toLowerCase() == 'rabbit';

const Map<String, int> _awardOrder = {
  'BIS': 0,
  'B4C': 1,
  'B6C': 2,
  'RIS': 3,
  'RBIS': 3,
  'HM': 4,
  'BOB': 5,
  'BOSB': 6,
  'BOS': 6,
  'BSB': 7,
  'BIB': 8,
  'BJB': 9,
  'BOG': 10,
  'BOSG': 11,
  'BOV': 12,
  'BOSV': 13,
  'BSV': 14,
  'BIV': 15,
  'BJV': 16,
};

int breedResultsDetailAwardRank(String awardCode) =>
    _awardOrder[awardCode.trim().toUpperCase()] ?? 999;

int compareBreedResultsDetailAwards(BreedAward a, BreedAward b) {
  final rank = breedResultsDetailAwardRank(
    a.award,
  ).compareTo(breedResultsDetailAwardRank(b.award));
  if (rank != 0) return rank;

  for (final pair in [
    (a.breedName, b.breedName),
    (a.variety, b.variety),
    (a.className, b.className),
    (a.sex, b.sex),
    (a.animal, b.animal),
  ]) {
    final compared = pair.$1.trim().toLowerCase().compareTo(
      pair.$2.trim().toLowerCase(),
    );
    if (compared != 0) return compared;
  }
  return 0;
}

int compareBreedResultsDetailSectionNames(String a, String b) =>
    a.trim().toLowerCase().compareTo(b.trim().toLowerCase());

int _orderValue(Object? value) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString().trim()) ?? 9999;
}

int compareRabbitVarietyJudgingOrder(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final group = _orderValue(
    a['group_sort_order'],
  ).compareTo(_orderValue(b['group_sort_order']));
  if (group != 0) return group;

  final variety = _orderValue(
    a['variety_sort_order'],
  ).compareTo(_orderValue(b['variety_sort_order']));
  if (variety != 0) return variety;

  final aName = (a['variety_name'] ?? a['variety'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final bName = (b['variety_name'] ?? b['variety'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return aName.compareTo(bName);
}

String _normalizedWords(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[-_/]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

int _rabbitAgeOrder(String value) {
  final text = _normalizedWords(value);
  if (RegExp(r'\b(senior|sr)\b').hasMatch(text)) return 0;
  if (RegExp(r'\b(intermediate|inter|6 8)\b').hasMatch(text)) return 1;
  if (RegExp(r'\b(junior|jr)\b').hasMatch(text)) return 2;
  return 99;
}

int _rabbitSexOrder(String className, String sexLabel) {
  final text = _normalizedWords('$className $sexLabel');
  if (RegExp(r'\b(buck|bucks|male)\b').hasMatch(text)) return 0;
  if (RegExp(r'\b(doe|does|female)\b').hasMatch(text)) return 1;
  return 9;
}

int rabbitBreedResultsClassSortOrder(String className, String sexLabel) {
  final age = _rabbitAgeOrder(className);
  final sex = _rabbitSexOrder(className, sexLabel);
  if (age == 99 || sex > 1) return 999;
  return age * 2 + sex;
}

String rabbitBreedResultsClassHeading(String className, String sexLabel) {
  final age = switch (_rabbitAgeOrder(className)) {
    0 => 'Senior',
    1 => 'Intermediate',
    2 => 'Junior',
    _ => className.trim(),
  };
  final sex = switch (_rabbitSexOrder(className, sexLabel)) {
    0 => 'Buck',
    1 => 'Doe',
    _ => sexLabel.trim(),
  };
  return [age, sex].where((part) => part.isNotEmpty).join(' ').trim();
}

class RabbitBreedResultsClassBlock {
  final String heading;
  final ClassSection classSection;

  const RabbitBreedResultsClassBlock({
    required this.heading,
    required this.classSection,
  });
}

List<RabbitBreedResultsClassBlock> rabbitBreedResultsClassBlocks(
  VarietySection variety,
) {
  final blocks = <({String sexLabel, ClassSection classSection})>[];
  for (final sexSection in variety.sexSections) {
    for (final classSection in sexSection.classes) {
      if (classSection.rows.isEmpty) continue;
      blocks.add((sexLabel: sexSection.sexLabel, classSection: classSection));
    }
  }

  blocks.sort((a, b) {
    final rank =
        rabbitBreedResultsClassSortOrder(
          a.classSection.className,
          a.sexLabel,
        ).compareTo(
          rabbitBreedResultsClassSortOrder(
            b.classSection.className,
            b.sexLabel,
          ),
        );
    if (rank != 0) return rank;
    return rabbitBreedResultsClassHeading(
      a.classSection.className,
      a.sexLabel,
    ).compareTo(
      rabbitBreedResultsClassHeading(b.classSection.className, b.sexLabel),
    );
  });

  return blocks
      .map(
        (block) => RabbitBreedResultsClassBlock(
          heading: rabbitBreedResultsClassHeading(
            block.classSection.className,
            block.sexLabel,
          ),
          classSection: block.classSection,
        ),
      )
      .toList(growable: false);
}
