import 'dart:async';

import 'package:flutter/material.dart';

/// Rechecks focus after a dialog finishes moving for the software keyboard.
/// EditableText's initial caret scroll can run before that animation completes.
/// Also handles browser viewport resizing and keyboard Next between fields.
class KeepFocusedFieldVisible extends StatefulWidget {
  const KeepFocusedFieldVisible({super.key, required this.child});

  final Widget child;

  @override
  State<KeepFocusedFieldVisible> createState() =>
      _KeepFocusedFieldVisibleState();
}

class _KeepFocusedFieldVisibleState extends State<KeepFocusedFieldVisible>
    with WidgetsBindingObserver {
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_scheduleReveal);
  }

  @override
  void didChangeMetrics() => _scheduleReveal();

  void _scheduleReveal() {
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final target = FocusManager.instance.primaryFocus?.context;
      if (target == null ||
          !target.mounted ||
          target.findAncestorStateOfType<_KeepFocusedFieldVisibleState>() !=
              this) {
        return;
      }
      Scrollable.ensureVisible(
        target,
        alignment: .35,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    FocusManager.instance.removeListener(_scheduleReveal);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
