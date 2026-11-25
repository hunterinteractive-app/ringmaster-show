import 'dart:convert';
import 'exhibitor_entry_order.dart';
import 'species_sex.dart';

/// A printable draft, not a receipt or a submission action.
String buildCartEntryReview({
  required String showName,
  required String showDate,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> submittedEntries,
  required Map<String, String> exhibitorNames,
  required Map<String, Map<String, dynamic>> sections,
  required List<String> feeLines,
  required List<String> notices,
}) {
  String esc(Object? v) => htmlEscape.convert('${v ?? ''}');
  final out = StringBuffer(
    '''<!doctype html><html><head><meta charset="utf-8"><title>${esc(showName)} — Entry Review</title>
<style>body{font:14px Arial,sans-serif;color:#17202b;margin:24px}h1{font-size:24px}h2{font-size:19px;margin-top:24px}h3{font-size:16px}.notice{border:2px solid #555;padding:12px}table{width:100%;border-collapse:collapse;margin-bottom:18px}th,td{border:1px solid #888;text-align:left;padding:7px;overflow-wrap:anywhere}th{background:#eee}thead{display:table-header-group}tr{break-inside:avoid}h3{break-after:avoid}button{padding:10px 18px}@page{size:landscape;margin:12mm}@media print{.no-print{display:none}body{margin:0;font-size:11px}}</style></head><body>
<button class="no-print" onclick="window.print()">Print / Save as PDF</button>
<h1>${esc(showName)} — Entry Review</h1><p>${esc(showDate)}</p>
<p class="notice"><strong>DRAFT REVIEW — not proof of submission or payment.</strong><br>Cart entries must still be submitted. Review each exhibitor, animal, and show section before continuing.</p>
''',
  );
  for (final notice in notices) {
    out.writeln('<p>${esc(notice)}</p>');
  }
  void roster(String heading, List<Map<String, dynamic>> rows) {
    out.writeln('<h2>${esc(heading)} (${rows.length})</h2>');
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      groups.putIfAbsent('${row['exhibitor_id']}', () => []).add(row);
    }
    final ids = groups.keys.toList()
      ..sort(
        (a, b) => (exhibitorNames[a] ?? a).compareTo(exhibitorNames[b] ?? b),
      );
    for (final id in ids) {
      final entries = groupExhibitorEntries(
        groups[id]!,
        sections,
      ).expand((group) => group).toList();
      out.writeln(
        '<h3>${esc(exhibitorNames[id] ?? entries.first['exhibitor_name'] ?? 'Exhibitor')}</h3><table><thead><tr><th>Section</th><th>Tattoo / Pen ID</th><th>Breed</th><th>Variety</th><th>Sex</th><th>Class</th><th>Entry</th></tr></thead><tbody>',
      );
      for (final e in entries) {
        final section = sections['${e['section_id']}'];
        out.writeln(
          '<tr><td>${esc(section?['display_name'] ?? section?['letter'] ?? '')}</td><td>${esc(e['tattoo'])}</td><td>${esc(e['breed'])}</td><td>${esc(e['is_fur'] == true ? e['fur_variety'] ?? e['variety'] : e['variety'])}</td><td>${esc(displaySexForSpecies(species: e['species'], sex: e['sex']))}</td><td>${esc(e['class_name'])}</td><td>${e['is_fur'] == true ? 'Fur/Wool' : 'Breed'}</td></tr>',
        );
      }
      out.writeln('</tbody></table>');
    }
    if (rows.isEmpty) out.writeln('<p>No entries.</p>');
  }

  roster('In this cart — not submitted', items);
  out.writeln('<h2>Fees and balances</h2><ul>');
  for (final line in feeLines) {
    out.writeln('<li>${esc(line)}</li>');
  }
  out.writeln('</ul>');
  if (submittedEntries.isNotEmpty) {
    roster('Previously submitted — separate from this cart', submittedEntries);
  }
  out.writeln(
    '<p>RingMaster Show · Generated ${esc(DateTime.now().toLocal().toString().split('.').first)}</p></body></html>',
  );
  return out.toString();
}
