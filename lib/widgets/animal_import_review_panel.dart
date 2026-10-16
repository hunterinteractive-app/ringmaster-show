import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_session.dart';

typedef ImportReviewCall = Future<dynamic> Function(Map<String, dynamic>);

class AnimalImportReviewPanel extends StatefulWidget {
  const AnimalImportReviewPanel({
    super.key,
    required this.ownerId,
    required this.onResolved,
    this.call,
  });
  final String? ownerId;
  final Future<void> Function() onResolved;
  final ImportReviewCall? call;
  @override
  State<AnimalImportReviewPanel> createState() =>
      _AnimalImportReviewPanelState();
}

class _AnimalImportReviewPanelState extends State<AnimalImportReviewPanel> {
  List<Map<String, dynamic>> reviews = [];
  String? error;
  bool busy = false;
  final offered = <String>{};
  Future<dynamic> call(Map<String, dynamic> args) =>
      widget.call?.call(args) ??
      Supabase.instance.client.rpc('animal_import_review', params: args);
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant AnimalImportReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) {
      reviews = [];
      offered.clear();
      error = null;
    }
    if (!busy) load();
  }

  Future<void> load() async {
    if (widget.ownerId == null || AppSession.isSupportMode) return;
    if (widget.call == null) {
      try {
        if (widget.ownerId != Supabase.instance.client.auth.currentUser?.id) {
          return;
        }
      } catch (_) {
        return;
      }
    }
    final owner = widget.ownerId;
    try {
      final data = await call({'p_action': 'list'});
      if (mounted && owner == widget.ownerId) {
        setState(() {
          reviews = (data as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          error = null;
        });
        if (!busy) {
          final next = reviews
              .where((r) => !offered.contains(r['id']))
              .firstOrNull;
          if (next != null) {
            offered.add(next['id'] as String);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !busy) review(next);
            });
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Animal match reviews could not load. Retry before importing again.',
        );
      }
    }
  }

  String details(Map a) =>
      '${a['name'] ?? 'Unnamed'} · ${a['tattoo'] ?? 'No tattoo'}\n${a['species'] ?? 'Unknown species'} · ${a['breed'] ?? 'Unknown breed'} · ${a['variety'] ?? 'Unknown variety'}\n${a['sex'] ?? 'Unknown sex'} · DOB ${a['dob'] ?? 'unknown'}';
  Future<void> review(Map<String, dynamic> row) async {
    String? target;
    final candidates = (row['candidates'] as List).cast<Map>();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: const Text('Is this the same animal?'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Incoming animal from ${providerName(row['provider'])}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(details(row['payload'] as Map)),
                  const SizedBox(height: 16),
                  const Text('Possible matches in My Animals'),
                  for (final a in candidates)
                    CheckboxListTile(
                      value: target == a['ringmaster_animal_id'],
                      onChanged: a['can_link'] == true
                          ? (v) => change(
                              () => target = v == true
                                  ? a['ringmaster_animal_id'] as String
                                  : null,
                            )
                          : null,
                      title: Text(details(a)),
                      subtitle: a['can_link'] == true
                          ? null
                          : const Text('Already linked to another source'),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Using an existing animal keeps its Show ID and entry history. Incoming animal fields will update that record. Your choice is saved for future imports.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Decide later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'separate'),
              child: const Text('Create a separate animal'),
            ),
            FilledButton(
              onPressed: target == null
                  ? null
                  : () => Navigator.pop(ctx, 'link'),
              child: const Text('Use this animal'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => busy = true);
    try {
      await call({
        'p_action': action,
        'p_id': row['id'],
        'p_target': action == 'link' ? target : null,
        'p_version': row['updated_at'],
      });
      await load();
      await widget.onResolved();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Match could not be saved. The source or selected animal may have changed. Reload and review again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.isSupportMode || widget.ownerId == null) {
      return const SizedBox.shrink();
    }
    if (reviews.isEmpty && error == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reviews.isNotEmpty)
                Text(
                  '${reviews.length} imported animals need confirmation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              for (final row in reviews)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (row['payload'] as Map)['name'] ??
                        (row['payload'] as Map)['tattoo'] ??
                        'Imported animal',
                  ),
                  subtitle: Text(providerName(row['provider'])),
                  trailing: TextButton(
                    onPressed: busy ? null : () => review(row),
                    child: const Text('Review match'),
                  ),
                ),
              if (error != null) Text(error!),
              if (error != null)
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Reload reviews'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String providerName(dynamic key) => switch (key) {
  'ringmaster_breeder' => 'RingMaster Breeder',
  'herdmaster' => 'HerdMaster',
  'pedigreehq' => 'Pedigree HQ',
  _ => 'Linked program',
};
