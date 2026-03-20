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
      final res = await supabase.functions.invoke(
        'import-arba-judges',
        body: {},
      );

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
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Superadmin'),
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
                  'Global Admin Tools',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage shared catalogs and system-wide imports.',
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(.18),
                      ),
                    ),
                    child: Text(
                      _msg!,
                      style: TextStyle(
                        color: success
                            ? Colors.white
                            : const Color(0xFFFFD7D7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF11285A).withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.pets,
                        color: Color(0xFF11285A),
                      ),
                    ),
                    title: const Text(
                      'Breed Catalog (Global)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Manage the shared breed and variety catalog used across shows',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openBreedCatalog,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF11285A).withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _importingJudges
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.download,
                              color: Color(0xFF11285A),
                            ),
                    ),
                    title: const Text(
                      'Import ARBA Judges',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sync the ARBA judge directory into the local judges table',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _importingJudges ? null : _runArbaJudgeImport,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}