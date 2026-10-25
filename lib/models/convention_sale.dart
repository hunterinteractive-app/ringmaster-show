import 'package:intl/intl.dart';

class ConventionSale {
  ConventionSale(this.data);
  final Map<String, dynamic> data;
  String get title => data['title'] as String;
  String get venue => data['venue'] as String;
  bool get active => data['active'] == true;
  bool get enabled => data['enabled'] == true;
  bool isActiveAt(DateTime serverNow) {
    final start = DateTime.tryParse('${data['starts_at']}');
    final end = DateTime.tryParse('${data['ends_at']}');
    return enabled &&
        active &&
        start != null &&
        end != null &&
        end.isAfter(start) &&
        !serverNow.isBefore(start) &&
        serverNow.isBefore(end);
  }

  double get radiusMiles => (data['radius_miles'] as num).toDouble();
  int bonusFor(String plan) =>
      (data[switch (plan) {
                'single_show' => 'single_bonus',
                'four_shows' => 'four_bonus',
                _ => 'unlimited_bonus_months',
              }]
              as num)
          .toInt();
  String totalFor(String plan) => switch (plan) {
    'single_show' => '${1 + bonusFor(plan)} tokens total',
    'four_shows' => '${4 + bonusFor(plan)} tokens total',
    _ => '${12 + bonusFor(plan)} months unlimited',
  };
  String get hours {
    final start = DateTime.parse(data['starts_local'] as String);
    final end = DateTime.parse(
      data['ends_local'] as String,
    ).subtract(const Duration(minutes: 1));
    final zone = data['time_zone'] == 'America/Los_Angeles'
        ? 'Pacific time'
        : data['time_zone'];
    final sameDay =
        DateFormat('yyyy-MM-dd').format(start) ==
        DateFormat('yyyy-MM-dd').format(end);
    return '${DateFormat.yMMMMd().format(start)} · ${DateFormat.jm().format(start)} – '
        '${sameDay ? '' : '${DateFormat.yMMMd().format(end)} '}${DateFormat.jm().format(end)} · $zone';
  }
}
