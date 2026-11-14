import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A searchable US state choice that stores a standard two-letter abbreviation.
class StateDropdownField extends StatefulWidget {
  const StateDropdownField({
    super.key,
    required this.label,
    required this.onSaved,
    this.initialValue = 'TX',
    this.enabled = true,
  });

  final String label;
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onSaved;

  @override
  State<StateDropdownField> createState() => _StateDropdownFieldState();
}

class _StateDropdownFieldState extends State<StateDropdownField> {
  static const _states = {
    'AL': 'Alabama',
    'AK': 'Alaska',
    'AZ': 'Arizona',
    'AR': 'Arkansas',
    'CA': 'California',
    'CO': 'Colorado',
    'CT': 'Connecticut',
    'DE': 'Delaware',
    'DC': 'District of Columbia',
    'FL': 'Florida',
    'GA': 'Georgia',
    'HI': 'Hawaii',
    'ID': 'Idaho',
    'IL': 'Illinois',
    'IN': 'Indiana',
    'IA': 'Iowa',
    'KS': 'Kansas',
    'KY': 'Kentucky',
    'LA': 'Louisiana',
    'ME': 'Maine',
    'MD': 'Maryland',
    'MA': 'Massachusetts',
    'MI': 'Michigan',
    'MN': 'Minnesota',
    'MS': 'Mississippi',
    'MO': 'Missouri',
    'MT': 'Montana',
    'NE': 'Nebraska',
    'NV': 'Nevada',
    'NH': 'New Hampshire',
    'NJ': 'New Jersey',
    'NM': 'New Mexico',
    'NY': 'New York',
    'NC': 'North Carolina',
    'ND': 'North Dakota',
    'OH': 'Ohio',
    'OK': 'Oklahoma',
    'OR': 'Oregon',
    'PA': 'Pennsylvania',
    'RI': 'Rhode Island',
    'SC': 'South Carolina',
    'SD': 'South Dakota',
    'TN': 'Tennessee',
    'TX': 'Texas',
    'UT': 'Utah',
    'VT': 'Vermont',
    'VA': 'Virginia',
    'WA': 'Washington',
    'WV': 'West Virginia',
    'WI': 'Wisconsin',
    'WY': 'Wyoming',
  };
  static String _label(String code) => '${_states[code]} ($code)';
  // Keep entries stable when FormField rebuilds after a filtered selection.
  // Replacing the list can make DropdownMenu reinterpret its filtered index.
  static final List<DropdownMenuEntry<String>> _entries = [
    for (final code in _states.keys)
      DropdownMenuEntry(
        value: code,
        label: _label(code),
        style: const ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.text),
        ),
      ),
  ];
  static String? _code(String text) {
    final query = text.trim().toLowerCase();
    for (final state in _states.entries) {
      if (query == state.key.toLowerCase() ||
          query == state.value.toLowerCase() ||
          query == _label(state.key).toLowerCase()) {
        return state.key;
      }
    }
    return null;
  }

  late final _controller = TextEditingController(
    text: switch (_code(widget.initialValue)) {
      final String code => _label(code),
      _ => widget.initialValue,
    },
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    enabled: widget.enabled,
    initialValue: _code(widget.initialValue),
    validator: (_) => _code(_controller.text) == null
        ? 'Choose a state from the list.'
        : null,
    onSaved: (_) => widget.onSaved(_code(_controller.text)!),
    builder: (field) => DropdownMenu<String>(
      controller: _controller,
      enabled: widget.enabled,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 240,
      label: Text(widget.label),
      hintText: 'Type a state name or abbreviation',
      errorText: field.errorText,
      textStyle: const TextStyle(color: AppColors.text),
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
      ),
      dropdownMenuEntries: _entries,
      onSelected: field.didChange,
    ),
  );
}
