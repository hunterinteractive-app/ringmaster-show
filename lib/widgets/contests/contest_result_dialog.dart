import 'package:flutter/material.dart';
import '../../models/contest_settings.dart';
import '../../theme/app_theme.dart';

class ContestResultEdit {
  ContestResultEdit(this.result, this.reason);
  final Map<String, dynamic> result;
  final String reason;
}

class ContestResultDialog extends StatefulWidget {
  const ContestResultDialog({
    super.key,
    required this.row,
    required this.settings,
  });
  final Map<String, dynamic> row;
  final ContestSettings settings;
  @override
  State<ContestResultDialog> createState() => _ContestResultDialogState();
}

class _ContestResultDialogState extends State<ContestResultDialog> {
  final form = GlobalKey<FormState>();
  late final previous = Map<String, dynamic>.from(
    widget.row['result'] as Map? ?? {},
  );
  late String status = previous['status'] == 'pending' || previous.isEmpty
      ? 'recorded'
      : previous['status'];
  late final place = TextEditingController(
    text: previous['place']?.toString() ?? '',
  );
  late final ribbon = TextEditingController(
    text: previous['ribbon']?.toString() ?? '',
  );
  late final awards = List<String>.from(previous['awards'] as List? ?? []);
  late final customAwards = TextEditingController(text: awards.join('\n'));
  final reason = TextEditingController();
  @override
  void dispose() {
    place.dispose();
    ribbon.dispose();
    customAwards.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.surfaceTheme(Theme.of(context)),
    child: AlertDialog(
      title: Text('Record result — ${contestEntryLabel(widget.row)}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    widget.row['division'],
                    widget.row['registration_data']?['category'],
                    widget.row['registration_data']?['session_name'],
                  ].where((v) => v != null).join(' • '),
                ),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Result status'),
                  items: [
                    for (final s in const {
                      'recorded': 'Recorded',
                      'pending': 'Not recorded',
                      'finalist': 'Finalist / callback',
                      'absent': 'Absent',
                      'withdrawn': 'Withdrawn',
                      'disqualified': 'Disqualified',
                    }.entries)
                      DropdownMenuItem(value: s.key, child: Text(s.value)),
                  ],
                  onChanged: (v) => setState(() => status = v!),
                ),
                if (status == 'recorded') ...[
                  if (widget.settings.number('places', 20) > 0)
                    TextFormField(
                      controller: place,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Place (optional)',
                        helperText:
                            '1–${widget.settings.number('places', 20)}. Leave blank for no placing.',
                      ),
                      validator: (v) => v!.isEmpty
                          ? null
                          : int.tryParse(v) == null ||
                                int.parse(v) < 1 ||
                                int.parse(v) >
                                    widget.settings.number('places', 20)
                          ? 'Enter a valid place.'
                          : null,
                    ),
                  const SizedBox(height: 12),
                  const Text('Named awards'),
                  if (widget.settings.awards.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final a in widget.settings.awards)
                          FilterChip(
                            label: Text('${a['name']}'),
                            selected: awards.contains(a['name']),
                            onSelected: (v) => setState(() {
                              if (v) {
                                awards.add(a['name']);
                              } else {
                                awards.remove(a['name']);
                              }
                            }),
                          ),
                      ],
                    )
                  else
                    TextFormField(
                      controller: customAwards,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Awards (one per line, optional)',
                      ),
                    ),
                  TextFormField(
                    controller: ribbon,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Ribbon rating (optional)',
                    ),
                  ),
                ],
                TextFormField(
                  controller: reason,
                  maxLines: 2,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText:
                        previous.isNotEmpty && previous['status'] != 'pending'
                        ? 'Reason for correction *'
                        : 'Notes (optional)',
                  ),
                  validator: (v) =>
                      previous.isNotEmpty &&
                          previous['status'] != 'pending' &&
                          v!.trim().isEmpty
                      ? 'Enter the reason for this correction.'
                      : null,
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
            if (!form.currentState!.validate()) return;
            Navigator.pop(
              context,
              ContestResultEdit({
                'status': status,
                'place': status == 'recorded' ? int.tryParse(place.text) : null,
                'awards': status == 'recorded'
                    ? (widget.settings.awards.isEmpty
                          ? customAwards.text
                                .split('\n')
                                .map((v) => v.trim())
                                .where((v) => v.isNotEmpty)
                                .toSet()
                                .toList()
                          : awards)
                    : <String>[],
                'ribbon': status == 'recorded' ? ribbon.text.trim() : '',
              }, reason.text.trim()),
            );
          },
          child: const Text('Save Result'),
        ),
      ],
    ),
  );
}
