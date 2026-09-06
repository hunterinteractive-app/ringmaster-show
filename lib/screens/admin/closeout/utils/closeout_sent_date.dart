String formatCloseoutSentDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.month}/${date.day}/${date.year}';
}

DateTime? parseCloseoutSentDate(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;

  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
  if (match == null) return null;

  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String? closeoutSentDateToIso8601(String? value, {required String fieldLabel}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;

  final date = parseCloseoutSentDate(text);
  if (date == null) {
    throw FormatException('Enter $fieldLabel as M/D/YYYY.');
  }
  return date.toUtc().toIso8601String();
}
