import 'package:flutter/material.dart';
import 'package:ringmaster_show/widgets/exhibitor_builder_dialog.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/app_session.dart';

import 'show_list_screen.dart';

class AccountProfileSetupScreen extends StatefulWidget {
  final String? exhibitorId;

  const AccountProfileSetupScreen({
    super.key,
    this.exhibitorId,
  });

  @override
  State<AccountProfileSetupScreen> createState() =>
      _AccountProfileSetupScreenState();
}

class _AccountProfileSetupScreenState extends State<AccountProfileSetupScreen> {
  bool _opening = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openBuilder();
    });
  }

  Future<void> _openBuilder() async {
    if (AppSession.isSupportMode) {
      if (!mounted) return;
      setState(() {
        _msg = 'Profile setup is disabled while viewing in support mode.';
        _opening = false;
      });
      return;
    }

    if (_opening || !mounted) return;

    setState(() {
      _opening = true;
      _msg = null;
    });

    try {
      final saved = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExhibitorBuilderDialog(
          exhibitorId: widget.exhibitorId,
        ),
      );

      if (!mounted) return;

      if (saved != null) {
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context, true);
          return;
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ShowListScreen()),
          (route) => false,
        );
        return;
      }

      if (Navigator.of(context).canPop()) {
        Navigator.pop(context, false);
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ShowListScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Failed to open exhibitor builder: $e';
        _opening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.exhibitorId != null;
    final isSupportMode = AppSession.isSupportMode;

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: isSupportMode
          ? 'Support Mode'
          : isEdit
              ? 'Edit Exhibitor'
              : 'Add Exhibitor',
      showBackButton: true,
      useScrollView: false,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isSupportMode) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                ],
                Text(
                  isSupportMode
                      ? 'Profile setup is read-only in support mode.'
                      : isEdit
                          ? 'Opening exhibitor editor...'
                          : 'Opening exhibitor builder...',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(.25),
                      ),
                    ),
                    child: Text(
                      _msg!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_opening || isSupportMode) ? null : _openBuilder,
                    child: const Text('Try Again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}