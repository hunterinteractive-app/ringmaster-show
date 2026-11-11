import 'package:flutter/material.dart';
import '../../services/class_payback.dart';
import '../../theme/app_theme.dart';

Future<ClassPaybackRow?> showClassPaybackRangeEditor(
  BuildContext context, {
  ClassPaybackRow? row,
}) {
  return showDialog<ClassPaybackRow>(
    context: context,
    builder: (dialogContext) => Theme(
      data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
      child: _ClassPaybackRangeDialog(row: row),
    ),
  );
}

class _ClassPaybackRangeDialog extends StatefulWidget {
  const _ClassPaybackRangeDialog({this.row});
  final ClassPaybackRow? row;
  @override
  State<_ClassPaybackRangeDialog> createState() =>
      _ClassPaybackRangeDialogState();
}

class _ClassPaybackRangeDialogState extends State<_ClassPaybackRangeDialog> {
  late final minimum = TextEditingController(
    text: '${widget.row?.minShown ?? 1}',
  );
  late final maximum = TextEditingController(
    text: widget.row?.maxShown?.toString() ?? '',
  );
  final form = GlobalKey<FormState>();
  late String species = widget.row?.appliesToSpecies ?? 'rabbit';

  @override
  void dispose() {
    minimum.dispose();
    maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return AlertDialog(
      title: Text(
        row == null ? 'Add class-size range' : 'Edit class-size range',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: species,
                decoration: const InputDecoration(labelText: 'Species'),
                items: const [
                  DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                  DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
                ],
                onChanged: (v) => setState(() => species = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: minimum,
                decoration: const InputDecoration(labelText: 'Minimum shown'),
                keyboardType: TextInputType.number,
                validator: (s) {
                  final n = int.tryParse(s?.trim() ?? '');
                  return n == null || n < 1 || n > 2147483647
                      ? 'Enter a positive whole number.'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: maximum,
                decoration: const InputDecoration(
                  labelText: 'Maximum shown',
                  helperText: 'Leave blank for no upper limit.',
                ),
                keyboardType: TextInputType.number,
                validator: (s) {
                  if ((s ?? '').trim().isEmpty) return null;
                  final n = int.tryParse(s!.trim());
                  return n == null ||
                          n < (int.tryParse(minimum.text) ?? 1) ||
                          n > 2147483647
                      ? 'Must be at least the minimum.'
                      : null;
                },
              ),
            ],
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
              ClassPaybackRow(
                appliesToSpecies: species,
                minShown: int.parse(minimum.text.trim()),
                maxShown: int.tryParse(maximum.text.trim()),
                amountsByPlacement: Map.from(
                  row?.amountsByPlacement ?? <int, int>{},
                ),
              )..amountErrors.addAll(row?.amountErrors ?? {}),
            );
          },
          child: const Text('Apply range'),
        ),
      ],
    );
  }
}

Future<HoustonPaybackPreset?> showHoustonPaybackPreset(
  BuildContext context, {
  String? sectionKind,
}) {
  final options = HoustonPaybackPreset.values
      .where((p) => sectionKind == null || p.kind == sectionKind.toLowerCase())
      .toList();
  if (options.isEmpty) return Future.value();
  var chosen = options.first;
  return showDialog<HoustonPaybackPreset>(
    context: context,
    builder: (dialogContext) => Theme(
      data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
      child: StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Houston premium tables'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<HoustonPaybackPreset>(
                    initialValue: chosen,
                    decoration: const InputDecoration(
                      labelText: 'Premium table',
                    ),
                    items: [
                      for (final p in options)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (p) => setState(() => chosen = p!),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This replaces this species’ class premiums in the selected show letter. Other species and Special Money stay unchanged. Review the table, then Save in Payback Settings to publish it.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Scroll horizontally to see all five placements.'),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      columns: [
                        const DataColumn(label: Text('Shown')),
                        for (final label in ['1st', '2nd', '3rd', '4th', '5th'])
                          DataColumn(label: Text(label)),
                      ],
                      rows: [
                        for (final r in chosen.rows())
                          DataRow(
                            cells: [
                              DataCell(Text(r.rangeLabel)),
                              for (var p = 1; p <= 5; p++)
                                DataCell(
                                  Text(
                                    r.amountsByPlacement[p] == null
                                        ? '—'
                                        : '\$${(r.amountsByPlacement[p]! / 100).toStringAsFixed(2)}',
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: const Text('Use this table'),
            ),
          ],
        ),
      ),
    ),
  );
}
