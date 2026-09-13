/// Separate youth logins are available after age 13 (from the 14th birthday).
bool canInviteHouseholdExhibitor(
  String type,
  DateTime? birthDate, {
  DateTime? today,
}) {
  if (type.toLowerCase() == 'adult') return true;
  if (type.toLowerCase() != 'youth' || birthDate == null) return false;
  final now = today ?? DateTime.now();
  final birthday = DateTime(
    birthDate.year + 14,
    birthDate.month,
    birthDate.day,
  );
  return !DateTime(now.year, now.month, now.day).isBefore(birthday);
}
