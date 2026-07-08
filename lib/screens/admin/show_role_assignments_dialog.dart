// lib/screens/admin/show_role_assignments_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowRoleAssignmentsDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ShowRoleAssignmentsDialog(showId: showId, showName: showName),
    );
  }
}

class _ShowRoleAssignmentsDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowRoleAssignmentsDialog({
    required this.showId,
    required this.showName,
  });

  @override
  State<_ShowRoleAssignmentsDialog> createState() =>
      _ShowRoleAssignmentsDialogState();
}

class _UserSearchResult {
  final String id;
  final String email;
  final String displayName;
  final String? exhibitorId;

  const _UserSearchResult({
    required this.id,
    required this.email,
    required this.displayName,
    this.exhibitorId,
  });

  String get selectionKey =>
      '${id}_${exhibitorId ?? displayName.trim().toLowerCase()}';

  String get label {
    final name = displayName.trim();
    final mail = email.trim();
    if (name.isNotEmpty && mail.isNotEmpty) return '$name • $mail';
    if (name.isNotEmpty) return name;
    if (mail.isNotEmpty) return mail;
    return id;
  }
}

class _RoleAssignmentRow {
  final String id;
  final String userId;
  final String role;
  final String email;
  final String displayName;

  const _RoleAssignmentRow({
    required this.id,
    required this.userId,
    required this.role,
    required this.email,
    required this.displayName,
  });

  String get personLabel {
    final name = displayName.trim();
    final mail = email.trim();
    if (name.isNotEmpty && mail.isNotEmpty) return '$name • $mail';
    if (name.isNotEmpty) return name;
    if (mail.isNotEmpty) return mail;
    return userId;
  }
}

