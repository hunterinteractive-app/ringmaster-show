import 'assistant_answers_screen.dart';
import 'assistant_conversations_screen.dart';
// lib/screens/superadmin/super_admin_home_screen.dart

import 'package:flutter/material.dart';
import '../../services/support_impersonation_session.dart';
export '../../services/support_impersonation_session.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/screens/super_admin/help_reports_screen.dart';
import 'package:ringmaster_show/screens/super_admin/club_payment_provider_migration_reviews_screen.dart';

import '../show_list_screen.dart';
import 'breed_catalog_screen.dart';
import 'assistant_usage_screen.dart';
import 'convention_sale_admin_screen.dart';

SupabaseClient get supabase => ringMasterClient;

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
      MaterialPageRoute(builder: (_) => const BreedCatalogScreen()),
    );
  }

  Future<void> _openHelpReports() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelpReportsScreen()),
    );
  }

  Future<void> _openPaymentProviderMigrationReviews() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ClubPaymentProviderMigrationReviewsScreen(),
      ),
    );
  }

  Future<void> _openImpersonateUser() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SupportImpersonationScreen()),
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMsg)));
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
                color: AppColors.headerForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Text(
              'Manage shared catalogs, support tools, and system-wide imports.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.headerForeground.withValues(alpha: .82),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: success ? AppColors.successBg : AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: success ? AppColors.success : AppColors.danger,
                  ),
                ),
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: success ? AppColors.success : AppColors.danger,
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
                  icon: Icons.local_offer_outlined,
                  title: 'Convention Token Sale',
                  subtitle:
                      'Set the venue, map radius, sale hours, bonus tokens, and extra unlimited months.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConventionSaleAdminScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                  icon: Icons.forum_outlined,
                  title: 'Chester Conversations',
                  subtitle:
                      'Read saved chats, prepared answers, and FAQ activity.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AssistantConversationsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SuperadminToolCard(
                  icon: Icons.library_books_outlined,
                  title: 'Chester Reviewed Answers',
                  subtitle:
                      'Review FAQ drafts, publish reusable answers, and manage matching questions.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AssistantAnswersScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SuperadminToolCard(
                  icon: Icons.smart_toy_outlined,
                  title: 'AI Assistant Usage',
                  subtitle:
                      'Review costs, set the monthly allowance, and pause AI answers.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AssistantUsageScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SuperadminToolCard(
                  icon: Icons.help_outline,
                  title: 'Help Reports',
                  subtitle:
                      'Review issue reports, screenshots, device details, and mark reports resolved.',
                  onTap: _openHelpReports,
                ),
                const SizedBox(height: 12),
                _SuperadminToolCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Club Payment Provider Reviews',
                  subtitle:
                      'Review legacy Stripe, Square, and PayPal connections that could not be safely migrated to a hosting club.',
                  onTap: _openPaymentProviderMigrationReviews,
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
    return AppTheme.surfaceTextScope(
      context,
      child: Card(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.headerForeground, width: 1.4),
        ),
        child: Builder(
          builder: (context) => ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.header.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  leadingOverride ??
                  Icon(icon, color: AppColors.secondaryButton),
            ),
            title: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.headerForeground,
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class SupportImpersonationScreen extends StatefulWidget {
  const SupportImpersonationScreen({super.key});

  @override
  State<SupportImpersonationScreen> createState() =>
      SupportImpersonationScreenState();
}

