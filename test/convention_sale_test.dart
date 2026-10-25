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
  'starts_at': '2026-10-26T07:00:00Z',
  'ends_at': '2026-10-27T07:00:00Z',
  'time_zone': 'America/Los_Angeles',
  'starts_local': '2026-10-26T00:00',
  'ends_local': '2026-10-27T00:00',
};

void main() {
  test(
    'purchase confirmation identifies the secretary receiving the full bonus',
    () {
      final receipt = <String, dynamic>{
        'plan': 'four_shows',
        'bonus_tokens': 2,
        'recipient_email': 'club@example.invalid',
        'recipient_pending': false,
      };
      expect(
        conventionPurchaseConfirmation(receipt),
        contains('6 tokens have been added to club@example.invalid'),
      );
      expect(
        conventionPurchaseConfirmation({...receipt, 'recipient_pending': true}),
        contains('6 tokens are reserved for club@example.invalid'),
      );
      expect(
        conventionPurchaseConfirmation({
          ...receipt,
          'plan': 'unlimited',
          'bonus_months': 2,
          'unlimited_expires_at': '2028-04-15T12:00:00Z',
        }),
        contains(
          '14 months of Unlimited access have been added to club@example.invalid',
        ),
      );
      expect(
        conventionPurchaseConfirmation({
          ...receipt,
          'plan': 'unlimited',
          'bonus_months': 2,
          'unlimited_expires_at': null,
        }),
        contains(
          'lifetime Unlimited access for club@example.invalid is preserved',
        ),
      );
    },
  );
  test('header stays hidden before the sale even when it is enabled', () {
    final model = ConventionSale({...sale(), 'active': true});
    expect(model.isActiveAt(DateTime.parse('2026-10-26T06:59:59Z')), false);
  });
  test(
    'active sale appears at its start and remains through the last minute',
    () {
      final model = ConventionSale({...sale(), 'active': true});
      expect(model.isActiveAt(DateTime.parse('2026-10-26T07:00:00Z')), true);
      expect(model.isActiveAt(DateTime.parse('2026-10-27T06:59:59Z')), true);
    },
  );
  test(
    'header disappears at the exclusive end even if the snapshot was active',
    () {
      final model = ConventionSale({...sale(), 'active': true});
      expect(model.isActiveAt(DateTime.parse('2026-10-27T07:00:00Z')), false);
    },
  );
  test('disabled and inactive sales stay hidden during scheduled hours', () {
    final now = DateTime.parse('2026-10-26T19:00:00Z');
    expect(
      ConventionSale({
        ...sale(),
        'active': true,
        'enabled': false,
      }).isActiveAt(now),
      false,
    );
    expect(ConventionSale(sale()).isActiveAt(now), false);
  });
  test('missing or invalid sale dates do not show a promotion', () {
    final now = DateTime.parse('2026-10-26T19:00:00Z');
    for (final dates in [
      {'starts_at': null},
      {'ends_at': 'invalid'},
      {'ends_at': '2026-10-26T07:00:00Z'},
    ]) {
      expect(
        ConventionSale({...sale(), 'active': true, ...dates}).isActiveAt(now),
        false,
      );
    }
  });
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
