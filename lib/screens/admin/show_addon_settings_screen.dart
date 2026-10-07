import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../widgets/contests/contest_configuration_editor.dart';
import '../../models/show_addon.dart';
import '../../models/contest_template.dart';
import '../../services/show_addon_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ringmaster_page_shell.dart';
import '../../utils/date_time_utils.dart';
import '../show_addon_registrations_screen.dart';

class ShowAddonSettingsScreen extends StatefulWidget {
  const ShowAddonSettingsScreen({
    super.key,
    required this.showId,
    required this.showName,
    required this.kind,
    this.service,
  });
  final String showId, showName, kind;
  final ShowAddonService? service;
  @override
  State<ShowAddonSettingsScreen> createState() =>
      _ShowAddonSettingsScreenState();
}

class _ShowAddonSettingsScreenState extends State<ShowAddonSettingsScreen> {
  late final _service = widget.service ?? ShowAddonService();
  bool _loading = true, _busy = false, _enabled = false;
  String? _error;
  String _currency = 'usd';
  List<ShowAddon> _items = [];
  DateTime? _showEntryOpenAt, _showEntryCloseAt;
  bool get _contest => widget.kind == 'contest';
  String get _title => _contest ? 'Contest Settings' : 'Show Add-Ons';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.catalog(widget.showId, admin: true);
      if (!mounted) return;
      setState(() {
        _enabled =
            data[_contest ? 'contests_enabled' : 'extras_enabled'] == true;
        _currency = data['currency'].toString();
        _showEntryOpenAt = DateTime.tryParse('${data['entry_open_at'] ?? ''}');
        _showEntryCloseAt = DateTime.tryParse(
          '${data['entry_close_at'] ?? ''}',
        );
        _items = (data['items'] as List)
            .map((r) => ShowAddon.fromJson(Map<String, dynamic>.from(r)))
            .where((o) => o.kind == widget.kind)
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.enable(widget.showId, widget.kind, value);
      if (mounted) setState(() => _enabled = value);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ShowAddon? item, bool duplicate = false]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShowAddonEditorScreen(
          showId: widget.showId,
          currency: _currency,
          item: item == null
              ? ShowAddon(kind: widget.kind, maxPerExhibitor: _contest ? 1 : 99)
              : ShowAddon.fromJson({
                  ...item.toJson(),
                  if (duplicate) 'id': const Uuid().v4(),
                  if (duplicate) 'name': '${item.name} (copy)',
                  if (duplicate) 'enabled': false,
                }),
          service: _service,
          offerings: _items,
          showEntryOpenAt: _showEntryOpenAt,
          showEntryCloseAt: _showEntryCloseAt,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(ShowAddon item) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.surfaceTheme(Theme.of(context)),
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('Delete Add-On?'),
          content: Text(
            'Delete “${item.name}”? It will no longer be available to order. '
            'Existing orders and payment history will be kept. '
            'Deleting an add-on does not cancel or refund existing orders.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.deleteOffering(widget.showId, item.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    useScrollView: true,
    title: _title,
    subtitle: widget.showName,
    showBackButton: true,
    actions: [
      IconButton(
        tooltip: 'Reload',
        onPressed: _busy ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
    ],
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : AppTheme.surfaceTextScope(
            context,
            child: Card(
              color: Colors.white,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _contest ? 'Enable contests' : 'Enable show add-ons',
                      ),
                      subtitle: Text(
                        _contest
                            ? 'Exhibitors can register for the contests you offer before checkout.'
                            : 'Offer tickets, passes, extra coops, and other items before checkout.',
                      ),
                      value: _enabled,
                      onChanged: _busy ? null : _toggle,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _contest
                          ? 'Registration uses the show’s entry dates by default. Each contest can have custom opening and closing dates in its setup. Saved registrations keep the price and answers recorded at entry.'
                          : 'Orders follow the show’s entry opening and closing dates. Saved orders keep the price recorded at checkout.',
                    ),
                    if (!_enabled)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Currently hidden from exhibitors. Set up your items, then enable them when ready.',
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _edit(),
                          icon: const Icon(Icons.add),
                          label: Text(_contest ? 'Add Contest' : 'Add Add-On'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ShowAddonRegistrationsScreen(
                                showId: widget.showId,
                                showName: widget.showName,
                                kind: widget.kind,
                                service: _service,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.list_alt),
                          label: Text(
                            _contest ? 'Manage Contests' : 'Add-On Orders',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_items.isEmpty)
                      Text(
                        _contest
                            ? 'No contests added yet.'
                            : 'No add-ons added yet.',
                      ),
                    for (final item in _items)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            _contest
                                ? Icons.emoji_events_outlined
                                : Icons.confirmation_number_outlined,
                          ),
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.priceCents == 0 ? 'Free' : addonMoney(item.priceCents, _currency)} • ${item.enabled ? 'Available when enabled' : 'Hidden'}${item.requiresAnimalEntry ? ' • Animal entry required' : ''}',
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: _contest
                                ? 'Contest options'
                                : 'Add-on options',
                            enabled: !_busy,
                            onSelected: (v) {
                              if (v == 'delete') {
                                _delete(item);
                              } else {
                                _edit(item, v == 'copy');
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('Duplicate'),
                              ),
                              if (!_contest)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                            ],
                          ),
                          onTap: _busy ? null : () => _edit(item),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
  );
}

class ShowAddonEditorScreen extends StatefulWidget {
  const ShowAddonEditorScreen({
    super.key,
    required this.showId,
    required this.currency,
    required this.item,
    required this.service,
    this.showEntryOpenAt,
    this.showEntryCloseAt,
    this.offerings = const [],
  });
  final String showId, currency;
  final ShowAddon item;
  final ShowAddonService service;
  final DateTime? showEntryOpenAt, showEntryCloseAt;
  final List<ShowAddon> offerings;
  @override
  State<ShowAddonEditorScreen> createState() => _ShowAddonEditorScreenState();
}

class _ShowAddonEditorScreenState extends State<ShowAddonEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item.name);
  late final _description = TextEditingController(
    text: widget.item.description,
  );
  late final _price = TextEditingController(
    text: (widget.item.priceCents / 100).toStringAsFixed(2),
  );
  late final _limit = TextEditingController(
    text: widget.item.maxPerExhibitor.toString(),
  );
  late List<String> _divisions = List.of(widget.item.divisions);
  bool _saving = false;
  bool _showAdditionalOptions = false;
  late bool _showDivisions = widget.item.divisions.isNotEmpty;
  ContestTemplate? _template;
  String _templateGroup = 'Individual', _templateSearch = '';
  List<String> _divisionNames() => List.of(_divisions);
  static const _ageDivisions = ['Junior', 'Intermediate', 'Senior'];
  static const _royaltyDivisions = [
    'King / Queen',
    'Duke / Duchess',
    'Prince / Princess',
    'Lord / Lady',
  ];
  List<String> get _suggestedDivisions =>
      _template == ContestTemplate.royalty ||
          _divisions.any(_royaltyDivisions.contains)
      ? _royaltyDivisions
      : _ageDivisions;
  String? _error;
  ShowAddon get item => widget.item;

  bool get _hasContestDetails =>
      _name.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _divisions.isNotEmpty ||
      item.fields.isNotEmpty ||
      item.requiresAnimalEntry ||
      item.animalSelection != 'none';

  Future<void> _applyTemplate(ContestTemplate template) async {
    if (_hasContestDetails) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          titleTextStyle: const TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: AppColors.text,
            fontSize: 16,
          ),
          title: const Text('Replace contest details?'),
          content: Text(
            '${template.title} will replace the name, instructions, divisions, animal requirements, and registration questions. Your fee, availability, and registration dates will be kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use Template'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final draft = template.createDraft();
    setState(() {
      _template = template;
      _showAdditionalOptions = false;
      _name.text = draft.name;
      _description.text = draft.description;
      _divisions = List.of(draft.divisions);
      _showDivisions = draft.divisions.isNotEmpty;
      item.requiresAnimalEntry = draft.requiresAnimalEntry;
      item.animalSelection = draft.animalSelection;
      item.fields = draft.fields;
      item.contest = draft.contest;
      _limit.text = draft.maxPerExhibitor.toString();
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _selectDivision(String name, bool selected) {
    if (!selected &&
        (item.contest.ageRules.any((r) => r['division'] == name) ||
            item.fields.any((f) => f.onlyDivision == name))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Remove the age range or question restriction for $name before removing this division.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (selected) {
        _divisions.add(name);
      } else {
        _divisions.remove(name);
      }
      _showDivisions = true;
    });
  }

  Future<void> _addDivision() async {
    final form = GlobalKey<FormState>();
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.surfaceTheme(Theme.of(dialogContext)),
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: AppColors.text),
          contentTextStyle: const TextStyle(color: AppColors.text),
          title: const Text('Add Custom Division'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: form,
              child: TextFormField(
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Division name',
                  helperText:
                      'Exhibitors will select this exact name when registering.',
                  helperMaxLines: 3,
                ),
                onChanged: (v) => name = v.trim(),
                validator: (_) {
                  if (name.isEmpty) return 'Enter a division name.';
                  if (_divisions.any(
                    (v) => v.toLowerCase() == name.toLowerCase(),
                  )) {
                    return 'That division is already selected.';
                  }
                  if (_divisions.length >= 100) {
                    return 'Use up to 100 divisions.';
                  }
                  return null;
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final canonical = [..._ageDivisions, ..._royaltyDivisions]
                    .where((v) => v.toLowerCase() == name.toLowerCase())
                    .firstOrNull;
                Navigator.pop(dialogContext, canonical ?? name);
              },
              child: const Text('Add Division'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) _selectDivision(result, true);
  }

  Widget _divisionChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Contest divisions', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Select the divisions offered. Exhibitors choose from these names. Leave all unselected if there are no divisions.',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in {..._suggestedDivisions, ..._divisions})
            FilterChip(
              label: Text(name),
              selected: _divisions.contains(name),
              onSelected: _saving
                  ? null
                  : (value) => _selectDivision(name, value),
            ),
        ],
      ),
      TextButton.icon(
        onPressed: _saving ? null : _addDivision,
        icon: const Icon(Icons.add),
        label: const Text('Add custom division'),
      ),
    ],
  );

  Future<void> _field([ContestField? existing]) async {
    final field = existing == null
        ? ContestField()
        : ContestField.fromJson(existing.toJson());
    final result = await showDialog<ContestField>(
      context: context,
      builder: (_) => _FieldEditor(
        field: field,
        categories: item.contest.categories,
        divisions: _divisionNames(),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (existing == null) {
          item.fields.add(result);
        } else {
          item.fields[item.fields.indexOf(existing)] = result;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final windowError = item.validateRegistrationWindow();
    if (windowError != null) {
      setState(() => _error = windowError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    item.name = _name.text;
    item.description = _description.text;
    item.priceCents = addonPriceCents(_price.text)!;
    item.maxPerExhibitor = int.parse(_limit.text);
    item.divisions = item.isContest ? _divisionNames() : [];
    final configError = item.contest.validate(item.divisions);
    if (item.isContest && configError != null) {
      setState(() {
        _error = configError;
        _saving = false;
      });
      return;
    }
    try {
      await widget.service.save(widget.showId, item);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickRegistrationDate(bool opening) async {
    final current = opening
        ? item.registrationOpenAt
        : item.registrationCloseAt;
    final base = current?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc();
      if (opening) {
        item.registrationOpenAt = picked;
      } else {
        item.registrationCloseAt = picked;
      }
      _error = null;
    });
  }

  Widget _registrationDate(bool opening) {
    final value = item.useShowEntryDates
        ? (opening ? widget.showEntryOpenAt : widget.showEntryCloseAt)
        : (opening ? item.registrationOpenAt : item.registrationCloseAt);
    final label = opening ? 'Registration opens' : 'Registration closes';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$label: ${value == null ? (item.useShowEntryDates ? 'No limit set on show' : 'Not set') : formatLocalDateTime(value.toIso8601String())}',
          ),
          if (!item.useShowEntryDates)
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _pickRegistrationDate(opening),
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(opening ? 'Set opening' : 'Set closing'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    useScrollView: true,
    title: item.isContest ? 'Contest Setup' : 'Add-On Setup',
    showBackButton: !_saving,
    body: AppTheme.surfaceTextScope(
      context,
      child: Card(
        color: Colors.white,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isContest) ...[
                  Text(
                    'Start with a template',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose a starting point or fill in a custom contest below. Review the suggested divisions, questions, and animal requirements for your show.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Find a contest template',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(
                      () => _templateSearch = v.trim().toLowerCase(),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final group in [
                        'Individual',
                        'Teams',
                        'Projects',
                        'Applications',
                      ])
                        ChoiceChip(
                          label: Text(group),
                          selected: _templateGroup == group,
                          onSelected: (_) =>
                              setState(() => _templateGroup = group),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final template in ContestTemplate.values.where(
                        (t) => _templateSearch.isEmpty
                            ? t.group == _templateGroup
                            : t.title.toLowerCase().contains(_templateSearch),
                      ))
                        ActionChip(
                          avatar: const Icon(
                            Icons.emoji_events_outlined,
                            size: 18,
                          ),
                          label: Text(template.title),
                          tooltip: template.summary,
                          onPressed: _saving
                              ? null
                              : () => _applyTemplate(template),
                        ),
                    ],
                  ),
                  if (_template != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${_template!.title} applied. Customize the details and fee below, then save.',
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
                if (!item.isContest) ...[
                  Text('Start with a suggested item, or enter your own name.'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in [
                        'Extra Coop',
                        'Parking Pass',
                        'Banquet Ticket',
                        'Tour Ticket',
                      ])
                        ActionChip(
                          label: Text(label),
                          onPressed: _saving ? null : () => _name.text = label,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _name,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: item.isContest ? 'Contest name' : 'Item name',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Description / instructions (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '${item.isContest ? 'Entry fee' : 'Unit price'} (${widget.currency.toUpperCase()})',
                    helperText: 'Enter 0 for no charge.',
                  ),
                  validator: (v) => addonPriceCents(v ?? '') == null
                      ? 'Enter an amount from 0 to 99,999.99.'
                      : null,
                ),
                ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: item.isContest
                          ? 'Maximum registrations per exhibitor'
                          : 'Maximum quantity per exhibitor',
                      helperText:
                          'Applies across the full show, including earlier purchases.',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 999
                          ? 'Enter a number from 1 to 999.'
                          : null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to exhibitors'),
                  subtitle: const Text(
                    'Turn off to stop new registrations or orders. Existing records are retained.',
                  ),
                  value: item.enabled,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => item.enabled = v),
                ),
                if (item.isContest) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use show entry dates'),
                    subtitle: const Text(
                      'Turn off to set custom registration dates for this contest.',
                    ),
                    value: item.useShowEntryDates,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            item.useShowEntryDates = value;
                            if (!value) {
                              item.registrationOpenAt ??=
                                  widget.showEntryOpenAt;
                              item.registrationCloseAt ??=
                                  widget.showEntryCloseAt;
                            }
                            _error = null;
                          }),
                  ),
                  _registrationDate(true),
                  _registrationDate(false),
                  const Text(
                    'Dates and times are shown in your current time zone.',
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: Icon(
                      _showAdditionalOptions ? Icons.remove : Icons.tune,
                    ),
                    label: Text(
                      _showAdditionalOptions
                          ? 'Hide unused setup options'
                          : 'Additional setup options',
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _showAdditionalOptions =
                                !_showAdditionalOptions,
                          ),
                  ),
                  if (_showAdditionalOptions || _showDivisions) ...[
                    _divisionChoices(),
                    const SizedBox(height: 20),
                  ],
                  if (_showAdditionalOptions ||
                      item.animalSelection != 'none' ||
                      item.contest.expandedAnimals) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(item.animalSelection),
                      initialValue: item.animalSelection,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Choose an entered animal',
                        helperText:
                            'Only animals entered for the selected exhibitor in this show or their current cart are offered.',
                        helperMaxLines: 3,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Not used for this contest'),
                        ),
                        DropdownMenuItem(
                          value: 'optional',
                          child: Text('Optional animal selection'),
                        ),
                        DropdownMenuItem(
                          value: 'required',
                          child: Text('Required animal selection'),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => item.animalSelection = v!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_showAdditionalOptions ||
                      item.requiresAnimalEntry ||
                      item.animalSelection != 'none' ||
                      item.contest.expandedAnimals)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Require an animal entry'),
                      subtitle: const Text(
                        'The same exhibitor must have an animal entered in this show or in this cart.',
                      ),
                      value: item.requiresAnimalEntry,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => item.requiresAnimalEntry = v),
                    ),
                  const Text(
                    'Exhibitor names and numbers are included automatically. Each project or team is a separate registration.',
                  ),
                  ContestConfigurationEditor(
                    key: ObjectKey(item.contest),
                    item: item,
                    divisions: _divisionNames,
                    offerings: widget.offerings,
                    showAdditionalOptions: _showAdditionalOptions,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Questions for exhibitors',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Exhibitors answer these questions when they register for this contest. Templates suggest a few to start with. Select a question to edit it, or use the trash icon to remove it.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Names, exhibitor numbers, and any division or animal selections are collected automatically. Only add questions for other information you need, such as club or chapter.',
                  ),
                  if (item.contest.needsBirthdate &&
                      item.fields.any(
                        (field) => field.label == 'Age on contest date',
                      )) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Birthdate is already collected under Age and eligibility. You can remove the separate age question if you do not need it.',
                    ),
                  ],
                  for (final field in item.fields)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(field.label),
                      subtitle: Text(
                        '${_fieldTypeLabel(field.type)}${field.required ? ' • Required' : ' • Optional'}',
                      ),
                      onTap: _saving ? null : () => _field(field),
                      trailing: IconButton(
                        tooltip: 'Remove ${field.label}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _saving
                            ? null
                            : () => setState(() => item.fields.remove(field)),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _saving || item.fields.length >= 40
                        ? null
                        : () => _field(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Question'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _fieldTypeLabel(String type) =>
    const {
      'text': 'Short text',
      'long_text': 'Long text',
      'number': 'Number',
      'date': 'Date',
      'checkbox': 'Checkbox',
      'select': 'Dropdown',
      'multi_select': 'Multiple choice',
      'url': 'Web / video link',
      'file': 'File upload (PDF or image)',
    }[type] ??
    type;

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.field,
    this.categories = const [],
    this.divisions = const [],
  });
  final List<String> categories, divisions;
  final ContestField field;
  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.field.label);
  late final _options = TextEditingController(
    text: widget.field.options.join('\n'),
  );
  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.surfaceTheme(Theme.of(context)),
    child: AlertDialog(
      backgroundColor: Colors.white,
      titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.text),
      title: const Text('Question for Exhibitors'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _label,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Question'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a label.' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: widget.field.type,
                  decoration: const InputDecoration(labelText: 'Answer format'),
                  items: [
                    for (final type in [
                      'text',
                      'long_text',
                      'number',
                      'date',
                      'checkbox',
                      'select',
                      'multi_select',
                      'url',
                      'file',
                    ])
                      DropdownMenuItem(
                        value: type,
                        child: Text(_fieldTypeLabel(type)),
                      ),
                  ],
                  onChanged: (v) => setState(() => widget.field.type = v!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Required'),
                  value: widget.field.required,
                  onChanged: (v) => setState(() => widget.field.required = v),
                ),
                if (widget.field.type == 'text' ||
                    widget.field.type == 'long_text')
                  TextFormField(
                    initialValue: widget.field.maxLength.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum answer length',
                    ),
                    validator: (v) =>
                        (int.tryParse(v ?? '') ?? 0) < 1 ||
                            (int.tryParse(v ?? '') ?? 0) > 20000
                        ? 'Enter 1–20,000.'
                        : null,
                    onChanged: (v) =>
                        widget.field.maxLength = int.tryParse(v) ?? 2000,
                  ),
                for (final division in [false, true])
                  if ((division ? widget.divisions : widget.categories)
                      .isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue:
                          (division ? widget.divisions : widget.categories)
                              .contains(
                                division
                                    ? widget.field.onlyDivision
                                    : widget.field.onlyCategory,
                              )
                          ? (division
                                ? widget.field.onlyDivision
                                : widget.field.onlyCategory)
                          : '',
                      decoration: InputDecoration(
                        labelText: division
                            ? 'Show for division'
                            : 'Show for category',
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All')),
                        for (final v
                            in (division
                                ? widget.divisions
                                : widget.categories))
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) {
                        if (division) {
                          widget.field.onlyDivision = v!;
                        } else {
                          widget.field.onlyCategory = v!;
                        }
                      },
                    ),
                if (['select', 'multi_select'].contains(widget.field.type))
                  TextFormField(
                    controller: _options,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Choices (one per line)',
                    ),
                    validator: (v) {
                      final choices = (v ?? '')
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      if (choices.isEmpty ||
                          choices.length > 100 ||
                          choices.any((s) => s.length > 120) ||
                          choices.toSet().length != choices.length) {
                        return 'Enter 1–100 unique choices, up to 120 characters each.';
                      }
                      return null;
                    },
                  ),
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
            if (!_form.currentState!.validate()) return;
            widget.field.label = _label.text.trim();
            widget.field.options =
                ['select', 'multi_select'].contains(widget.field.type)
                ? _options.text
                      .split('\n')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList()
                : [];
            Navigator.pop(context, widget.field);
          },
          child: const Text('Save Question'),
        ),
      ],
    ),
  );
}
