import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/superintendent/linked_workspace_data.dart';

void main() {
  final shows = [
    {'id': 'sala', 'name': 'Miss Sala Bash'},
    {'id': 'dune', 'name': 'Fall Duneabash'},
    {'id': 'other', 'name': 'Other show'},
  ];
  final groups = [
    {
      'id': 'shared',
      'name': 'Both shows',
      'show_ids': ['sala', 'dune'],
    },
  ];
  test('two authorized shows produce one card and unrelated shows stay', () {
    final result = groupSuperintendentShows(shows, groups);
    expect(result.length, 2);
    expect(result.first['workspace_id'], 'shared');
    expect((result.first['member_shows'] as List).length, 2);
    expect(result.last['id'], 'other');
    expect(shows.length, 3);
  });
  test(
    'partial access never hides a show or creates an unauthorized workspace',
    () {
      final result = groupSuperintendentShows([shows.first], groups);
      expect(result.single['id'], 'sala');
      expect(result.single['workspace_id'], isNull);
    },
  );
  test('overlapping workspace config cannot duplicate cards', () {
    expect(groupSuperintendentShows(shows, [...groups, ...groups]).length, 2);
  });
  test('same section names across shows stay distinct and varieties sum', () {
    final rows = <Map<String, dynamic>>[
      {
        'show_id': 'sala',
        'section_id': 'open-a',
        'species': 'rabbit',
        'breed': 'Havana',
        'variety': 'Black',
        'entry_count': 3,
      },
      {
        'show_id': 'sala',
        'section_id': 'open-a',
        'species': 'rabbit',
        'breed': 'Havana',
        'variety': 'Chocolate',
        'entry_count': 2,
      },
      {
        'show_id': 'dune',
        'section_id': 'open-a',
        'species': 'rabbit',
        'breed': 'Havana',
        'variety': 'Black',
        'entry_count': 7,
      },
    ];
    expect(workspaceBreedTotals(rows)['rabbit · Havana'], {
      'sala/open-a': 5,
      'dune/open-a': 7,
    });
  });
  test('commercial classes and species do not collapse into one breed', () {
    final rows = <Map<String, dynamic>>[
      for (final variety in ['Meat Pens', 'Single Fryer'])
        {
          'show_id': 'sala',
          'section_id': 'a',
          'species': 'rabbit',
          'breed': 'Commercial',
          'variety': variety,
          'entry_count': 1,
        },
      for (final species in ['rabbit', 'cavy'])
        {
          'show_id': 'sala',
          'section_id': 'a',
          'species': species,
          'breed': 'American',
          'entry_count': 2,
        },
    ];
    expect(workspaceBreedTotals(rows).length, 4);
  });
}
