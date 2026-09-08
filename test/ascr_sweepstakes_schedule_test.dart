import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ASCRA reports use flat class points without award bonuses', () {
    final migration = File(
      'supabase/migrations/20260906030557_seed_ascr_flat_sweepstakes_schedule.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains('american standard chinchilla rabbit association'),
    );
    expect(migration, contains("'class_points_model', 'FLAT_BY_PLACING'"));
    expect(migration, contains("'place', 1, 'points', 6"));
    expect(migration, contains("'place', 2, 'points', 4"));
    expect(migration, contains("'place', 3, 'points', 3"));
    expect(migration, contains("'place', 4, 'points', 2"));
    expect(migration, contains("'place', 5, 'points', 1"));
    expect(migration, contains("'awards', '[]'::jsonb"));
  });

  test('portal schedules recognize numeric result placements', () {
    final migration = File(
      'supabase/migrations/20260906031335_fix_flat_sweepstakes_placement_parsing.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'calculate_sweepstakes_for_breed_portal_class_schedule(uuid,text,text,text)',
      ),
    );
    expect(migration, contains("~ '^[0-9]+\$'"));
    expect(migration, contains('Expected numeric-placement expression'));
  });
}
