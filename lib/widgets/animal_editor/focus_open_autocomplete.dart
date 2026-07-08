// lib/widgets/animal_editor/focus_open_autocomplete.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

class FocusOpenAutocomplete extends StatefulWidget {
  final TextEditingController textController;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final List<Map<String, dynamic>> options;
  final String Function(Map<String, dynamic>) displayStringForOption;
  final Future<void> Function(Map<String, dynamic>)? onSelectedAsync;
  final void Function(Map<String, dynamic>)? onSelected;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onFieldTap;
  final Widget? suffixIcon;

  const FocusOpenAutocomplete({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.options,
    required this.displayStringForOption,
    this.onSelectedAsync,
    this.onSelected,
    this.enabled = true,
    this.readOnly = false,
    this.onFieldTap,
    this.suffixIcon,
  });

  @override
  State<FocusOpenAutocomplete> createState() => _FocusOpenAutocompleteState();
}

class _FocusOpenAutocompleteState extends State<FocusOpenAutocomplete> {
  late final TextEditingController _fieldController;

  bool _syncingFromExternal = false;
  bool _syncingToExternal = false;

  List<Map<String, dynamic>> _lastOptions = const [];
  int _highlightedIndex = 0;

  void Function(Map<String, dynamic>)? _rawOnSelected;

  @override
  void initState() {
    super.initState();

    _fieldController = TextEditingController(text: widget.textController.text);

    widget.textController.addListener(_handleExternalTextChanged);
    _fieldController.addListener(_handleFieldTextChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_handleExternalTextChanged);

    widget.focusNode.removeListener(_handleFocusChanged);

    _fieldController.removeListener(_handleFieldTextChanged);

    _fieldController.dispose();

    super.dispose();
  }

  void _handleExternalTextChanged() {
    if (_syncingToExternal) return;

    if (_fieldController.text == widget.textController.text) {
      return;
    }

    _syncingFromExternal = true;

    _fieldController.value = widget.textController.value;

    _syncingFromExternal = false;
  }

  void _handleFieldTextChanged() {
    if (_syncingFromExternal) return;

    if (widget.textController.text == _fieldController.text) {
      return;
    }

    _syncingToExternal = true;

    widget.textController.value = _fieldController.value;

    _syncingToExternal = false;
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) return;
    if (!widget.enabled || widget.readOnly) return;

    _openOptions();
  }

  void _openOptions() {
    final currentText = _fieldController.text;

    final currentSelection = _fieldController.selection;

    _syncingToExternal = true;

    _fieldController.value = TextEditingValue(
      text: '$currentText ',
      selection: TextSelection.collapsed(offset: currentText.length + 1),
    );

    _syncingToExternal = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _syncingToExternal = true;

      _fieldController.value = TextEditingValue(
        text: currentText,
        selection: currentSelection.isValid
            ? currentSelection
            : TextSelection.collapsed(offset: currentText.length),
      );

      _syncingToExternal = false;

      widget.textController.value = _fieldController.value;
    });
  }

  void _commitHighlightedOption() {
    if (_lastOptions.isEmpty || _rawOnSelected == null) {
      return;
    }

    final index = _highlightedIndex.clamp(0, _lastOptions.length - 1);

    final selected = _lastOptions[index];

    _rawOnSelected!(selected);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: _fieldController,
      focusNode: widget.focusNode,
      displayStringForOption: widget.displayStringForOption,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!widget.enabled) {
          _lastOptions = const [];
          _highlightedIndex = 0;

          return const Iterable<Map<String, dynamic>>.empty();
        }

        final q = textEditingValue.text.trim().toLowerCase();

        final results =
            widget.options.where((opt) {
              final label = widget
                  .displayStringForOption(opt)
                  .trim()
                  .toLowerCase();

              return q.isEmpty || label.contains(q);
            }).toList()..sort((a, b) {
              final aSort = a['sort_order'];
              final bSort = b['sort_order'];

              if (aSort != null || bSort != null) {
                final ai = aSort is int
                    ? aSort
                    : int.tryParse(aSort?.toString() ?? '') ?? 9999;

                final bi = bSort is int
                    ? bSort
                    : int.tryParse(bSort?.toString() ?? '') ?? 9999;

                final cmp = ai.compareTo(bi);

                if (cmp != 0) return cmp;
              }

              final aLabel = widget.displayStringForOption(a).toLowerCase();

              final bLabel = widget.displayStringForOption(b).toLowerCase();

              return aLabel.compareTo(bLabel);
            });

        _lastOptions = List<Map<String, dynamic>>.from(results);

        if (_highlightedIndex >= _lastOptions.length) {
          _highlightedIndex = 0;
        }

        return results;
      },
      onSelected: (opt) async {
        final label = widget.displayStringForOption(opt);

        _syncingToExternal = true;

        _fieldController.value = TextEditingValue(
          text: label,
          selection: TextSelection.collapsed(offset: label.length),
        );

        _syncingToExternal = false;

        widget.textController.value = _fieldController.value;

        if (widget.onSelected != null) {
          widget.onSelected!(opt);
        }

        if (widget.onSelectedAsync != null) {
          await widget.onSelectedAsync!(opt);
        }
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_lastOptions.isNotEmpty) {
                    setState(() {
                      _highlightedIndex =
                          (_highlightedIndex + 1) % _lastOptions.length;
                    });
                    return KeyEventResult.handled;
                  }
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  if (_lastOptions.isNotEmpty) {
                    setState(() {
                      _highlightedIndex =
                          (_highlightedIndex - 1 + _lastOptions.length) %
                          _lastOptions.length;
                    });
                    return KeyEventResult.handled;
                  }
                }

                if (event.logicalKey == LogicalKeyboardKey.tab ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  if (_lastOptions.isNotEmpty) {
                    _commitHighlightedOption();
                    return KeyEventResult.handled;
                  }
                }

                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: textEditingController,
                focusNode: focusNode,
                enabled: widget.enabled,
                readOnly: widget.readOnly,
                textInputAction: TextInputAction.next,
                onTap: () {
                  widget.onFieldTap?.call();

                  if (widget.enabled && !widget.readOnly) {
                    _openOptions();
                  }
                },
                onSubmitted: (_) => onFieldSubmitted(),
                decoration: InputDecoration(
                  labelText: widget.labelText,
                  hintText: widget.hintText,
                  suffixIcon: widget.suffixIcon,
                ),
              ),
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();

        _rawOnSelected = onSelected;

        if (opts.isEmpty) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppColors.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, index) {
                  final opt = opts[index];

                  final label = widget.displayStringForOption(opt);

                  final isHighlighted = index == _highlightedIndex;

                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Container(
                      color: isHighlighted ? AppColors.infoBg : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: isHighlighted
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
