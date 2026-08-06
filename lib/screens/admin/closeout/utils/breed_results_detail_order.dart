import '../models/clubs/breed_results_detail_report_data.dart';

bool breedResultsDetailUsesRabbitClassLayout(String species) =>
    species.trim().toLowerCase() == 'rabbit';

const Map<String, int> _awardOrder = {
  'BIS': 0,
  'RIS': 1,
  'RBIS': 1,
  'B4C': 2,
  'B6C': 3,
  'BOB': 4,
  'BOSB': 5,
  'BOS': 5,
  // Group and variety pairs share a rank so their identifying name can
  // control ordering and keep each Best/Best Opposite pair together.
  'BOG': 6,
  'BOSG': 6,
  'BOV': 7,
  'BOSV': 7,
  'BSB': 8,
  'BIB': 9,
  'BJB': 10,
  'HM': 11,
};

int breedResultsDetailAwardRank(String awardCode) =>
    _awardOrder[awardCode.trim().toUpperCase()] ?? 999;

int compareBreedResultsDetailAwards(BreedAward a, BreedAward b) {
  final aCode = a.award.trim().toUpperCase();
  final bCode = b.award.trim().toUpperCase();
  final rank = breedResultsDetailAwardRank(
    aCode,
  ).compareTo(breedResultsDetailAwardRank(bCode));
  if (rank != 0) return rank;

  // Page-one award order is grouped by the award's subject: every group gets
  // Best of Group followed by Best Opposite Sex of Group; every variety gets
  // Best of Variety followed by Best Opposite Sex of Variety.
  if (const {'BOG', 'BOSG'}.contains(aCode) &&
      const {'BOG', 'BOSG'}.contains(bCode)) {
    final group = _compareText(_groupSortName(a), _groupSortName(b));
    if (group != 0) return group;
    final award = _groupPairRank(aCode).compareTo(_groupPairRank(bCode));
    if (award != 0) return award;
  }

  if (const {'BOV', 'BOSV'}.contains(aCode) &&
      const {'BOV', 'BOSV'}.contains(bCode)) {
    final variety = _compareText(a.variety, b.variety);
    if (variety != 0) return variety;
    final award = _varietyPairRank(aCode).compareTo(_varietyPairRank(bCode));
    if (award != 0) return award;
  }

  for (final pair in [
    (a.breedName, b.breedName),
    (a.groupName, b.groupName),
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

int _compareText(String a, String b) =>
    a.trim().toLowerCase().compareTo(b.trim().toLowerCase());

String _groupSortName(BreedAward award) {
  final group = award.groupName.trim();
  // Older stored report rows may not expose group_name. In those rows,
  // variety is the best stable, human-readable fallback for pairing awards.
  return group.isEmpty ? award.variety : group;
}

int _groupPairRank(String awardCode) => awardCode == 'BOG' ? 0 : 1;

int _varietyPairRank(String awardCode) => awardCode == 'BOV' ? 0 : 1;

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
