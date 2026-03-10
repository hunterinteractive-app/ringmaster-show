// lib/screens/admin/show_sections_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowSectionsDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShowSectionsDialog(
        showId: showId,
        showName: showName,
      ),
    );
  }
}

class _ShowSectionsDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowSectionsDialog({
    required this.showId,
    required this.showName,
  });

  @override
  State<_ShowSectionsDialog> createState() => _ShowSectionsDialogState();
}

class _ShowSectionsDialogState extends State<_ShowSectionsDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  final List<_EditableSection> _sections = [];
  final Set<String> _deletedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSections() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final res = await supabase
          .from('show_sections')
          .select('id, show_id, kind, letter, display_name, is_enabled, sort_order')
          .eq('show_id', widget.showId);

      final rows = (res as List).cast<Map<String, dynamic>>();

      rows.sort((a, b) {
        int rank(String kind) {
          switch (kind.toLowerCase()) {
            case 'open':
              return 0;
            case 'youth':
              return 1;
            default:
              return 99;
          }
        }

        final kr = rank((a['kind'] ?? '').toString())
            .compareTo(rank((b['kind'] ?? '').toString()));
        if (kr != 0) return kr;

        final aso = int.tryParse((a['sort_order'] ?? '').toString()) ?? 9999;
        final bso = int.tryParse((b['sort_order'] ?? '').toString()) ?? 9999;
        final sr = aso.compareTo(bso);
        if (sr != 0) return sr;

        final ad = (a['display_name'] ?? a['letter'] ?? '').toString().toLowerCase();
        final bd = (b['display_name'] ?? b['letter'] ?? '').toString().toLowerCase();
        return ad.compareTo(bd);
      });

      for (final s in _sections) {
        s.dispose();
      }
      _sections.clear();
      _deletedIds.clear();

      for (final row in rows) {
        _sections.add(
          _EditableSection.fromDb(row),
        );
      }

      _normalizeSortOrder();
      _rebuildLettersByKind();

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  void _normalizeSortOrder() {
    for (int i = 0; i < _sections.length; i++) {
      _sections[i].sortOrder = i + 1;
    }
  }

  void _rebuildLettersByKind() {
    int openIndex = 0;
    int youthIndex = 0;

    for (final s in _sections) {
      if (s.kind == 'open') {
        openIndex++;
        s.letterCtrl.text = _alphaLabel(openIndex);
      } else if (s.kind == 'youth') {
        youthIndex++;
        s.letterCtrl.text = _alphaLabel(youthIndex);
      }
    }
  }

  String _alphaLabel(int index) {
    if (index <= 0) return '';
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    var n = index;
    var result = '';

    while (n > 0) {
      n--;
      result = letters[n % 26] + result;
      n ~/= 26;
    }

    return result;
  }

  String _defaultDisplayNameForKind(String kind) {
    final count = _sections.where((s) => s.kind == kind).length + 1;
    final letter = _alphaLabel(count);
    final label = kind == 'youth' ? 'Youth' : 'Open';
    return '$label $letter';
  }

  void _addSection(String kind) {
    setState(() {
      _sections.add(
        _EditableSection.newRow(
          kind: kind,
          displayName: _defaultDisplayNameForKind(kind),
        ),
      );
      _normalizeSortOrder();
      _rebuildLettersByKind();
    });
  }

  void _removeSection(int index) {
    final row = _sections[index];

    setState(() {
      if (row.id != null && row.id!.isNotEmpty) {
        _deletedIds.add(row.id!);
      }
      row.dispose();
      _sections.removeAt(index);
      _normalizeSortOrder();
      _rebuildLettersByKind();
    });
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(index - 1, item);
      _normalizeSortOrder();
      _rebuildLettersByKind();
    });
  }

  void _moveDown(int index) {
    if (index >= _sections.length - 1) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(index + 1, item);
      _normalizeSortOrder();
      _rebuildLettersByKind();
    });
  }

  bool _validate() {
    if (_sections.isEmpty) {
      setState(() => _msg = 'Add at least one section.');
      return false;
    }

    final enabled = _sections.where((s) => s.isEnabled).toList();
    if (enabled.isEmpty) {
      setState(() => _msg = 'At least one section must be enabled.');
      return false;
    }

    for (final s in _sections) {
      final name = s.displayNameCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _msg = 'Every section needs a display name.');
        return false;
      }
    }

    return true;
  }

  Future<void> _saveAll() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      // Delete removed rows first
      for (final id in _deletedIds) {
        await supabase.from('show_sections').delete().eq('id', id);
      }

      _deletedIds.clear();

      // Save current rows
      for (int i = 0; i < _sections.length; i++) {
        final s = _sections[i];
        s.sortOrder = i + 1;

        final payload = <String, dynamic>{
          'show_id': widget.showId,
          'kind': s.kind,
          'letter': s.letterCtrl.text.trim(),
          'display_name': s.displayNameCtrl.text.trim(),
          'is_enabled': s.isEnabled,
          'sort_order': s.sortOrder,
        };

        if (s.id != null && s.id!.isNotEmpty) {
          await supabase.from('show_sections').update(payload).eq('id', s.id!);
        } else {
          final inserted = await supabase
              .from('show_sections')
              .insert(payload)
              .select('id')
              .single();

          s.id = (inserted['id'] ?? '').toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  Widget _kindChip(String kind) {
    final label = kind == 'youth' ? 'Youth' : 'Open';
    final color = kind == 'youth' ? Colors.deepPurple : Colors.blue;

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      labelStyle: TextStyle(
        color: color.shade700,
        fontWeight: FontWeight.w600,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _sectionCard(int index) {
    final s = _sections[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                _kindChip(s.kind),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Section ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: _saving || index == 0 ? null : () => _moveUp(index),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: _saving || index == _sections.length - 1
                      ? null
                      : () => _moveDown(index),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: _saving ? null : () => _removeSection(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: s.letterCtrl,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Letter',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: s.displayNameCtrl,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      hintText: 'Example: Open A or Sweepstakes Youth',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: s.isEnabled,
              onChanged: _saving
                  ? null
                  : (v) {
                      setState(() {
                        s.isEnabled = v;
                      });
                    },
              title: const Text('Enabled'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width * 0.72,
          maxHeight: media.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Show Sections — ${widget.showName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Set the show order, enable/disable sections, and customize names like Open A or Youth B.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_msg != null) ...[
                Text(
                  _msg!,
                  style: TextStyle(
                    color: _msg == 'Saved.' ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _addSection('open'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Open'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _addSection('youth'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Youth'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _loadSections,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _sections.isEmpty
                        ? const Align(
                            alignment: Alignment.topLeft,
                            child: Text('No sections yet. Add Open and/or Youth sections.'),
                          )
                        : ListView.builder(
                            itemCount: _sections.length,
                            itemBuilder: (context, index) => _sectionCard(index),
                          ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _saveAll,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableSection {
  String? id;
  String kind;
  bool isEnabled;
  int sortOrder;
  final TextEditingController letterCtrl;
  final TextEditingController displayNameCtrl;

  _EditableSection({
    required this.id,
    required this.kind,
    required this.isEnabled,
    required this.sortOrder,
    required this.letterCtrl,
    required this.displayNameCtrl,
  });

  factory _EditableSection.fromDb(Map<String, dynamic> row) {
    return _EditableSection(
      id: (row['id'] ?? '').toString(),
      kind: (row['kind'] ?? 'open').toString().trim().toLowerCase(),
      isEnabled: row['is_enabled'] == true,
      sortOrder: int.tryParse((row['sort_order'] ?? '').toString()) ?? 0,
      letterCtrl: TextEditingController(
        text: (row['letter'] ?? '').toString(),
      ),
      displayNameCtrl: TextEditingController(
        text: (row['display_name'] ?? '').toString(),
      ),
    );
  }

  factory _EditableSection.newRow({
    required String kind,
    required String displayName,
  }) {
    return _EditableSection(
      id: null,
      kind: kind,
      isEnabled: true,
      sortOrder: 0,
      letterCtrl: TextEditingController(),
      displayNameCtrl: TextEditingController(text: displayName),
    );
  }

  void dispose() {
    letterCtrl.dispose();
    displayNameCtrl.dispose();
  }
}