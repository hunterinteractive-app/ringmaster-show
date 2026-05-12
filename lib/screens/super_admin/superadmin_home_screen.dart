// lib/screens/superadmin/superadmin_home_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import '../show_list_screen.dart';
import 'breed_catalog_screen.dart';

final supabase = Supabase.instance.client;

class SupportImpersonationSession {
  static final ValueNotifier<SupportImpersonatedUser?> current =
      ValueNotifier<SupportImpersonatedUser?>(null);

  static bool get isActive => current.value != null;

  static String? get targetUserId => current.value?.userId;

  static void start(SupportImpersonatedUser user) {
    current.value = user;
  }

  static void stop() {
    current.value = null;
  }
}

class SupportImpersonatedUser {
  const SupportImpersonatedUser({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final String userId;
  final String email;
  final String displayName;

  String get label {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (email.trim().isNotEmpty) return email.trim();
    return userId;
  }
}

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

  Future<void> _openImpersonateUser() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _SupportImpersonationScreen(),
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
              'Manage shared catalogs, support tools, and system-wide imports.',
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
                _SuperadminToolCard(
                  icon: Icons.pets,
                  title: 'Breed Catalog (Global)',
                  subtitle:
                      'Manage the shared breed and variety catalog used across shows',
                  onTap: _openBreedCatalog,
                ),
                const SizedBox(height: 12),
                _SuperadminToolCard(
                  icon: Icons.support_agent,
                  title: 'View As User',
                  subtitle:
                      'Open support mode and view RingMaster as another user',
                  onTap: _openImpersonateUser,
                ),
                const SizedBox(height: 12),
                _SuperadminToolCard(
                  icon: Icons.download,
                  title: 'Import ARBA Judges',
                  subtitle:
                      'Sync the ARBA judge directory into the local judges table',
                  onTap: _importingJudges ? null : _runArbaJudgeImport,
                  leadingOverride: _importingJudges
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuperadminToolCard extends StatelessWidget {
  const _SuperadminToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leadingOverride,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? leadingOverride;

  @override
  Widget build(BuildContext context) {
    return Card(
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
          child: leadingOverride ??
              Icon(
                icon,
                color: const Color(0xFF11285A),
              ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SupportImpersonationScreen extends StatefulWidget {
  const _SupportImpersonationScreen();

  @override
  State<_SupportImpersonationScreen> createState() =>
      _SupportImpersonationScreenState();
}

class _SupportImpersonationScreenState
    extends State<_SupportImpersonationScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;
  String? _error;
  List<SupportImpersonatedUser> _users = <SupportImpersonatedUser>[];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();

    if (query.length < 2) {
      setState(() {
        _error = 'Enter at least 2 characters to search.';
        _users = <SupportImpersonatedUser>[];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final safeQuery = query.replaceAll('%', '').replaceAll(',', '');

      final rows = await supabase
          .from('profiles')
          .select('user_id,email,display_name')
          .or('email.ilike.%$safeQuery%,display_name.ilike.%$safeQuery%')
          .order('email')
          .limit(25);

      final users = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(
            (row) => SupportImpersonatedUser(
              userId: (row['user_id'] ?? '').toString(),
              email: (row['email'] ?? '').toString(),
              displayName: (row['display_name'] ?? '').toString(),
            ),
          )
          .where((user) => user.userId.isNotEmpty)
          .toList();

      if (!mounted) return;

      setState(() {
        _users = users;
        _loading = false;
        _error = users.isEmpty ? 'No matching users found.' : null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'User search failed: $e';
      });
    }
  }

  Future<void> _startImpersonation(SupportImpersonatedUser user) async {
    SupportImpersonationSession.start(user);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Support mode started for ${user.label}')),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ShowListScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'View As User',
      showBackButton: true,
      useScrollView: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Support Impersonation',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Search for a user by email or display name, then open the app using that user context.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search users',
                      hintText: 'Email or name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchUsers(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _searchUsers,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(.25)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final user = _users[index];

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: CircleAvatar(
                      child: Text(
                        user.label.isEmpty
                            ? '?'
                            : user.label.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(
                      user.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        user.email.isEmpty ? user.userId : user.email,
                      ),
                    ),
                    trailing: FilledButton.icon(
                      onPressed: () => _startImpersonation(user),
                      icon: const Icon(Icons.visibility),
                      label: const Text('View As'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}