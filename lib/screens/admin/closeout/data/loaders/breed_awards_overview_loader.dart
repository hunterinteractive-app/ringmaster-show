import 'package:supabase/supabase.dart';

import '../../models/base/report_request.dart';

class BreedAwardsOverviewData {
  const BreedAwardsOverviewData(this.showName, this.rows);
  final String showName;
  final List<BreedAwardOverviewRow> rows;
}

class BreedAwardOverviewRow {
  const BreedAwardOverviewRow({
    required this.sectionId,
    required this.sectionLabel,
    required this.species,
    required this.award,
    required this.tattoo,
    required this.coop,
    required this.breed,
    required this.variety,
    required this.className,
    required this.sex,
    required this.exhibitor,
  });
  final String sectionId, sectionLabel, species, award, tattoo, coop;
  final String breed, variety, className, sex, exhibitor;
}

class BreedAwardsOverviewLoader {
  const BreedAwardsOverviewLoader(this.supabase);
  final SupabaseClient supabase;

  Future<BreedAwardsOverviewData> load(ReportRequest request) async {
    final sections = request.sectionIds ?? const <String>[];
    if (sections.isEmpty) throw StateError('Select at least one show section.');
    final show = await supabase
        .from('shows')
        .select('name,coop_numbering_mode')
        .eq('id', request.showId)
        .single();
    final awards = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 1000) {
      final page = await supabase
          .from('entry_awards')
          .select('''
        id,entry_id,award_code,
        entries!entry_awards_entry_id_fkey!inner(
          id,animal_id,section_id,species,tattoo,breed,variety,class_name,sex,
          scratched_at,is_shown,is_disqualified,is_fur,
          exhibitors!entries_exhibitor_id_fkey(display_name,first_name,last_name),
          show_sections(id,kind,letter,display_name,sort_order)
        )
      ''')
          .eq('show_id', request.showId)
          .inFilter('entries.section_id', sections)
          .order('id')
          .range(offset, offset + 999);
      awards.addAll(page);
      if (page.length < 1000) break;
    }
    final coops = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 1000) {
      final page = await supabase
          .from('show_animal_coop_numbers')
          .select('animal_id,scope,coop_number')
          .eq('show_id', request.showId)
          .order('animal_id')
          .order('scope')
          .range(offset, offset + 999);
      coops.addAll(page);
      if (page.length < 1000) break;
    }
    return BreedAwardsOverviewData(
      _text(show['name']),
      buildBreedAwardOverviewRows(
        awards,
        coops,
        combinedCoops: show['coop_numbering_mode'] == 'combined',
      ),
    );
  }
}

String _text(Object? value) => value?.toString().trim() ?? '';
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

String? overviewAwardCode(Object? value) {
  final code = _text(value).toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  return switch (code) {
    'BOB' || 'BESTOFBREED' || 'BESTBREED' => 'BOB',
    'BOS' ||
    'BOSB' ||
    'BESTOPPOSITESEXOFBREED' ||
    'BESTOPPOSITESEXBREED' ||
    'BESTOPPOSITEBREED' => 'BOS',
    'BOV' || 'BESTOFVARIETY' || 'BESTVARIETY' => 'BOV',
    'BOSV' ||
    'BESTOPPOSITESEXOFVARIETY' ||
    'BESTOPPOSITESEXVARIETY' ||
    'BESTOPPOSITEVARIETY' => 'BOSV',
    'BOG' || 'BESTOFGROUP' || 'BESTGROUP' => 'BOG',
    'BOSG' ||
    'BESTOPPOSITESEXOFGROUP' ||
    'BESTOPPOSITESEXGROUP' ||
    'BESTOPPOSITEGROUP' => 'BOSG',
    _ => null,
  };
}

List<BreedAwardOverviewRow> buildBreedAwardOverviewRows(
  List<Map<String, dynamic>> awards,
  List<Map<String, dynamic>> coops, {
  required bool combinedCoops,
}) {
  final coopByAnimalScope = {
    for (final row in coops)
      '${_text(row['animal_id'])}|${_text(row['scope']).toLowerCase()}': _text(
        row['coop_number'],
      ),
  };
  final unique = <String>{};
  final rows = <BreedAwardOverviewRow>[];
  final sectionOrder = <String, int>{};
  for (final row in awards) {
    final award = overviewAwardCode(row['award_code']);
    if (award == null) continue;
    final entry = _map(row['entries']);
    if (entry.isEmpty ||
        entry['scratched_at'] != null ||
        entry['is_shown'] == false ||
        entry['is_disqualified'] == true ||
        entry['is_fur'] == true) {
      continue;
    }
    final section = _map(entry['show_sections']);
    final sectionId = _text(entry['section_id']);
    final entryId = _text(entry['id']);
    if (entryId.isEmpty ||
        sectionId.isEmpty ||
        !unique.add('$sectionId|$entryId|$award')) {
      continue;
    }
    sectionOrder[sectionId] = (section['sort_order'] as num?)?.toInt() ?? 0;
    final kind = _text(section['kind']).toLowerCase();
    final label =
        '${kind == 'youth' ? 'Youth' : 'Open'} ${_text(section['letter']).toUpperCase()}';
    final displayName = _text(section['display_name']);
    final exhibitor = _map(entry['exhibitors']);
    rows.add(
      BreedAwardOverviewRow(
        sectionId: sectionId,
        sectionLabel:
            displayName.isEmpty ||
                displayName.toLowerCase() == label.toLowerCase()
            ? label
            : '$label — $displayName',
        species: _text(entry['species']),
        award: award,
        tattoo: _text(entry['tattoo']),
        coop:
            coopByAnimalScope['${_text(entry['animal_id'])}|${combinedCoops ? 'all' : kind}'] ??
            '',
        breed: _text(entry['breed']),
        variety: _text(entry['variety']),
        className: _text(entry['class_name']),
        sex: _text(entry['sex']),
        exhibitor: _text(exhibitor['display_name']).isNotEmpty
            ? _text(exhibitor['display_name'])
            : [
                _text(exhibitor['first_name']),
                _text(exhibitor['last_name']),
              ].where((part) => part.isNotEmpty).join(' '),
      ),
    );
  }
  const awardOrder = ['BOB', 'BOS', 'BOV', 'BOSV', 'BOG', 'BOSG'];
  rows.sort((a, b) {
    for (final comparison in [
      sectionOrder[a.sectionId]!.compareTo(sectionOrder[b.sectionId]!),
      a.sectionId.compareTo(b.sectionId),
      a.species.compareTo(b.species),
      a.breed.toLowerCase().compareTo(b.breed.toLowerCase()),
      awardOrder.indexOf(a.award).compareTo(awardOrder.indexOf(b.award)),
      a.variety.toLowerCase().compareTo(b.variety.toLowerCase()),
      a.exhibitor.toLowerCase().compareTo(b.exhibitor.toLowerCase()),
      a.tattoo.compareTo(b.tattoo),
    ]) {
      if (comparison != 0) return comparison;
    }
    return 0;
  });
  return rows;
}
