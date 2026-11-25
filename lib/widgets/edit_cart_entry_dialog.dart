import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/entry_class_options.dart';
import '../utils/species_sex.dart';

/// Corrects the draft snapshot, without changing the saved animal or other rows.
class EditCartEntryDialog extends StatefulWidget {
  const EditCartEntryDialog({
    super.key,
    required this.item,
    required this.breeds,
    required this.description,
    required this.onSave,
  });
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> breeds;
  final String description;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<EditCartEntryDialog> createState() => _EditCartEntryDialogState();
}

class _EditCartEntryDialogState extends State<EditCartEntryDialog> {
  final _form = GlobalKey<FormState>();
  final _tattoo = TextEditingController();
  final _variety = TextEditingController();
  final _furVariety = TextEditingController();
  final _penTattoos = List.generate(3, (_) => TextEditingController());
  String? _breed, _className, _sex;
  bool _saving = false, _unassigned = false;
  String? _error;
  bool get _pen => widget.item['meat_pen_id'] != null;
  bool get _fur => widget.item['is_fur'] == true;
  bool get _standard =>
      !_pen &&
      !_fur &&
      const [
        'Junior',
        'Intermediate',
        'Senior',
        'Pre-Junior',
      ].contains(widget.item['class_name']);
  List<String> get _classes {
    final b = widget.breeds.where((b) => b['name'] == _breed).firstOrNull;
    return allowedEntryClassOptions(
      species: widget.item['species'],
      classSystem: b?['class_system'],
      hasPreJunior: b?['has_prejunior'],
    );
  }

  @override
  void initState() {
    super.initState();
    _tattoo.text = '${widget.item['tattoo'] ?? ''}';
    _variety.text = '${widget.item['variety'] ?? ''}';
    _furVariety.text = '${widget.item['fur_variety'] ?? ''}';
    _breed = widget.breeds.any((b) => b['name'] == widget.item['breed'])
        ? widget.item['breed']
        : null;
    _className = widget.item['class_name'];
    _sex = displaySexForSpecies(
      species: widget.item['species'],
      sex: widget.item['sex'],
    );
    if (isCavySpecies(widget.item['species'])) {
      if (!['Boar', 'Sow'].contains(_sex)) _sex = null;
    } else {
      _sex = switch (_sex?.toLowerCase()) {
        'buck' => 'Buck',
        'doe' => 'Doe',
        _ => null,
      };
    }
    final tattoos = widget.item['meat_pen_tattoos'] as List? ?? [];
    _unassigned = tattoos.isEmpty;
    for (var n = 0; n < tattoos.length && n < 3; n++) {
      _penTattoos[n].text = '${tattoos[n]}';
    }
    if (_standard && !_classes.contains(_className)) _className = null;
  }

  @override
  void dispose() {
    for (final c in [_tattoo, _variety, _furVariety, ..._penTattoos]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final values = <String, dynamic>{
      if (!_pen) 'tattoo': _tattoo.text.trim(),
      'breed': _breed,
      'variety': _variety.text.trim(),
      if (!_pen && !_fur) 'sex': _sex,
      if (_standard) 'class_name': _className,
      if (_fur) 'fur_variety': _furVariety.text.trim(),
      if (_pen)
        'meat_pen_tattoos': _unassigned
            ? <String>[]
            : _penTattoos.map((c) => c.text.trim()).toList(),
    };
    if (values['sex'] ==
            displaySexForSpecies(
              species: widget.item['species'],
              sex: widget.item['sex'],
            ) ||
        '${values['sex']}'.toLowerCase() ==
            '${widget.item['sex']}'.toLowerCase()) {
      values.remove('sex');
    }
    values.removeWhere(
      (k, v) => k != 'meat_pen_tattoos' && v == widget.item[k],
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (values.isNotEmpty) await widget.onSave(values);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to save: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Theme(
      data: AppTheme.surfaceDialogTheme(Theme.of(context)),
      child: AlertDialog(
        title: const Text('Edit Cart Entry'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.description),
                  const SizedBox(height: 8),
                  const Text(
                    'Changes apply to this cart line only. Your saved animal and entries in other sections stay the same.',
                  ),
                  const SizedBox(height: 16),
                  if (_pen) ...[
                    Text('Pen ${widget.item['meat_pen_id']}'),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tattoos not yet assigned'),
                      value: _unassigned,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _unassigned = v!),
                    ),
                    if (!_unassigned)
                      for (var n = 0; n < 3; n++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: _penTattoos[n],
                            enabled: !_saving,
                            maxLength: 40,
                            decoration: InputDecoration(
                              labelText: 'Tattoo ${n + 1}',
                            ),
                            validator: (v) =>
                                v == null ||
                                    v.trim().isEmpty ||
                                    RegExp(r'[|/]').hasMatch(v)
                                ? 'Enter one tattoo without / or |.'
                                : null,
                          ),
                        ),
                  ] else
                    TextFormField(
                      controller: _tattoo,
                      enabled: !_saving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Tattoo / ear number',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter a tattoo / ear number.'
                          : null,
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _breed,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Breed'),
                    items: widget.breeds
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['name'] as String,
                            child: Text(b['name'] as String),
                          ),
                        )
                        .toList(),
                    validator: (v) => v == null ? 'Choose a breed.' : null,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                            _breed = v;
                            if (!_classes.contains(_className)) {
                              _className = null;
                            }
                          }),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _variety,
                    enabled: !_saving,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Variety'),
                  ),
                  if (_fur)
                    DropdownButtonFormField<String>(
                      initialValue:
                          ['White', 'Colored'].contains(_furVariety.text)
                          ? _furVariety.text
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Fur/Wool variety',
                      ),
                      items: ['White', 'Colored']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      validator: (v) =>
                          v == null ? 'Choose White or Colored.' : null,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _furVariety.text = v!),
                    ),
                  if (!_pen && !_fur) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _sex,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sex'),
                      items:
                          (isCavySpecies(widget.item['species'])
                                  ? ['Boar', 'Sow']
                                  : ['Buck', 'Doe'])
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                      validator: (v) => v == null ? 'Choose a sex.' : null,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _sex = v),
                    ),
                  ],
                  if (_standard) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('class-$_breed'),
                      initialValue: _className,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Show class',
                      ),
                      items: _classes
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      validator: (v) =>
                          v == null ? 'Choose a show class.' : null,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _className = v),
                    ),
                  ] else
                    Text('Class: ${widget.item['class_name'] ?? 'Fur/Wool'}'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save Changes'),
          ),
        ],
      ),
    ),
  );
}
