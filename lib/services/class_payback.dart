class ClassPaybackRow {
  String? appliesToSpecies;
  int minShown;
  int? maxShown;
  Map<int, int> amountsByPlacement;
  final Map<int, String> amountErrors = {};

  ClassPaybackRow({
    required this.appliesToSpecies,
    required this.minShown,
    required this.maxShown,
    required this.amountsByPlacement,
  });

  String get rangeLabel => maxShown == null
      ? '$minShown+'
      : maxShown == minShown
      ? '$minShown'
      : '$minShown–$maxShown';

  bool get hasAnyAmount => amountsByPlacement.values.any((v) => v > 0);

  int get maxPayingPlaces {
    if (maxShown != null) return maxShown! < 1 ? 1 : maxShown!;

    var max = 5;
    for (final placement in amountsByPlacement.keys) {
      if (placement > max) max = placement;
    }
    return max;
  }

  ClassPaybackRow copy() {
    return ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: minShown,
      maxShown: maxShown,
      amountsByPlacement: Map<int, int>.from(amountsByPlacement),
    )..amountErrors.addAll(amountErrors);
  }

  List<Map<String, dynamic>> toRpcRows() {
    final rows = <Map<String, dynamic>>[];

    for (final entry in amountsByPlacement.entries) {
      if (entry.value <= 0) continue;

      rows.add({
        'applies_to_species': appliesToSpecies,
        'min_shown': minShown,
        'max_shown': maxShown,
        'placement': entry.key,
        'amount_cents': entry.value,
      });
    }

    return rows;
  }
}

/// A range is inclusive. Null maximum means an open-ended final bracket.
String? validateClassPaybackRanges(List<ClassPaybackRow> rows) {
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i];
    if (a.amountErrors.isNotEmpty) return a.amountErrors.values.first;
    if (!['rabbit', 'cavy'].contains(a.appliesToSpecies) ||
        a.minShown < 1 ||
        a.minShown > 2147483647 ||
        (a.maxShown != null &&
            (a.maxShown! < a.minShown || a.maxShown! > 2147483647))) {
      return 'Use a minimum of 1 or more and a maximum at least as large as the minimum.';
    }
    for (final p in a.amountsByPlacement.entries) {
      if (p.key < 1 ||
          p.value < 0 ||
          p.value > 2147483647 ||
          (p.value > 0 && a.maxShown != null && p.key > a.maxShown!)) {
        return 'Check the placement and premium amounts for ${a.rangeLabel} shown.';
      }
    }
    for (var j = i + 1; j < rows.length; j++) {
      final b = rows[j];
      if (a.appliesToSpecies == b.appliesToSpecies &&
          (a.maxShown == null || b.minShown <= a.maxShown!) &&
          (b.maxShown == null || a.minShown <= b.maxShown!)) {
        return 'Class-size ranges overlap for ${a.appliesToSpecies}: ${a.rangeLabel} and ${b.rangeLabel}.';
      }
    }
  }
  return null;
}

String? validatePremiumAmount(String? input) {
  final value = (input ?? '').replaceAll(r'$', '').trim();
  if (value.isEmpty) return null;
  final number = double.tryParse(value);
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(value) ||
      number == null ||
      !number.isFinite ||
      number < 0 ||
      number > 21474836.47) {
    return 'Use a nonnegative amount with up to 2 decimals.';
  }
  return null;
}

enum HoustonPaybackPreset {
  openRabbit('Open Rabbit', 'open', 'rabbit'),
  youthRabbit('Youth Rabbit', 'youth', 'rabbit'),
  openCavy('Open Cavy', 'open', 'cavy'),
  youthCavy('Youth Cavy', 'youth', 'cavy');

  const HoustonPaybackPreset(this.label, this.kind, this.species);
  final String label;
  final String kind;
  final String species;

  List<ClassPaybackRow> rows() {
    final List<(int, int?, List<int>)> table;
    if (kind == 'open') {
      table = [
        (2, 2, [2]),
        (3, 4, [4, 2]),
        (5, 6, [6, 4, 2]),
        (7, 8, [8, 6, 4, 2]),
        (9, null, [10, 8, 6, 4, 2]),
      ];
    } else if (species == 'rabbit') {
      table = [
        (1, 3, [10]),
        (4, 5, [12, 11, 10]),
        (6, 7, [14, 13, 12, 11]),
        (8, 9, [15, 14, 13, 12, 11]),
        (10, 14, [18, 16, 15, 14, 13]),
        (15, null, [23, 21, 20, 19, 18]),
      ];
    } else {
      table = [
        (1, 3, [10]),
        (4, 5, [12, 11]),
        (6, 7, [14, 13, 12]),
        (8, 9, [15, 14, 13, 12]),
        (10, null, [18, 16, 15, 14, 13]),
      ];
    }
    return [
      for (final (min, max, amounts) in table)
        ClassPaybackRow(
          appliesToSpecies: species,
          minShown: min,
          maxShown: max,
          amountsByPlacement: {
            for (var i = 0; i < amounts.length; i++) i + 1: amounts[i] * 100,
          },
        ),
    ];
  }
}
