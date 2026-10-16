import 'animal_import_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/animal_sync_service.dart';
import '../services/app_session.dart';

class _LinkedRefreshPanel extends StatefulWidget {
  const _LinkedRefreshPanel({
    required this.ownerId,
    required this.onRefreshed,
    this.controller,
  });
  final String? ownerId;
  final AnimalSyncController? controller;
  final Future<void> Function() onRefreshed;

  @override
  State<_LinkedRefreshPanel> createState() => _AnimalSyncPanelState();
}

class _AnimalSyncPanelState extends State<_LinkedRefreshPanel> {
  AnimalSyncController? _controller;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _LinkedRefreshPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) _bind();
  }

  void _bind() {
    _controller?.removeListener(_changed);
    final owner = widget.ownerId;
    _controller = owner == null || AppSession.isSupportMode
        ? null
        : (widget.controller ?? AnimalSyncService.forOwner(owner));
    _controller?.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller?.load();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller;
    if (state == null || AppSession.isSupportMode) {
      return const SizedBox.shrink();
    }
    if (state.providers.isEmpty) {
      if (state.error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(state.error!)),
            TextButton(
              onPressed: state.loading ? null : state.load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final canRefresh = state.providers.any((p) => p.canRefresh);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: state.refreshing || state.loading || !canRefresh
                ? null
                : () async {
                    final owner = widget.ownerId;
                    final changed = await state.refresh();
                    if (mounted && owner == widget.ownerId && changed) {
                      await widget.onRefreshed();
                    }
                  },
            icon: state.refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(
              state.refreshing
                  ? 'Refreshing animals…'
                  : 'Refresh linked animals',
            ),
          ),
          for (final provider in state.providers)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${provider.name} · ${provider.lastRefreshedAt == null ? 'Not refreshed yet' : 'Last refreshed ${DateFormat.yMMMd().add_jm().format(provider.lastRefreshedAt!.toLocal())}'}${provider.canRefresh ? '' : ' · ${provider.unavailableReason ?? 'Refresh not available yet'}'}',
              ),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(liveRegion: true, child: Text(state.error!)),
            ),
        ],
      ),
    );
  }
}

class AnimalSyncPanel extends StatelessWidget {
  const AnimalSyncPanel({
    super.key,
    required this.ownerId,
    required this.onRefreshed,
    this.controller,
  });
  final String? ownerId;
  final Future<void> Function() onRefreshed;
  final AnimalSyncController? controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _LinkedRefreshPanel(
        ownerId: ownerId,
        onRefreshed: onRefreshed,
        controller: controller,
      ),
      AnimalImportReviewPanel(ownerId: ownerId, onResolved: onRefreshed),
    ],
  );
}
