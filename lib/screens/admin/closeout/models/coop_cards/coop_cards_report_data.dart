
// lib/screens/admin/closeout/models/coop_cards/coop_cards_report_data.dart

class CoopCardsReportData {
  final String showId;
  final String showName;
  final String showDateLabel;
  final String showLocationLabel;
  final String coopNumberingMode;
  final DateTime generatedAt;
  final List<CoopCardRow> cards;

  const CoopCardsReportData({
    required this.showId,
    required this.showName,
    required this.showDateLabel,
    required this.showLocationLabel,
    required this.coopNumberingMode,
    required this.generatedAt,
    required this.cards,
  });

  bool get usesCombinedNumbering =>
      coopNumberingMode.trim().toLowerCase() == 'combined';

  bool get isEmpty => cards.isEmpty;

  int get cardCount => cards.length;
}

class CoopCardRow {
  final String coopNumber;
  final String scope;
  final String species;

  final String animalId;
  final String animalName;
  final String tattoo;

  final String breed;
  final String variety;
  final String groupName;
  final String className;
  final String sex;

  final String exhibitorId;
  final String exhibitorName;
  final String exhibitorCity;
  final String exhibitorState;
  final String exhibitorNumber;

  final List<String> showLetters;
  final List<String> sectionLabels;

  final int classEntryCount;
  final int classExhibitorCount;

  const CoopCardRow({
    required this.coopNumber,
    required this.scope,
    required this.species,
    required this.animalId,
    required this.animalName,
    required this.tattoo,
    required this.breed,
    required this.variety,
    required this.groupName,
    required this.className,
    required this.sex,
    required this.exhibitorId,
    required this.exhibitorName,
    required this.exhibitorCity,
    required this.exhibitorState,
    required this.exhibitorNumber,
    required this.showLetters,
    required this.sectionLabels,
    required this.classEntryCount,
    required this.classExhibitorCount,
  });

  String get normalizedScope => scope.trim().toLowerCase();

  String get normalizedSpecies => species.trim().toLowerCase();

  bool get isOpen => normalizedScope == 'open';

  bool get isYouth => normalizedScope == 'youth';

  bool get isCombined => normalizedScope == 'all';

  bool get isCavy => normalizedSpecies == 'cavy';

  bool get isRabbit => !isCavy;

  String get scopeLabel {
    if (isOpen) return 'OPEN';
    if (isYouth) return 'YOUTH';
    if (isCombined) return 'OPEN / YOUTH';
    return scope.trim().isEmpty ? 'SHOW' : scope.trim().toUpperCase();
  }

  String get speciesLabel => isCavy ? 'CAVY' : 'RABBIT';

  String get footerLabel => '$scopeLabel $speciesLabel';

  String get animalDisplayName {
    final name = animalName.trim();
    final earNumber = tattoo.trim();

    if (name.isNotEmpty) return name;
    if (earNumber.isNotEmpty) return earNumber;
    return '(Unnamed Animal)';
  }

  String get groupVarietyLabel {
    final group = groupName.trim();
    final varietyName = variety.trim();

    if (group.isNotEmpty && varietyName.isNotEmpty) {
      return '$group / $varietyName';
    }
    if (group.isNotEmpty) return group;
    return varietyName;
  }

  String get classSexLabel {
    final ageClass = className.trim();
    final sexLabel = sex.trim();

    if (ageClass.isNotEmpty && sexLabel.isNotEmpty) {
      return '$ageClass $sexLabel';
    }
    if (ageClass.isNotEmpty) return ageClass;
    return sexLabel;
  }

  String get exhibitorLocation {
    final city = exhibitorCity.trim();
    final state = exhibitorState.trim();

    if (city.isNotEmpty && state.isNotEmpty) return '$city, $state';
    if (city.isNotEmpty) return city;
    return state;
  }

  String get showLettersLabel {
    final values = showLetters
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    return values.join(', ');
  }

  String get sectionsLabel {
    final values = sectionLabels
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (values.isNotEmpty) return values.join(', ');
    return showLettersLabel;
  }

  String get coopPrefix {
    return coopNumber.replaceAll(RegExp(r'\d+$'), '').trim().toUpperCase();
  }

  String get coopSequence {
    final match = RegExp(r'(\d+)$').firstMatch(coopNumber.trim());
    return match?.group(1) ?? coopNumber.trim();
  }

  int get coopSequenceValue {
    return int.tryParse(coopSequence) ?? 999999;
  }
}

