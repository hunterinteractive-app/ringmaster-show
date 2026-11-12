import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/species_sex.dart';
import '../utils/entry_class_name.dart';
import '../utils/entry_class_options.dart';

class EditEntryResult {
  final String animalId;
  final String className;
  final String sectionId;
  final String exhibitorId;

  EditEntryResult({
    required this.animalId,
    required this.className,
    required this.sectionId,
    required this.exhibitorId,
  });
}

class EditEntryDialog extends StatefulWidget {
  final String initialAnimalId;
  final String initialClassName;
  final String initialSectionId;
  final String initialExhibitorId;
  final List<Map<String, dynamic>> breeds;
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> exhibitors;
  final List<Map<String, dynamic>> sections;
  final String Function(String? sectionId) sectionLabel;
  final Future<void> Function() onAddNewAnimal;
  final Future<List<Map<String, dynamic>>> Function() reloadAnimals;

  const EditEntryDialog({
    required this.initialAnimalId,
    required this.initialClassName,
    required this.initialSectionId,
    required this.initialExhibitorId,
    super.key,
    required this.breeds,
    required this.animals,
    required this.exhibitors,
    required this.sections,
    required this.sectionLabel,
    required this.onAddNewAnimal,
    required this.reloadAnimals,
  });

  @override
  State<EditEntryDialog> createState() => EditEntryDialogState();
}

