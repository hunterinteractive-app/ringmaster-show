import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../services/app_session.dart';
import '../../services/show_wave_schedule.dart';
import '../../theme/app_theme.dart';

class ShowWaveScheduleDialog extends StatefulWidget {
  const ShowWaveScheduleDialog({
    super.key,
    required this.showId,
    required this.showName,
    this.readOnly = false,
  });
  final String showId;
  final String showName;
  final bool readOnly;
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
    bool readOnly = false,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppTheme.gradientTextScope(
      context,
      child: ShowWaveScheduleDialog(
        showId: showId,
        showName: showName,
        readOnly: readOnly,
      ),
    ),
  );
  @override
  State<ShowWaveScheduleDialog> createState() => _ShowWaveScheduleDialogState();
}

class _ShowWaveScheduleDialogState extends State<ShowWaveScheduleDialog> {
  late final _service = ShowWaveScheduleService(Supabase.instance.client);
  ShowWaveSchedule? _schedule;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _search = '';
  bool get _readOnly =>
      widget.readOnly ||
      AppSession.isSupportMode ||
      _schedule?.canConfigure != true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final schedule = await _service.load(widget.showId);
      if (schedule.waves.isEmpty) {
        schedule.waves.addAll(
          List.generate(
            3,
            (i) => ShowWave(id: const Uuid().v4(), number: i + 1),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _schedule = schedule;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  String _message(Object e) => e is PostgrestException
      ? e.message
      : e.toString().replaceFirst('Bad state: ', '');
  Future<void> _save() async {
    final validation = _schedule!.validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.save(widget.showId, _schedule!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _pickDate(
    DateTime? value,
    void Function(DateTime) change, {
    bool withTime = false,
  }) async {
    final current = value ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) =>
          AppTheme.surfaceTextScope(context, child: child!),
    );
    if (date == null || !mounted) return;
    TimeOfDay? time;
    if (withTime) {
      time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: value?.hour ?? 8,
          minute: value?.minute ?? 0,
        ),
        builder: (context, child) =>
            AppTheme.surfaceTextScope(context, child: child!),
      );
      if (time == null || !mounted) return;
    }
    setState(
      () => change(
        DateTime(
          date.year,
          date.month,
          date.day,
          time?.hour ?? 0,
          time?.minute ?? 0,
        ),
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime? value,
    void Function(DateTime) change, {
    bool withTime = false,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      value == null
          ? 'Not set'
          : DateFormat(
              withTime ? 'MMM d, yyyy • h:mm a' : 'MMM d, yyyy',
            ).format(value),
    ),
    trailing: const Icon(Icons.calendar_today_outlined),
    onTap: _saving || _readOnly
        ? null
        : () => _pickDate(value, change, withTime: withTime),
  );
  Widget _breedTab() {
    final schedule = _schedule!;
    final breeds =
        schedule.breeds
            .where(
              (b) =>
                  b.hasEntries &&
                  '${b.name} ${b.species}'.toLowerCase().contains(
                    _search.toLowerCase(),
                  ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Text(
            'Entered breeds from all show sections. A wave is required for '
            'check-in and wave sheets.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: AppTheme.surfaceTextScope(
            context,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Find a breed',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
        Expanded(
          child: breeds.isEmpty
              ? Center(
                  child: Text(
                    _search.isEmpty
                        ? 'No breeds have been entered in this show yet.'
                        : 'No entered breeds match your search.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: breeds.length,
                  itemBuilder: (context, index) {
                    final breed = breeds[index];
                    return ListTile(
                      title: Text(breed.name),
                      subtitle: Text(
                        breed.species == 'cavy' ? 'Cavy' : 'Rabbit',
                      ),
                      trailing: SizedBox(
                        width: 150,
                        child: AppTheme.surfaceTextScope(
                          context,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              '${breed.species}:${breed.name}:${breed.waveId}',
                            ),
                            initialValue: breed.waveId ?? '',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Wave',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.never,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Unassigned'),
                              ),
                              ...schedule.waves.map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: Text(w.name),
                                ),
                              ),
                            ],
                            onChanged: _saving || _readOnly
                                ? null
                                : (v) => setState(
                                    () => breed.waveId = v == '' ? null : v,
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _scheduleTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Text('All dates and times use ${_schedule!.timezone}.'),
      const SizedBox(height: 8),
      ..._schedule!.waves.map(
        (wave) => Card(
          color: AppColors.pageBackgroundMid,
          surfaceTintColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        wave.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${wave.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _saving || _readOnly
                          ? null
                          : () => setState(() {
                              _schedule!.waves.remove(wave);
                              for (final b in _schedule!.breeds) {
                                if (b.waveId == wave.id) b.waveId = null;
                              }
                            }),
                    ),
                  ],
                ),
                _dateField(
                  'Check-in start',
                  wave.checkinStart,
                  (v) => wave.checkinStart = v,
                  withTime: true,
                ),
                _dateField(
                  'Check-in end',
                  wave.checkinEnd,
                  (v) => wave.checkinEnd = v,
                  withTime: true,
                ),
                _dateField(
                  'Show date',
                  wave.showDate,
                  (v) => wave.showDate = v,
                ),
                _dateField(
                  'Check-out date',
                  wave.checkoutDate,
                  (v) => wave.checkoutDate = v,
                ),
                const SizedBox(height: 8),
                const Text('Email sheets before check-in starts'),
                const SizedBox(height: 8),
                AppTheme.surfaceTextScope(
                  context,
                  child: DropdownButtonFormField<int>(
                    initialValue: wave.emailLeadHours,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Email sheets before check-in starts',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    items: waveEmailLeadHours
                        .map(
                          (h) => DropdownMenuItem(
                            value: h,
                            child: Text(
                              '${waveLeadLabel(h)}${h == 24 ? ' (default)' : ''}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving || _readOnly
                        ? null
                        : (v) => setState(() => wave.emailLeadHours = v ?? 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add wave'),
        onPressed: _saving || _readOnly || _schedule!.waves.length >= 50
            ? null
            : () => setState(() {
                final numbers = _schedule!.waves.map((w) => w.number).toSet();
                var n = 1;
                while (numbers.contains(n)) {
                  n++;
                }
                _schedule!.waves.add(
                  ShowWave(id: const Uuid().v4(), number: n),
                );
                _schedule!.waves.sort((a, b) => a.number.compareTo(b.number));
              }),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: AppColors.pageBackground,
      surfaceTintColor: Colors.transparent,
      child: SizedBox(
        width: 850,
        height: MediaQuery.sizeOf(context).height * .88,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Wave Schedule',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                widget.showName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.orange.shade200),
                  ),
                ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_schedule != null) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable wave schedule'),
                  subtitle: const Text(
                    'Automatically email sheets per wave and restrict portal check-in to its scheduled window. Enable the portal in Check-In Settings.',
                  ),
                  value: _schedule!.enabled,
                  onChanged: _saving || _readOnly
                      ? null
                      : (v) => setState(() => _schedule!.enabled = v),
                ),
                const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: AppColors.primaryButton,
                  tabs: [
                    Tab(text: 'Breed Assignments'),
                    Tab(text: 'Schedule'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [_breedTab(), _scheduleTab()]),
                ),
              ] else
                const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed:
                        _loading || _saving || _schedule == null || _readOnly
                        ? null
                        : _save,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
