// lib/screens/super_admin/breed_editor_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class BreedEditorScreen extends StatefulWidget {
  final String species;
  final Map<String, dynamic>? existing;

  const BreedEditorScreen({
    super.key,
    required this.species,
    this.existing,
  });

  @override
  State<BreedEditorScreen> createState() => _BreedEditorScreenState();
}

class _BreedEditorScreenState extends State<BreedEditorScreen> {
  final _name = TextEditingController();
  String _classSystem = 'four';
  bool _active = true;

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
        'name': _name.text.trim(),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isEdit ? 'Edit Breed' : 'Add Breed'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF11285A),
                  Color(0xFF0B1C43),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEdit ? 'Update Breed Details' : 'Create New Breed',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Species: ${widget.species[0].toUpperCase()}${widget.species.substring(1)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
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
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _classSystem,
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
                              : (v) => setState(() => _classSystem = v ?? 'four'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Active'),
                          subtitle: const Text(
                            'Inactive breeds stay in the database but are hidden from normal use.',
                          ),
                          value: _active,
                          onChanged:
                              _saving ? null : (v) => setState(() => _active = v),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(.22),
                      ),
                    ),
                    child: Text(
                      _msg!,
                      style: const TextStyle(
                        color: Colors.red,
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
                        backgroundColor: const Color(0xFFD4A623),
                        foregroundColor: Colors.black,
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