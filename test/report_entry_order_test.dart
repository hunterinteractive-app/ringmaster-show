import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/report_entry_order.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/breed_results_detail_order.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart';

Map<String, dynamic> animal(
  String variety,
  int rank,
  String age,
  String sex, {
  String breed = 'Tan',
  String species = 'rabbit',
  int? groupRank,
  String group = '',
}) => {
  'species': species,
  'breed_name': breed,
  'variety_name': variety,
  'variety_sort_order': rank,
  'group_sort_order': groupRank,
  'group_name': group,
  'class_name': age,
  'sex': sex,
  'tattoo': '$variety $age $sex',
};

void main() {
  test(
    'PDF class blocks recognize intermediate abbreviations and cavy ages',
    () {
      final variety = VarietySection(
        varietyName: 'Teddy — Self',
        awards: [],
        sexSections: [
          for (final sex in ['Sows', 'Boars'])
            SexSection(
              sexLabel: sex,
              classes: [
                for (final age in ['Sr', 'Int', 'Jr'])
                  ClassSection(
                    className: '$age $sex',
                    entryCount: 1,
                    placedCount: 1,
                    animalsJudged: 1,
                    exhibitorsJudged: 1,
                    rows: [
                      ClassEntry(
                        place: '1',
                        animal: 'x',
                        exhibitorName: 'Example',
                      ),
                    ],
                  ),
              ],
            ),
        ],
      );
      expect(cavyBreedResultsClassBlocks(variety).map((b) => b.heading), [
        'Junior Boar',
        'Junior Sow',
        'Intermediate Boar',
        'Intermediate Sow',
        'Senior Boar',
        'Senior Sow',
      ]);
      expect(rabbitBreedResultsClassSortOrder('Int Bucks', 'Bucks'), 2);
      expect(
        rabbitBreedResultsClassHeading('Pre-Jr Bucks', 'Bucks'),
        'Pre-Junior Buck',
      );
    },
  );

  test(
    'Tan follows catalog variety order, then senior/junior with sexes paired',
    () {
      final expected = [
        for (final variety in ['Lilac', 'Blue', 'Chocolate', 'Black'])
          for (final age in ['Senior', 'Junior'])
            for (final sex in ['Buck', 'Doe']) '$variety $age $sex',
      ];
      final rows = [
        for (final (i, variety) in [
          'Lilac',
          'Blue',
          'Chocolate',
          'Black',
        ].indexed)
          for (final age in ['Senior', 'Junior'])
            for (final sex in ['Buck', 'Doe']) animal(variety, i + 1, age, sex),
      ];
      for (var seed = 0; seed < 10; seed++) {
        rows.shuffle(Random(seed));
        rows.sort(compareReportAnimalRows);
        expect(rows.map((r) => r['tattoo']), expected);
      }
    },
  );

  test(
    'six-class breeds interleave sexes and recognize legacy age spellings',
    () {
      final rows = [
        for (final age in ['Jr', '6/8', 'Sr'])
          for (final sex in ['Doe', 'Buck'])
            animal('White', 1, age, sex, breed: 'New Zealand'),
      ]..sort(compareReportAnimalRows);
      expect(rows.map((r) => r['tattoo']), [
        'White Sr Buck',
        'White Sr Doe',
        'White 6/8 Buck',
        'White 6/8 Doe',
        'White Jr Buck',
        'White Jr Doe',
      ]);
    },
  );

  test('group order takes precedence over a variety rank and case', () {
    final rows = [
      animal(
        'Chestnut',
        1,
        'Senior',
        'Buck',
        breed: 'Netherland Dwarf',
        groupRank: 30,
        group: 'Agouti',
      ),
      animal(
        'Sable Point',
        24,
        'Senior',
        'Buck',
        breed: 'Netherland Dwarf',
        groupRank: 20,
        group: 'Shaded',
      ),
      animal(
        'black',
        2,
        'Senior',
        'Buck',
        breed: 'Netherland Dwarf',
        groupRank: 10,
        group: 'Self',
      ),
    ]..sort(compareReportAnimalRows);
    expect(rows.map((r) => r['variety_name']), [
      'black',
      'Sable Point',
      'Chestnut',
    ]);
  });

  test('cavy SOP age/sex order overrides legacy rabbit class ranks', () {
    final rows = [
      for (final age in ['Senior', 'Intermediate', 'Junior'])
        for (final sex in ['Sow', 'Boar'])
          {
            ...animal('Self', 1, age, sex, breed: 'Teddy', species: 'cavy'),
            'class_sort_order': age == 'Senior' ? 0 : 2,
          },
    ]..sort(compareReportAnimalRows);
    expect(rows.map((r) => r['tattoo']), [
      'Self Junior Boar',
      'Self Junior Sow',
      'Self Intermediate Boar',
      'Self Intermediate Sow',
      'Self Senior Boar',
      'Self Senior Sow',
    ]);
  });

  test(
    'sections stay intact and fur follows regular classes within the breed',
    () {
      final rows = [
        for (final kind in ['youth', 'open'])
          for (final letter in ['B', 'A'])
            for (final fur in [true, false])
              {
                ...animal(
                  fur ? 'Black' : 'Lilac',
                  fur ? 0 : 1,
                  'Senior',
                  'Doe',
                ),
                'section_kind': kind,
                'section_letter': letter,
                'section_id': '$kind$letter',
                'is_fur': fur,
              },
      ]..sort(compareReportEntryRows);
      expect(rows.map((r) => '${r['section_id']}:${r['is_fur']}'), [
        'openA:false',
        'openA:true',
        'openB:false',
        'openB:true',
        'youthA:false',
        'youthA:true',
        'youthB:false',
        'youthB:true',
      ]);
    },
  );

  test(
    'unknown classes remain contiguous and tie breaks are deterministic',
    () {
      final rows = [
        for (final c in ['Novel B', 'Novel A'])
          for (final sex in ['Doe', 'Buck']) animal('Local', 99, c, sex),
      ]..sort(compareReportAnimalRows);
      expect(rows.map((r) => r['tattoo']), [
        'Local Novel A Buck',
        'Local Novel A Doe',
        'Local Novel B Buck',
        'Local Novel B Doe',
      ]);
    },
  );

  test('variety awards use catalog order while retaining BOV/BOSV pairs', () {
    final rows =
        [
            for (final (i, v) in [
              'Lilac',
              'Blue',
              'Chocolate',
              'Black',
            ].indexed)
              for (final code in ['BOSV', 'BOV'])
                BreedAward(
                  award: code,
                  animal: 'x',
                  className: 'Senior',
                  exhibitorName: 'Example',
                  variety: v,
                  varietySortOrder: i,
                ),
          ]
          ..shuffle(Random(4))
          ..sort(compareBreedResultsDetailAwards);
    expect(rows.map((r) => '${r.variety}:${r.award}'), [
      for (final v in ['Lilac', 'Blue', 'Chocolate', 'Black']) ...[
        '$v:BOV',
        '$v:BOSV',
      ],
    ]);
  });
}
