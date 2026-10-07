import 'package:uuid/uuid.dart';
import 'contest_settings.dart';

int? addonPriceCents(String text) {
  if (!RegExp(r'^\d{1,5}(\.\d{1,2})?$').hasMatch(text.trim())) return null;
  final parts = text.trim().split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String addonMoney(int cents, String currency) =>
    '${currency.toUpperCase()} ${(cents / 100).toStringAsFixed(2)}';

class ContestField {
  ContestField({
    String? id,
    this.label = '',
    this.type = 'text',
    this.required = false,
    List<String>? options,
    this.maxLength = 2000,
    this.onlyCategory = '',
    this.onlyDivision = '',
  }) : id = id ?? const Uuid().v4(),
       options = options ?? [];
  final String id;
  String label;
  String type;
  bool required;
  List<String> options;
  int maxLength;
  String onlyCategory, onlyDivision;
  bool visibleFor(String? category, String? division) =>
      (onlyCategory.isEmpty || category == onlyCategory) &&
      (onlyDivision.isEmpty || division == onlyDivision);
  factory ContestField.fromJson(Map<String, dynamic> row) => ContestField(
    id: row['id'] as String,
    label: row['label'] as String,
    type: row['type'] as String,
    required: row['required'] == true,
    options: (row['options'] as List? ?? []).cast<String>(),
    maxLength: (row['max_length'] as num?)?.toInt() ?? 2000,
    onlyCategory: row['only_category'] as String? ?? '',
    onlyDivision: row['only_division'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label.trim(),
    'type': type,
    'required': required,
    'options': options,
    'max_length': maxLength,
    'only_category': onlyCategory,
    'only_division': onlyDivision,
  };
  String? validate(dynamic value) {
    if (type == 'file') {
      return required && (value is! Map || value['path'] == null)
          ? '$label is required.'
          : null;
    }
    if (type == 'multi_select') {
      if (value == null) return required ? '$label is required.' : null;
      if (value is! List ||
          value.any((v) => !options.contains(v)) ||
          value.toSet().length != value.length) {
        return 'Choose valid options for $label.';
      }
      return required && value.isEmpty ? '$label is required.' : null;
    }
    final text = value?.toString().trim() ?? '';
    if (required && (text.isEmpty || (type == 'checkbox' && value != true))) {
      return '$label is required.';
    }
    if (text.isEmpty) return null;
    if (text.length > maxLength) {
      return '$label must be $maxLength characters or fewer.';
    }
    if (type == 'url') {
      final uri = Uri.tryParse(text);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        return 'Enter a full web link for $label.';
      }
    }
    if (type == 'number' && !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
      return 'Enter a number for $label.';
    }
    if (type == 'select' && !options.contains(text)) {
      return 'Choose an option for $label.';
    }
    if (type == 'date') {
      final date = DateTime.tryParse(text);
      if (date == null ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
          date.toIso8601String().substring(0, 10) != text) {
        return 'Enter a valid date for $label (YYYY-MM-DD).';
      }
    }
    return null;
  }
}

class ShowAddon {
  ShowAddon({
    String? id,
    required this.kind,
    this.name = '',
    this.description = '',
    this.priceCents = 0,
    this.enabled = true,
    this.requiresAnimalEntry = false,
    this.animalSelection = 'none',
    this.useShowEntryDates = true,
    this.registrationOpenAt,
    this.registrationCloseAt,
    this.effectiveOpenAt,
    this.effectiveCloseAt,
    this.registrationStatus = 'open',
    List<String>? divisions,
    this.maxPerExhibitor = 1,
    List<ContestField>? fields,
    ContestSettings? contestSettings,
  }) : id = id ?? const Uuid().v4(),
       fields = fields ?? [],
       divisions = divisions ?? [],
       contest = contestSettings ?? ContestSettings();
  final String id;
  final String kind;
  String name;
  String description;
  int priceCents;
  bool enabled;
  bool requiresAnimalEntry;
  String animalSelection;
  bool useShowEntryDates;
  DateTime? registrationOpenAt, registrationCloseAt;
  final DateTime? effectiveOpenAt, effectiveCloseAt;
  final String registrationStatus;
  bool get registrationIsOpen => registrationStatus == 'open';
  String? validateRegistrationWindow() {
    if (useShowEntryDates) return null;
    if (registrationOpenAt == null || registrationCloseAt == null) {
      return 'Choose both an opening and closing date and time.';
    }
    if (!registrationCloseAt!.isAfter(registrationOpenAt!)) {
      return 'Registration must close after it opens.';
    }
    return null;
  }

  List<String> divisions;
  int maxPerExhibitor;
  List<ContestField> fields;
  ContestSettings contest;
  bool get isContest => kind == 'contest';
  factory ShowAddon.fromJson(Map<String, dynamic> row) => ShowAddon(
    id: row['id'].toString(),
    kind: row['kind'].toString(),
    name: row['name'].toString(),
    description: (row['description'] ?? '').toString(),
    priceCents: (row['price_cents'] as num).toInt(),
    enabled: row['enabled'] == true,
    requiresAnimalEntry: row['requires_animal_entry'] == true,
    animalSelection: (row['animal_selection'] ?? 'none').toString(),
    useShowEntryDates: row['use_show_entry_dates'] != false,
    registrationOpenAt: DateTime.tryParse(
      '${row['registration_open_at'] ?? ''}',
    ),
    registrationCloseAt: DateTime.tryParse(
      '${row['registration_close_at'] ?? ''}',
    ),
    effectiveOpenAt: DateTime.tryParse('${row['effective_open_at'] ?? ''}'),
    effectiveCloseAt: DateTime.tryParse('${row['effective_close_at'] ?? ''}'),
    registrationStatus: (row['registration_status'] ?? 'open').toString(),
    divisions: (row['divisions'] as List? ?? []).cast<String>(),
    maxPerExhibitor: (row['max_per_exhibitor'] as num).toInt(),
    contestSettings: ContestSettings(
      Map<String, dynamic>.from(row['contest_config'] as Map? ?? {}),
    ),
    fields: (row['fields'] as List? ?? [])
        .map((f) => ContestField.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'name': name.trim(),
    'description': description.trim(),
    'price_cents': priceCents,
    'enabled': enabled,
    'requires_animal_entry': requiresAnimalEntry,
    'animal_selection': animalSelection,
    'use_show_entry_dates': useShowEntryDates,
    'registration_open_at': useShowEntryDates
        ? null
        : registrationOpenAt?.toUtc().toIso8601String(),
    'registration_close_at': useShowEntryDates
        ? null
        : registrationCloseAt?.toUtc().toIso8601String(),
    'divisions': divisions,
    'max_per_exhibitor': maxPerExhibitor,
    'fields': fields.map((f) => f.toJson()).toList(),
    'contest_config': contest.toJson(),
  };
}
