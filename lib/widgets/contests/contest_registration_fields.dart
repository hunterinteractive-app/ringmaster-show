import 'package:flutter/material.dart';
import '../../models/show_addon.dart';
import '../../models/contest_settings.dart';
import '../../utils/date_time_utils.dart';

class ContestRegistrationFields extends StatefulWidget {
  const ContestRegistrationFields({
    super.key,
    required this.item,
    required this.data,
    required this.animals,
    required this.onChanged,
  });
  final ShowAddon item;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> animals;
  final VoidCallback onChanged;
  @override
  State<ContestRegistrationFields> createState() =>
      _ContestRegistrationFieldsState();
}

class _ContestRegistrationFieldsState extends State<ContestRegistrationFields> {
  Map<String, dynamic> get data => widget.data;
  ContestSettings get rules => widget.item.contest;
  void changed() {
    setState(() {});
    widget.onChanged();
  }

  Widget field(
    String label,
    Map<String, dynamic> target,
    String key, {
    bool required = true,
    bool date = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      initialValue: target[key]?.toString() ?? '',
      decoration: InputDecoration(
        labelText: '$label${required ? ' *' : ''}',
        helperText: date ? 'YYYY-MM-DD' : null,
      ),
      maxLength: date ? 10 : 200,
      onChanged: (v) => target[key] = v.trim(),
      validator: (v) {
        if (required && (v ?? '').trim().isEmpty) return 'Enter $label.';
        if (date &&
            (v ?? '').isNotEmpty &&
            (ContestSettings.date(v!) == null ||
                ContestSettings.date(v)!.isAfter(DateTime.now()))) {
          return 'Enter a valid birthdate.';
        }
        return null;
      },
    ),
  );
  Widget choice(String label, String key, List<String> options) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: DropdownButtonFormField<String>(
      initialValue: options.contains(data[key]) ? data[key] : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: '$label *'),
      items: [
        for (final v in options) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: (v) {
        data[key] = v;
        changed();
      },
      validator: (v) => v == null ? 'Choose $label.' : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final team =
        data.putIfAbsent('team', () => <String, dynamic>{})
            as Map<String, dynamic>;
    final members = team.putIfAbsent('members', () => <dynamic>[]) as List;
    final selectedAnimals =
        data.putIfAbsent('animals', () => <dynamic>[]) as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rules.categories.isNotEmpty)
          choice('Category', 'category', rules.categories),
        if (rules.isProject) field('Project title', data, 'project_title'),
        if (!rules.isTeam && rules.needsBirthdate)
          field('Date of birth', data, 'birthdate', date: true),
        if (rules.needsBirthdate || rules.isTeam)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Age is determined ${rules.text('age_as_of', 'show_start') == 'custom'
                  ? 'on ${rules.text('age_date')}'
                  : rules.text('age_as_of', 'show_start') == 'show_end'
                  ? 'on the last day of the show'
                  : 'on the first day of the show'}.',
            ),
          ),
        if (rules.sessions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: DropdownButtonFormField<String>(
              initialValue:
                  rules.sessions.any((s) => s['id'] == data['session_id'])
                  ? data['session_id']
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Session *'),
              items: [
                for (final s in rules.sessions)
                  DropdownMenuItem(
                    value: '${s['id']}',
                    child: Text(
                      '${s['name']} • ${formatLocalDateTime(s['starts_at'])}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                data['session_id'] = v;
                changed();
              },
              validator: (v) => v == null ? 'Choose a session.' : null,
            ),
          ),
        if (rules.text('schedule_notes').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(rules.text('schedule_notes')),
          ),
        for (final key in [
          'checkin_open_at',
          'checkin_close_at',
          'submission_close_at',
        ])
          if (rules.text(key).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${const {'checkin_open_at': 'Check-in opens', 'checkin_close_at': 'Check-in closes', 'submission_close_at': 'Materials due'}[key]}: ${formatLocalDateTime(rules.text(key))} (your time zone)',
              ),
            ),
        if (rules.isTeam) ...[
          field('Team name', team, 'name'),
          field(
            'Represented club / state / district',
            team,
            'organization',
            required: false,
          ),
          field('Coordinator contact', team, 'contact', required: false),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${rules.number('team_min', 3)}–${rules.number('team_max', 4)} active members; up to ${rules.number('team_alternates')} alternates. The registration fee covers this team.',
            ),
          ),
          if (rules.text('prerequisite_contest_id').isNotEmpty)
            const Text(
              'Each active member must also be registered for the required individual contest. Enter each member’s exhibitor number.',
            ),
          for (final member in members)
            Card(
              key: ObjectKey(member),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Member ${members.indexOf(member) + 1}'),
                        ),
                        IconButton(
                          tooltip: 'Remove member',
                          onPressed: () {
                            members.remove(member);
                            changed();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    field('Member name', member, 'name'),
                    field('Date of birth', member, 'birthdate', date: true),
                    field(
                      'Exhibitor number',
                      member,
                      'exhibitor_number',
                      required:
                          rules.text('prerequisite_contest_id').isNotEmpty &&
                          member['alternate'] != true,
                    ),
                    if (rules.number('team_alternates') > 0)
                      CheckboxListTile(
                        title: const Text('Alternate'),
                        value: member['alternate'] == true,
                        onChanged: (v) {
                          member['alternate'] = v;
                          changed();
                        },
                      ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed:
                members.length >=
                    rules.number('team_max', 4) +
                        rules.number('team_alternates')
                ? null
                : () {
                    members.add(<String, dynamic>{});
                    changed();
                  },
            icon: const Icon(Icons.person_add),
            label: const Text('Add Team Member'),
          ),
          FormField<bool>(
            validator: (_) {
              final active = members
                  .where((m) => m['alternate'] != true)
                  .length;
              final alternate = members.length - active;
              return active < rules.number('team_min', 3) ||
                      active > rules.number('team_max', 4) ||
                      alternate > rules.number('team_alternates')
                  ? 'Check the number of active members and alternates.'
                  : null;
            },
            builder: (state) => state.hasError
                ? Text(
                    state.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          FormField<bool>(
            initialValue: team['authorized'] == true,
            validator: (v) => v != true
                ? 'Confirm you are authorized to enter this team.'
                : null,
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I am authorized to register these members and provide their information, including guardian permission where required.',
                  ),
                  value: state.value ?? false,
                  onChanged: (v) {
                    state.didChange(v);
                    team['authorized'] = v;
                  },
                ),
                if (state.hasError)
                  Text(
                    state.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (rules.expandedAnimals) ...[
          const SizedBox(height: 16),
          Text(
            'Contest animals',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final role
              in rules.animalRoles.isEmpty ? ['Animal'] : rules.animalRoles)
            _animal(role, selectedAnimals),
        ],
      ],
    );
  }

  Widget _animal(String role, List selected) {
    var a = selected
        .cast<Map<String, dynamic>>()
        .where((v) => v['role'] == role)
        .firstOrNull;
    if (a == null) {
      a = <String, dynamic>{'role': role};
      selected.add(a);
    }
    final animal = a;
    final sources = rules.animalSources.isEmpty
        ? ['entered']
        : rules.animalSources;
    final required = widget.item.animalSelection == 'required';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(role),
            DropdownButtonFormField<String>(
              initialValue: sources.contains(animal['source'])
                  ? animal['source']
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: required
                    ? 'Animal source *'
                    : 'Animal source (optional)',
              ),
              items: [
                if (!required)
                  const DropdownMenuItem(value: '', child: Text('None')),
                for (final source in sources)
                  DropdownMenuItem(
                    value: source,
                    child: Text(
                      const {
                        'entered': 'An animal entered in this show',
                        'own': 'My animal, not entered in this show',
                        'provided': 'Organizer-provided animal',
                      }[source]!,
                    ),
                  ),
              ],
              onChanged: (v) {
                animal['source'] = v;
                animal.remove('key');
                changed();
              },
              validator: (v) => required && (v == null || v.isEmpty)
                  ? 'Choose an animal source.'
                  : null,
            ),
            if (animal['source'] == 'entered')
              DropdownButtonFormField<String>(
                initialValue:
                    widget.animals.any((v) => v['key'] == animal['key'])
                    ? animal['key']
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Entered animal *',
                ),
                items: [
                  for (final v in widget.animals)
                    DropdownMenuItem(
                      value: '${v['key']}',
                      child: Text(
                        '${v['label']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => animal['key'] = v,
                validator: (v) =>
                    v == null ? 'Choose an entered animal.' : null,
              ),
            if (animal['source'] == 'own') ...[
              DropdownButtonFormField<String>(
                initialValue: ['rabbit', 'cavy'].contains(animal['species'])
                    ? animal['species']
                    : null,
                decoration: const InputDecoration(labelText: 'Species *'),
                items: const [
                  DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                  DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
                ],
                onChanged: (v) => animal['species'] = v,
                validator: (v) => v == null ? 'Choose a species.' : null,
              ),
              field('Animal name / ear number', animal, 'label'),
            ],
          ],
        ),
      ),
    );
  }
}
