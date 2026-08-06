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

  test('breed, group, and variety section names sort alphabetically', () {
    final names = ['Tortoise', 'Castor', 'Blue', 'Black', 'Otter', 'Broken']
      ..sort(compareBreedResultsDetailSectionNames);

    expect(names, ['Black', 'Blue', 'Broken', 'Castor', 'Otter', 'Tortoise']);
  });

  test('show awards follow the standardized hierarchy', () {
    BreedAward award(
      String code, {
      String breed = '',
      String group = '',
      String variety = '',
    }) => BreedAward(
      award: code,
      animal: code,
      breedName: breed,
      groupName: group,
      variety: variety,
      className: '',
      exhibitorName: '',
    );

    final awards = [
      award('BJV'),
      award('BOSG', group: 'Tan'),
      award('BOB', breed: 'Teddy'),
      award('HM'),
      award('BIS'),
      award('BOV', variety: 'White'),
      award('B4C'),
      award('RIS'),
      award('BOSB'),
      award('BSB'),
      award('BIB'),
      award('BJB'),
      award('BOG', group: 'Tan'),
      award('BOSV', variety: 'White'),
      award('BSV'),
      award('BIV'),
      award('B6C'),
    ]..sort(compareBreedResultsDetailAwards);

    expect(awards.map((award) => award.award), [
      'BIS',
      'RIS',
      'B4C',
      'B6C',
      'BOB',
      'BOSB',
      'BOG',
      'BOSG',
      'BOV',
      'BOSV',
      'BSB',
      'BSV',
      'BIB',
      'BIV',
      'BJB',
      'BJV',
      'HM',
    ]);
  });

  test('display labels follow the same show-award hierarchy as codes', () {
    BreedAward award(String label, {String group = '', String variety = ''}) =>
        BreedAward(
          award: label,
          animal: label,
          groupName: group,
          variety: variety,
          className: '',
          exhibitorName: '',
        );

    final awards = [
      award('Best of Group', group: 'Tan'),
      award('Best of Breed'),
      award('Best Opposite Sex of Breed'),
      award('Best in Show'),
      award('Reserve in Show'),
      award('Best Opposite Sex of Group', group: 'Tan'),
      award('Best Opposite Sex of Variety', variety: 'Black'),
      award('Best of Variety', variety: 'Black'),
      award('Best Junior Breed'),
    ]..sort(compareBreedResultsDetailAwards);

    expect(awards.map((award) => award.award), [
      'Best in Show',
      'Reserve in Show',
      'Best of Breed',
      'Best Opposite Sex of Breed',
      'Best of Group',
      'Best Opposite Sex of Group',
      'Best of Variety',
      'Best Opposite Sex of Variety',
      'Best Junior Breed',
    ]);
  });

  test('group and variety awards are paired alphabetically', () {
    BreedAward award(String code, {String group = '', String variety = ''}) =>
        BreedAward(
          award: code,
          animal: code,
          groupName: group,
          variety: variety,
          className: '',
          exhibitorName: '',
        );

    final awards = [
      award('BOSG', group: 'Tan'),
      award('BOG', group: 'Broken'),
      award('BOSG', group: 'Broken'),
      award('BOG', group: 'Tan'),
      award('BOSG', variety: 'AOV'),
      award('BOG', variety: 'AOV'),
      award('BOSV', variety: 'Ruby Eyed White'),
      award('BOV', variety: 'Black'),
      award('BOSV', variety: 'Black'),
      award('BOV', variety: 'Ruby Eyed White'),
    ]..sort(compareBreedResultsDetailAwards);

    expect(
      awards.map(
        (award) => '${award.award}:${award.groupName}${award.variety}',
      ),
      [
        'BOG:AOV',
        'BOSG:AOV',
        'BOG:Broken',
        'BOSG:Broken',
        'BOG:Tan',
        'BOSG:Tan',
        'BOV:Black',
        'BOSV:Black',
        'BOV:Ruby Eyed White',
        'BOSV:Ruby Eyed White',
      ],
    );
  });

  test('cavy reports retain their existing sex-section layout branch', () {
    expect(breedResultsDetailUsesRabbitClassLayout('rabbit'), isTrue);
    expect(breedResultsDetailUsesRabbitClassLayout('cavy'), isFalse);
    expect(breedResultsDetailUsesRabbitClassLayout(''), isFalse);
  });
}
