// lib/screens/my_animals_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'my_entries_screen.dart';
import 'account_settings_screen.dart';

import '../theme/app_theme.dart';
import '../services/app_session.dart';

import '../widgets/rm_widgets.dart';

import '../widgets/animal_editor/open_animal_editor_dialog.dart';

final supabase = Supabase.instance.client;

class MyAnimalsScreen extends StatefulWidget {
  const MyAnimalsScreen({super.key});

  @override
  State<MyAnimalsScreen> createState() => _MyAnimalsScreenState();
}

class _MyAnimalsScreenState extends State<MyAnimalsScreen> {
  Future<List<Map<String, dynamic>>> _loadAnimals() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final res = await supabase
        .from('animals')
        .select(
          'id,species,name,tattoo,breed,variety,sex,birth_date,is_dob_unknown,created_at',
        )
        .eq('owner_user_id', userId)
        .order('created_at', ascending: false);

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _deleteAnimal(String id) async {
    await supabase.from('animals').delete().eq('id', id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _confirmDeleteAnimal(Map<String, dynamic> animal) async {
    final name = (animal['name'] ?? '').toString().trim();
    final tattoo = (animal['tattoo'] ?? '').toString().trim().toUpperCase();
    final breed = (animal['breed'] ?? '').toString().trim();

    final label = name.isNotEmpty
        ? '$name${tattoo.isNotEmpty ? ' ($tattoo)' : ''}'
        : '$breed${tattoo.isNotEmpty ? ' ($tattoo)' : ''}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Animal'),
        content: Text('Are you sure you want to delete $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAnimal(animal['id'] as String);
    }
  }

  Future<void> _openAnimalEditor({
    Map<String, dynamic>? existing,
  }) async {
    final saved = await openAnimalEditorDialog(
      context,
      existing: existing,
    );

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  void _openEntries(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
    );
  }

  void _openAccount(BuildContext context) {
    if (AppSession.isSupportMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account settings are disabled while viewing in support mode.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
  }

  String _speciesLabel(String value) {
    final s = value.trim().toLowerCase();
    if (s == 'rabbit') return 'Rabbit';
    if (s == 'cavy') return 'Cavy';
    return value;
  }

  String _dobBadgeText(Map<String, dynamic> animal) {
    final isUnknown = animal['is_dob_unknown'] == true;
    final dob = (animal['birth_date'] ?? '').toString().trim();

    if (isUnknown) return 'DOB Unknown';
    if (dob.isNotEmpty) return 'DOB: $dob';
    return 'DOB Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'My Animals',
      showBackButton: true,
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Entries',
          icon: const Icon(Icons.receipt_long),
          onPressed: () => _openEntries(context),
        ),
        IconButton(
          tooltip: AppSession.isSupportMode
              ? 'Account disabled in support mode'
              : 'Account',
          icon: const Icon(Icons.manage_accounts),
          onPressed: AppSession.isSupportMode
              ? null
              : () => _openAccount(context),
        ),
        IconButton(
          tooltip: AppSession.isSupportMode
              ? 'Add animal while viewing as this user'
              : 'Add Animal',
          icon: const Icon(Icons.add),
          onPressed: () => _openAnimalEditor(),
        ),
      ],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadAnimals(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final animals = snap.data ?? [];

          if (animals.isEmpty) {
            return const RMEmptyState(
              title: 'No animals yet',
              subtitle: 'Add your animals here so they are ready when entering shows.',
              icon: Icons.pets_outlined,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: animals.length,
            itemBuilder: (context, i) {
              final a = animals[i];
              final species = (a['species'] ?? '').toString();
              final breed = (a['breed'] ?? '').toString();
              final variety = (a['variety'] ?? '').toString();
              final sex = (a['sex'] ?? '').toString();
              final tattoo =
                  (a['tattoo'] ?? '').toString().trim().toUpperCase();
              final name = (a['name'] ?? '').toString().trim();

              final title = name.isEmpty
                  ? '$breed${tattoo.isNotEmpty ? ' ($tattoo)' : ''}'
                  : '$name${tattoo.isNotEmpty ? ' ($tattoo)' : ''}';

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: RMCard(
                  onTap: () => _openAnimalEditor(existing: a),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: AppSession.isSupportMode
                                ? 'Actions while viewing as this user'
                                : 'Actions',
                            onSelected: (value) {
                              if (value == 'edit') {
                                _openAnimalEditor(existing: a);
                              } else if (value == 'delete') {
                                _confirmDeleteAnimal(a);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          RMBadge(
                            text: _speciesLabel(species),
                            icon: Icons.category_outlined,
                          ),
                          if (sex.isNotEmpty)
                            RMBadge(
                              text: sex,
                              icon: Icons.info_outline,
                            ),
                          RMBadge(
                            text: _dobBadgeText(a),
                            icon: Icons.cake_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '$breed • $variety',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}