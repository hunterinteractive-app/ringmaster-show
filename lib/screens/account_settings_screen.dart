// lib/screens/account_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'account_profile_setup_screen.dart';
import '../widgets/exhibitor_builder_dialog.dart';

final supabase = Supabase.instance.client;

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _loading = true;
  String? _msg;
  List<Map<String, dynamic>> _exhibitors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ------------------------------
  // Load Exhibitors
  // ------------------------------
  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _msg = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rows = await supabase
          .from('exhibitors')
          .select(
            'id,type,display_name,arba_number,email,phone,'
            'birth_date,is_active,created_at',
          )
          .eq('owner_user_id', user.id)
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        _exhibitors = (rows as List).cast<Map<String, dynamic>>();
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

  // ------------------------------
  // Profile Setup
  // ------------------------------
  Future<void> _openProfileSetup() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AccountProfileSetupScreen()),
    );

    if (saved == true) {
      if (mounted) setState(() => _msg = 'Profile saved.');
    }
  }

  // ------------------------------
  // Exhibitor Dialog (NEW)
  // ------------------------------
  Future<void> _openExhibitorEditor({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExhibitorBuilderDialog(
        exhibitorId: existing?['id']?.toString(),
      ),
    );

    if (saved != null) {
      await _load();
    }
  }

  // ------------------------------
  // Toggle Active
  // ------------------------------
  Future<void> _toggleActive(String id, bool newActive) async {
    try {
      await supabase
          .from('exhibitors')
          .update({'is_active': newActive})
          .eq('id', id);

      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
  }

  // ------------------------------
  // UI
  // ------------------------------
  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Account Settings',
      showBackButton: true,
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Add Exhibitor',
          icon: const Icon(Icons.person_add_alt_1),
          onPressed: _loading ? null : () => _openExhibitorEditor(),
        ),
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(.25),
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
                  ),
                Expanded(
                  child: _exhibitors.isEmpty
                      ? const Center(
                          child: Text(
                            'No exhibitors yet.\nTap + to add one.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _exhibitors.length,
                          itemBuilder: (context, i) {
                            final e = _exhibitors[i];
                            final id = e['id'].toString();
                            final type = (e['type'] ?? '').toString();
                            final name = (e['display_name'] ?? '').toString();
                            final active = e['is_active'] == true;
                            final bd = e['birth_date']?.toString();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.05),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'Type: ${type.toUpperCase()}'
                                  '${bd == null ? '' : ' • DOB: $bd'}'
                                  '${active ? '' : ' • INACTIVE'}',
                                ),
                                onTap: () => _openExhibitorEditor(existing: e),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      _openExhibitorEditor(existing: e);
                                    }
                                    if (v == 'deactivate') {
                                      _toggleActive(id, false);
                                    }
                                    if (v == 'activate') {
                                      _toggleActive(id, true);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    if (active)
                                      const PopupMenuItem(
                                        value: 'deactivate',
                                        child: Text('Deactivate'),
                                      )
                                    else
                                      const PopupMenuItem(
                                        value: 'activate',
                                        child: Text('Activate'),
                                      ),
                                  ],
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