import 'package:ringmaster_show/utils/cavy/cavy_sop_order.dart';

const String cavyClubReportBreedName = 'Cavy';
const int cavyClubReportGroupingVersion = 1;

const Set<String> breedClubReportNames = {
  'sweepstakes_report',
  'breed_results_detail_report',
};

const Set<String> stateClubReportNames = {
  'details_by_breed',
  'exh_by_breed',
  'best_display_report',
};

const Set<String> clubReportNames = {
  ...breedClubReportNames,
  ...stateClubReportNames,
};

bool isClubReportName(String reportName) =>
    clubReportNames.contains(reportName);

bool isBreedClubReportName(String reportName) =>
    breedClubReportNames.contains(reportName);

bool isStateClubReportName(String reportName) =>
    stateClubReportNames.contains(reportName);

String normalizeClubReportSpecies(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == 'rabbit' || normalized == 'cavy' ? normalized : '';
}

bool isKnownCavyBreed(String? breedName) {
  final normalized = _normalizeKey(breedName ?? '');
  if (normalized.isEmpty) return false;
  if (normalized == _normalizeKey(cavyClubReportBreedName)) return true;
  return cavyBreedOrder.any((breed) => _normalizeKey(breed) == normalized);
}

bool isCavyClubReportTarget({String? species, String? breedName}) {
  final normalizedSpecies = normalizeClubReportSpecies(species);
  return normalizedSpecies == 'cavy' ||
      (normalizedSpecies.isEmpty && isKnownCavyBreed(breedName));
}

String displayBreedNameForClubReport({
  required String reportName,
  String? breedName,
  String? species,
}) {
  if (!isClubReportName(reportName)) return (breedName ?? '').trim();
  if (isCavyClubReportTarget(species: species, breedName: breedName)) {
    return cavyClubReportBreedName;
  }
  return (breedName ?? '').trim();
}

String? loaderBreedNameForClubReport({
  required String reportName,
  String? breedName,
  String? species,
}) {
  if (isBreedClubReportName(reportName) &&
      isCavyClubReportTarget(species: species, breedName: breedName)) {
    return null;
  }

  final trimmed = (breedName ?? '').trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, dynamic> normalizedClubReportMetadata({
  required String reportName,
  required Map<String, dynamic> metadata,
}) {
  if (!isClubReportName(reportName)) return Map<String, dynamic>.from(metadata);

  final output = Map<String, dynamic>.from(metadata);
  final breedName = (output['breed_name'] ?? '').toString().trim();
  final species = normalizeClubReportSpecies(
    (output['species'] ?? '').toString(),
  );

  if (isCavyClubReportTarget(species: species, breedName: breedName)) {
    output['species'] = 'cavy';
    output['breed_name'] = cavyClubReportBreedName;
    output['cavy_club_report_grouping_version'] = cavyClubReportGroupingVersion;
    return output;
  }

  if (species == 'rabbit') {
    output['species'] = 'rabbit';
  }

  return output;
}

String cavyClubReportGroupKey({
  required String reportName,
  required Map<String, dynamic> metadata,
}) {
  if (!isClubReportName(reportName)) return '';

  final normalized = normalizedClubReportMetadata(
    reportName: reportName,
    metadata: metadata,
  );

  if (normalizeClubReportSpecies(normalized['species']?.toString()) != 'cavy') {
    return '';
  }

  final scope = _upper(normalized['scope']);
  final showLetter = _upper(normalized['show_letter']);
  if (scope.isEmpty || showLetter.isEmpty) return '';

  return [
    reportName.trim(),
    scope,
    showLetter,
    _lower(normalized['club_name']),
    _lower(normalized['sanctioning_body']),
    _text(normalized['section_id']),
    cavyClubReportBreedName.toLowerCase(),
  ].join('|');
}

bool isNormalizedCavyClubReportMetadata({
  required String reportName,
  required Map<String, dynamic> metadata,
}) {
  if (!isClubReportName(reportName)) return true;
  if (!isCavyClubReportTarget(
    species: metadata['species']?.toString(),
    breedName: metadata['breed_name']?.toString(),
  )) {
    return true;
  }

  final version = metadata['cavy_club_report_grouping_version'];
  final parsedVersion = version is int
      ? version
      : int.tryParse((version ?? '').toString()) ?? 0;

  return normalizeClubReportSpecies(metadata['species']?.toString()) ==
          'cavy' &&
      _normalizeKey(metadata['breed_name']?.toString() ?? '') ==
          _normalizeKey(cavyClubReportBreedName) &&
      parsedVersion >= cavyClubReportGroupingVersion;
}

String _text(Object? value) => (value ?? '').toString().trim();

String _upper(Object? value) => _text(value).toUpperCase();

String _lower(Object? value) => _text(value).toLowerCase();

String _normalizeKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
