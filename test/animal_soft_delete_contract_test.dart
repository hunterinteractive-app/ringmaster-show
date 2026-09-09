import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260909013815_soft_delete_animals.sql';

  test('animal deletion is a soft delete', () {
    final source = File(
      'lib/screens/my_animals_screen.dart',
    ).readAsStringSync();

    expect(source, contains(".update({'deleted_at':"));
    expect(source, isNot(contains("from('animals').delete()")));
    expect(source, contains(".isFilter('deleted_at', null)"));
    expect(source, contains("'Animal deleted.'"));
    expect(source, contains("'Delete failed: \$e'"));
  });

  test('new-entry animal lists exclude soft-deleted animals', () {
    final entrySources = [
      'lib/screens/enter_show_screen.dart',
      'lib/screens/my_entries_screen.dart',
      'lib/screens/admin/admin_entry_management_screen.dart',
    ].map((path) => File(path).readAsStringSync());

    for (final source in entrySources) {
      expect(source, contains(".isFilter('deleted_at', null)"));
    }
  });

  test('migration adds deletion timestamp and active lookup indexes', () {
    final migration = File(migrationPath).readAsStringSync();

    expect(migration, contains('add column if not exists deleted_at'));
    expect(migration, contains('animals_active_owner_user_id_idx'));
    expect(migration, contains('animals_active_exhibitor_id_idx'));
    expect(migration, contains('where deleted_at is null'));
  });
}
