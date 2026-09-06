import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final previewSource = File(
    'lib/screens/admin/show_closeout_v2_preview.dart',
  ).readAsStringSync();
  final migration = File(
    'supabase/migrations/20260906031429_add_closeout_blocking_entry_issues_rpc.sql',
  ).readAsStringSync();

  test('Needs Fixed loads blockers from the non-truncating RPC', () {
    final panelStart = previewSource.indexOf('class _MustFixPanelState');
    final panelEnd = previewSource.indexOf(
      'enum _ResultsReadinessIssueType',
      panelStart,
    );
    final panelSource = previewSource.substring(panelStart, panelEnd);

    expect(
      panelSource,
      contains("'show_results_blocking_entry_issues_scoped'"),
    );
    expect(panelSource, isNot(contains("'report_results_entry_rows'")));
    expect(panelSource, contains("blockingEntryIssues['items']"));
  });

  test('blocking issue RPC returns one JSON document', () {
    expect(migration, contains('show_results_blocking_entry_issues_scoped('));
    expect(migration, contains('returns jsonb'));
    expect(migration, contains("'items', items"));
    expect(migration, isNot(contains('returns table(')));
  });
}
