// lib/screens/super_admin/breed_editor_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'variety_editor_screen.dart';

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
        await supabase.from('breeds').update(payload).eq('id', widget.existing!['id']);
      } else {
        await supabase.from('breeds').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _msg = 'Save failed: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final breedId = widget.existing?['id']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Breed' : 'Add Breed'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Edit varieties',
              icon: const Icon(Icons.list),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VarietyEditorScreen(
                    breedId: breedId!,
                    breedName: _name.text.trim().isEmpty ? '(breed)' : _name.text.trim(),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Breed name (required)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _classSystem,
              decoration: const InputDecoration(labelText: 'Class system'),
              items: const [
                DropdownMenuItem(value: 'four', child: Text('Four-class (Jr/Sr)')),
                DropdownMenuItem(value: 'six', child: Text('Six-class (Jr/Int/Sr)')),
              ],
              onChanged: (v) => setState(() => _classSystem = v ?? 'four'),
            ),
            SwitchListTile(
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 8),
              Text(_msg!, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}