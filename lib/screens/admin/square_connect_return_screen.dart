import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/show_permissions_service.dart';
import '../../theme/app_theme.dart';
import 'show_fees_dialog.dart';

class SquareConnectReturnScreen extends StatefulWidget {
  const SquareConnectReturnScreen({super.key, required this.uri});

  final Uri uri;

  @override
  State<SquareConnectReturnScreen> createState() =>
      _SquareConnectReturnScreenState();
}

class _SquareConnectReturnScreenState extends State<SquareConnectReturnScreen> {
  String _message = 'Returning to Show Fees & Payments…';
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPaymentSettings());
  }

  Future<void> _openPaymentSettings() async {
    if (_opened) return;
    _opened = true;
    final showId = widget.uri.queryParameters['showId']?.trim() ?? '';
    if (showId.isEmpty) {
      setState(() => _message = 'The Square return link is missing its show.');
      return;
    }

    try {
      final permissions = await ShowPermissionsService.load(showId);
      if (!permissions.canManageShowSettings && !permissions.isSupportMode) {
        throw Exception('You do not have permission to manage this show.');
      }
      final show = await Supabase.instance.client
          .from('shows')
          .select('name')
          .eq('id', showId)
          .single();
      if (!mounted) return;
      await ShowFeesDialog.open(
        context,
        showId: showId,
        showName: (show['name'] ?? 'Show').toString(),
        squareReturnStatus: widget.uri.queryParameters['square'],
        squareReturnMessage: widget.uri.queryParameters['message'],
      );
      if (!mounted) return;
      setState(() => _message = 'Square connection settings closed.');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(_message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
