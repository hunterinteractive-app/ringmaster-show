import 'package:supabase/supabase.dart';
import '../../models/base/report_request.dart';

enum MailingLabelMode { address, exhibitorNumber }

enum MailingLabelSort { lastName, exhibitorNumber }

class ExhibitorMailingLabel {
  const ExhibitorMailingLabel({
    required this.id,
    required this.name,
    required this.lastName,
    required this.number,
    required this.address,
    this.hasMailingAddress = true,
  });
  final String id, name, lastName, number;
  final List<String> address;
  final bool hasMailingAddress;
}

class ExhibitorMailingLabelsLoader {
  const ExhibitorMailingLabelsLoader(this.supabase);
  final SupabaseClient supabase;

  Future<List<ExhibitorMailingLabel>> load(ReportRequest request) async {
    final sections = request.sectionIds ?? const <String>[];
    if (sections.isEmpty) throw StateError('Select at least one show section.');
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 1000) {
      final page = await supabase
          .from('entries')
          .select('''
        id,exhibitor_id,
        exhibitors!entries_exhibitor_id_fkey(
          id,display_name,first_name,last_name,exhibitor_number,
          address_line1,address_line2,city,state,zip
        )
      ''')
          .eq('show_id', request.showId)
          .inFilter('section_id', sections)
          .order('id')
          .range(offset, offset + 999);
      rows.addAll(page);
      if (page.length < 1000) break;
    }
    return buildExhibitorMailingLabels(rows);
  }
}

List<ExhibitorMailingLabel> buildExhibitorMailingLabels(
  List<Map<String, dynamic>> entries,
) {
  String text(Object? v) => v?.toString().trim() ?? '';
  final labels = <String, ExhibitorMailingLabel>{};
  for (final entry in entries) {
    final id = text(entry['exhibitor_id']);
    final raw = entry['exhibitors'];
    if (id.isEmpty || raw is! Map) continue;
    final display = text(raw['display_name']);
    final full = [
      text(raw['first_name']),
      text(raw['last_name']),
    ].where((v) => v.isNotEmpty).join(' ');
    final name = display.isEmpty ? full : display;
    final cityState = [
      text(raw['city']),
      text(raw['state']),
    ].where((v) => v.isNotEmpty).join(', ');
    final locality = [
      cityState,
      text(raw['zip']),
    ].where((v) => v.isNotEmpty).join(' ');
    labels[id] = ExhibitorMailingLabel(
      id: id,
      name: name,
      lastName: text(raw['last_name']),
      number: text(raw['exhibitor_number']),
      hasMailingAddress:
          text(raw['address_line1']).isNotEmpty &&
          text(raw['city']).isNotEmpty &&
          text(raw['zip']).isNotEmpty,
      address: [
        text(raw['address_line1']),
        text(raw['address_line2']),
        locality,
      ].where((v) => v.isNotEmpty).toList(),
    );
  }
  return labels.values.toList();
}

List<ExhibitorMailingLabel> sortExhibitorMailingLabels(
  List<ExhibitorMailingLabel> labels,
  MailingLabelSort sort,
) {
  String surname(ExhibitorMailingLabel row) =>
      (row.lastName.isNotEmpty
              ? row.lastName
              : row.name.split(RegExp(r'\s+')).last)
          .toLowerCase();
  return [...labels]..sort((a, b) {
    if (sort == MailingLabelSort.exhibitorNumber) {
      if (a.number.isEmpty != b.number.isEmpty) {
        return a.number.isEmpty ? 1 : -1;
      }
      final an = int.tryParse(a.number), bn = int.tryParse(b.number);
      final number = an != null && bn != null
          ? an.compareTo(bn)
          : a.number.toLowerCase().compareTo(b.number.toLowerCase());
      if (number != 0) return number;
    }
    final last = surname(a).compareTo(surname(b));
    if (last != 0) return last;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name == 0 ? a.id.compareTo(b.id) : name;
  });
}
