// lib/screens/admin/admin_shows_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../create_show_screen.dart';
import 'edit_show_settings_screen.dart';

final supabase = Supabase.instance.client;

class AdminShowsScreen extends StatefulWidget {
  /// Only these shows will appear in Admin.
  /// Pass from ShowListScreen based on show_admins rows.
  final List<String> allowedShowIds;

  const AdminShowsScreen({
    super.key,
    required this.allowedShowIds,
  });

  @override
  State<AdminShowsScreen> createState() => _AdminShowsScreenState();
}

class _AdminShowsScreenState extends State<AdminShowsScreen> {
  Future<List<Map<String, dynamic>>> _loadShows() async {
    // If somehow opened without access, show nothing.
    if (widget.allowedShowIds.isEmpty) return [];

    final res = await supabase
        .from('shows')
        .select('id,name,start_date,end_date,location_name,is_published,entry_open_at,entry_close_at,created_at')
        .inFilter('id', widget.allowedShowIds)
        .order('start_date');

    return (res as List).cast<Map<String, dynamic>>();
  }

  String _fmtDate(String? v) {
    if (v == null || v.isEmpty) return '';
    return v.length >= 10 ? v.substring(0, 10) : v;
  }

  String _fmtTs(String? v) {
    if (v == null || v.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(v);
    if (dt == null) return '—';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _openCreate() async {
    // Even if user has access to some shows, they may not have permission to create.
    // If RLS blocks it, CreateShowScreen will fail and show an error.
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateShowScreen()),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _openEditShow(String showId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditShowSettingsScreen(showId: showId)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = false; // flip to true only if you add a permission check later

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin: Shows'),
        actions: [
          if (canCreate)
            IconButton(
              tooltip: 'Create Show',
              icon: const Icon(Icons.add),
              onPressed: _openCreate,
            ),
        ],
      ),
      body: widget.allowedShowIds.isEmpty
          ? const Center(child: Text('You do not have admin access to any shows.'))
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadShows(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final shows = snap.data ?? [];
                if (shows.isEmpty) {
                  return const Center(child: Text('No shows available for your admin access.'));
                }

                return ListView.separated(
                  itemCount: shows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = shows[i];

                    final showId = s['id'].toString();
                    final name = (s['name'] ?? '').toString();
                    final start = _fmtDate((s['start_date'] ?? '').toString());
                    final end = _fmtDate((s['end_date'] ?? '').toString());
                    final loc = (s['location_name'] ?? '').toString();
                    final published = s['is_published'] == true;

                    final openAt = _fmtTs(s['entry_open_at']?.toString());
                    final closeAt = _fmtTs(s['entry_close_at']?.toString());

                    final subtitleLines = <String>[
                      '$start${end.isNotEmpty ? ' → $end' : ''} • $loc',
                      'Entries: $openAt → $closeAt',
                    ];

                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(name)),
                          const SizedBox(width: 8),
                          Chip(label: Text(published ? 'Published' : 'Draft')),
                        ],
                      ),
                      subtitle: Text(subtitleLines.join('\n')),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openEditShow(showId),
                    );
                  },
                );
              },
            ),
    );
  }
}