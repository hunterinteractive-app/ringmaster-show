// lib/screens/admin/show_sections_dialog.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';

final supabase = Supabase.instance.client;

class ShowSectionsDialog {
  static Future<bool> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShowSectionsDialog(showId: showId, showName: showName),
    );

    return result == true;
  }
}

class _ShowSectionsDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowSectionsDialog({required this.showId, required this.showName});

  @override
  State<_ShowSectionsDialog> createState() => _ShowSectionsDialogState();
}

class _ShowSectionsDialogState extends State<_ShowSectionsDialog> {
  bool _loading = true;
  bool _saving = false;
  bool _loadingBreeds = false;
  String? _msg;
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  final List<_EditableSection> _sections = [];
  final Set<String> _deletedIds = <String>{};
  List<Map<String, dynamic>> _breedOptions = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select('is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();

      _isLocked = show['is_locked'] == true;
      _isFinalized = (show['finalized_at'] ?? '').toString().trim().isNotEmpty;

      await Future.wait([_loadBreeds(), _loadSections()]);

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

  Future<void> _loadBreeds() async {
    _loadingBreeds = true;

    final res = await supabase
        .from('breeds')
        .select('id, name, species, is_active')
        .eq('is_active', true)
        .order('species')
        .order('name');

    _breedOptions = (res as List).cast<Map<String, dynamic>>();
    _loadingBreeds = false;
  }

  Future<void> _loadSections() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final res = await supabase
          .from('show_sections')
          .select(
            'id, show_id, kind, letter, display_name, is_enabled, sort_order, breed_scope, allowed_breed_ids, allow_meat_classes',
          )
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

        final kr = rank(
          (a['kind'] ?? '').toString(),
        ).compareTo(rank((b['kind'] ?? '').toString()));
        if (kr != 0) return kr;

        final aso = int.tryParse((a['sort_order'] ?? '').toString()) ?? 9999;
        final bso = int.tryParse((b['sort_order'] ?? '').toString()) ?? 9999;
        final sr = aso.compareTo(bso);
        if (sr != 0) return sr;

        final ad = (a['display_name'] ?? a['letter'] ?? '')
            .toString()
            .toLowerCase();
        final bd = (b['display_name'] ?? b['letter'] ?? '')
            .toString()
            .toLowerCase();
        return ad.compareTo(bd);
      });

      for (final s in _sections) {
        s.dispose();
      }
      _sections.clear();
      _deletedIds.clear();

      for (final row in rows) {
        _sections.add(_EditableSection.fromDb(row));
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
    if (_saving || _isReadOnly) return;
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
    if (_saving || _isReadOnly) return;
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
    if (_saving || _isReadOnly || index <= 0) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(index - 1, item);
      _normalizeSortOrder();
      _rebuildLettersByKind();
    });
  }

  void _moveDown(int index) {
    if (_saving || _isReadOnly || index >= _sections.length - 1) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(index + 1, item);
      _normalizeSortOrder();
      _rebuildLettersByKind();
    });
  }

  bool _validate() {
    if (_isReadOnly) {
      setState(
        () => _msg = _isFinalized
            ? 'This show has been finalized. Sections can no longer be changed.'
            : 'This show is locked. Sections can no longer be changed.',
      );
      return false;
    }
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

      if (s.breedScope == 'single' && s.allowedBreedIds.length != 1) {
        setState(
          () => _msg =
              '${name.isEmpty ? "A section" : name} must have exactly 1 breed selected.',
        );
        return false;
      }

      if (s.breedScope == 'limited') {
        if (s.allowedBreedIds.isEmpty) {
          setState(
            () => _msg =
                '${name.isEmpty ? "A section" : name} must have at least 1 allowed breed.',
          );
          return false;
        }
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
      await ShowLockService.assertShowUnlocked(widget.showId);

      for (final id in _deletedIds) {
        await supabase.from('show_sections').delete().eq('id', id);
      }
      _deletedIds.clear();

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
          'breed_scope': s.breedScope,
          'allowed_breed_ids': s.allowedBreedIds.isEmpty
              ? null
              : s.allowedBreedIds,
          'allow_meat_classes': s.allowMeatClasses,
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
      Navigator.pop(context, true);
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
    final bgColor = kind == 'youth'
        ? const Color(0xFFEEE8FF)
        : const Color(0xFFE8F0FF);
    final fgColor = kind == 'youth'
        ? const Color(0xFF5B3FA8)
        : const Color(0xFF1D4E89);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fgColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _breedLabelFromId(String breedId) {
    final match = _breedOptions.cast<Map<String, dynamic>?>().firstWhere(
      (b) => b?['id']?.toString() == breedId,
      orElse: () => null,
    );

    if (match == null) return breedId;

    final species = (match['species'] ?? '').toString().trim();
    final name = (match['name'] ?? '').toString().trim();

    if (species.isEmpty) return name;
    return '${species.toUpperCase()} — $name';
  }

  Future<void> _pickBreedsForSection(_EditableSection s) async {
    if (_loadingBreeds) return;

    final working = Set<String>.from(s.allowedBreedIds);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
              title: Text(
                s.breedScope == 'single'
                    ? 'Select breed'
                    : 'Select allowed breeds',
              ),
              content: SizedBox(
                width: 520,
                height: 420,
                child: _loadingBreeds
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _breedOptions.length,
                        itemBuilder: (context, index) {
                          final breed = _breedOptions[index];
                          final breedId = breed['id'].toString();
                          final species = (breed['species'] ?? '')
                              .toString()
                              .toUpperCase();
                          final name = (breed['name'] ?? '').toString();
                          final checked = working.contains(breedId);

                          if (s.breedScope == 'single') {
                            return RadioListTile<String>(
                              value: breedId,
                              groupValue: working.isEmpty
                                  ? null
                                  : working.first,
                              title: Text('$species — $name'),
                              onChanged: _isReadOnly
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setInnerState(() {
                                        working
                                          ..clear()
                                          ..add(value);
                                      });
                                    },
                            );
                          }

                          return CheckboxListTile(
                            value: checked,
                            title: Text('$species — $name'),
                            subtitle: const Text(
                              'Choose the breeds allowed in this show.',
                            ),
                            onChanged: _isReadOnly
                                ? null
                                : (value) {
                                    setInnerState(() {
                                      if (value == true) {
                                        working.add(breedId);
                                      } else {
                                        working.remove(breedId);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: _isReadOnly
                      ? null
                      : () {
                          working.clear();
                          Navigator.pop(ctx);
                        },
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isReadOnly
                      ? null
                      : () {
                          setState(() {
                            s.allowedBreedIds = working.toList();
                          });
                          Navigator.pop(ctx);
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBreedScopeSelector(_EditableSection s) {
    return DropdownButtonFormField<String>(
      initialValue: s.breedScope,
      decoration: const InputDecoration(
        labelText: 'Breed scope',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All Breeds')),
        DropdownMenuItem(value: 'single', child: Text('Single Breed')),
        DropdownMenuItem(value: 'limited', child: Text('Selected Breeds')),
        DropdownMenuItem(value: 'meat_only', child: Text('Meat Classes Only')),
      ],
      onChanged: (_saving || _isReadOnly)
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                s.breedScope = value;
                if (value == 'all') {
                  s.allowedBreedIds = [];
                } else if (value == 'single' && s.allowedBreedIds.length > 1) {
                  s.allowedBreedIds = [s.allowedBreedIds.first];
                }
                if (value == 'meat_only') {
                  s.allowedBreedIds = [];
                  s.allowMeatClasses = true; // force on
                }
              });
            },
    );
  }

  Widget _buildAllowedBreedSummary(_EditableSection s) {
    if (s.breedScope == 'meat_only') {
      return Text(
        'This section is for commercial (meat) classes only.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    if (s.breedScope == 'all') {
      return Text(
        'This section accepts all breeds.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final labels = s.allowedBreedIds.map(_breedLabelFromId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: labels.isEmpty
              ? [const Chip(label: Text('No breeds selected'))]
              : labels
                    .map(
                      (x) =>
                          Chip(label: Text(x, overflow: TextOverflow.ellipsis)),
                    )
                    .toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: (_saving || _isReadOnly)
                  ? null
                  : () => _pickBreedsForSection(s),
              icon: const Icon(Icons.pets),
              label: Text(
                s.breedScope == 'single' ? 'Choose Breed' : 'Choose Breeds',
              ),
            ),
            if (s.allowedBreedIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: (_saving || _isReadOnly)
                    ? null
                    : () => setState(() => s.allowedBreedIds = []),
                child: const Text('Clear'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _sectionCard(int index) {
    final s = _sections[index];

    return AppTheme.surfaceTextScope(
      context,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: (_saving || _isReadOnly || index == 0)
                        ? null
                        : () => _moveUp(index),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed:
                        (_saving ||
                            _isReadOnly ||
                            index == _sections.length - 1)
                        ? null
                        : () => _moveDown(index),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: (_saving || _isReadOnly)
                        ? null
                        : () => _removeSection(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: s.displayNameCtrl,
                      enabled: !_saving && !_isReadOnly,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'Example: Open A or Sweepstakes Youth',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildBreedScopeSelector(s),
              const SizedBox(height: 10),
              _buildAllowedBreedSummary(s),
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: s.allowMeatClasses,
                onChanged: (_saving || _isReadOnly)
                    ? null
                    : (v) {
                        setState(() {
                          s.allowMeatClasses = v;
                        });
                      },
                title: const Text('Allow Meat Classes'),
                subtitle: const Text(
                  'Show commercial entries like Fryer, Roaster, Stewer, and Meat Pen for this section.',
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: s.isEnabled,
                onChanged: (_saving || _isReadOnly)
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width < 700 ? media.width - 16 : media.width * 0.76,
          maxHeight: media.height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.page,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/RingMaster_One_Show_Transparent.png',
                      height: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Show Sections — ${widget.showName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: AppTheme.gradientTextScope(
                    context,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Set the show order, enable or disable sections, customize names, and control which breeds are allowed in each letter show.',
                            style: TextStyle(
                              color: AppColors.headerForeground.withValues(
                                alpha: .9,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_isReadOnly) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.amber.shade300,
                                ),
                              ),
                              child: Text(
                                _isFinalized
                                    ? 'This show has been finalized. Sections are view-only.'
                                    : 'This show is locked. Sections are view-only.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_msg != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: .25),
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
                            const SizedBox(height: 12),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: (_saving || _isReadOnly)
                                    ? null
                                    : () => _addSection('open'),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Open'),
                              ),
                              FilledButton.icon(
                                onPressed: (_saving || _isReadOnly)
                                    ? null
                                    : () => _addSection('youth'),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Youth'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _loadAll,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reload'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _sections.isEmpty
                                ? const Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      'No sections yet. Add Open and/or Youth sections.',
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _sections.length,
                                    itemBuilder: (context, index) =>
                                        _sectionCard(index),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving
                                      ? null
                                      : () => Navigator.pop(context, false),
                                  child: const Text('Close'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primaryButton,
                                    foregroundColor:
                                        AppColors.primaryButtonText,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: (_saving || _isReadOnly)
                                      ? null
                                      : _saveAll,
                                  child: Text(_saving ? 'Saving…' : 'Save'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
  bool allowMeatClasses;
  int sortOrder;
  String breedScope;
  List<String> allowedBreedIds;
  final TextEditingController letterCtrl;
  final TextEditingController displayNameCtrl;

  _EditableSection({
    required this.id,
    required this.kind,
    required this.isEnabled,
    required this.allowMeatClasses,
    required this.sortOrder,
    required this.breedScope,
    required this.allowedBreedIds,
    required this.letterCtrl,
    required this.displayNameCtrl,
  });

  factory _EditableSection.fromDb(Map<String, dynamic> row) {
    final rawAllowed = row['allowed_breed_ids'];
    final allowed = <String>[];

    if (rawAllowed is List) {
      allowed.addAll(
        rawAllowed.map((e) => e.toString()).where((e) => e.trim().isNotEmpty),
      );
    }

    return _EditableSection(
      id: (row['id'] ?? '').toString(),
      kind: (row['kind'] ?? 'open').toString().trim().toLowerCase(),
      isEnabled: row['is_enabled'] == true,
      allowMeatClasses: row['allow_meat_classes'] == true,
      sortOrder: int.tryParse((row['sort_order'] ?? '').toString()) ?? 0,
      breedScope: (row['breed_scope'] ?? 'all').toString().trim().toLowerCase(),
      allowedBreedIds: allowed,
      letterCtrl: TextEditingController(text: (row['letter'] ?? '').toString()),
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
      allowMeatClasses: false,
      sortOrder: 0,
      breedScope: 'all',
      allowedBreedIds: <String>[],
      letterCtrl: TextEditingController(),
      displayNameCtrl: TextEditingController(text: displayName),
    );
  }

  void dispose() {
    letterCtrl.dispose();
    displayNameCtrl.dispose();
  }
}
