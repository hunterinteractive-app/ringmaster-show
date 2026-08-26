import 'package:flutter/material.dart';

/// An icon-only control with an explicit, consistent accessible name.
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon),
      ),
    );
  }
}
