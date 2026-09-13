import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

/// A local display selection; it does not change the account's primary exhibitor.
class AccountExhibitorWelcome extends StatefulWidget {
  const AccountExhibitorWelcome({
    super.key,
    required this.exhibitors,
    required this.initialExhibitorId,
  });

  final List<Map<String, dynamic>> exhibitors;
  final String initialExhibitorId;

  @override
  State<AccountExhibitorWelcome> createState() =>
      _AccountExhibitorWelcomeState();
}

class _AccountExhibitorWelcomeState extends State<AccountExhibitorWelcome> {
  String? _selectedId;

  String _name(Map<String, dynamic> row) {
    final display = '${row['display_name'] ?? ''}'.trim();
    if (display.isNotEmpty) return display;
    final full = [row['first_name'], row['last_name']]
        .map((value) => '${value ?? ''}'.trim())
        .where((value) => value.isNotEmpty)
        .join(' ');
    return full.isEmpty ? 'Exhibitor' : full;
  }

  String _number(Map<String, dynamic> row) {
    final number = '${row['exhibitor_number'] ?? ''}'.trim();
    return number.isEmpty
        ? 'Exhibitor number not assigned'
        : 'Exhibitor #$number';
  }

  Widget _welcome(Map<String, dynamic> row) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Welcome, ${_name(row)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: AppColors.surface,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        _number(row),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.surface,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.exhibitors.isEmpty) return const SizedBox.shrink();
    final ids = widget.exhibitors.map((row) => '${row['id']}').toSet();
    final selected = ids.contains(_selectedId)
        ? _selectedId!
        : ids.contains(widget.initialExhibitorId)
        ? widget.initialExhibitorId
        : '${widget.exhibitors.first['id']}';
    if (widget.exhibitors.length == 1) return _welcome(widget.exhibitors.first);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Theme(
        data: Theme.of(context).copyWith(
          focusColor: Colors.white.withValues(alpha: 0.12),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            itemHeight: 72,
            dropdownColor: AppColors.pageBackground,
            icon: const Icon(Icons.arrow_drop_down, color: AppColors.surface),
            selectedItemBuilder: (context) => widget.exhibitors
                .map(
                  (row) => Align(
                    alignment: Alignment.centerLeft,
                    child: _welcome(row),
                  ),
                )
                .toList(),
            items: widget.exhibitors
                .map(
                  (row) => DropdownMenuItem<String>(
                    value: '${row['id']}',
                    child: Text(
                      '${_name(row)}\n${_number(row)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedId = value),
          ),
        ),
      ),
    );
  }
}
