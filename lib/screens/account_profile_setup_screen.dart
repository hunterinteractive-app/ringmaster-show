import 'package:flutter/material.dart';
import 'package:ringmaster_show/widgets/exhibitor_builder_dialog.dart';

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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            Image.asset(
              'assets/images/ringmaster_show_logo.png',
              height: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isEdit ? 'Edit Exhibitor' : 'Add Exhibitor',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF11285A),
              Color(0xFF0B1C43),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F6FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        isEdit
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
                          onPressed: _opening ? null : _openBuilder,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}