import 'show_addon.dart';
import 'contest_settings.dart';

/// Editable starting points. Event-specific rules are configured by the secretary.
enum ContestTemplate {
  rabbitJudging,
  showmanship,
  costume,
  royalty,
  breedId,
  skillathon,
  presentation,
  individualQuizbowl,
  teamJudging,
  teamBreedId,
  teamQuizbowl,
  educational,
  artCraft,
  photography,
  creativeWriting,
  illustratedTalk,
  shirtDesign,
  rabbitManagement,
  cavyManagement,
  achievement,
  breederAward;

  String get title => switch (this) {
    rabbitJudging => 'Rabbit Judging (Individual)',
    showmanship => 'Rabbit/Cavy Showmanship',
    costume => 'Rabbit/Cavy Costume Contest',
    royalty => 'Royalty',
    breedId => 'Breed Identification',
    skillathon => 'Skill-a-Thon',
    presentation => 'Presentation',
    individualQuizbowl => 'Individual Quizbowl',
    teamJudging => 'Team Judging',
    teamBreedId => 'Team Breed Identification',
    teamQuizbowl => 'Team Quizbowl',
    educational => 'Educational Exhibit',
    artCraft => 'Art / Craft',
    photography => 'Photography',
    creativeWriting => 'Creative Writing',
    illustratedTalk => 'Illustrated Talk',
    shirtDesign => 'T-Shirt Design',
    rabbitManagement => 'Rabbit Management',
    cavyManagement => 'Cavy Management',
    achievement => 'Achievement',
    breederAward => 'Youth Breeder Award',
  };
  String get group => switch (this) {
    teamJudging || teamBreedId || teamQuizbowl => 'Teams',
    educational ||
    artCraft ||
    photography ||
    creativeWriting ||
    illustratedTalk ||
    shirtDesign => 'Projects',
    rabbitManagement ||
    cavyManagement ||
    achievement ||
    breederAward => 'Applications',
    _ => 'Individual',
  };
  String get summary => switch (group) {
    'Teams' => 'Team name, coordinator, members, and alternates.',
    'Projects' =>
      'Project details, categories, and editable submission questions.',
    'Applications' =>
      'Application questions, supporting documents, and optional approval.',
    _ =>
      this == royalty
          ? 'Individual entry with customizable divisions and named awards.'
          : 'Individual entry with editable divisions and requirements.',
  };

  ShowAddon createDraft() {
    final team = group == 'Teams';
    final project = group == 'Projects';
    final application = group == 'Applications';
    final config = ContestSettings({
      'group': group,
      'entry_type': team
          ? 'team'
          : project
          ? 'project'
          : 'individual',
    });
    if (team) {
      config.data.addAll({
        'team_min': 3,
        'team_max': 4,
        'team_alternates': 0,
        'team_age_rule': 'oldest',
      });
    }
    if (project) config.data['category_limit'] = 1;
    if (application) config.data['requires_approval'] = true;
    if (this == royalty) {
      config.data['awards'] = [
        for (final name in [
          'King',
          'Queen',
          'Duke',
          'Duchess',
          'Prince',
          'Princess',
          'Lord',
          'Lady',
        ])
          {'name': name, 'recipients': 1, 'scope': 'contest'},
      ];
    }
    final categories = switch (this) {
      educational => ['Display', 'Game', 'Poster'],
      artCraft => ['Drawing', 'Painting', 'Sculpture', 'Craft'],
      photography => ['Black & White', 'Color', 'Photo Series'],
      creativeWriting => ['Poem', 'Short Story'],
      shirtDesign => ['Participant', 'Volunteer'],
      _ => <String>[],
    };
    if (categories.isNotEmpty) config.data['categories'] = categories;
    if (this == breederAward) {
      config.data.addAll({
        'animal_sources': ['entered', 'own'],
        'animal_roles': ['Doe / Sow', 'Offspring 1', 'Offspring 2'],
      });
    }
    return ShowAddon(
      kind: 'contest',
      name: title,
      description: switch (this) {
        royalty =>
          'Register the exhibitor for Royalty. Review the divisions, required activities, and application instructions for this show.',
        showmanship =>
          'Choose your division and the entered rabbit or cavy you will use for showmanship.',
        costume =>
          'Choose the entered rabbit or cavy you will use and select a costume category.',
        _ =>
          team
              ? 'Register your team and roster. Review the team size, division, and participation requirements.'
              : project
              ? 'Register your project and complete the submission requirements below.'
              : 'Register as an individual and complete the questions below.',
      },
      maxPerExhibitor: project
          ? (categories.isEmpty ? 1 : categories.length)
          : 1,
      divisions: this == costume || application
          ? []
          : this == royalty
          ? [
              'King / Queen',
              'Duke / Duchess',
              'Prince / Princess',
              'Lord / Lady',
            ]
          : ['Junior', 'Intermediate', 'Senior'],
      requiresAnimalEntry: this == showmanship || this == costume,
      animalSelection:
          this == showmanship || this == costume || this == breederAward
          ? 'required'
          : 'none',
      contestSettings: config,
      fields: this == costume
          ? [
              ContestField(
                label: 'Costume category',
                type: 'select',
                required: true,
                options: [
                  'Rodeo theme',
                  'Elaborate costume',
                  'Funny costume',
                  'Character impersonation',
                  'Colorful costume',
                ],
              ),
              ContestField(label: 'Costume title', required: true),
              ContestField(label: 'Costume description', type: 'long_text'),
            ]
          : [
              if (!team && !project && !application)
                ContestField(
                  label: 'Age on contest date',
                  type: 'number',
                  required: true,
                ),
              ContestField(label: 'Club or chapter'),
              if (this == royalty || application)
                ContestField(label: 'Application', type: 'file'),
              if (this == royalty)
                ContestField(label: 'Portrait photo', type: 'file'),
              if (project)
                ContestField(label: 'Project description', type: 'long_text'),
              if (this == illustratedTalk)
                ContestField(label: 'Video link', type: 'url', required: true),
              if (project && this != illustratedTalk)
                ContestField(label: 'Supporting file', type: 'file'),
              if (this == breederAward)
                ContestField(
                  label: 'Describe your breeding goals and records',
                  type: 'long_text',
                  required: true,
                  maxLength: 12000,
                ),
            ],
    );
  }
}
