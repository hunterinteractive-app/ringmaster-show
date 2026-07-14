import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/breed_results_detail_order.dart';

void main() {
  ClassEntry row(String animal) => ClassEntry(
    place: '1',
    animal: animal,
    exhibitorName: 'Exhibitor',
    pointsEarned: 7,
  );

  ClassSection classSection(String className, {bool populated = true}) =>
      ClassSection(
        className: className,
        entryCount: populated ? 2 : 0,
        placedCount: populated ? 1 : 0,
        animalsJudged: populated ? 2 : 0,
        exhibitorsJudged: populated ? 2 : 0,
        rows: populated ? [row(className)] : const [],
      );

  test('rabbit class rank is age-first with sexes interleaved', () {
    expect(rabbitBreedResultsClassSortOrder('Senior', 'Bucks'), 0);
    expect(rabbitBreedResultsClassSortOrder('Sr', 'Female'), 1);
    expect(rabbitBreedResultsClassSortOrder('6-8', 'Male'), 2);
    expect(rabbitBreedResultsClassSortOrder('Inter', 'Does'), 3);
    expect(rabbitBreedResultsClassSortOrder('Junior', 'Buck'), 4);
    expect(rabbitBreedResultsClassSortOrder('Jr', 'Doe'), 5);
    expect(rabbitBreedResultsClassSortOrder('Unknown', 'Buck'), 999);
  });

  test('rabbit headings combine normalized age and singular sex', () {
    expect(rabbitBreedResultsClassHeading('Sr', 'Bucks'), 'Senior Buck');
    expect(
      rabbitBreedResultsClassHeading('Intermediate', 'Female'),
      'Intermediate Doe',
    );
    expect(rabbitBreedResultsClassHeading('Jr Doe', ''), 'Junior Doe');
  });

  test('missing rabbit classes are omitted without disturbing order', () {
    final award = BreedAward(
      award: 'BOV',
      animal: 'Winner',
      className: 'Senior',
      exhibitorName: 'Exhibitor',
      pointsEarned: 12,
    );
    final variety = VarietySection(
      varietyName: 'Black',
      awards: [award],
      sexSections: [
        SexSection(
          sexLabel: 'Bucks',
          classes: [
            classSection('Junior'),
            classSection('Intermediate', populated: false),
            classSection('Senior'),
          ],
        ),
        SexSection(
          sexLabel: 'Does',
          classes: [classSection('Junior'), classSection('Senior')],
        ),
      ],
    );

    final blocks = rabbitBreedResultsClassBlocks(variety);
    expect(blocks.map((block) => block.heading), [
      'Senior Buck',
      'Senior Doe',
      'Junior Buck',
      'Junior Doe',
    ]);
    expect(blocks.every((block) => block.classSection.rows.isNotEmpty), isTrue);
    expect(
      blocks.fold<int>(
        0,
        (sum, block) => sum + block.classSection.animalsJudged,
      ),
      8,
    );
    expect(variety.awards, same(variety.awards));
    expect(variety.awards.single, same(award));
  });

  test('configured rabbit group and variety order beats alphabetic order', () {
    final rows = [
      {
        'variety_name': 'Broken',
        'group_sort_order': 60,
        'variety_sort_order': 5,
      },
      {
        'variety_name': 'Castor',
        'group_sort_order': 30,
        'variety_sort_order': 6,
      },
      {
        'variety_name': 'Tortoise',
        'group_sort_order': 20,
        'variety_sort_order': 23,
      },
      {'variety_name': 'Blue', 'group_sort_order': 10, 'variety_sort_order': 3},
      {
        'variety_name': 'Black',
        'group_sort_order': 10,
        'variety_sort_order': 2,
      },
      {
        'variety_name': 'Otter',
        'group_sort_order': 40,
        'variety_sort_order': 13,
      },
    ]..sort(compareRabbitVarietyJudgingOrder);

    expect(rows.map((row) => row['variety_name']), [
      'Black',
      'Blue',
      'Tortoise',
      'Castor',
      'Otter',
      'Broken',
    ]);
    expect(
      rows.map((row) => row['variety_name']),
      isNot(
        orderedEquals([
          'Black',
          'Blue',
          'Broken',
          'Castor',
          'Otter',
          'Tortoise',
        ]),
      ),
    );
  });

  test('cavy reports retain their existing sex-section layout branch', () {
    expect(breedResultsDetailUsesRabbitClassLayout('rabbit'), isTrue);
    expect(breedResultsDetailUsesRabbitClassLayout('cavy'), isFalse);
    expect(breedResultsDetailUsesRabbitClassLayout(''), isFalse);
  });
}
