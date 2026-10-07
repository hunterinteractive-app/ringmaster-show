import 'package:flutter/material.dart';
import '../../models/show_addon.dart';
import '../../theme/app_theme.dart';

class ContestAnswerField extends StatefulWidget {
  const ContestAnswerField({
    super.key,
    required this.field,
    this.value,
    required this.onChanged,
    this.upload,
    this.openFile,
  });
  final ContestField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final Future<Map<String, dynamic>?> Function()? upload;
  final Future<void> Function(Map<String, dynamic>)? openFile;
  @override
  State<ContestAnswerField> createState() => _ContestAnswerFieldState();
}

class _ContestAnswerFieldState extends State<ContestAnswerField> {
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final label = '${f.label}${f.required ? ' *' : ' (optional)'}';
    if (f.type == 'file') {
      return FormField<dynamic>(
        initialValue: widget.value,
        validator: f.validate,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            if (state.value is Map)
              Row(
                children: [
                  Expanded(child: Text('${state.value['name']}')),
                  if (widget.openFile != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await widget.openFile!(
                                  Map<String, dynamic>.from(state.value),
                                );
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = e.toString());
                                }
                              }
                            },
                      child: const Text('View'),
                    ),
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: busy
                        ? null
                        : () {
                            state.didChange(null);
                            widget.onChanged(null);
                          },
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(busy ? 'Uploading…' : 'Upload PDF or Image'),
              onPressed: busy || widget.upload == null
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final file = await widget.upload!();
                        if (file != null && mounted) {
                          state.didChange(file);
                          widget.onChanged(file);
                        }
                      } catch (e) {
                        if (mounted) setState(() => error = e.toString());
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
            const Text('PDF, PNG, or JPEG. Maximum 10 MB.'),
            if (error != null || state.hasError)
              Text(
                error ?? state.errorText!,
                style: const TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      );
    }
    if (f.type == 'checkbox') {
      return FormField<bool>(
        initialValue: widget.value == true,
        validator: f.validate,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: state.value ?? false,
              onChanged: (v) {
                state.didChange(v);
                widget.onChanged(v);
              },
            ),
            if (state.hasError)
              Text(
                state.errorText!,
                style: const TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      );
    }
    if (f.type == 'multi_select') {
      return FormField<List<String>>(
        initialValue: (widget.value as List? ?? []).cast<String>(),
        validator: f.validate,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Wrap(
              spacing: 8,
              children: [
                for (final v in f.options)
                  FilterChip(
                    label: Text(v),
                    selected: state.value!.contains(v),
                    onSelected: (selected) {
                      final values = List<String>.from(state.value!);
                      if (selected) {
                        values.add(v);
                      } else {
                        values.remove(v);
                      }
                      state.didChange(values);
                      widget.onChanged(values);
                    },
                  ),
              ],
            ),
            if (state.hasError)
              Text(
                state.errorText!,
                style: const TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      );
    }
    if (f.type == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: f.options.contains(widget.value) ? widget.value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final v in f.options)
            DropdownMenuItem(
              value: v,
              child: Text(v, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: widget.onChanged,
        validator: f.validate,
      );
    }
    return TextFormField(
      initialValue: widget.value?.toString() ?? '',
      maxLines: f.type == 'long_text' ? 4 : 1,
      maxLength: f.maxLength,
      keyboardType: f.type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : f.type == 'url'
          ? TextInputType.url
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: f.type == 'date'
            ? 'YYYY-MM-DD'
            : f.type == 'url'
            ? 'Include https://'
            : null,
        counterText: '',
      ),
      onChanged: widget.onChanged,
      validator: f.validate,
    );
  }
}
