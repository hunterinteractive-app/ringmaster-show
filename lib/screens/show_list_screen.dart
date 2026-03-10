import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/screens/admin/admin_shows_screen.dart';
import 'package:ringmaster_show/screens/admin/edit_show_settings_screen.dart';
import 'package:ringmaster_show/screens/super_admin/superadmin_home_screen.dart';

import 'login_screen.dart';
import 'my_animals_screen.dart';
import 'enter_show_screen.dart';
import 'account_settings_screen.dart';
import 'my_entries_screen.dart';

import '../services/role_service.dart';

final supabase = Supabase.instance.client;

class ShowListScreen extends StatelessWidget {
  const ShowListScreen({super.key});

  // ------------------------------
  // Loaders
  // ------------------------------

  Future<List<Map<String, dynamic>>> _loadShows() async {
    final res = await supabase
        .from('shows')
        .select('id,name,start_date,location_name')
        .eq('is_published', true)
        .order('start_date');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Set<String>> _loadAdminShowIds() async {
    final user = supabase.auth.currentUser;
    if (user == null) return <String>{};

    final rows = await supabase
        .from('role_assignments')
        .select('show_id, role')
        .eq('user_id', user.id);

    const allowedRoles = {
      'super_admin',
      'admin',
      'superintendent',
      'reporting_clerk',
    };

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => allowedRoles.contains((r['role'] ?? '').toString()))
        .map((r) => (r['show_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<_ShowListBundle> _loadBundle() async {
    final shows = await _loadShows();
    final isSuper = await RoleService.isSuperAdmin();

    Set<String> adminShowIds = <String>{};
    try {
      adminShowIds = await _loadAdminShowIds();
    } catch (_) {
      adminShowIds = <String>{};
    }

    return _ShowListBundle(
      shows: shows,
      adminShowIds: adminShowIds,
      isSuperAdmin: isSuper,
    );
  }

  // ------------------------------
  // Actions
  // ------------------------------

  Future<void> _logout(BuildContext context) async {
    await supabase.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _openEditShow(BuildContext context, String showId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditShowSettingsScreen(showId: showId),
      ),
    );
  }

  void _openEnterShow(BuildContext context, String showId, String showName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnterShowScreen(
          showId: showId,
          showName: showName,
        ),
      ),
    );
  }

  // ------------------------------
  // UI
  // ------------------------------

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShowListBundle>(
      future: _loadBundle(),
      builder: (context, snap) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Upcoming Shows'),
            actions: [
              // We can only decide Admin visibility once bundle is loaded
              if (snap.connectionState == ConnectionState.done &&
                  snap.hasError == false &&
                  (snap.data?.canSeeAdminButton ?? false))
                IconButton(
                  tooltip: 'Admin',
                  icon: const Icon(Icons.admin_panel_settings),
                  onPressed: () {
                    final bundle = snap.data!;
                    final allowedShowIds = (bundle.isSuperAdmin
                            ? bundle.allShowIds
                            : bundle.adminShowIds)
                        .toList();

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminShowsScreen(
                          allowedShowIds: allowedShowIds,
                        ),
                      ),
                    );
                  },
                ),

              IconButton(
                tooltip: 'My Animals',
                icon: const Icon(Icons.pets),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
                  );
                },
              ),

              IconButton(
                tooltip: 'My Entries',
                icon: const Icon(Icons.receipt_long),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
                  );
                },
              ),

              // Super Admin shortcut
              FutureBuilder<bool>(
                future: RoleService.isSuperAdmin(),
                builder: (context, snap) {
                  final isSuper = snap.data == true;
                  if (!isSuper) return const SizedBox.shrink();

                  return IconButton(
                    tooltip: 'Super Admin',
                    icon: const Icon(Icons.library_books),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SuperadminHomeScreen()),
                      );
                    },
                  );
                },
              ),

              IconButton(
                tooltip: 'Account Settings',
                icon: const Icon(Icons.manage_accounts),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
                  );
                },
              ),

              IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout),
                onPressed: () => _logout(context),
              ),
            ],
          ),
          body: Builder(
            builder: (_) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }

              final bundle = snap.data!;
              final shows = bundle.shows;

              if (shows.isEmpty) {
                return const Center(child: Text('No published shows yet.'));
              }

              return ListView.builder(
                itemCount: shows.length,
                itemBuilder: (context, i) {
                  final s = shows[i];
                  final showId = s['id'].toString();
                  final showName = (s['name'] ?? '').toString();
                  final startDate = (s['start_date'] ?? '').toString();
                  final location = (s['location_name'] ?? '').toString();

                  // ✅ Super Admin can admin any show
                  final isAdminForShow =
                      bundle.isSuperAdmin || bundle.adminShowIds.contains(showId);

                  return ListTile(
                    title: Text(showName),
                    subtitle: Text('$startDate • $location'),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Actions',
                      onSelected: (v) {
                        if (v == 'enter') {
                          _openEnterShow(context, showId, showName);
                        } else if (v == 'admin') {
                          _openEditShow(context, showId);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'enter',
                          child: Text('Enter Show'),
                        ),
                        if (isAdminForShow)
                          const PopupMenuItem(
                            value: 'admin',
                            child: Text('Admin Settings'),
                          ),
                      ],
                    ),
                    onTap: () => _openEnterShow(context, showId, showName),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _ShowListBundle {
  final List<Map<String, dynamic>> shows;
  final Set<String> adminShowIds;
  final bool isSuperAdmin;

  _ShowListBundle({
    required this.shows,
    required this.adminShowIds,
    required this.isSuperAdmin,
  });

  Set<String> get allShowIds => shows
      .map((s) => (s['id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();

  bool get canSeeAdminButton => isSuperAdmin || adminShowIds.isNotEmpty;
}