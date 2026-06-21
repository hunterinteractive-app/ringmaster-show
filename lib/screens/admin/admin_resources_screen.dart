// lib/screens/admin/admin_resources_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/app_session.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

final supabase = Supabase.instance.client;

class AdminResourcesScreen extends StatefulWidget {
  const AdminResourcesScreen({super.key});

  @override
  State<AdminResourcesScreen> createState() => _AdminResourcesScreenState();
}

class _AdminResourcesScreenState extends State<AdminResourcesScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  static const List<Map<String, dynamic>> _scribeGuides = [
    {
      'id': 'scribe-exhibitor-account-first-show',
      'title': 'Creating Your RingMaster Show Account and Entering Your First Show',
      'description': 'Guide for exhibitors creating an account, adding animals, entering a show, and completing checkout.',
      'category': 'Exhibitor Guide',
      'file_url': 'https://scribehow.com/o/vr7q0-IrTfO8a62Y0VO4Wg/viewer/Creating_Your_RingMaster_Show_Account_and_Entering_Your_First_Show__CnLLYjeMQBuMcB7lxzsI8Q',
      'resource_type': 'scribe',
      'sort_order': 10,
    },
    {
      'id': 'scribe-create-new-show',
      'title': 'How to Create a New Show in RingMaster Show',
      'description': 'Guide for show secretaries creating the basic show record before completing setup.',
      'category': 'Show Secretary Setup',
      'file_url': 'https://scribehow.com/o/vr7q0-IrTfO8a62Y0VO4Wg/viewer/How_to_Create_a_New_Show_in_RingMaster_Show__fr5D5Jg_TfOftdRZg_TojQ',
      'resource_type': 'scribe',
      'sort_order': 20,
    },
    {
      'id': 'scribe-prepare-show-entries',
      'title': 'Preparing a Show for Entries: Settings, Fees, and Payments',
      'description': 'Guide for reviewing show settings, fees, staff setup, judges, and connecting Stripe payments.',
      'category': 'Show Secretary Setup',
      'file_url': 'https://scribehow.com/o/vr7q0-IrTfO8a62Y0VO4Wg/viewer/Preparing_a_Show_for_Entries_Settings_Fees_and_Payments__aivMCQC2Sd-C9ZwNf6hZ5Q',
      'resource_type': 'scribe',
      'sort_order': 30,
    },
    {
      'id': 'scribe-review-entries-print-materials',
      'title': 'Reviewing Entries and Preparing Show Materials',
      'description': 'Pre-show guide for reviewing entries, adding manual entries, breed counts, coop numbers, and generating print materials.',
      'category': 'Pre-Show Guide',
      'file_url': 'https://scribehow.com/o/vr7q0-IrTfO8a62Y0VO4Wg/viewer/Reviewing_Entries_and_Preparing_Show_Materials__2mobhQgrSZySm1eqrNKq2g',
      'resource_type': 'scribe',
      'sort_order': 50,
    },
    {
      'id': 'scribe-closeout-after-show',
      'title': 'Closeout / After Show Guide',
      'description': 'After-show guide for entering final results, closeout checks, generating reports, sending reports, and locking the show.',
      'category': 'After Show Guide',
      'file_url': 'https://scribehow.com/o/vr7q0-IrTfO8a62Y0VO4Wg/viewer/Closeout__After_Show_Guide__8SEf6HRcSvi70sUQdAhfNg',
      'resource_type': 'scribe',
      'sort_order': 60,
    },
    {
      'id': 'scribe-custom-varieties',
      'title': 'How to Add Custom Varieties to Your Show',
      'description': 'Guide for show secretaries adding custom varieties that are not already available in the default list.',
      'category': 'Show Secretary Setup',
      'file_url': 'https://scribehow.com/o/vr7q0-IrTfO8a62Y0VO4Wg/viewer/How_to_Add_Custom_Varieties_to_Your_Show__kZ5VXAAlRvStkL533gyJoA',
      'resource_type': 'scribe',
      'sort_order': 40,
    },
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadResources();
  }

  Future<List<Map<String, dynamic>>> _loadResources() async {
    final uploadedResources = <Map<String, dynamic>>[];

    try {
      final res = await supabase
          .from('secretary_resources')
          .select(
            'id,title,description,category,storage_path,file_name,mime_type,sort_order',
          )
          .eq('is_active', true)
          .eq('audience', 'secretary')
          .isFilter('club_id', null)
          .isFilter('show_id', null)
          .order('sort_order');

      final rows = (res as List).cast<Map<String, dynamic>>();

      uploadedResources.addAll(rows.map((row) {
        final storagePath = (row['storage_path'] ?? '').toString();

        final publicUrl = storagePath.isEmpty
            ? ''
            : supabase.storage
                .from('secretary-resources')
                .getPublicUrl(storagePath);

        return {
          ...row,
          'file_url': publicUrl,
          'resource_type': 'file',
        };
      }));
    } catch (error) {
      debugPrint('Unable to load uploaded secretary resources: $error');
    }

    final allResources = <Map<String, dynamic>>[
      ..._scribeGuides,
      ...uploadedResources,
    ];

    allResources.sort((a, b) {
      final aSort = int.tryParse((a['sort_order'] ?? '').toString()) ?? 9999;
      final bSort = int.tryParse((b['sort_order'] ?? '').toString()) ?? 9999;
      final sortCompare = aSort.compareTo(bSort);
      if (sortCompare != 0) return sortCompare;
      return (a['title'] ?? '').toString().compareTo(
            (b['title'] ?? '').toString(),
          );
    });

    return allResources;
  }

  Future<void> _openResource(String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No resource link available')),
      );
      return;
    }

    final uri = Uri.parse(url);

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!mounted) return;

    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open resource link')),
      );
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadResources();
    });
  }

  void _previewImage(String imageUrl) {
    if (imageUrl.trim().isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: InteractiveViewer(
          child: Image.network(imageUrl),
        ),
      ),
    );
  }

  void _showResourceDialog(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final desc = (item['description'] ?? '').toString();
    final category = (item['category'] ?? '').toString();
    final url = (item['file_url'] ?? '').toString();
    final resourceType = (item['resource_type'] ?? 'file').toString();
    final isScribe = resourceType == 'scribe';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RMBadge(
                      text: category,
                      icon: isScribe
                          ? Icons.menu_book_outlined
                          : Icons.folder_open,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    RMBadge(
                      text: isScribe ? 'Guide' : 'Resource File',
                      icon: isScribe
                          ? Icons.open_in_new
                          : Icons.insert_drive_file_outlined,
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    desc,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.muted),
                  ),
                ],
                if (!isScribe && url.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Container(
                      color: const Color(0xFFF2F2F2),
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Image.network(
                        url,
                        height: 260,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const SizedBox(
                          height: 180,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (!isScribe && url.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _previewImage(url);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
          FilledButton.icon(
            onPressed: url.isEmpty
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _openResource(url);
                  },
            icon: Icon(isScribe ? Icons.open_in_new : Icons.download),
            label: Text(isScribe ? 'Open Guide' : 'Download'),
          ),
        ],
      ),
    );
  }

  void _showResourceCollectionDialog({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Map<String, dynamic>> items,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: AppColors.navy),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: MediaQuery.of(context).size.height * .62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final itemTitle = (item['title'] ?? '').toString();
                    final itemDesc = (item['description'] ?? '').toString();
                    final itemCategory = (item['category'] ?? '').toString();
                    final url = (item['file_url'] ?? '').toString();
                    final resourceType =
                        (item['resource_type'] ?? 'file').toString();
                    final isScribe = resourceType == 'scribe';

                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FC),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: const Color(0xFFE5E9F2)),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 520;

                          final leadingIcon = Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.navy.withOpacity(.08),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              isScribe
                                  ? Icons.menu_book_outlined
                                  : Icons.image_outlined,
                              color: AppColors.navy,
                            ),
                          );

                          final details = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (itemDesc.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  itemDesc,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.muted),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              RMBadge(
                                text: itemCategory,
                                icon: isScribe
                                    ? Icons.menu_book_outlined
                                    : Icons.folder_open,
                              ),
                            ],
                          );

                          final actions = Wrap(
                            spacing: AppSpacing.xs,
                            children: [
                              if (!isScribe && url.isNotEmpty)
                                IconButton(
                                  tooltip: 'Preview',
                                  icon: const Icon(Icons.visibility_outlined),
                                  onPressed: () => _previewImage(url),
                                ),
                              IconButton(
                                tooltip: isScribe ? 'Open Guide' : 'Download',
                                icon: Icon(
                                  isScribe
                                      ? Icons.open_in_new
                                      : Icons.download,
                                ),
                                onPressed: url.isEmpty
                                    ? null
                                    : () => _openResource(url),
                              ),
                            ],
                          );

                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    leadingIcon,
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(child: details),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              leadingIcon,
                              const SizedBox(width: AppSpacing.md),
                              Expanded(child: details),
                              const SizedBox(width: AppSpacing.sm),
                              actions,
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _resourceCollectionCard({
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required List<Map<String, dynamic>> items,
  }) {
    return RMCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _showResourceCollectionDialog(
          title: title,
          subtitle: subtitle,
          icon: icon,
          items: items,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.navy.withOpacity(.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: AppColors.navy),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      RMBadge(text: badge, icon: icon),
                      RMBadge(
                        text: '${items.length} item${items.length == 1 ? '' : 's'}',
                        icon: Icons.list_alt_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _showResourceCollectionDialog(
                title: title,
                subtitle: subtitle,
                icon: icon,
                items: items,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Secretary Resources',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final items = snap.data ?? [];
          final guideItems = items
              .where((item) => (item['resource_type'] ?? '').toString() == 'scribe')
              .toList();
          final fileItems = items
              .where((item) => (item['resource_type'] ?? '').toString() != 'scribe')
              .toList();
          final logoItems = fileItems.where((item) {
            final category = (item['category'] ?? '').toString().toLowerCase();
            final title = (item['title'] ?? '').toString().toLowerCase();
            return category.contains('logo') || title.contains('logo');
          }).toList();
          final referenceFileItems = fileItems.where((item) {
            final category = (item['category'] ?? '').toString().toLowerCase();
            final title = (item['title'] ?? '').toString().toLowerCase();
            return !category.contains('logo') && !title.contains('logo');
          }).toList();

          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  if (AppSession.isSupportMode) ...[
                    _SupportModeNotice(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const Expanded(
                    child: Center(
                      child: RMEmptyState(
                        title: 'No resources available',
                        subtitle: 'There are no secretary resources available yet.',
                        icon: Icons.perm_media_outlined,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                if (AppSession.isSupportMode) ...[
                  _SupportModeNotice(),
                  const SizedBox(height: AppSpacing.md),
                ],
                Expanded(
                  child: ListView(
                    children: [
                      if (guideItems.isNotEmpty) ...[
                        _resourceCollectionCard(
                          title: 'RingMaster Show Help Guides',
                          subtitle:
                              'Step-by-step Scribe guides for exhibitors, show secretaries, pre-show work, and after-show closeout.',
                          badge: 'Guides',
                          icon: Icons.menu_book_outlined,
                          items: guideItems,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (referenceFileItems.isNotEmpty) ...[
                        _resourceCollectionCard(
                          title: 'RingMaster Reference Graphics',
                          subtitle:
                              'Open, preview, or download quick-reference graphics such as role comparison guides and setup checklists.',
                          badge: 'Reference Graphics',
                          icon: Icons.fact_check_outlined,
                          items: referenceFileItems,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (logoItems.isNotEmpty)
                        _resourceCollectionCard(
                          title: 'RingMaster Logos & Brand Files',
                          subtitle:
                              'Open, preview, or download RingMaster logos and brand files.',
                          badge: 'Logos / Files',
                          icon: Icons.image_outlined,
                          items: logoItems,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SupportModeNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
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
              'Support Mode — Viewing secretary resources as an admin while viewing another user.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}