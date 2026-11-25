import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/cart_entry_review.dart';

void main() {
  test(
    'draft print groups rabbits A before B and keeps submissions separate, escaping all text',
    () {
      final document = buildCartEntryReview(
        showName: '<script>alert(1)</script>',
        showDate: '2026-12-01',
        items: [
          for (final row in [('one', 'B'), ('two', 'A'), ('one', 'A')])
            {
              'id': '${row.$1}${row.$2}',
              'animal_id': row.$1,
              'tattoo': row.$1,
              'exhibitor_id': 'family',
              'section_id': row.$2,
              'breed': 'Havana',
              'variety': 'Black',
              'class_name': 'Senior',
              'sex': 'Buck',
            },
        ],
        submittedEntries: [
          {
            'id': 'old',
            'tattoo': 'OLDER',
            'exhibitor_id': 'other',
            'section_id': 'A',
          },
        ],
        exhibitorNames: {'family': 'Family <One>', 'other': 'Other'},
        sections: {
          'A': {'display_name': 'Open A', 'letter': 'A'},
          'B': {'display_name': 'Open B', 'letter': 'B'},
        },
        feeLines: ['Cart total: USD 15.00', 'Previously submitted: USD 5.00'],
        notices: ['Review duplicates'],
      );
      expect(document, contains('DRAFT REVIEW — not proof'));
      expect(document, contains('In this cart — not submitted (3)'));
      expect(document, contains('Family &lt;One&gt;'));
      expect(document, isNot(contains('<script>')));
      expect(
        document.indexOf('<td>Open A</td><td>one'),
        lessThan(document.indexOf('<td>Open B</td><td>one')),
      );
      expect(
        document.indexOf('<td>Open B</td><td>one'),
        lessThan(document.indexOf('<td>Open A</td><td>two')),
      );
      expect(
        document,
        contains('Previously submitted — separate from this cart (1)'),
      );
      expect(document, contains('Cart total: USD 15.00'));
      expect(document, contains('Print / Save as PDF'));
    },
  );
}
