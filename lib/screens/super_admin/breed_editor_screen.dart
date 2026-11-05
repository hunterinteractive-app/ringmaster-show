// lib/screens/super_admin/breed_editor_screen.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/services/catalog/recognition_catalog_labels.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

SupabaseClient get supabase => ringMasterClient;

class BreedEditorScreen extends StatefulWidget {
  final String species;
  final Map<String, dynamic>? existing;

  const BreedEditorScreen({super.key, required this.species, this.existing});

  @override
  State<BreedEditorScreen> createState() => _BreedEditorScreenState();
}

class _BreedEditorScreenState extends State<BreedEditorScreen> {
  final _name = TextEditingController();
  String _classSystem = 'four';
  bool _active = true;
  String? _initialDisplayName;

  bool _saving = false;
  String? _msg;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = (e['name'] ?? '').toString();
      _classSystem = (e['class_system'] ?? 'four').toString();
      _active = e['is_active'] == true;
      _loadDisplayName();
    }
  }

  Future<void> _loadDisplayName() async {
    try {
      final original = widget.existing!['name'].toString();
      final labels = await RecognitionCatalogLabels.load(supabase);
      if (!mounted || _name.text != original) return;
      setState(() {
        _initialDisplayName = labels.label(widget.species, original);
        _name.text = _initialDisplayName!;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _msg = 'Could not load current recognition name: $e');
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _msg = 'Name is required.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final payload = {
        'name': _isEdit && _initialDisplayName == _name.text.trim()
            ? widget.existing!['name']
            : _name.text.trim(),
        'species': widget.species,
        'class_system': _classSystem,
        'is_active': _active,
      };

      if (_isEdit) {
        await supabase
            .from('breeds')
            .update(payload)
            .eq('id', widget.existing!['id']);
      } else {
        await supabase.from('breeds').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _msg = 'Save failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final speciesLabel =
        '${widget.species[0].toUpperCase()}${widget.species.substring(1)}';

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: _isEdit ? 'Edit Breed' : 'Add Breed',
      showBackButton: true,
      useScrollView: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                _isEdit ? 'Update Breed Details' : 'Create New Breed',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.headerForeground,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Species: $speciesLabel',
                style: const TextStyle(color: AppColors.headerForeground),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppTheme.surfaceTextScope(
                  context,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _name,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Breed name',
                              hintText: 'Enter breed name',
                              helperText:
                                  'COD labels follow the dated status history.',
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _classSystem,
                            decoration: const InputDecoration(
                              labelText: 'Class system',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'four',
                                child: Text('Four-class (Jr/Sr)'),
                              ),
                              DropdownMenuItem(
                                value: 'six',
                                child: Text('Six-class (Jr/Int/Sr)'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) {
                                    setState(() {
                                      _classSystem = v ?? 'four';
                                    });
                                  },
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Available in catalog'),
                            subtitle: const Text(
                              'Inactive breeds stay in the database but are hidden from normal use.',
                            ),
                            value: _active,
                            onChanged: _saving
                                ? null
                                : (v) {
                                    setState(() {
                                      _active = v;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: .22),
                      ),
                    ),
                    child: Text(
                      _msg!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryButton,
                        foregroundColor: AppColors.primaryButtonText,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
