import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/show_addon.dart';
import '../../models/contest_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_time_utils.dart';

class ContestConfigurationEditor extends StatefulWidget {
  const ContestConfigurationEditor({
    super.key,
    required this.item,
    required this.divisions,
    this.offerings = const [],
    this.showAdditionalOptions = false,
    required this.onChanged,
  });
  final ShowAddon item;
  final List<String> Function() divisions;
  final List<ShowAddon> offerings;
  final bool showAdditionalOptions;
  final VoidCallback onChanged;
  @override
  State<ContestConfigurationEditor> createState() =>
      _ContestConfigurationEditorState();
}

class _ContestConfigurationEditorState
    extends State<ContestConfigurationEditor> {
  ContestSettings get cfg => widget.item.contest;
  bool _editingCategories = false;
  bool get showCategories =>
      widget.showAdditionalOptions ||
      _editingCategories ||
      cfg.categories.isNotEmpty;
  bool get showAnimals => widget.showAdditionalOptions || cfg.expandedAnimals;
  bool get showSubmissions =>
      widget.showAdditionalOptions ||
      cfg.isProject ||
      cfg.group == 'Applications' ||
      cfg.text('submission_close_at').isNotEmpty ||
      widget.item.fields.any((f) => f.type == 'file' || f.type == 'url');
  List<String> get resultGroups => [
    if (widget.divisions().isNotEmpty) 'division',
    if (cfg.categories.isNotEmpty) 'category',
    if (cfg.sessions.isNotEmpty) 'session',
  ];
  String get resultScope => resultGroups.isEmpty
      ? 'the full contest'
      : 'each ${resultGroups.join(' / ')} group';
  void change(VoidCallback action) {
    setState(action);
    widget.onChanged();
  }

  Widget number(
    String key,
    String label, {
    int initial = 0,
    int max = 100000,
    String? help,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey('number-$key-${widget.item.id}'),
      initialValue: cfg.number(key, initial).toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        label: Text(label, softWrap: true),
        helperText: help,
        helperMaxLines: 5,
      ),
      validator: (s) {
        final n = int.tryParse(s ?? '');
        return n == null || n < 0 || n > max ? 'Enter 0–$max.' : null;
      },
      onChanged: (v) => cfg.data[key] = int.tryParse(v) ?? -1,
    ),
  );
  Widget lines(String key, String label, {String? help}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey('lines-$key-${widget.item.id}'),
      initialValue: cfg.strings(key).join('\n'),
      minLines: 2,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: label,
        helperText: help,
        helperMaxLines: 3,
      ),
      onChanged: (v) {
        if (key == 'categories') _editingCategories = true;
        cfg.data[key] = v
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        widget.onChanged();
      },
    ),
  );
  Widget toggle(
    String key,
    String label, {
    bool initial = false,
    String? help,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: help == null ? null : Text(help),
    value: cfg.flag(key, initial),
    onChanged: (v) => change(() => cfg.data[key] = v),
  );
  Widget select(
    String key,
    String label,
    Map<String, String> choices,
    String initial,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$key-${cfg.text(key, initial)}'),
      initialValue: cfg.text(key, initial),
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in choices.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) => change(() => cfg.data[key] = v),
    ),
  );
  Widget section(String title, List<Widget> children) => ExpansionTile(
    key: ValueKey(title),
    maintainState: true,
    tilePadding: EdgeInsets.zero,
    title: Text(title),
    childrenPadding: const EdgeInsets.only(bottom: 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
  Future<void> pickDate(String key, {bool dateOnly = false}) async {
    final value = DateTime.tryParse(cfg.text(key))?.toLocal() ?? DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    if (dateOnly) {
      change(() => cfg.data[key] = day.toIso8601String().substring(0, 10));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !mounted) return;
    change(
      () => cfg.data[key] = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).toUtc().toIso8601String(),
    );
  }

  Widget date(String key, String label, {bool dateOnly = false}) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      cfg.text(key).isEmpty
          ? 'Not set'
          : dateOnly
          ? cfg.text(key)
          : formatLocalDateTime(cfg.text(key)),
    ),
    trailing: Wrap(
      children: [
        IconButton(
          tooltip: 'Set $label',
          onPressed: () => pickDate(key, dateOnly: dateOnly),
          icon: const Icon(Icons.calendar_today),
        ),
        if (cfg.text(key).isNotEmpty)
          IconButton(
            tooltip: 'Clear $label',
            onPressed: () => change(() => cfg.data.remove(key)),
            icon: const Icon(Icons.clear),
          ),
      ],
    ),
  );
  Future<void> edit(String kind, [Map<String, dynamic>? existing]) async {
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RuleDialog(
        kind: kind,
        existing: existing,
        divisions: widget.divisions(),
        resultGroups: resultGroups,
      ),
    );
    if (value == null || !mounted) return;
    change(() {
      final list = cfg.rows(kind);
      if (existing == null) {
        list.add(value);
      } else {
        list[list.indexWhere(
              (r) => kind == 'age_rules'
                  ? r['division'] == existing['division']
                  : kind == 'sessions'
                  ? r['id'] == existing['id']
                  : r['name'] == existing['name'],
            )] =
            value;
      }
      cfg.data[kind] = list;
    });
  }

  Widget records(String kind, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final r in cfg.rows(kind))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${r['name'] ?? r['division']}'),
          subtitle: Text(
            kind == 'age_rules'
                ? 'Ages ${r['min']}–${r['max']}'
                : kind == 'sessions'
                ? '${formatLocalDateTime(r['starts_at'])} • ${r['capacity'] == 0 ? 'No capacity limit' : 'Capacity ${r['capacity']}'}'
                : '${r['scope'] == 'contest' ? 'Full contest' : resultScope} • ${r['recipients'] == 0 ? 'Multiple recipients' : '${r['recipients']} recipient(s)'}',
          ),
          onTap: () => edit(kind, r),
          trailing: IconButton(
            tooltip: 'Remove ${r['name'] ?? r['division']}',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => change(
              () => cfg.data[kind] = cfg.rows(kind)
                ..removeWhere(
                  (v) => kind == 'age_rules'
                      ? v['division'] == r['division']
                      : kind == 'sessions'
                      ? v['id'] == r['id']
                      : v['name'] == r['name'],
                ),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => edit(kind),
        icon: const Icon(Icons.add),
        label: Text(label),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      if (widget.showAdditionalOptions)
        select('entry_type', 'Who is entering?', {
          'individual': 'Individual',
          'team': 'Team',
          'project': 'Individual project',
        }, 'individual')
      else
        Text(
          cfg.isTeam
              ? 'Team contest'
              : cfg.isProject
              ? 'Project contest'
              : 'Individual contest',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      if (cfg.isTeam)
        const Text(
          'The selected exhibitor coordinates the team. One checkout pays the team fee.',
        ),
      if (cfg.isProject)
        const Text(
          'Each project has its own title, registration, and results.',
        ),
      if (showCategories)
        section('Categories', [
          lines(
            'categories',
            'Categories (one per line)',
            help: cfg.isProject
                ? 'Optional. For example: Poster and Photography. Categories are separate from age divisions.'
                : 'Optional separate contest tracks, such as Rabbit Judging and Cavy Judging. Use divisions for age groups.',
          ),
          number(
            'category_limit',
            'Maximum entries per exhibitor in each category',
            help: '0 means use only the overall entry limit.',
          ),
        ]),
      section('Full contest registration limit', [
        const Text(
          'This limit covers all exhibitors, divisions, categories, and sessions combined. Each team or project counts as one registration.',
        ),
        number(
          'capacity',
          'Maximum total registrations',
          help:
              '0 means unlimited. The per-exhibitor limit is set separately above. A place is reserved when registration is submitted at checkout.',
        ),
        toggle(
          'requires_approval',
          'Secretary approval required',
          help:
              'Submitted registrations wait for review. Payment remains separate.',
        ),
      ]),
      section('Age and eligibility', [
        toggle('collect_birthdate', 'Collect contestant birthdate'),
        if (cfg.needsBirthdate || cfg.isTeam || widget.showAdditionalOptions)
          select('age_as_of', 'Determine age as of', {
            'show_start': 'Show start date',
            'show_end': 'Show end date',
            'custom': 'Custom date',
          }, 'show_start'),
        if ((cfg.needsBirthdate ||
                cfg.isTeam ||
                widget.showAdditionalOptions) &&
            cfg.text('age_as_of') == 'custom')
          date('age_date', 'Age cutoff date', dateOnly: true),
        if (widget.divisions().isNotEmpty || cfg.ageRules.isNotEmpty) ...[
          const Text('Optionally set an age range for each division.'),
          records('age_rules', 'Add Age Range'),
        ],
        const SizedBox(height: 8),
        const Text(
          'Use Questions for exhibitors below for membership requirements, acknowledgments, and other eligibility questions.',
        ),
      ]),
      if (cfg.isTeam)
        section('Team roster', [
          number('team_min', 'Minimum active members', initial: 3, max: 20),
          number('team_max', 'Maximum active members', initial: 4, max: 20),
          number('team_alternates', 'Maximum alternates', max: 10),
          if (cfg.ageRules.isNotEmpty || widget.showAdditionalOptions)
            select('team_age_rule', 'Team division age rule', {
              'oldest': 'Age of oldest member',
              'all': 'Every member must fit the division',
            }, 'oldest'),
          if (widget.offerings.any(
                (o) =>
                    o.id != widget.item.id &&
                    o.isContest &&
                    o.contest.entryType == 'individual',
              ) ||
              cfg.text('prerequisite_contest_id').isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(cfg.text('prerequisite_contest_id')),
              initialValue: cfg.text('prerequisite_contest_id'),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Required individual contest',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('No individual registration required'),
                ),
                for (final o in widget.offerings.where(
                  (o) =>
                      o.id != widget.item.id &&
                      o.isContest &&
                      o.contest.entryType == 'individual',
                ))
                  DropdownMenuItem(
                    value: o.id,
                    child: Text(o.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => cfg.data['prerequisite_contest_id'] = v,
            ),
            const Text(
              'When required, members supply exhibitor numbers so their individual registrations can be verified.',
            ),
          ],
        ]),
      if (showAnimals)
        section('Animal options', [
          const Text(
            'Leave these choices blank to use the entered-animal setting above. Otherwise choose the allowed animal sources.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final source in {
                'entered': 'Entered animal',
                'own': 'Bring an animal',
                'provided': 'Organizer provides animal',
              }.entries)
                FilterChip(
                  label: Text(source.value),
                  selected: cfg.animalSources.contains(source.key),
                  onSelected: (v) => change(() {
                    final values = cfg.animalSources;
                    if (v) {
                      values.add(source.key);
                    } else {
                      values.remove(source.key);
                    }
                    cfg.data['animal_sources'] = values;
                  }),
                ),
            ],
          ),
          lines(
            'animal_roles',
            'Animal roles (one per line)',
            help:
                'Optional. For example: Doe / Sow, Offspring 1, Offspring 2. Set animal selection to Required above when each role is required.',
          ),
        ]),
      section('Schedule and sessions', [
        const Text(
          'Contest check-in is recorded by staff under Contest Settings → Manage Contests → Check-In. It is separate from the animal check-in portal. These dates tell exhibitors when to report for contest check-in.',
        ),
        const SizedBox(height: 12),
        toggle(
          'allow_walkup',
          'Allow secretary-entered walk-up registrations',
          help:
              'Secretaries can register an exhibitor after online registration closes. Fees are added to their balance for payment at the show.',
        ),
        date('checkin_open_at', 'Check-in opens'),
        date('checkin_close_at', 'Check-in closes'),
        if (showSubmissions) date('submission_close_at', 'Submission deadline'),
        const SizedBox(height: 12),
        const Text(
          'Sessions are optional time slots for this contest, such as Morning Judging and Afternoon Judging. Add them only if exhibitors should choose a time slot. Each slot can have its own registration limit.',
        ),
        records('sessions', 'Add Time Slot'),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: cfg.text('schedule_notes'),
          minLines: 3,
          maxLines: 6,
          maxLength: 3000,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Schedule instructions',
            alignLabelWithHint: true,
            hintText:
                'Activity times, drop-off, pickup, location, or other instructions.',
            hintMaxLines: 3,
            helperText: 'Shown to exhibitors during registration.',
            helperMaxLines: 2,
          ),
          onChanged: (v) => cfg.data['schedule_notes'] = v,
        ),
      ]),
      section('Placings and awards', [
        toggle('results_enabled', 'Record contest results', initial: true),
        if (cfg.flag('results_enabled', true)) ...[
          number(
            'places',
            'Maximum number of placements available',
            initial: 20,
            max: 9999,
            help:
                'Enter 3 to allow first through third place for $resultScope.',
          ),
          toggle('allow_ties', 'Allow tied placings'),
          if (cfg.isProject ||
              cfg.number('max_awarded_per_exhibitor') > 0 ||
              widget.showAdditionalOptions)
            number(
              'max_awarded_per_exhibitor',
              cfg.isProject
                  ? 'Maximum placed projects per exhibitor in a category'
                  : 'Maximum placed entries per exhibitor in a category',
              help: '0 means no additional limit.',
            ),
          const SizedBox(height: 12),
          const Text(
            'Special awards are optional titles, such as Champion, Best Presentation, King, or Queen. They are recorded alongside numbered placings.',
          ),
          records('awards', 'Add Special Award'),
          const Text(
            'Skip this if you only use numbered placings. Award recipients are selected in Manage Contests → Results.',
          ),
        ],
      ]),
    ],
  );
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.kind,
    this.existing,
    required this.divisions,
    required this.resultGroups,
  });
  final String kind;
  final Map<String, dynamic>? existing;
  final List<String> divisions;
  final List<String> resultGroups;
  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final form = GlobalKey<FormState>();
  late final Map<String, dynamic> row = Map.of(widget.existing ?? {});
  String? error;
  Widget number(String key, String label, int fallback) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      initialValue: '${row[key] ?? fallback}',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onSaved: (v) => row[key] = int.parse(v!),
      validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0
          ? 'Enter a nonnegative whole number.'
          : null,
    ),
  );
  Future<void> pick(String key) async {
    final current =
        DateTime.tryParse('${row[key] ?? ''}')?.toLocal() ?? DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(
      () => row[key] = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).toUtc().toIso8601String(),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.surfaceTheme(Theme.of(context)),
    child: AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(color: AppColors.text),
      contentTextStyle: const TextStyle(color: AppColors.text),
      title: Text(
        widget.kind == 'age_rules'
            ? 'Division Age Range'
            : widget.kind == 'sessions'
            ? 'Contest Time Slot'
            : 'Special Award',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.kind == 'age_rules') ...[
                  DropdownButtonFormField<String>(
                    initialValue: row['division'],
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Division'),
                    items: [
                      for (final v in widget.divisions)
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) => row['division'] = v,
                    validator: (v) => v == null ? 'Choose a division.' : null,
                  ),
                  number('min', 'Minimum age', 0),
                  number('max', 'Maximum age', 18),
                ] else ...[
                  Text(
                    widget.kind == 'sessions'
                        ? 'Offer a time slot exhibitors can select when registering, such as Morning Judging. Leave sessions empty if everyone attends together.'
                        : 'Add an award title, such as Champion or Best Presentation. Choose the recipient later in contest results.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: row['name'],
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: widget.kind == 'sessions'
                          ? 'Time slot name'
                          : 'Award title',
                    ),
                    onSaved: (v) => row['name'] = v!.trim(),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                  ),
                  if (widget.kind == 'sessions') ...[
                    for (final key in ['starts_at', 'ends_at'])
                      ListTile(
                        title: Text(key == 'starts_at' ? 'Starts' : 'Ends'),
                        subtitle: Text(
                          row[key] == null
                              ? 'Not set'
                              : formatLocalDateTime(row[key]),
                        ),
                        trailing: IconButton(
                          tooltip: 'Set date and time',
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () => pick(key),
                        ),
                      ),
                    number('capacity', 'Time slot limit (0 = unlimited)', 0),
                    const Text(
                      'Total registrations in this time slot. The full contest limit still applies.',
                    ),
                  ] else ...[
                    number('recipients', 'Recipients (0 = unlimited)', 1),
                    const SizedBox(height: 16),
                    if (widget.resultGroups.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: row['scope'] ?? 'division',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Award applies to',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'division',
                            child: const Text('Each result group'),
                          ),
                          const DropdownMenuItem(
                            value: 'contest',
                            child: Text('One award across the contest'),
                          ),
                        ],
                        onChanged: (v) => row['scope'] = v,
                      ),
                    if (widget.resultGroups.isNotEmpty)
                      Text(
                        'A result group is each ${widget.resultGroups.join(' / ')} combination. The recipient limit applies to each group, or to the full contest if selected.',
                      )
                    else
                      const Text(
                        'The recipient limit applies to the full contest.',
                      ),
                  ],
                ],
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            form.currentState!.save();
            if (widget.kind == 'age_rules' &&
                ((row['max'] as int) < (row['min'] as int) ||
                    (row['max'] as int) > 120)) {
              setState(() => error = 'Check the age range.');
              return;
            }
            if (widget.kind == 'sessions') {
              final start = DateTime.tryParse('${row['starts_at']}');
              final end = DateTime.tryParse('${row['ends_at']}');
              if (start == null || end == null || !end.isAfter(start)) {
                setState(() => error = 'Set an ending after the start.');
                return;
              }
              row['id'] ??= const Uuid().v4();
            }
            if (widget.kind == 'awards') row['scope'] ??= 'division';
            Navigator.pop(context, row);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