class _ShowRoleAssignmentsDialogState
    extends State<_ShowRoleAssignmentsDialog> {
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  String? _msg;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _selectedRole = 'superintendent';
  _UserSearchResult? _selectedUser;

  List<_RoleAssignmentRow> _assignments = [];
  List<_UserSearchResult> _searchResults = [];

  static const _allowedRoles = <String>[
    'admin',
    'superintendent',
    'reporting_clerk',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'superintendent':
        return 'Show Superintendent';
      case 'reporting_clerk':
        return 'Reporting Clerk';
      case 'admin':
      case 'show_admin':
        return 'Show Secretary';
      case 'super_admin':
        return 'Super Admin';
      default:
        return role;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rows = await supabase
          .from('role_assignments')
          .select('id,user_id,role')
          .eq('show_id', widget.showId)
          .inFilter('role', _allowedRoles)
          .order('role')
          .order('created_at');

      final rawRows = List<Map<String, dynamic>>.from(
        (rows as List).map((row) => Map<String, dynamic>.from(row as Map)),
      );

      final userIds = rawRows
          .map((row) => row['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usersById = await _loadUsersByIds(userIds);

      final assignments = rawRows.map((row) {
        final userId = row['user_id']?.toString() ?? '';
        final user = usersById[userId];
        return _RoleAssignmentRow(
          id: row['id']?.toString() ?? '',
          userId: userId,
          role: row['role']?.toString() ?? '',
          email: user?.email ?? '',
          displayName: user?.displayName ?? '',
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _assignments = assignments;
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

  Future<Map<String, _UserSearchResult>> _loadUsersByIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    final response = await supabase.rpc(
      'search_show_staff_users',
      params: {'p_query': null, 'p_user_ids': userIds},
    );

    final users = <String, _UserSearchResult>{};
    for (final raw in response as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final user = _userFromRow(row);
      if (user.id.isNotEmpty) {
        users[user.id] = user;
      }
    }

    return users;
  }

  _UserSearchResult _userFromRow(Map<String, dynamic> row) {
    final id = (row['id'] ?? row['user_id'])?.toString() ?? '';
    final email = row['email']?.toString() ?? '';
    final firstName = row['first_name']?.toString().trim() ?? '';
    final lastName = row['last_name']?.toString().trim() ?? '';
    final combinedName = [
      firstName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ').trim();

    final displayName =
        (row['display_name'] ??
                row['full_name'] ??
                row['name'] ??
                (combinedName.isNotEmpty ? combinedName : null) ??
                '')
            .toString();

    return _UserSearchResult(
      id: id,
      email: email,
      displayName: displayName,
      exhibitorId: row['exhibitor_id']?.toString(),
    );
  }

  void _queueUserSearch(String value) {
    _selectedUser = null;
    _searchDebounce?.cancel();

    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _msg = null;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _searchUsers(query);
    });
  }

  Future<void> _searchUsers(String value) async {
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _msg = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _msg = null;
    });

    try {
      final response = await supabase.rpc(
        'search_show_staff_users',
        params: {'p_query': query, 'p_user_ids': null},
      );

      final resultsByKey = <String, _UserSearchResult>{};
      for (final raw in response as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final user = _userFromRow(row);
        if (user.id.isNotEmpty) {
          resultsByKey[user.selectionKey] = user;
        }
      }

      if (!mounted) return;
      setState(() {
        _searchResults = resultsByKey.values.toList()
          ..sort((a, b) {
            final aLabel = a.label.toLowerCase();
            final bLabel = b.label.toLowerCase();
            final lowerQuery = query.toLowerCase();

            final aStarts = aLabel.startsWith(lowerQuery);
            final bStarts = bLabel.startsWith(lowerQuery);
            if (aStarts != bStarts) return aStarts ? -1 : 1;

            final aContains = aLabel.contains(lowerQuery);
            final bContains = bLabel.contains(lowerQuery);
            if (aContains != bContains) return aContains ? -1 : 1;

            return aLabel.compareTo(bLabel);
          });
        _searching = false;
        if (_searchResults.isEmpty) {
          _msg = 'No matching users found.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _msg = 'User search failed: $e';
      });
    }
  }

  Future<void> _addAssignment() async {
    final user = _selectedUser;
    if (user == null) {
      setState(() => _msg = 'Search for and select a user first.');
      return;
    }

    if (!_allowedRoles.contains(_selectedRole)) {
      setState(
        () => _msg =
            'Only Show Secretary/Admin, Superintendent, and Reporting Clerk can be assigned here.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final existing = await supabase
          .from('role_assignments')
          .select('id,role')
          .eq('show_id', widget.showId)
          .eq('user_id', user.id)
          .maybeSingle();

      final wasUpdate = existing != null;

      if (existing != null) {
        final existingRole = existing['role']?.toString() ?? '';
        if (!_allowedRoles.contains(existingRole)) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _msg =
                '${user.label} already has ${_roleLabel(existingRole)} access. '
                'That role cannot be changed from this dialog.';
          });
          return;
        }
      }

      final assignmentId =
          (await supabase.rpc(
            'assign_show_staff_role',
            params: {
              'p_show_id': widget.showId,
              'p_user_id': user.id,
              'p_role': _selectedRole,
            },
          ))?.toString() ??
          '';

      final updatedAssignment = _RoleAssignmentRow(
        id: assignmentId,
        userId: user.id,
        role: _selectedRole,
        email: user.email,
        displayName: user.displayName,
      );

      final nextAssignments = [..._assignments];
      final existingIndex = nextAssignments.indexWhere(
        (assignment) => assignment.userId == user.id,
      );

      if (existingIndex >= 0) {
        nextAssignments[existingIndex] = updatedAssignment;
      } else {
        nextAssignments.add(updatedAssignment);
      }

      nextAssignments.sort((a, b) {
        final roleCompare = _roleLabel(a.role).compareTo(_roleLabel(b.role));
        if (roleCompare != 0) return roleCompare;
        return a.personLabel.toLowerCase().compareTo(
          b.personLabel.toLowerCase(),
        );
      });

      if (!mounted) return;
      setState(() {
        _assignments = nextAssignments;
        _searchController.clear();
        _selectedUser = null;
        _searchResults = [];
        _saving = false;
        _msg = wasUpdate
            ? 'Role assignment updated.'
            : 'Role assignment added.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  Future<void> _removeAssignment(_RoleAssignmentRow assignment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove role assignment?'),
        content: Text(
          'Remove ${assignment.personLabel} as ${_roleLabel(assignment.role)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.rpc(
        'remove_show_staff_role',
        params: {'p_assignment_id': assignment.id},
      );

      if (!mounted) return;
      setState(() {
        _assignments = _assignments
            .where((row) => row.id != assignment.id)
            .toList();
        _saving = false;
        _msg = 'Role assignment removed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Remove failed: $e';
      });
    }
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return AppTheme.surfaceTextScope(
      context,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
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
        child: Builder(
          builder: (context) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                ...children,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAssignmentTile(_RoleAssignmentRow assignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: .08)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.assignment_ind),
        title: Text(assignment.personLabel),
        subtitle: Text(_roleLabel(assignment.role)),
        trailing: IconButton(
          tooltip: 'Remove',
          onPressed: _saving ? null : () => _removeAssignment(assignment),
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(_UserSearchResult user) {
    final selected = _selectedUser?.selectionKey == user.selectionKey;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.gold.withValues(alpha: .12) : Colors.white,
        border: Border.all(
          color: selected
              ? AppColors.gold
              : Colors.black.withValues(alpha: .08),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(selected ? Icons.check_circle : Icons.person_search),
        title: Text(
          user.displayName.trim().isEmpty ? user.email : user.displayName,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user.email.trim().isNotEmpty) Text(user.email),
            if (user.exhibitorId != null)
              const Text(
                'Exhibitor on this account',
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
        onTap: _saving
            ? null
            : () {
                _searchDebounce?.cancel();
                setState(() {
                  _selectedUser = user;
                  _searchController.text = user.label;
                  _searchResults = [];
                  _msg = null;
                });
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final successMessage =
        _msg != null &&
        (_msg!.contains('added') ||
            _msg!.contains('updated') ||
            _msg!.contains('removed'));

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width < 700 ? media.width - 16 : media.width * 0.76,
          maxHeight: media.height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.page,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/RingMaster_One_Show_Transparent.png',
                      height: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Role Assignments — ${widget.showName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: AppTheme.gradientTextScope(
                    context,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                            child: Column(
                              children: [
                                if (_msg != null)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: successMessage
                                          ? Colors.green.withValues(alpha: .08)
                                          : Colors.red.withValues(alpha: .08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: successMessage
                                            ? Colors.green.withValues(
                                                alpha: .25,
                                              )
                                            : Colors.red.withValues(alpha: .25),
                                      ),
                                    ),
                                    child: Text(
                                      _msg!,
                                      style: TextStyle(
                                        color: successMessage
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        _buildSectionCard(
                                          context: context,
                                          title: 'Current Staff Roles',
                                          children: [
                                            if (_assignments.isEmpty)
                                              const Text(
                                                'No staff roles have been assigned yet.',
                                              )
                                            else
                                              ..._assignments.map(
                                                _buildAssignmentTile,
                                              ),
                                          ],
                                        ),
                                        _buildSectionCard(
                                          context: context,
                                          title: 'Add or Update Staff Role',
                                          children: [
                                            const Text(
                                              'Search by any exhibitor name or account email. Every exhibitor on an account can be selected, including non-primary exhibitors. Access is still assigned to the login account connected to that exhibitor.',
                                            ),
                                            const SizedBox(height: 12),
                                            DropdownButtonFormField<String>(
                                              initialValue: _selectedRole,
                                              decoration: const InputDecoration(
                                                labelText: 'Role',
                                                border: OutlineInputBorder(),
                                              ),
                                              items: _allowedRoles
                                                  .map(
                                                    (role) => DropdownMenuItem(
                                                      value: role,
                                                      child: Text(
                                                        _roleLabel(role),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: _saving
                                                  ? null
                                                  : (value) => setState(
                                                      () => _selectedRole =
                                                          value ??
                                                          'superintendent',
                                                    ),
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: _searchController,
                                              enabled: !_saving,
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Search current users by name or email',
                                                border:
                                                    const OutlineInputBorder(),
                                                suffixIcon: _searching
                                                    ? const Padding(
                                                        padding: EdgeInsets.all(
                                                          12,
                                                        ),
                                                        child: SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        ),
                                                      )
                                                    : IconButton(
                                                        tooltip: 'Search',
                                                        onPressed: _saving
                                                            ? null
                                                            : () => _searchUsers(
                                                                _searchController
                                                                    .text,
                                                              ),
                                                        icon: const Icon(
                                                          Icons.search,
                                                        ),
                                                      ),
                                              ),
                                              onChanged: _saving
                                                  ? null
                                                  : _queueUserSearch,
                                              onSubmitted: _saving
                                                  ? null
                                                  : _searchUsers,
                                            ),
                                            if (_searchResults.isNotEmpty)
                                              ..._searchResults.map(
                                                _buildSearchResultTile,
                                              ),
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child: FilledButton.icon(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primaryButton,
                                                  foregroundColor: AppColors
                                                      .primaryButtonText,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 16,
                                                      ),
                                                ),
                                                onPressed: _saving
                                                    ? null
                                                    : _addAssignment,
                                                icon: const Icon(
                                                  Icons.person_add,
                                                ),
                                                label: Text(
                                                  _saving
                                                      ? 'Saving…'
                                                      : 'Add / Update Role',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _saving
                                            ? null
                                            : () => Navigator.pop(context),
                                        child: const Text('Close'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
