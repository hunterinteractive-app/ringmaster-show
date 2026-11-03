import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/catalog/recognition_timeline.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

class RecognitionTimelineScreen extends StatefulWidget {
  const RecognitionTimelineScreen({
    super.key,
    required this.species,
    required this.breedName,
    this.varietyName = '',
  });
  final String species;
  final String breedName;
  final String varietyName;

  @override
  State<RecognitionTimelineScreen> createState() =>
      _RecognitionTimelineScreenState();
}

class _RecognitionTimelineScreenState extends State<RecognitionTimelineScreen> {
  final _date = TextEditingController();
  final _source = TextEditingController();
  final _preview = TextEditingController();
  RecognitionStatus _status = RecognitionStatus.recognized;
  List<RecognitionTransition> _events = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _form = GlobalKey<FormState>();
  String get _target {
    final date = DateTime.now();
    final breedStatus = resolveRecognitionStatus(
      breedName: widget.breedName,
      judgingDate: date,
      transitions: _events,
    );
    final breedLabel = recognitionDisplayName(widget.breedName, breedStatus);
    if (widget.varietyName.isEmpty) return breedLabel;
    final status = resolveRecognitionStatus(
      breedName: widget.breedName,
      varietyName: widget.varietyName,
      judgingDate: date,
      transitions: _events,
    );
    return '$breedLabel — ${recognitionDisplayName(widget.varietyName, status)}';
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime? _parse(String value) {
    final d = DateTime.tryParse(value);
    return d != null && d.year >= 1900 && d.year <= 2200 && _iso(d) == value
        ? d
        : null;
  }

  @override
  void initState() {
    super.initState();
    _date.text = _iso(DateTime.now());
    _preview.text = _date.text;
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    _source.dispose();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final events = <RecognitionTransition>[];
      // Read all transitions even when the API caps pages below our limit.
      while (true) {
        final rows = await Supabase.instance.client
            .from('catalog_recognition_history')
            .select()
            .eq('species', widget.species)
            .eq('breed_key', recognitionKey(widget.breedName))
            .order('effective_date')
            .order('id')
            .range(events.length, events.length + 999);
        if (rows.isEmpty) break;
        events.addAll(rows.map(RecognitionTransition.fromJson));
      }
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load status history: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .from('catalog_recognition_history')
          .insert({
            'species': widget.species,
            'breed_name': widget.breedName,
            'variety_name': widget.varietyName,
            'status': _status.name,
            'effective_date': _date.text.trim(),
            'source_note': _source.text.trim(),
          });
      _source.clear();
      await _load();
      if (mounted && _error == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dated status saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(RecognitionTransition event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove scheduled change?'),
        content: Text(
          '${event.status.label} from ${_iso(event.effectiveDate)} will be removed. The previous status will continue to apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('catalog_recognition_history')
          .delete()
          .eq('id', event.id)
          .select()
          .single();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not remove: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateField(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      hintText: 'YYYY-MM-DD',
      suffixIcon: IconButton(
        tooltip: 'Choose date',
        icon: const Icon(Icons.calendar_today),
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _parse(controller.text) ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (d != null && mounted) setState(() => controller.text = _iso(d));
        },
      ),
    ),
    onChanged: (_) => setState(() {}),
    validator: required
        ? (v) => _parse(v?.trim() ?? '') == null
              ? 'Enter a valid date as YYYY-MM-DD.'
              : null
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final own = _events
        .where(
          (e) =>
              recognitionKey(e.varietyName) ==
              recognitionKey(widget.varietyName),
        )
        .toList();
    final date = _parse(_preview.text.trim());
    final status = resolveRecognitionStatus(
      breedName: widget.breedName,
      varietyName: widget.varietyName,
      judgingDate: date,
      transitions: _events,
    );
    final today = DateTime.now();
    final todayStatus = resolveRecognitionStatus(
      breedName: widget.breedName,
      varietyName: widget.varietyName,
      judgingDate: today,
      transitions: _events,
    );
    final shownName = recognitionDisplayName(
      widget.varietyName.isEmpty ? widget.breedName : widget.varietyName,
      todayStatus,
    );
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Status history — $_target',
      showBackButton: true,
      useScrollView: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppTheme.surfaceTextScope(
              context,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _target,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Each change starts on its effective date. Eligibility follows the section’s judging date, not the entry date or the date a report is generated. Before the first change, the existing catalog status applies.',
                          ),
                          if (widget.varietyName.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'The breed’s status also applies. A recognized variety cannot override a COD or retired breed.',
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            'Current name: $shownName',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'The (COD) suffix follows the effective status automatically. Recognized means active for awards; catalog availability is separate.',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Status history',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (own.isEmpty) const Text('No dated changes yet.'),
                          for (final event in own)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${event.status.label} — effective ${_iso(event.effectiveDate)}',
                              ),
                              subtitle: Text(
                                event.sourceNote.isEmpty
                                    ? 'No source note'
                                    : event.sourceNote,
                              ),
                              trailing:
                                  event.effectiveDate.isAfter(
                                    DateTime(
                                      today.year,
                                      today.month,
                                      today.day,
                                    ),
                                  )
                                  ? IconButton(
                                      tooltip: 'Remove scheduled change',
                                      onPressed: _saving
                                          ? null
                                          : () => _remove(event),
                                      icon: const Icon(Icons.delete_outline),
                                    )
                                  : const Tooltip(
                                      message: 'Effective history is preserved',
                                      child: Icon(Icons.lock_outline),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add dated status',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<RecognitionStatus>(
                              initialValue: _status,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                              ),
                              items: RecognitionStatus.values
                                  .where(
                                    (s) => s != RecognitionStatus.unrecognized,
                                  )
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _saving
                                  ? null
                                  : (s) => setState(() => _status = s!),
                            ),
                            const SizedBox(height: 12),
                            _dateField(_date, 'Effective date', required: true),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _source,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Source / reason',
                                hintText:
                                    'ARBA approval notice or reason for this change',
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Enter the source or reason.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: const Icon(Icons.save),
                              label: Text(
                                _saving ? 'Saving…' : 'Save dated status',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Dates that overlap judged entries are blocked to protect historical results. Future scheduled changes can be removed; effective history is retained.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preview eligibility',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _dateField(_preview, 'Section judging date'),
                          const SizedBox(height: 16),
                          if (date == null)
                            const Text('Enter a valid judging date.')
                          else ...[
                            Text(
                              'Name: ${recognitionDisplayName(widget.varietyName.isEmpty ? widget.breedName : widget.varietyName, status)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('Effective status: ${status.label}'),
                            Text(switch (status) {
                              RecognitionStatus.cod =>
                                'Class placements, BOV and BOSV allowed. No higher awards or legs.',
                              RecognitionStatus.recognized =>
                                'Normal award and leg eligibility; all other requirements still apply.',
                              RecognitionStatus.retired =>
                                'Not eligible for new show entries, awards or legs. Saved animals and historical results remain.',
                              RecognitionStatus.unrecognized =>
                                'A judging date is required to determine eligibility.',
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
