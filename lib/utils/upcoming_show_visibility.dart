/// Published shows are discoverable only during their animal entry window.
/// A missing opening/closing date means that side of the window is unrestricted.
List<Map<String, dynamic>> visibleUpcomingShows(
  Iterable<Map<String, dynamic>> shows, {
  required DateTime now,
  Iterable<Map<String, dynamic>> contestShows = const [],
}) {
  final openContestIds = contestShows
      .where((show) => show['contest_registration_open'] == true)
      .map((show) => show['id'].toString())
      .toSet();
  final visible = shows
      .where((show) {
        if (show['is_published'] != true) return false;
        for (final field in ['entry_open_at', 'entry_close_at']) {
          final value = show[field];
          if (value == null) continue;
          final date = DateTime.tryParse(value.toString());
          if (date == null) return false;
          if (field == 'entry_open_at' && now.isBefore(date)) return false;
          if (field == 'entry_close_at' && now.isAfter(date)) return false;
        }
        return true;
      })
      .map(
        (show) => <String, dynamic>{
          ...show,
          'contest_registration_open': openContestIds.contains(
            show['id'].toString(),
          ),
        },
      )
      .toList();
  visible.sort(
    (a, b) => (a['start_date'] ?? '').toString().compareTo(
      (b['start_date'] ?? '').toString(),
    ),
  );
  return visible;
}
