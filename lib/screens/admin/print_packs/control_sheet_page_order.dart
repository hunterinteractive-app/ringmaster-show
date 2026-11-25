import '../../../utils/cavy/cavy_sop_order.dart';
import 'control_sheet_judging_order.dart';

/// Rabbits print first; cavies stay together at the end in breed show order.
/// A selected judging lineup is honored within each species.
List<Map<String, dynamic>> sortControlSheetPages(
  List<Map<String, dynamic>> pages, {
  required bool combineSections,
  required bool youthFirst,
  ControlSheetJudgingOrder? judgingOrder,
}) {
  int cavyBreedRank(Map<String, dynamic> page) {
    if (!isCavyControlPage(page)) return 0;
    final configured = page['cavyBreedSortOrder'];
    if (configured is int && configured != 9999) return configured;
    final breed = (page['breed'] ?? '').toString().trim().toLowerCase();
    final rank = cavyBreedOrder.indexWhere(
      (name) => name.toLowerCase() == breed,
    );
    // The cavy catalog uses 10, 20, ... for the same breed sequence.
    return rank < 0 ? 9999 : (rank + 1) * 10;
  }

  String sectionKindForPage(Map<String, dynamic> page) {
    final rawKind = (page['sectionKind'] ?? '').toString().trim().toLowerCase();
    if (rawKind == 'open' || rawKind == 'youth') return rawKind;

    final title = (page['sectionTitle'] ?? '').toString().trim().toLowerCase();
    if (title.startsWith('open') || title.contains(' open ')) return 'open';
    if (title.startsWith('youth') || title.contains(' youth ')) {
      return 'youth';
    }

    return rawKind;
  }

  int sectionKindRank(Map<String, dynamic> page) {
    final kind = sectionKindForPage(page);
    switch (kind) {
      case 'open':
        return youthFirst ? 1 : 0;
      case 'youth':
        return youthFirst ? 0 : 1;
      default:
        return 99;
    }
  }

  String sectionLetterForPage(Map<String, dynamic> page) {
    final rawLetter = (page['sectionLetter'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (rawLetter.isNotEmpty) return rawLetter;

    final title = (page['sectionTitle'] ?? '').toString().trim().toUpperCase();
    final match = RegExp(r'\b([A-Z])$').firstMatch(title);
    return match?.group(1) ?? '';
  }

  int pageInt(Map<String, dynamic> page, String key) {
    final value = page[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 9999;
  }

  int compareControlPages(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (combineSections) {
      // Paired control sheets should be ordered by breed, then by section.
      // This keeps Open A American Fuzzy Lop together, then Youth A
      // American Fuzzy Lop together, instead of splitting the same breed
      // into repeated Open/Youth runs by class or sex.
      final cavyBreedCmp = cavyBreedRank(a).compareTo(cavyBreedRank(b));
      if (cavyBreedCmp != 0) return cavyBreedCmp;

      final breedCmp = (a['breed'] ?? '').toString().toLowerCase().compareTo(
        (b['breed'] ?? '').toString().toLowerCase(),
      );
      if (breedCmp != 0) return breedCmp;

      final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
      if (kindCmp != 0) return kindCmp;

      final sectionSortCmp = pageInt(
        a,
        'sectionSortOrder',
      ).compareTo(pageInt(b, 'sectionSortOrder'));
      if (sectionSortCmp != 0) return sectionSortCmp;

      final sectionLetterCmp = sectionLetterForPage(
        a,
      ).compareTo(sectionLetterForPage(b));
      if (sectionLetterCmp != 0) return sectionLetterCmp;

      final titleCmp = (a['sectionTitle'] ?? '').toString().compareTo(
        (b['sectionTitle'] ?? '').toString(),
      );
      if (titleCmp != 0) return titleCmp;

      // Within each Open or Youth section, print all regular breed
      // classes first and place Fur/Wool at the end of that section.
      final aIsFurOrWool = a['isFurOrWool'] == true;
      final bIsFurOrWool = b['isFurOrWool'] == true;
      if (aIsFurOrWool != bIsFurOrWool) {
        return aIsFurOrWool ? 1 : -1;
      }

      final groupCmp = pageInt(
        a,
        'groupSortOrder',
      ).compareTo(pageInt(b, 'groupSortOrder'));
      if (groupCmp != 0) return groupCmp;

      final varietyCmp = pageInt(
        a,
        'varietySortOrder',
      ).compareTo(pageInt(b, 'varietySortOrder'));
      if (varietyCmp != 0) return varietyCmp;

      final colorCmp = (a['color'] ?? '').toString().toLowerCase().compareTo(
        (b['color'] ?? '').toString().toLowerCase(),
      );
      if (colorCmp != 0) return colorCmp;

      final classCmp = pageInt(
        a,
        'classSortRank',
      ).compareTo(pageInt(b, 'classSortRank'));
      if (classCmp != 0) return classCmp;

      final sexCmp = (a['sex'] ?? '').toString().toLowerCase().compareTo(
        (b['sex'] ?? '').toString().toLowerCase(),
      );
      if (sexCmp != 0) return sexCmp;

      return 0;
    } else {
      final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
      if (kindCmp != 0) return kindCmp;

      final sectionSortCmp = pageInt(
        a,
        'sectionSortOrder',
      ).compareTo(pageInt(b, 'sectionSortOrder'));
      if (sectionSortCmp != 0) return sectionSortCmp;

      final sectionLetterCmp = sectionLetterForPage(
        a,
      ).compareTo(sectionLetterForPage(b));
      if (sectionLetterCmp != 0) return sectionLetterCmp;

      final cavyBreedCmp = cavyBreedRank(a).compareTo(cavyBreedRank(b));
      if (cavyBreedCmp != 0) return cavyBreedCmp;

      final breedCmp = (a['breed'] ?? '').toString().toLowerCase().compareTo(
        (b['breed'] ?? '').toString().toLowerCase(),
      );
      if (breedCmp != 0) return breedCmp;

      // Fur/Wool must always print after every regular class in the breed.
      final aIsFurOrWool = a['isFurOrWool'] == true;
      final bIsFurOrWool = b['isFurOrWool'] == true;

      if (aIsFurOrWool != bIsFurOrWool) {
        return aIsFurOrWool ? 1 : -1;
      }
    }

    // Only use the fallback sorting when not combining sections
    if (!combineSections) {
      final groupCmp = pageInt(
        a,
        'groupSortOrder',
      ).compareTo(pageInt(b, 'groupSortOrder'));
      if (groupCmp != 0) return groupCmp;

      final varietyCmp = pageInt(
        a,
        'varietySortOrder',
      ).compareTo(pageInt(b, 'varietySortOrder'));
      if (varietyCmp != 0) return varietyCmp;

      final colorCmp = (a['color'] ?? '').toString().toLowerCase().compareTo(
        (b['color'] ?? '').toString().toLowerCase(),
      );
      if (colorCmp != 0) return colorCmp;

      final classCmp = pageInt(
        a,
        'classSortRank',
      ).compareTo(pageInt(b, 'classSortRank'));
      if (classCmp != 0) return classCmp;

      final sexCmp = (a['sex'] ?? '').toString().toLowerCase().compareTo(
        (b['sex'] ?? '').toString().toLowerCase(),
      );
      if (sexCmp != 0) return sexCmp;

      return (a['sectionTitle'] ?? '').toString().compareTo(
        (b['sectionTitle'] ?? '').toString(),
      );
    }

    return 0;
  }

  return [...pages]..sort((a, b) {
    final species = (isCavyControlPage(a) ? 1 : 0).compareTo(
      isCavyControlPage(b) ? 1 : 0,
    );
    if (species != 0) return species;
    final order = judgingOrder == null
        ? 0
        : judgingOrder.rank(a).compareTo(judgingOrder.rank(b));
    return order != 0 ? order : compareControlPages(a, b);
  });
}

bool isCavyControlPage(Map<String, dynamic> page) =>
    (page['species'] ?? '').toString().trim().toLowerCase() == 'cavy';
