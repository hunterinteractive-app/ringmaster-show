import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/models/convention_sale.dart';

Map<String, dynamic> sale() => {
  'title': 'Convention token bonus',
  'venue': 'Reno–Sparks Convention Center',
  'address': '4590 S Virginia St, Reno, NV 89502',
  'radius_miles': 1.0,
  'single_bonus': 1,
  'four_bonus': 2,
  'unlimited_bonus_months': 2,
  'enabled': true,
  'active': false,
  'time_zone': 'America/Los_Angeles',
  'starts_local': '2026-10-26T00:00',
  'ends_local': '2026-10-27T00:00',
};

void main() {
  test(
    'full-day offer ends at 11:59 PM in Reno, with the three requested totals',
    () {
      final model = ConventionSale(sale());
      expect(model.hours, contains('October 26, 2026'));
      expect(model.hours.replaceAll('\u202f', ' '), contains('11:59 PM'));
      expect(model.hours, contains('Pacific time'));
      expect(model.totalFor('single_show'), '2 tokens total');
      expect(model.totalFor('four_shows'), '6 tokens total');
      expect(model.totalFor('unlimited'), '14 months unlimited');
    },
  );
}