class SupportImpersonationScreenState
    extends State<SupportImpersonationScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;
  String? _error;
  List<SupportImpersonatedUser> _users = <SupportImpersonatedUser>[];
  bool _showingInitialUsers = true;

  @override
  void initState() {
    super.initState();
    _loadInitialUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<SupportImpersonatedUser>> _findUsers(
    String query,
    int limit,
  ) async {
    final rows = await supabase.rpc(
      'search_support_users',
      params: {'p_query': query, 'p_limit': limit},
    );
    return (rows as List)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return SupportImpersonatedUser(
            userId: (row['user_id'] ?? '').toString(),
            email: (row['email'] ?? '').toString(),
            displayName: (row['display_name'] ?? '').toString(),
            exhibitorName: (row['exhibitor_name'] ?? '').toString(),
          );
        })
        .where((user) => user.userId.isNotEmpty)
        .toList();
  }

  Future<void> _loadInitialUsers() async {
    setState(() {
      _loading = true;
      _error = null;
      _showingInitialUsers = true;
    });

    try {
      final users = await _findUsers('', 100);

      if (!mounted) return;

      setState(() {
        _users = users;
        _loading = false;
        _error = users.isEmpty ? 'No users found.' : null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'User list failed: $e';
      });
    }
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      await _loadInitialUsers();
      return;
    }

    if (query.length < 2) {
      setState(() {
        _error =
            'Enter at least 2 characters to search, or clear the search to show users.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _showingInitialUsers = false;
    });

    try {
      final users = await _findUsers(query, 200);

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

  bool _startingSupport = false;

  Future<void> _startImpersonation(SupportImpersonatedUser user) async {
    if (_startingSupport) return;
    setState(() => _startingSupport = true);
    try {
      await SupportImpersonationSession.begin(user);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start Support Mode: $e');
      return;
    } finally {
      if (mounted) setState(() => _startingSupport = false);
    }
    if (!SupportImpersonationSession.isActive) {
      return; // Web is opening the new workspace.
    }

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
                color: AppColors.headerForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Search login or exhibitor emails, profile names, or linked exhibitor names. Partial names and comma-separated names are supported.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.headerForeground.withValues(alpha: .82),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: AppTheme.surfaceTextScope(
                    context,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: AppColors.text),
                      decoration: const InputDecoration(
                        labelText: 'Search users',
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        hintText: 'Login email, exhibitor email, or name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search, color: AppColors.muted),
                        labelStyle: TextStyle(color: AppColors.muted),
                        hintStyle: TextStyle(color: AppColors.muted),
                        filled: true,
                        fillColor: AppColors.surface,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchUsers(),
                      onChanged: (value) {
                        if (value.trim().isEmpty && !_showingInitialUsers) {
                          _loadInitialUsers();
                        }
                      },
                    ),
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
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          _searchController.clear();
                          _loadInitialUsers();
                        },
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
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
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading && _users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          _showingInitialUsers
                              ? 'Showing up to 100 users'
                              : 'Search results',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.headerForeground.withValues(
                                  alpha: .82,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _users.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final user = _users[index];

                            return AppTheme.surfaceTextScope(
                              context,
                              child: Card(
                                elevation: 0,
                                color: AppColors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  side: const BorderSide(
                                    color: AppColors.headerForeground,
                                    width: 1.4,
                                  ),
                                ),
                                child: Builder(
                                  builder: (context) => ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.header
                                          .withValues(alpha: .18),
                                      foregroundColor:
                                          AppColors.secondaryButton,
                                      child: Text(
                                        user.label.isEmpty
                                            ? '?'
                                            : user.label.characters.first
                                                  .toUpperCase(),
                                      ),
                                    ),
                                    title: Text(
                                      user.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: AppColors.text,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        [
                                              if (user.email.isNotEmpty)
                                                user.email,
                                              if (user.displayName
                                                      .trim()
                                                      .isNotEmpty &&
                                                  user.displayName.trim() !=
                                                      user.label)
                                                'Profile: ${user.displayName.trim()}',
                                            ].join(' • ').isEmpty
                                            ? user.userId
                                            : [
                                                if (user.email.isNotEmpty)
                                                  user.email,
                                                if (user.displayName
                                                        .trim()
                                                        .isNotEmpty &&
                                                    user.displayName.trim() !=
                                                        user.label)
                                                  'Profile: ${user.displayName.trim()}',
                                              ].join(' • '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(color: AppColors.muted),
                                      ),
                                    ),
                                    trailing: FilledButton.icon(
                                      onPressed: () =>
                                          _startImpersonation(user),
                                      icon: const Icon(Icons.visibility),
                                      label: const Text('View As'),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
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
