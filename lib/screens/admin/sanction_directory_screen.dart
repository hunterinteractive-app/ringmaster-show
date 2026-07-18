// lib/screens/admin/sanction_directory_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/ringmaster_page_shell.dart';
import '../../services/app_session.dart';

final _supabase = Supabase.instance.client;

class SanctionDirectoryScreen extends StatefulWidget {
  const SanctionDirectoryScreen({super.key, this.showId});

  final String? showId;

  @override
  State<SanctionDirectoryScreen> createState() =>
      _SanctionDirectoryScreenState();
}

class _SanctionDirectoryScreenState extends State<SanctionDirectoryScreen> {
  bool _loading = true;
  bool _hasAdminAccess = false;
  bool _markingRequested = false;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  _SanctionDirectoryFilter _selectedFilter =
      _SanctionDirectoryFilter.nationalBreedClubs;

  List<_SanctionDirectoryRow> _rows = const [];
  List<_ShowSectionOption> _sections = const [];
  final Map<String, _SanctionDirectoryStatus> _statusByBreedClubId = {};
  final Map<String, _LinkReport> _openReportByLinkId = {};
  final Set<String> _reviewingLinkIds = {};

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
          _sections = const [];
          _statusByBreedClubId.clear();
          _openReportByLinkId.clear();
          _loading = false;
        });
        return;
      }

      final hasAdminAccess = await _hasSuperAdminAccess(user.id);
      if (!hasAdminAccess) {
        setState(() {
          _hasAdminAccess = false;
          _rows = const [];
          _sections = const [];
          _statusByBreedClubId.clear();
          _openReportByLinkId.clear();
          _loading = false;
        });
        return;
      }

      var sections = <_ShowSectionOption>[];
      if (widget.showId != null && widget.showId!.trim().isNotEmpty) {
        final sectionRows = await _supabase
            .from('show_sections')
            .select('id,kind,letter,sort_order,is_enabled')
            .eq('show_id', widget.showId!)
            .eq('is_enabled', true)
            .order('sort_order', ascending: true)
            .order('letter', ascending: true);

        sections = (sectionRows as List)
            .whereType<Map>()
            .map(
              (raw) =>
                  _ShowSectionOption.fromMap(Map<String, dynamic>.from(raw)),
            )
            .toList();

        sections.sort((a, b) {
          final kindCompare = a.kindRank.compareTo(b.kindRank);
          if (kindCompare != 0) return kindCompare;
          final sortCompare = a.sortOrder.compareTo(b.sortOrder);
          if (sortCompare != 0) return sortCompare;
          return a.letter.compareTo(b.letter);
        });
      }

      final statusByBreedClubId = <String, _SanctionDirectoryStatus>{};
      if (widget.showId != null && widget.showId!.trim().isNotEmpty) {
        final sanctionRows = await _supabase
            .from('show_sanctions')
            .select('breed_club_id,request_status,sanction_number')
            .eq('show_id', widget.showId!);

        for (final raw in sanctionRows as List) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final breedClubId = (map['breed_club_id'] ?? '').toString().trim();
          if (breedClubId.isEmpty) continue;

          final status = _SanctionDirectoryStatus.fromSanctionRow(
            requestStatus: (map['request_status'] ?? '').toString(),
            sanctionNumber: (map['sanction_number'] ?? '').toString(),
          );

          final current = statusByBreedClubId[breedClubId];
          if (current == null || status.priority > current.priority) {
            statusByBreedClubId[breedClubId] = status;
          }
        }
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
        final breedCompare = a.breedName.toLowerCase().compareTo(
          b.breedName.toLowerCase(),
        );
        if (breedCompare != 0) return breedCompare;
        final clubCompare = a.clubName.toLowerCase().compareTo(
          b.clubName.toLowerCase(),
        );
        if (clubCompare != 0) return clubCompare;
        return a.linkLabel.toLowerCase().compareTo(b.linkLabel.toLowerCase());
      });

      final openReportByLinkId = <String, _LinkReport>{};
      final reportRows = await _supabase
          .from('breed_club_link_reports')
          .select(
            'id,sanction_link_id,report_reason,proposed_url,status,created_at',
          )
          .eq('status', 'open')
          .order('created_at', ascending: false);
      for (final raw in reportRows as List) {
        if (raw is! Map) continue;
        final report = _LinkReport.fromMap(Map<String, dynamic>.from(raw));
        if (report.sanctionLinkId.isEmpty) continue;
        openReportByLinkId.putIfAbsent(report.sanctionLinkId, () => report);
      }

      setState(() {
        _hasAdminAccess = true;
        _rows = rows;
        _sections = sections;
        _statusByBreedClubId
          ..clear()
          ..addAll(statusByBreedClubId);
        _openReportByLinkId
          ..clear()
          ..addAll(openReportByLinkId);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<bool> _hasSuperAdminAccess(String userId) async {
    // Older super-admin accounts are stored in super_admins, while newer ones
    // may use role_assignments. The directory must recognize both sources.
    try {
      final legacySuperAdmin = await _supabase
          .from('super_admins')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      if (legacySuperAdmin != null) return true;
    } catch (_) {
      // Continue to the current role source.
    }

    try {
      final roleRows = await _supabase
          .from('role_assignments')
          .select('role')
          .eq('user_id', userId)
          .eq('role', 'super_admin')
          .limit(1);
      return (roleRows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<_SanctionDirectoryRow> get _filteredRows {
    return _rows.where((row) {
      final matchesSearch =
          _searchText.isEmpty ||
          row.breedName.toLowerCase().contains(_searchText) ||
          row.clubName.toLowerCase().contains(_searchText) ||
          row.clubType.toLowerCase().contains(_searchText) ||
          row.sanctioningBody.toLowerCase().contains(_searchText) ||
          row.stateCode.toLowerCase().contains(_searchText) ||
          row.linkLabel.toLowerCase().contains(_searchText);

      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case _SanctionDirectoryFilter.all:
          return true;
        case _SanctionDirectoryFilter.nationalBreedClubs:
          return row.isNationalBreedClub;
        case _SanctionDirectoryFilter.stateClubs:
          return row.isStateClub;
        case _SanctionDirectoryFilter.missingLink:
          return row.url.trim().isEmpty;
        case _SanctionDirectoryFilter.linkChecked:
          return row.lastVerifiedAt != null;
        case _SanctionDirectoryFilter.linkNotCheckedOrBroken:
          return row.lastVerifiedAt == null ||
              (row.linkId != null &&
                  _openReportByLinkId.containsKey(row.linkId));
      }
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
    final proposedUrlController = TextEditingController();
    var hasCorrectLink = false;

    final submission = await showDialog<_BrokenLinkSubmission>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Report broken link'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.clubName,
                      style: Theme.of(dialogContext).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    const Text('Do you have the correct replacement link?'),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: hasCorrectLink,
                      title: const Text('Yes, I have the correct link'),
                      onChanged: (value) {
                        setDialogState(() {
                          hasCorrectLink = value == true;
                          if (!hasCorrectLink) proposedUrlController.clear();
                        });
                      },
                    ),
                    if (hasCorrectLink) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: proposedUrlController,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Correct link',
                          hintText: 'https://example.com/sanctions',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final proposedUrl = proposedUrlController.text.trim();
                    if (hasCorrectLink && !_isValidWebUrl(proposedUrl)) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a complete http:// or https:// link.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _BrokenLinkSubmission(
                        proposedUrl: hasCorrectLink ? proposedUrl : null,
                      ),
                    );
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Submit for Review'),
                ),
              ],
            );
          },
        );
      },
    );
    proposedUrlController.dispose();
    if (submission == null) return;

    try {
      await _supabase.from('breed_club_link_reports').insert({
        'sanction_link_id': row.linkId,
        'breed_club_id': row.clubId,
        'reported_by_user_id': user?.id,
        'report_reason': 'Broken or outdated sanction directory link',
        'proposed_url': submission.proposedUrl,
        'status': 'open',
        'show_id': widget.showId,
      });

      if (mounted) {
        _showSnack('This link is now pending review.');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showSnack('Could not report the link: $e');
      }
    }
  }

  bool _isValidWebUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _approveLinkReport(
    _SanctionDirectoryRow row,
    _LinkReport report,
  ) async {
    final proposedUrl = report.proposedUrl.trim();
    if (row.linkId == null || !_isValidWebUrl(proposedUrl)) {
      _showSnack('This report does not include a valid replacement link.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve replacement link?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.clubName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text('Current link:'),
            SelectableText(row.url),
            const SizedBox(height: 12),
            const Text('Proposed link:'),
            SelectableText(proposedUrl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('Approve Change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _reviewingLinkIds.add(row.linkId!));
    try {
      final userId = _supabase.auth.currentUser?.id;
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase
          .from('breed_club_sanction_links')
          .update({
            'url': proposedUrl,
            'last_verified_at': now,
            'last_verified_by': userId,
            'updated_at': now,
          })
          .eq('id', row.linkId!);
      await _supabase
          .from('breed_club_link_reports')
          .update({
            'status': 'approved',
            'admin_notes': 'Replacement link approved from Sanction Directory.',
            'resolved_at': now,
            'resolved_by': userId,
          })
          .eq('id', report.id);
      if (mounted) _showSnack('Replacement link approved and published.');
      await _load();
    } catch (e) {
      if (mounted) _showSnack('Could not approve the link: $e');
    } finally {
      if (mounted) setState(() => _reviewingLinkIds.remove(row.linkId));
    }
  }

  Future<void> _dismissLinkReport(
    _SanctionDirectoryRow row,
    _LinkReport report,
  ) async {
    if (row.linkId == null) return;
    setState(() => _reviewingLinkIds.add(row.linkId!));
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase
          .from('breed_club_link_reports')
          .update({
            'status': 'dismissed',
            'admin_notes': 'Report dismissed from Sanction Directory.',
            'resolved_at': now,
            'resolved_by': _supabase.auth.currentUser?.id,
          })
          .eq('id', report.id);
      if (mounted) _showSnack('Broken-link report dismissed.');
      await _load();
    } catch (e) {
      if (mounted) _showSnack('Could not dismiss the report: $e');
    } finally {
      if (mounted) setState(() => _reviewingLinkIds.remove(row.linkId));
    }
  }

  Future<void> _markRequested(_SanctionDirectoryRow row) async {
    final showId = widget.showId?.trim();
    if (showId == null || showId.isEmpty) {
      _showSnack(
        'Open this directory from a show to mark a sanction requested.',
      );
      return;
    }

    if (_sections.isEmpty) {
      _showSnack('No enabled sections were found for this show.');
      return;
    }

    final selectedSectionIds = _sections.map((section) => section.id).toSet();

    final confirmedSectionIds = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Mark sanction requested'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.breedName.isEmpty
                          ? row.clubName
                          : '${row.breedName} • ${row.clubName}',
                      style: Theme.of(dialogContext).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Choose the show sections this request applies to:',
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _sections.map((section) {
                            final selected = selectedSectionIds.contains(
                              section.id,
                            );
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: selected,
                              title: Text(section.label),
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedSectionIds.add(section.id);
                                  } else {
                                    selectedSectionIds.remove(section.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: selectedSectionIds.isEmpty
                      ? null
                      : () => Navigator.of(
                          dialogContext,
                        ).pop(Set<String>.from(selectedSectionIds)),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark Requested'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmedSectionIds == null || confirmedSectionIds.isEmpty) return;

    setState(() {
      _markingRequested = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      for (final sectionId in confirmedSectionIds) {
        final existingRows = await _supabase
            .from('show_sanctions')
            .select('id')
            .eq('show_id', showId)
            .eq('section_id', sectionId)
            .eq('breed_club_id', row.clubId)
            .limit(1);

        final existing = (existingRows as List).isNotEmpty
            ? Map<String, dynamic>.from(existingRows.first as Map)
            : null;

        final payload = <String, dynamic>{
          'show_id': showId,
          'section_id': sectionId,
          'breed_club_id': row.clubId,
          'sanctioning_body': row.sanctioningBody,
          'club_name': row.clubName,
          'breed_name': row.breedName,
          'request_status': 'secretary_requested',
          'requested_by_user_id': user?.id,
          'requested_by_role': 'admin',
          'requested_at': DateTime.now().toUtc().toIso8601String(),
          'request_source': 'sanction_directory',
        };

        final insertPayload = <String, dynamic>{
          ...payload,
          'sanction_number': '',
          'notes': null,
        };

        if (existing == null) {
          await _supabase.from('show_sanctions').insert(insertPayload);
        } else {
          await _supabase
              .from('show_sanctions')
              .update(payload)
              .eq('id', existing['id'].toString());
        }
      }

      if (mounted) {
        _showSnack(
          'Marked requested for ${confirmedSectionIds.length} section(s).',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showSnack('Could not mark requested: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _markingRequested = false;
        });
      }
    }
  }

  Future<void> _clearRequested(_SanctionDirectoryRow row) async {
    final showId = widget.showId?.trim();
    if (showId == null || showId.isEmpty) {
      _showSnack('Open this directory from a show to remove a request flag.');
      return;
    }

    if (_sections.isEmpty) {
      _showSnack('No enabled sections were found for this show.');
      return;
    }

    final selectedSectionIds = _sections.map((section) => section.id).toSet();

    final confirmedSectionIds = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Remove requested flag'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.breedName.isEmpty
                          ? row.clubName
                          : '${row.breedName} • ${row.clubName}',
                      style: Theme.of(dialogContext).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Choose the show sections where the requested flag should be removed. Existing sanction numbers will not be removed.',
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _sections.map((section) {
                            final selected = selectedSectionIds.contains(
                              section.id,
                            );
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: selected,
                              title: Text(section.label),
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedSectionIds.add(section.id);
                                  } else {
                                    selectedSectionIds.remove(section.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: selectedSectionIds.isEmpty
                      ? null
                      : () => Navigator.of(
                          dialogContext,
                        ).pop(Set<String>.from(selectedSectionIds)),
                  icon: const Icon(Icons.clear),
                  label: const Text('Remove Flag'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmedSectionIds == null || confirmedSectionIds.isEmpty) return;

    setState(() {
      _markingRequested = true;
    });

    try {
      var clearedCount = 0;

      for (final sectionId in confirmedSectionIds) {
        final existingRows = await _supabase
            .from('show_sanctions')
            .select('id,sanction_number,request_status')
            .eq('show_id', showId)
            .eq('section_id', sectionId)
            .eq('breed_club_id', row.clubId)
            .inFilter('request_status', [
              'secretary_requested',
              'exhibitor_requested',
            ]);

        for (final raw in existingRows as List) {
          if (raw is! Map) continue;
          final existing = Map<String, dynamic>.from(raw);
          final sanctionNumber = (existing['sanction_number'] ?? '')
              .toString()
              .trim();

          if (sanctionNumber.isEmpty) {
            await _supabase
                .from('show_sanctions')
                .delete()
                .eq('id', existing['id'].toString());
          } else {
            await _supabase
                .from('show_sanctions')
                .update({
                  'request_status': 'received',
                  'requested_by_user_id': null,
                  'requested_by_role': null,
                  'requested_at': null,
                  'request_source': null,
                })
                .eq('id', existing['id'].toString());
          }

          clearedCount++;
        }
      }

      if (mounted) {
        _showSnack(
          clearedCount == 0
              ? 'No secretary or exhibitor request flags were found.'
              : 'Removed requested flag from $clearedCount section(s).',
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        _showSnack('Could not remove requested flag: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _markingRequested = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Sanction Directory',
      body: _buildBody(context),
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
                    'This directory is available to Show Secretary/Admin and Super Admin users while sanction links are being built and verified.',
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
        if (AppSession.isSupportMode) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.support_agent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Support Mode — You are managing sanction requests as an admin while viewing another user.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildHeaderCard(context),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.black87),
          cursorColor: Colors.black87,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.search, color: Colors.black87),
            labelText: 'Search breed, club, state, or sanctioning body',
            labelStyle: const TextStyle(color: Colors.black54),
            floatingLabelStyle: const TextStyle(color: Colors.black87),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _buildFilterChips(),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${rows.length} of ${_rows.length} links / clubs',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: .82),
              ),
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
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final report = row.linkId == null
                        ? null
                        : _openReportByLinkId[row.linkId];
                    return _SanctionDirectoryCard(
                      row: row,
                      pendingReport: report,
                      status: _statusByBreedClubId[row.clubId],
                      showRequestButton:
                          widget.showId != null &&
                          widget.showId!.trim().isNotEmpty,
                      isBusy:
                          _markingRequested ||
                          (row.linkId != null &&
                              _reviewingLinkIds.contains(row.linkId)),
                      onOpen: () => _openUrl(row.url),
                      onMarkRequested: () => _markRequested(row),
                      onClearRequested: () => _clearRequested(row),
                      onReportBroken: () => _reportBrokenLink(row),
                      onApproveReport: report == null
                          ? null
                          : () => _approveLinkReport(row, report),
                      onDismissReport: report == null
                          ? null
                          : () => _dismissLinkReport(row, report),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _SanctionDirectoryFilter.values.map((filter) {
        return ChoiceChip(
          label: Text(filter.label),
          selected: _selectedFilter == filter,
          onSelected: (_) {
            setState(() {
              _selectedFilter = filter;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Card(
      color: Colors.white.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_outlined, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sanction Directory',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Admin view for maintaining breed club sanction and sweepstakes links before this is opened more broadly to show secretaries.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: .88),
                    ),
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
    required this.pendingReport,
    required this.status,
    required this.showRequestButton,
    required this.isBusy,
    required this.onOpen,
    required this.onMarkRequested,
    required this.onClearRequested,
    required this.onReportBroken,
    required this.onApproveReport,
    required this.onDismissReport,
  });

  final _SanctionDirectoryRow row;
  final _LinkReport? pendingReport;
  final _SanctionDirectoryStatus? status;
  final bool showRequestButton;
  final bool isBusy;
  final VoidCallback onOpen;
  final VoidCallback onMarkRequested;
  final VoidCallback onClearRequested;
  final VoidCallback onReportBroken;
  final VoidCallback? onApproveReport;
  final VoidCallback? onDismissReport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    final hasLink = row.url.trim().isNotEmpty;
    final statusColor = status?.color;
    final hasPendingReport = pendingReport != null;
    final canClearRequest =
        showRequestButton &&
        (status == _SanctionDirectoryStatus.secretaryRequested ||
            status == _SanctionDirectoryStatus.exhibitorRequested);

    final cardColor = hasPendingReport
        ? Color.alphaBlend(
            Colors.red.withValues(alpha: .12),
            colorScheme.surface,
          )
        : statusColor == null
        ? colorScheme.surface
        : Color.alphaBlend(
            statusColor.withValues(alpha: .14),
            colorScheme.surface,
          );

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasPendingReport
              ? Colors.red.shade700
              : statusColor ?? Colors.transparent,
          width: hasPendingReport || statusColor != null ? 1.4 : 0,
        ),
      ),
      child: IconTheme(
        data: IconThemeData(color: onSurface),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: onSurface),
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
                            row.breedName.isEmpty
                                ? 'All Breeds / General Sanction'
                                : row.breedName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            row.clubName,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: onSurface),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StatusChip(label: row.clubTypeLabel),
                        if (status != null) ...[
                          const SizedBox(height: 6),
                          _DirectoryRequestStatusChip(status: status!),
                        ],
                        if (hasPendingReport) ...[
                          const SizedBox(height: 6),
                          const _PendingReviewChip(),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (row.sanctioningBody.isNotEmpty)
                      _InfoChip(
                        icon: Icons.account_balance,
                        label: row.sanctioningBody,
                      ),
                    if (row.stateCode.isNotEmpty)
                      _InfoChip(
                        icon: Icons.place_outlined,
                        label: row.stateCode,
                      ),
                    if (row.linkType.isNotEmpty)
                      _InfoChip(icon: Icons.link, label: row.linkType),
                    _InfoChip(
                      icon: row.lastVerifiedAt == null
                          ? Icons.report_problem_outlined
                          : Icons.fact_check_outlined,
                      label: row.linkCheckedLabel,
                    ),
                  ],
                ),
                if (row.linkLabel.isNotEmpty || row.linkNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  if (row.linkLabel.isNotEmpty)
                    Text(
                      row.linkLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (row.linkNotes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(row.linkNotes),
                  ],
                ],
                if (hasPendingReport) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Broken link reported — review required',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (pendingReport!.proposedUrl.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          const Text('Suggested replacement:'),
                          SelectableText(
                            pendingReport!.proposedUrl,
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                        ] else ...[
                          const SizedBox(height: 6),
                          const Text('No replacement link was supplied.'),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        disabledBackgroundColor: onSurface.withValues(
                          alpha: .12,
                        ),
                        disabledForegroundColor: onSurface.withValues(
                          alpha: .48,
                        ),
                      ),
                      onPressed: hasLink && !isBusy ? onOpen : null,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Link'),
                    ),
                    Tooltip(
                      message: !showRequestButton
                          ? 'Open this directory from a show sanctions dialog to mark or remove a request.'
                          : canClearRequest
                          ? 'Remove the requested flag for this show.'
                          : 'Mark this sanction as requested for this show.',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          disabledForegroundColor: onSurface.withValues(
                            alpha: .48,
                          ),
                          side: BorderSide(color: colorScheme.primary),
                        ),
                        onPressed: !showRequestButton || isBusy
                            ? null
                            : canClearRequest
                            ? onClearRequested
                            : onMarkRequested,
                        icon: Icon(
                          canClearRequest
                              ? Icons.remove_circle_outline
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          canClearRequest
                              ? 'Remove Requested'
                              : 'Mark Requested',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        disabledForegroundColor: onSurface.withValues(
                          alpha: .48,
                        ),
                        side: BorderSide(color: colorScheme.primary),
                      ),
                      onPressed:
                          row.linkId == null || isBusy || hasPendingReport
                          ? null
                          : onReportBroken,
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(
                        hasPendingReport
                            ? 'Report Pending Review'
                            : 'Report Broken Link',
                      ),
                    ),
                    if (hasPendingReport &&
                        pendingReport!.proposedUrl.trim().isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: isBusy ? null : onApproveReport,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Approve New Link'),
                      ),
                    if (hasPendingReport)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade800,
                          side: BorderSide(color: Colors.red.shade700),
                        ),
                        onPressed: isBusy ? null : onDismissReport,
                        icon: const Icon(Icons.close),
                        label: const Text('Dismiss Report'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryRequestStatusChip extends StatelessWidget {
  const _DirectoryRequestStatusChip({required this.status});

  final _SanctionDirectoryStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: .08)),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PendingReviewChip extends StatelessWidget {
  const _PendingReviewChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Text(
        'Broken link review',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.red.shade900,
          fontWeight: FontWeight.w800,
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
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          primary.withValues(alpha: .10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: primary.withValues(alpha: .18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: primary,
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
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
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

  bool get isNationalBreedClub {
    final type = _normalizeClubValue(clubType);
    final body = _normalizeClubValue(sanctioningBody);

    return (type.contains('national') && type.contains('club')) ||
        (body.contains('national') && body.contains('club'));
  }

  bool get isStateClub {
    final type = _normalizeClubValue(clubType);
    final body = _normalizeClubValue(sanctioningBody);

    return (type.contains('state') && type.contains('club')) ||
        (body.contains('state') && body.contains('club'));
  }

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
      url: _firstNonEmpty([link?['url'], club['website']]),
      linkNotes: _firstNonEmpty([link?['notes'], club['notes']]),
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

  String get linkCheckedLabel {
    if (lastVerifiedAt == null) return 'Link not checked/broken';
    final date = lastVerifiedAt!;
    return 'Link checked ${date.month}/${date.day}/${date.year}';
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _normalizeClubValue(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _LinkReport {
  const _LinkReport({
    required this.id,
    required this.sanctionLinkId,
    required this.proposedUrl,
  });

  final String id;
  final String sanctionLinkId;
  final String proposedUrl;

  factory _LinkReport.fromMap(Map<String, dynamic> map) {
    return _LinkReport(
      id: (map['id'] ?? '').toString(),
      sanctionLinkId: (map['sanction_link_id'] ?? '').toString(),
      proposedUrl: (map['proposed_url'] ?? '').toString(),
    );
  }
}

class _BrokenLinkSubmission {
  const _BrokenLinkSubmission({required this.proposedUrl});

  final String? proposedUrl;
}

enum _SanctionDirectoryFilter {
  all,
  nationalBreedClubs,
  stateClubs,
  missingLink,
  linkChecked,
  linkNotCheckedOrBroken;

  String get label {
    switch (this) {
      case _SanctionDirectoryFilter.all:
        return 'All';
      case _SanctionDirectoryFilter.nationalBreedClubs:
        return 'National Breed Clubs';
      case _SanctionDirectoryFilter.stateClubs:
        return 'State Clubs';
      case _SanctionDirectoryFilter.missingLink:
        return 'Missing Link';
      case _SanctionDirectoryFilter.linkChecked:
        return 'Link checked';
      case _SanctionDirectoryFilter.linkNotCheckedOrBroken:
        return 'Link not checked/broken';
    }
  }
}

class _ShowSectionOption {
  const _ShowSectionOption({
    required this.id,
    required this.kind,
    required this.letter,
    required this.sortOrder,
  });

  final String id;
  final String kind;
  final String letter;
  final int sortOrder;

  factory _ShowSectionOption.fromMap(Map<String, dynamic> map) {
    return _ShowSectionOption(
      id: (map['id'] ?? '').toString(),
      kind: (map['kind'] ?? '').toString(),
      letter: (map['letter'] ?? '').toString(),
      sortOrder: int.tryParse((map['sort_order'] ?? '0').toString()) ?? 0,
    );
  }

  int get kindRank {
    final normalized = kind.trim().toLowerCase();
    if (normalized == 'open') return 0;
    if (normalized == 'youth') return 1;
    return 2;
  }

  String get label {
    final kindLabel = kind.trim().isEmpty
        ? 'Section'
        : kind.trim()[0].toUpperCase() + kind.trim().substring(1).toLowerCase();
    final letterLabel = letter.trim();
    return letterLabel.isEmpty ? kindLabel : '$kindLabel $letterLabel';
  }
}

enum _SanctionDirectoryStatus {
  secretaryRequested,
  exhibitorRequested,
  received,
  problem;

  static _SanctionDirectoryStatus fromSanctionRow({
    required String requestStatus,
    required String sanctionNumber,
  }) {
    if (sanctionNumber.trim().isNotEmpty) {
      return _SanctionDirectoryStatus.received;
    }

    switch (requestStatus.trim().toLowerCase()) {
      case 'problem':
        return _SanctionDirectoryStatus.problem;
      case 'exhibitor_requested':
        return _SanctionDirectoryStatus.exhibitorRequested;
      case 'secretary_requested':
      default:
        return _SanctionDirectoryStatus.secretaryRequested;
    }
  }

  int get priority {
    switch (this) {
      case _SanctionDirectoryStatus.problem:
        return 4;
      case _SanctionDirectoryStatus.received:
        return 3;
      case _SanctionDirectoryStatus.exhibitorRequested:
        return 2;
      case _SanctionDirectoryStatus.secretaryRequested:
        return 1;
    }
  }

  Color get color {
    switch (this) {
      case _SanctionDirectoryStatus.secretaryRequested:
        return Colors.orange.shade100;
      case _SanctionDirectoryStatus.exhibitorRequested:
        return Colors.blue.shade100;
      case _SanctionDirectoryStatus.received:
        return Colors.green.shade100;
      case _SanctionDirectoryStatus.problem:
        return Colors.red.shade100;
    }
  }

  String get label {
    switch (this) {
      case _SanctionDirectoryStatus.secretaryRequested:
        return 'Secretary requested';
      case _SanctionDirectoryStatus.exhibitorRequested:
        return 'Exhibitor requested';
      case _SanctionDirectoryStatus.received:
        return 'Received';
      case _SanctionDirectoryStatus.problem:
        return 'Problem';
    }
  }
}
