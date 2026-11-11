import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

/// This row sits directly on purple, even when adjacent light input fields
/// are inside a surface text scope.
class NoEmailExhibitorOption extends StatelessWidget {
  const NoEmailExhibitorOption({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.onGradientTheme(Theme.of(context)).copyWith(
      disabledColor: AppColors.headerForeground.withValues(alpha: .82),
    ),
    child: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('No email address'),
      subtitle: const Text(
        'Reports will need to be printed and handed out or mailed. Keep each family member as a separate exhibitor.',
      ),
      side: const BorderSide(color: AppColors.headerForeground, width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primaryButton
            : Colors.transparent,
      ),
      checkColor: AppColors.primaryButtonText,
      value: value,
      onChanged: onChanged,
    ),
  );
}
