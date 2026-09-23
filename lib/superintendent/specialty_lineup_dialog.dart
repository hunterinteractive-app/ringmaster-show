import 'package:flutter/material.dart';

String specialtyStatus(String value) => switch (value) {
  'completed' => 'Complete',
  'in_progress' => 'Judging',
  _ => 'Planned',
};

Map<String, dynamic> specialtyLineupRow(Map<String, dynamic> row) => {
  ...row,
  'is_external_specialty': row['award_code'] == null,
  'is_award_plan': row['award_code'] != null,
  if (row['award_code'] != null) 'section_id': row['award_section_id'],
  'breed_id': row['award_code'] != null
      ? row['breed']
      : '${row['name']} • ${row['breed']}',
  'entry_count_actual': row['entry_count'],
  'show_letter': row['award_code'] != null
      ? (row['show_letter'] ?? row['name'])
      : 'Outside specialty • ${row['scope'] == 'youth'
            ? 'Youth'
            : row['scope'] == 'open'
            ? 'Open'
            : 'Open/Youth not set'}',
  'species': 'rabbit',
};

Future<bool?> editSpecialtyLineup(
  BuildContext context, {
  Map<String, dynamic>? row,
  required Future<void> Function(Map<String, dynamic>) save,
}) async {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{
    for (final key in ['name', 'breed', 'entry_count', 'table_number'])
      key: TextEditingController(
        text: (row?[key] ?? (key == 'sort_order' ? 0 : '')).toString(),
      ),
  };
  var scope = row?['scope'] as String?;
  var status = (row?['status'] ?? 'draft').toString();
  var saving = false;
  String? error;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          row == null ? 'Add outside specialty' : 'Edit outside specialty',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Planning counts only. This does not create entries, collect fees, or record results for the specialty.',
                  ),
                  const SizedBox(height: 12),
                  for (final field in <String, String>{
                    'name': 'Specialty name',
                    'breed': 'Breed',
                    'entry_count': 'Entry count',
                    'table_number': 'Table',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: fields[field.key],
                        enabled: !saving,
                        decoration: InputDecoration(labelText: field.value),
                        keyboardType:
                            ['entry_count', 'sort_order'].contains(field.key)
                            ? TextInputType.number
                            : TextInputType.text,
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (field.key == 'judge_name') {
                            return text.length > 160
                                ? 'Use 160 characters or fewer.'
                                : null;
                          }
                          if (text.isEmpty) return 'Required';
                          if (['entry_count'].contains(field.key)) {
                            final n = int.tryParse(text);
                            if (n == null || n < 0 || n > 2147483647) {
                              return 'Enter a valid whole number, 0 or greater.';
                            }
                          }
                          final limit = field.key == 'name'
                              ? 160
                              : field.key == 'breed'
                              ? 100
                              : field.key == 'table_number'
                              ? 40
                              : 160;
                          return text.length > limit
                              ? 'Use $limit characters or fewer.'
                              : null;
                        },
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    decoration: const InputDecoration(
                      labelText: 'Open or Youth',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(value: 'youth', child: Text('Youth')),
                    ],
                    validator: (value) =>
                        value == null ? 'Choose Open or Youth' : null,
                    onChanged: saving
                        ? null
                        : (value) => update(() => scope = value),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'New specialties go at the end of the table. Drag them in the line-up to change the order.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Judging progress',
                    ),
                    items: ['draft', 'in_progress', 'completed']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(specialtyStatus(s)),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => update(() => status = value!),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    update(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await save({
                        if (row != null) 'id': row['id'],
                        for (final field in fields.entries)
                          field.key:
                              ['entry_count', 'sort_order'].contains(field.key)
                              ? int.parse(field.value.text.trim())
                              : field.value.text.trim(),
                        'status': status,
                        'scope': scope,
                      });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        update(() {
                          saving = false;
                          error = 'Could not save: $e';
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save specialty'),
          ),
        ],
      ),
    ),
  );
  // Controllers are disposed after the closing route transition.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final controller in fields.values) {
    controller.dispose();
  }
  return result;
}
