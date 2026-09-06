import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/report_distribution_selection.dart';

void main() {
  const reportsByGroup = <String, List<String>>{
    'arba': ['arba_report'],
    'club': ['breed_results_detail_report', 'sweepstakes_report'],
  };
  const metadataByReport = <String, Map<String, List<String>>>{
    'sweepstakes_report': {
      'breed_name': ['Cavy', 'Netherland Dwarf'],
      'show_letter': ['A', 'B'],
      'scope': ['OPEN', 'YOUTH'],
    },
  };

  test('retains an available report and all active report filters', () {
    const selection = CloseoutReportSelection(
      group: 'club',
      reportName: 'sweepstakes_report',
      breedName: 'Cavy',
      showLetter: 'B',
      scope: 'YOUTH',
    );

    final reconciled = selection.reconcile(
      groupOrder: const ['arba', 'club'],
      reportNamesByGroup: reportsByGroup,
      arbaArtifactIds: const ['arba-a'],
      metadataByReport: metadataByReport,
    );

    expect(reconciled.group, 'club');
    expect(reconciled.reportName, 'sweepstakes_report');
    expect(reconciled.breedName, 'Cavy');
    expect(reconciled.showLetter, 'B');
    expect(reconciled.scope, 'YOUTH');
  });

  test('falls back safely when regenerated artifacts remove a selection', () {
    const selection = CloseoutReportSelection(
      group: 'club',
      reportName: 'missing_report',
      breedName: 'Cavy',
      showLetter: 'B',
      scope: 'YOUTH',
    );

    final reconciled = selection.reconcile(
      groupOrder: const ['arba', 'club'],
      reportNamesByGroup: reportsByGroup,
      arbaArtifactIds: const ['arba-a'],
      metadataByReport: metadataByReport,
    );

    expect(reconciled.group, 'club');
    expect(reconciled.reportName, 'breed_results_detail_report');
    expect(reconciled.breedName, isNull);
    expect(reconciled.showLetter, isNull);
    expect(reconciled.scope, isNull);
  });

  test('replaces a superseded ARBA artifact with the current one', () {
    const selection = CloseoutReportSelection(
      group: 'arba',
      reportName: 'arba_report',
      arbaArtifactId: 'old-arba',
    );

    final reconciled = selection.reconcile(
      groupOrder: const ['arba', 'club'],
      reportNamesByGroup: reportsByGroup,
      arbaArtifactIds: const ['new-arba'],
      metadataByReport: metadataByReport,
    );

    expect(reconciled.arbaArtifactId, 'new-arba');
  });

  test('round trips through persisted JSON', () {
    const selection = CloseoutReportSelection(
      group: 'club',
      reportName: 'sweepstakes_report',
      breedName: 'Cavy',
      showLetter: 'A',
      scope: 'OPEN',
    );

    final restored = CloseoutReportSelection.fromJson(selection.toJson());

    expect(restored.group, selection.group);
    expect(restored.reportName, selection.reportName);
    expect(restored.breedName, selection.breedName);
    expect(restored.showLetter, selection.showLetter);
    expect(restored.scope, selection.scope);
  });
}