class EditEntryDialogState extends State<EditEntryDialog> {
  late List<Map<String, dynamic>> _animals;
  late String _animalId;
  late String _sectionId;
  late String _exhibitorId;
  String? _className;
  String? _dialogError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _animals = widget.animals;
    _animalId = widget.initialAnimalId;
    _sectionId = widget.initialSectionId;
    _exhibitorId = widget.initialExhibitorId;
    _className = canonicalEntryClassName(widget.initialClassName);
    _validateClassSelection();
  }

  List<String> get _classOptions {
    final animals = _animals.where((a) => a['id'] == _animalId);
    if (animals.isEmpty) return const [];
    final animal = animals.first;
    String name(Object? value) => (value ?? '')
        .toString()
        .trim()
        .replaceFirst(RegExp(r'\s*\(COD\)$', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    final matches = widget.breeds.where(
      (b) =>
          name(b['name']) == name(animal['breed']) &&
          name(b['species']) == name(animal['species']),
    );
    if (matches.isEmpty) return const [];
    final breed = matches.first;
    return allowedEntryClassOptions(
      species: animal['species'],
      classSystem: breed['class_system'],
      hasPreJunior: breed['has_prejunior'],
    );
  }

  void _validateClassSelection() {
    if (!_classOptions.contains(_className)) _className = null;
  }

  String _animalLabel(Map<String, dynamic> a) {
    final tattoo = (a['tattoo'] ?? '').toString().trim();
    final name = (a['name'] ?? '').toString().trim();
    final breed = (a['breed'] ?? '').toString().trim();
    final variety = (a['variety'] ?? '').toString().trim();
    final sex = displaySexForSpecies(species: a['species'], sex: a['sex']);
    final top = tattoo.isNotEmpty
        ? tattoo
        : (name.isNotEmpty ? name : (a['id'] ?? '').toString());

    final details = [
      breed,
      variety,
      sex,
    ].where((part) => part.trim().isNotEmpty).join(' • ');

    return details.isEmpty ? top : '$top — $details';
  }

  String _exhibitorLabel(Map<String, dynamic> e) {
    final showingName = (e['showing_name'] ?? '').toString().trim();
    if (showingName.isNotEmpty) return showingName;

    final displayName = (e['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    return (e['id'] ?? '').toString();
  }

  Future<void> _addNewAnimal() async {
    setState(() => _busy = true);
    try {
      await widget.onAddNewAnimal();
      final refreshed = await widget.reloadAnimals();
      if (!mounted) return;

      setState(() {
        _animals = refreshed;
        final exists = _animals.any(
          (a) => (a['id'] ?? '').toString() == _animalId,
        );
        if (!exists && _animals.isNotEmpty) {
          _animalId = (_animals.first['id'] ?? '').toString();
        }
        _validateClassSelection();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _animals.any(
      (a) => (a['id'] ?? '').toString() == _animalId,
    );
    final hasSelectedSection = widget.sections.any(
      (s) => (s['id'] ?? '').toString() == _sectionId,
    );
    final hasSelectedExhibitor = widget.exhibitors.any(
      (e) => (e['id'] ?? '').toString() == _exhibitorId,
    );

    return Theme(
      data: AppTheme.surfaceDialogTheme(Theme.of(context)),
      child: AlertDialog(
        title: const Text('Edit Entry'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_dialogError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _dialogError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: hasSelectedSection ? _sectionId : null,
                  items: widget.sections.map((s) {
                    final id = (s['id'] ?? '').toString();
                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(widget.sectionLabel(id)),
                    );
                  }).toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _sectionId = v;
                          });
                        },
                  decoration: const InputDecoration(
                    labelText: 'Show / Section',
                    helperText:
                        'Move this entry to another open/youth show section.',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: hasSelectedExhibitor ? _exhibitorId : null,
                  items: widget.exhibitors.map((e) {
                    final id = (e['id'] ?? '').toString();
                    final label = _exhibitorLabel(e);

                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(label),
                    );
                  }).toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _exhibitorId = v);
                        },
                  decoration: const InputDecoration(
                    labelText: 'Exhibitor',
                    helperText:
                        'Move this entry to another exhibitor on your account.',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: hasSelected ? _animalId : null,
                  isExpanded: true,
                  items: _animals.map((a) {
                    final id = (a['id'] ?? '').toString();
                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(
                        _animalLabel(a),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _animalId = v ?? _animalId;
                          _validateClassSelection();
                          _dialogError = null;
                        }),
                  decoration: const InputDecoration(
                    labelText: 'Animal',
                    helperText: 'Swap to an existing animal from My Animals.',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _addNewAnimal,
                    icon: const Icon(Icons.add),
                    label: const Text('Add new animal'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('class-$_animalId-${_classOptions.join(',')}'),
                  initialValue: _className,
                  isExpanded: true,
                  items: _classOptions
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _className = value),
                  decoration: InputDecoration(
                    labelText: 'Class (required)',
                    helperMaxLines: 3,
                    helperText: _classOptions.isEmpty
                        ? 'Class options are unavailable for this breed. Contact the show secretary.'
                        : 'Select a class offered for this breed.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy || _classOptions.isEmpty
                ? null
                : () {
                    final hasValidAnimal = _animals.any(
                      (a) => (a['id'] ?? '').toString() == _animalId,
                    );
                    final hasValidSection = widget.sections.any(
                      (s) => (s['id'] ?? '').toString() == _sectionId,
                    );
                    final hasValidExhibitor = widget.exhibitors.any(
                      (e) => (e['id'] ?? '').toString() == _exhibitorId,
                    );

                    if (!hasValidSection) {
                      setState(() => _dialogError = 'Select a show / section.');
                      return;
                    }

                    if (!hasValidExhibitor) {
                      setState(() => _dialogError = 'Select an exhibitor.');
                      return;
                    }

                    if (!hasValidAnimal) {
                      setState(() => _dialogError = 'Select an animal.');
                      return;
                    }

                    if (!_classOptions.contains(_className)) {
                      setState(
                        () => _dialogError =
                            'Select a valid class for this breed.',
                      );
                      return;
                    }

                    Navigator.pop(
                      context,
                      EditEntryResult(
                        animalId: _animalId,
                        className: _className!,
                        sectionId: _sectionId,
                        exhibitorId: _exhibitorId,
                      ),
                    );
                  },
            child: Text(_busy ? 'Working…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
