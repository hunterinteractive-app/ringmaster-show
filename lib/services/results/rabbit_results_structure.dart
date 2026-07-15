import 'results_rules.dart';

enum RabbitBreedStructure {
  directBreed,
  varietyOnly,
  groupOnly,
  groupedVarieties,
}

class ResolvedRabbitGroup {
  final String stableKey;
  final String displayName;
  final bool recognized;

  const ResolvedRabbitGroup({
    required this.stableKey,
    required this.displayName,
    required this.recognized,
  });
}

class ResolvedRabbitVariety {
  final String stableKey;
  final String displayName;
  final bool recognized;

  const ResolvedRabbitVariety({
    required this.stableKey,
    required this.displayName,
    required this.recognized,
  });
}

RabbitBreedStructure rabbitBreedStructure(Map<String, dynamic> entry) {
  final groups = resultsRuleBool(entry['uses_group_awards']);
  final varieties = resultsRuleBool(entry['uses_variety_awards']);
  if (groups && varieties) return RabbitBreedStructure.groupedVarieties;
  if (groups) return RabbitBreedStructure.groupOnly;
  if (varieties) return RabbitBreedStructure.varietyOnly;
  return RabbitBreedStructure.directBreed;
}

String _rabbitBreedKey(Map<String, dynamic> entry) => normalizeResultsRuleKey(
  resultsRuleText(entry, const [
    'breed_id',
    'breed_catalog_id',
    'breed_name',
    'breed',
  ]),
);

ResolvedRabbitVariety resolveRabbitVariety(Map<String, dynamic> entry) {
  final id = resultsRuleText(entry, const [
    'rabbit_variety_id',
    'variety_id',
    'exact_variety_id',
    'breed_variety_id',
  ]);
  final name = resultsRuleText(entry, const [
    'rabbit_variety_name',
    'exact_variety_name',
    'variety_name',
    'variety',
  ]);
  final identity = normalizeResultsRuleKey(id.isNotEmpty ? id : name);
  final breed = _rabbitBreedKey(entry);
  return ResolvedRabbitVariety(
    stableKey: identity.isEmpty
        ? 'variety:$breed:unassigned'
        : 'variety:$breed:$identity',
    displayName: name.isEmpty ? '(No Variety Assigned)' : name,
    recognized: identity.isNotEmpty,
  );
}

ResolvedRabbitGroup resolveRabbitGroup(Map<String, dynamic> entry) {
  final breed = _rabbitBreedKey(entry);
  final structure = rabbitBreedStructure(entry);
  if (structure == RabbitBreedStructure.groupOnly) {
    final variety = resolveRabbitVariety(entry);
    return ResolvedRabbitGroup(
      stableKey: variety.recognized
          ? 'rabbit-group:$breed:${variety.stableKey.split(':').last}'
          : 'rabbit-group:$breed:unassigned',
      displayName: variety.recognized
          ? variety.displayName
          : '(No Rabbit Group Assigned)',
      recognized: variety.recognized,
    );
  }

  final id = resultsRuleText(entry, const [
    'rabbit_group_id',
    'variety_group_id',
  ]);
  final name = resultsRuleText(entry, const [
    'rabbit_group_name',
    'variety_group_name',
    'group_name',
  ]);
  final identity = normalizeResultsRuleKey(id.isNotEmpty ? id : name);
  if (identity.isNotEmpty) {
    return ResolvedRabbitGroup(
      stableKey: 'rabbit-group:$breed:$identity',
      displayName: name.isEmpty ? '(Unnamed Rabbit Group)' : name,
      recognized: true,
    );
  }

  final variety = resolveRabbitVariety(entry);
  return ResolvedRabbitGroup(
    stableKey:
        'rabbit-group:$breed:unmapped:${variety.stableKey.split(':').last}',
    displayName: '(Ungrouped Rabbit Varieties)',
    recognized: false,
  );
}
