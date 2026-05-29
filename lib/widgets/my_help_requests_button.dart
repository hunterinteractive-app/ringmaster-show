

// lib/widgets/my_help_requests_button.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/screens/my_help_requests_screen.dart';

class MyHelpRequestsButton extends StatefulWidget {
  const MyHelpRequestsButton({
    super.key,
    this.showLabel = true,
    this.iconColor,
    this.textColor,
  });

  final bool showLabel;
  final Color? iconColor;
  final Color? textColor;

  @override
  State<MyHelpRequestsButton> createState() => _MyHelpRequestsButtonState();
}

class _MyHelpRequestsButtonState extends State<MyHelpRequestsButton> {
  final SupabaseClient supabase = Supabase.instance.client;

  int _waitingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWaitingCount();
  }

  Future<void> _loadWaitingCount() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _waitingCount = 0;
        _loading = false;
      });
      return;
    }

    try {
      final rows = await supabase
          .from('help_reports')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'waiting_on_user');

      if (!mounted) return;

      setState(() {
        _waitingCount = (rows as List).length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _waitingCount = 0;
        _loading = false;
      });
    }
  }

  Future<void> _openHelpRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MyHelpRequestsScreen(),
      ),
    );

    if (mounted) {
      await _loadWaitingCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _HelpIconWithBadge(
      count: _loading ? 0 : _waitingCount,
      iconColor: widget.iconColor,
    );

    if (!widget.showLabel) {
      return IconButton(
        tooltip: 'My Help Requests',
        onPressed: _openHelpRequests,
        icon: icon,
      );
    }

    return TextButton.icon(
      onPressed: _openHelpRequests,
      icon: icon,
      label: Text(
        'Help Requests',
        style: widget.textColor == null
            ? null
            : TextStyle(color: widget.textColor),
      ),
    );
  }
}

class _HelpIconWithBadge extends StatelessWidget {
  const _HelpIconWithBadge({
    required this.count,
    this.iconColor,
  });

  final int count;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.support_agent,
          color: iconColor,
        ),
        if (count > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 9 ? '9+' : count.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}