// lib/screens/account_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';


import '../services/app_session.dart';
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
  String? _primaryExhibitorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ------------------------------
  // Load Exhibitors
  // ------------------------------
  Future<void> _load() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
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
          .eq('owner_user_id', userId)
          .order('created_at', ascending: true);

      final exhibitors = (rows as List).cast<Map<String, dynamic>>();

      String? primaryExhibitorId;
      try {
        final profile = await supabase
            .from('profiles')
            .select('primary_exhibitor_id')
            .eq('user_id', userId)
            .maybeSingle();

        primaryExhibitorId = profile?['primary_exhibitor_id']?.toString();
      } catch (_) {
        primaryExhibitorId = null;
      }

      final activeIds = exhibitors
          .where((e) => e['is_active'] == true)
          .map((e) => e['id']?.toString())
          .whereType<String>()
          .toSet();

      if (primaryExhibitorId == null ||
          !activeIds.contains(primaryExhibitorId)) {
        Map<String, dynamic>? defaultExhibitor;

        for (final exhibitor in exhibitors) {
          final type = (exhibitor['type'] ?? '').toString().toLowerCase();
          final active = exhibitor['is_active'] == true;
          if (active && type == 'adult') {
            defaultExhibitor = exhibitor;
            break;
          }
        }

        if (defaultExhibitor == null) {
          for (final exhibitor in exhibitors) {
            if (exhibitor['is_active'] == true) {
              defaultExhibitor = exhibitor;
              break;
            }
          }
        }

        primaryExhibitorId = defaultExhibitor?['id']?.toString();

        if (primaryExhibitorId != null && !AppSession.isSupportMode) {
          await supabase.from('profiles').update({
            'primary_exhibitor_id': primaryExhibitorId,
          }).eq('user_id', userId);
        }
      }

      if (!mounted) return;

      setState(() {
        _exhibitors = exhibitors;
        _primaryExhibitorId = primaryExhibitorId;
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
  // Exhibitor Dialog (NEW)
  // ------------------------------
  Future<void> _openExhibitorEditor({Map<String, dynamic>? existing}) async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Exhibitor editing is disabled while viewing in support mode.';
      });
      return;
    }

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
  // Set Primary Exhibitor
  // ------------------------------
  Future<void> _setPrimaryExhibitor(Map<String, dynamic> exhibitor) async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Changing the primary exhibitor is disabled while viewing in support mode.';
      });
      return;
    }

    final userId = AppSession.effectiveUserId;
    final exhibitorId = exhibitor['id']?.toString();

    if (userId == null || exhibitorId == null || exhibitorId.isEmpty) {
      return;
    }

    if (exhibitor['is_active'] != true) {
      setState(() {
        _msg = 'Activate this exhibitor before making them primary.';
      });
      return;
    }

    try {
      await supabase.from('profiles').update({
        'primary_exhibitor_id': exhibitorId,
      }).eq('user_id', userId);

      if (!mounted) return;
      setState(() {
        _primaryExhibitorId = exhibitorId;
        _msg = '${(exhibitor['display_name'] ?? 'Exhibitor').toString()} is now the primary exhibitor.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Unable to change primary exhibitor: $e');
    }
  }

  // ------------------------------
  // Toggle Active
  // ------------------------------
  Future<void> _toggleActive(String id, bool newActive) async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Activating and deactivating exhibitors is disabled while viewing in support mode.';
      });
      return;
    }

    try {
      await supabase
          .from('exhibitors')
          .update({'is_active': newActive})
          .eq('id', id);

      if (!newActive && id == _primaryExhibitorId) {
        final userId = AppSession.effectiveUserId;
        if (userId != null) {
          await supabase.from('profiles').update({
            'primary_exhibitor_id': null,
          }).eq('user_id', userId);
        }
      }

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
          tooltip: AppSession.isSupportMode
              ? 'Add exhibitor is disabled while viewing as another user'
              : 'Add Exhibitor',
          icon: const Icon(Icons.person_add_alt_1),
          onPressed: (_loading || AppSession.isSupportMode)
              ? null
              : () => _openExhibitorEditor(),
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
                if (AppSession.isSupportMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Text(
                        'Support Mode — Account settings are view-only while viewing as another user.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
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
                  ),
                Expanded(
                  child: _exhibitors.isEmpty
                      ? Center(
                          child: Text(
                            AppSession.isSupportMode
                                ? 'No exhibitors yet.'
                                : 'No exhibitors yet.\nTap + to add one.',
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
                            final isPrimary = id == _primaryExhibitorId;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
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
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isPrimary)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: .10),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: Colors.blue.withValues(alpha: .30),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.star,
                                              size: 15,
                                              color: Colors.blue,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'PRIMARY',
                                              style: TextStyle(
                                                color: Colors.blue,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Type: ${type.toUpperCase()}'
                                  '${bd == null ? '' : ' • DOB: $bd'}'
                                  '${active ? '' : ' • INACTIVE'}',
                                ),
                                onTap: AppSession.isSupportMode
                                    ? null
                                    : () => _openExhibitorEditor(existing: e),
                                trailing: AppSession.isSupportMode
                                    ? null
                                    : PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'edit') {
                                            _openExhibitorEditor(existing: e);
                                          }
                                          if (v == 'primary') {
                                            _setPrimaryExhibitor(e);
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
                                          if (active && !isPrimary)
                                            const PopupMenuItem(
                                              value: 'primary',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.star_outline),
                                                  SizedBox(width: 8),
                                                  Text('Set as primary'),
                                                ],
                                              ),
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