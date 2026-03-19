String formatLocalDateTime(String? ts) {
  if (ts == null || ts.trim().isEmpty) return '';

  final dt = DateTime.tryParse(ts);
  if (dt == null) return '';

  final local = dt.toLocal();

  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');

  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');

  final suffix = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;

  return '$y-$m-$d $h12:$minute $suffix';
}