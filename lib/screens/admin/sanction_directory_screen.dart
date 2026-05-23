// lib/screens/admin/sanction_directory_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ringmaster_page_shell.dart';

final _supabase = Supabase.instance.client;

class SanctionDirectoryScreen extends StatefulWidget {
  const SanctionDirectoryScreen({super.key});

  @override
  State<SanctionDirectoryScreen> createState() => _SanctionDirectoryScreenState();
}

class _SanctionDirectoryScreenState extends State<SanctionDirectoryScreen> {
  bool _loading = true;
  bool _hasAdminAccess = false;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  List<_SanctionDirectoryRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _hasAdminAccess = false;
          _rows = const [];
          _loading = false;
        });
        return;
      }

      final roleRows = await _supabase
          .from('role_assignments')
          .select('role')
          .eq('user_id', user.id)
          .inFilter('role', ['super_admin', 'admin'])
          .limit(1);

      final hasAdminAccess = (roleRows as List).isNotEmpty;
      if (!hasAdminAccess) {
        setState(() {
          _hasAdminAccess = false;
          _rows = const [];
          _loading = false;
        });
        return;
      }

      final clubRows = await _supabase
          .from('breed_clubs')
          .select('''
            id,
            sanctioning_body,
            club_name,
            breed_name,
            website,
            notes,
            is_active,
            club_type,
            state_code,
            breed_club_sanction_links(
              id,
              link_type,
              label,
              url,
              notes,
              is_active,
              last_verified_at
            )
          ''')
          .eq('is_active', true)
          .order('club_type', ascending: true)
          .order('breed_name', ascending: true)
          .order('club_name', ascending: true);

      final rows = <_SanctionDirectoryRow>[];

      for (final rawClub in clubRows as List) {
        final club = Map<String, dynamic>.from(rawClub as Map);
        final linksRaw = club['breed_club_sanction_links'];
        final links = linksRaw is List ? linksRaw : const [];
        final activeLinks = links
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .where((link) => link['is_active'] == true)
            .toList();

        if (activeLinks.isEmpty) {
          rows.add(_SanctionDirectoryRow.fromClub(club: club));
          continue;
        }

        for (final link in activeLinks) {
          rows.add(_SanctionDirectoryRow.fromClub(club: club, link: link));
        }
      }

      rows.sort((a, b) {
        final breedCompare = a.breedName.toLowerCase().compareTo(b.breedName.toLowerCase());
        if (breedCompare != 0) return breedCompare;
        final clubCompare = a.clubName.toLowerCase().compareTo(b.clubName.toLowerCase());
        if (clubCompare != 0) return clubCompare;
        return a.linkLabel.toLowerCase().compareTo(b.linkLabel.toLowerCase());
      });

      setState(() {
        _hasAdminAccess = true;
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_SanctionDirectoryRow> get _filteredRows {
    if (_searchText.isEmpty) return _rows;

    return _rows.where((row) {
      return row.breedName.toLowerCase().contains(_searchText) ||
          row.clubName.toLowerCase().contains(_searchText) ||
          row.clubType.toLowerCase().contains(_searchText) ||
          row.sanctioningBody.toLowerCase().contains(_searchText) ||
          row.stateCode.toLowerCase().contains(_searchText) ||
          row.linkLabel.toLowerCase().contains(_searchText);
    }).toList();
  }

  Future<void> _openUrl(String? rawUrl) async {
    final url = rawUrl?.trim();
    if (url == null || url.isEmpty) {
      _showSnack('No link is available yet.');
      return;
    }

    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) {
      _showSnack('That link is not valid.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showSnack('Could not open the link.');
    }
  }

  Future<void> _reportBrokenLink(_SanctionDirectoryRow row) async {
    final user = _supabase.auth.currentUser;

    try {
      await _supabase.from('breed_club_link_reports').insert({
        'sanction_link_id': row.linkId,
        'breed_club_id': row.clubId,
        'reported_by_user_id': user?.id,
        'report_reason': 'Broken or outdated sanction directory link',
        'status': 'open',
      });

      if (mounted) {
        _showSnack('Thanks. This link was flagged for review.');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Could not report the link: $e');
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Sanction Directory',
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasAdminAccess) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Admin Access Required',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This directory is available to Admin and Super Admin users while sanction links are being built and verified.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Could not load sanction directory',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final rows = _filteredRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderCard(context),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search breed, club, state, or sanctioning body',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${rows.length} of ${_rows.length} links / clubs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No sanction links found.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _SanctionDirectoryCard(
                      row: rows[index],
                      onOpen: () => _openUrl(rows[index].url),
                      onReportBroken: () => _reportBrokenLink(rows[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      color: AppTheme.primaryBlue.withOpacity(.06),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_outlined, color: AppTheme.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sanction Directory',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryBlue,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Admin view for maintaining breed club sanction and sweepstakes links before this is opened more broadly to show secretaries.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SanctionDirectoryCard extends StatelessWidget {
  const _SanctionDirectoryCard({
    required this.row,
    required this.onOpen,
    required this.onReportBroken,
  });

  final _SanctionDirectoryRow row;
  final VoidCallback onOpen;
  final VoidCallback onReportBroken;

  @override
  Widget build(BuildContext context) {
    final hasLink = row.url.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.breedName.isEmpty ? 'All Breeds / General Sanction' : row.breedName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.clubName,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                _StatusChip(label: row.clubTypeLabel),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (row.sanctioningBody.isNotEmpty)
                  _InfoChip(icon: Icons.account_balance, label: row.sanctioningBody),
                if (row.stateCode.isNotEmpty)
                  _InfoChip(icon: Icons.place_outlined, label: row.stateCode),
                if (row.linkType.isNotEmpty)
                  _InfoChip(icon: Icons.link, label: row.linkType),
                _InfoChip(
                  icon: Icons.fact_check_outlined,
                  label: row.lastVerifiedLabel,
                ),
              ],
            ),
            if (row.linkLabel.isNotEmpty || row.linkNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (row.linkLabel.isNotEmpty)
                Text(
                  row.linkLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              if (row.linkNotes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(row.linkNotes),
              ],
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: hasLink ? onOpen : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Link'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: row.linkId == null ? null : onReportBroken,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Report Broken Link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _SanctionDirectoryRow {
  const _SanctionDirectoryRow({
    required this.clubId,
    required this.sanctioningBody,
    required this.clubName,
    required this.breedName,
    required this.clubType,
    required this.stateCode,
    required this.linkId,
    required this.linkType,
    required this.linkLabel,
    required this.url,
    required this.linkNotes,
    required this.lastVerifiedAt,
  });

  final String clubId;
  final String sanctioningBody;
  final String clubName;
  final String breedName;
  final String clubType;
  final String stateCode;
  final String? linkId;
  final String linkType;
  final String linkLabel;
  final String url;
  final String linkNotes;
  final DateTime? lastVerifiedAt;

  factory _SanctionDirectoryRow.fromClub({
    required Map<String, dynamic> club,
    Map<String, dynamic>? link,
  }) {
    return _SanctionDirectoryRow(
      clubId: (club['id'] ?? '').toString(),
      sanctioningBody: (club['sanctioning_body'] ?? '').toString(),
      clubName: (club['club_name'] ?? '').toString(),
      breedName: (club['breed_name'] ?? '').toString(),
      clubType: (club['club_type'] ?? '').toString(),
      stateCode: (club['state_code'] ?? '').toString(),
      linkId: link == null ? null : (link['id'] ?? '').toString(),
      linkType: (link?['link_type'] ?? '').toString(),
      linkLabel: (link?['label'] ?? '').toString(),
      url: (link?['url'] ?? club['website'] ?? '').toString(),
      linkNotes: (link?['notes'] ?? club['notes'] ?? '').toString(),
      lastVerifiedAt: _tryParseDate(link?['last_verified_at']),
    );
  }

  String get clubTypeLabel {
    final value = clubType.trim();
    if (value.isEmpty) return 'Club';
    return value
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  String get lastVerifiedLabel {
    if (lastVerifiedAt == null) return 'Not verified';
    final date = lastVerifiedAt!;
    return 'Verified ${date.month}/${date.day}/${date.year}';
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}