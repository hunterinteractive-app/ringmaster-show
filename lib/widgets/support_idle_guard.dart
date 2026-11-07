import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/support_idle_controller.dart';

class SupportIdleGuard extends StatefulWidget {
  const SupportIdleGuard({
    super.key,
    required this.controller,
    required this.onExit,
    required this.child,
  });
  final SupportIdleController? controller;
  final Future<void> Function() onExit;
  final Widget child;
  @override
  State<SupportIdleGuard> createState() => _SupportIdleGuardState();
}

class _SupportIdleGuardState extends State<SupportIdleGuard> {
  bool _key(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      widget.controller?.activity();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => controller.activity(),
      onPointerSignal: (_) => controller.activity(),
      onPointerPanZoomUpdate: (_) => controller.activity(),
      child: AnimatedBuilder(
        animation: controller,
        child: widget.child,
        builder: (context, child) => Column(
          children: [
            if (controller.warning || controller.error != null)
              Material(
                color: const Color(0xfffff3cd),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            controller.expired
                                ? 'Support Mode ended after inactivity. Exit and reopen Support Mode to continue.'
                                : controller.error ??
                                      'Support Mode will end soon due to inactivity.',
                            style: const TextStyle(color: Color(0xff17213d)),
                          ),
                        ),
                        if (!controller.expired)
                          FilledButton(
                            onPressed: controller.busy
                                ? null
                                : controller.continueSession,
                            child: Text(
                              controller.busy
                                  ? 'Continuing…'
                                  : 'Continue Support Session',
                            ),
                          ),
                        TextButton(
                          onPressed: widget.onExit,
                          child: const Text('Exit Support Mode'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: AbsorbPointer(
                key: const ValueKey('support-idle-content'),
                absorbing: controller.expired,
                child: ExcludeFocus(
                  excluding: controller.expired,
                  child: child!,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
