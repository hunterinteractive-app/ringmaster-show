// lib/screens/superadmin/home_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'breed_catalog_screen.dart';

final supabase = Supabase.instance.client;

class SuperadminHomeScreen extends StatefulWidget {
  const SuperadminHomeScreen({super.key});

  @override
  State<SuperadminHomeScreen> createState() => _SuperadminHomeScreenState();
}

class _SuperadminHomeScreenState extends State<SuperadminHomeScreen> {
  bool _importingJudges = false;
  String? _msg;

  Future<void> _openBreedCatalog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BreedCatalogScreen(),
      ),
    );
  }

  Future<void> _runArbaJudgeImport() async {
    setState(() {
      _importingJudges = true;
      _msg = null;
    });

    try {
      final res = await supabase.functions.invoke('import-arba-judges');

      if (!mounted) return;

      if (res.status != 200) {
        setState(() {
          _importingJudges = false;
          _msg = 'Judge import failed: ${res.data}';
        });
        return;
      }

      final data = (res.data is Map<String, dynamic>)
          ? res.data as Map<String, dynamic>
          : <String, dynamic>{};

      final importedCount = data['imported_count']?.toString() ?? '0';
      final activeCount = data['active_arba_judges']?.toString() ?? '0';
      final inactiveCount = data['inactive_arba_judges']?.toString() ?? '0';
      final sourceUpdatedAt = data['source_updated_at']?.toString() ?? '';

      final successMsg = sourceUpdatedAt.isEmpty
          ? 'ARBA judges imported. Imported: $importedCount • Active: $activeCount • Inactive: $inactiveCount'
          : 'ARBA judges imported. Imported: $importedCount • Active: $activeCount • Inactive: $inactiveCount • Source: $sourceUpdatedAt';

      setState(() {
        _importingJudges = false;
        _msg = successMsg;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMsg)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importingJudges = false;
        _msg = 'Judge import failed: $e';
      });
    }
  }

  Widget _toolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? leadingOverride,
  }) {
    return Card(
      child: ListTile(
        leading: leadingOverride ?? Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final success = _msg != null && _msg!.startsWith('ARBA judges imported');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Superadmin'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Global Admin Tools',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Manage shared catalogs and system-wide imports.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _msg!,
                style: TextStyle(
                  color: success ? Colors.green : Colors.red,
                ),
              ),
            ),

          _toolCard(
            icon: Icons.pets,
            title: 'Breed Catalog (Global)',
            subtitle: 'Manage the shared breed and variety catalog used across shows',
            onTap: _openBreedCatalog,
          ),

          const SizedBox(height: 12),

          _toolCard(
            icon: Icons.download,
            title: 'Import ARBA Judges',
            subtitle: 'Sync the ARBA judge directory into the local judges table',
            onTap: _importingJudges ? null : _runArbaJudgeImport,
            leadingOverride: _importingJudges
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}