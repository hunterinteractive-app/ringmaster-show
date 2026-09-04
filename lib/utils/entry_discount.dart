double calculatePerEntryDiscount({
  required double entryFee,
  required String discountType,
  required double discountValue,
}) {
  final safeFee = entryFee < 0 ? 0.0 : entryFee;
  final safeValue = discountValue < 0 ? 0.0 : discountValue;

  final discount = switch (discountType.trim().toLowerCase()) {
    'fixed_rate' => safeFee - safeValue,
    'percent' => safeFee * (safeValue > 1 ? safeValue / 100 : safeValue),
    'amount' => safeValue,
    _ => 0.0,
  };

  return discount.clamp(0.0, safeFee).toDouble();
}

double selectBetterDiscount(double first, double second) {
  final safeFirst = first < 0 ? 0.0 : first;
  final safeSecond = second < 0 ? 0.0 : second;
  return safeFirst > safeSecond ? safeFirst : safeSecond;
}

bool isCanadianExhibitorAddress({Object? stateOrProvince, Object? postalCode}) {
  final province = (stateOrProvince ?? '').toString().toUpperCase().replaceAll(
    RegExp(r'[^A-Z]'),
    '',
  );
  final postal = (postalCode ?? '').toString().toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]'),
    '',
  );

  const canadianProvinces = {
    'AB',
    'ALBERTA',
    'BC',
    'BRITISHCOLUMBIA',
    'MB',
    'MANITOBA',
    'NB',
    'NEWBRUNSWICK',
    'NL',
    'NEWFOUNDLAND',
    'LABRADOR',
    'NEWFOUNDLANDANDLABRADOR',
    'NS',
    'NOVASCOTIA',
    'NT',
    'NORTHWESTTERRITORIES',
    'NU',
    'NUNAVUT',
    'ON',
    'ONTARIO',
    'PE',
    'PEI',
    'PRINCEEDWARDISLAND',
    'PQ',
    'QC',
    'QUBEC',
    'QUEBEC',
    'SK',
    'SASKATCHEWAN',
    'YK',
    'YT',
    'YUKON',
  };

  final canadianPostalCode = RegExp(
    r'^[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTV-Z][0-9][ABCEGHJ-NPRSTV-Z][0-9]$',
  );

  return canadianProvinces.contains(province) ||
      canadianPostalCode.hasMatch(postal);
}
