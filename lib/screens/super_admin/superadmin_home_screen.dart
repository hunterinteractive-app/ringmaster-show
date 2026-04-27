// lib/screens/superadmin/home_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

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

  @override
  Widget build(BuildContext context) {
    final success = _msg != null && _msg!.startsWith('ARBA judges imported');

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Superadmin',
      showBackButton: true,
      useScrollView: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Global Admin Tools',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Text(
              'Manage shared catalogs and system-wide imports.',
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: success
                      ? Colors.green.withOpacity(.08)
                      : Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: success
                        ? Colors.green.withOpacity(.25)
                        : Colors.red.withOpacity(.25),
                  ),
                ),
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: success ? Colors.green.shade800 : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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