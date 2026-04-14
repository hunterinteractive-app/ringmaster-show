// lib/screens/admin/admin_resources_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() {
    super.initState();
    _future = _loadResources();
  }

  Future<List<Map<String, dynamic>>> _loadResources() async {
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

    return rows.map((row) {
      final storagePath = (row['storage_path'] ?? '').toString();

      final publicUrl = supabase.storage
          .from('secretary-resources')
          .getPublicUrl(storagePath);

      return {
        ...row,
        'file_url': publicUrl,
      };
    }).toList();
  }

  Future<void> _downloadFile(String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file URL available')),
      );
      return;
    }

    final uri = Uri.parse(url);

    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open download link')),
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
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(imageUrl),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secretary Resources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
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

          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: RMEmptyState(
                title: 'No resources available',
                subtitle: 'There are no secretary resources available yet.',
                icon: Icons.perm_media_outlined,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                final item = items[i];
                final title = (item['title'] ?? '').toString();
                final desc = (item['description'] ?? '').toString();
                final category = (item['category'] ?? '').toString();
                final imageUrl = (item['file_url'] ?? '').toString();

                return RMCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Container(
                            color: const Color(0xFFF2F2F2),
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Image.network(
                              imageUrl,
                              height: 180,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                height: 180,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                  desc,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.muted),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                RMBadge(
                                  text: category,
                                  icon: Icons.folder_open,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Column(
                            children: [
                              IconButton(
                                tooltip: 'Preview',
                                icon: const Icon(Icons.visibility_outlined),
                                onPressed: imageUrl.isEmpty
                                    ? null
                                    : () => _previewImage(imageUrl),
                              ),
                              IconButton(
                                tooltip: 'Download',
                                icon: const Icon(Icons.download),
                                onPressed: imageUrl.isEmpty
                                    ? null
                                    : () => _downloadFile(imageUrl),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}