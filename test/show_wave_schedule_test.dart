import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/show_wave_schedule.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/check_in_sheet_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/check_in_sheet_report_pdf.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';

ShowWave wave(int number, int hour) => ShowWave(
  id: 'wave$number',
  number: number,
  checkinStart: DateTime(2027, 3, 10, hour),
  checkinEnd: DateTime(2027, 3, 10, hour + 2),
  showDate: DateTime(2027, 3, 11),
  checkoutDate: DateTime(2027, 3, 12),
);
ShowWaveSchedule schedule(List<ShowWave> waves) => ShowWaveSchedule(
  enabled: true,
  timezone: 'America/Chicago',
  waves: waves,
  breeds: [],
);
void main() {
  test('lead-time choices include 24-hour default and day options', () {
    expect(wave(1, 8).emailLeadHours, 24);
    expect(waveEmailLeadHours, [1, 2, 5, 10, 15, 20, 24, 48, 72]);
    expect(waveLeadLabel(48), '2 days');
  });
  test('date serialization preserves show-local wall clock', () {
    final value = wave(1, 8);
    expect(value.toJson()['checkin_start_local'], '2027-03-10T08:00:00.000');
    expect(ShowWave.fromJson(value.toJson()).checkinStart, value.checkinStart);
  });
  test('adjacent windows are allowed while overlap is rejected', () {
    expect(schedule([wave(1, 8), wave(2, 10)]).validate(), isNull);
    expect(schedule([wave(1, 8), wave(2, 9)]).validate(), contains('overlap'));
  });
  test(
    'incomplete dates and invalid check-in or departure order are rejected',
    () {
      final w = wave(1, 8)..checkinEnd = DateTime(2027, 3, 10, 7);
      expect(schedule([w]).validate(), contains('after it starts'));
      w.checkinEnd = null;
      expect(schedule([w]).validate(), contains('Complete all'));
      w.checkinEnd = DateTime(2027, 3, 10, 10);
      w.checkoutDate = DateTime(2027, 3, 9);
      expect(schedule([w]).validate(), contains('check out'));
    },
  );
  test('disabled drafts do not require completed dates', () {
    final draft = schedule([ShowWave(id: 'draft', number: 1)])..enabled = false;
    expect(draft.validate(), isNull);
  });
  test(
    'report requests retain wave selection across serialization and copies',
    () {
      final request = ReportRequest(
        showId: 'show',
        reportName: 'checkin_sheet',
        finalizeRunId: 'run',
        waveId: 'wave1',
      );
      expect(request.toJson()['waveId'], 'wave1');
      expect(request.copyWith(exhibitorId: 'exhibitor').waveId, 'wave1');
    },
  );
  test('wave sheet PDF includes schedule, note, and section entries', () async {
    final data = CheckInSheetReportData(
      showName: 'Houston Wave Preview',
      sectionLabel: 'Wave 1 • All Sections',
      showContact: const {'secretary_name': 'Show Secretary'},
      waveNote: waveCheckinSheetNote,
      waveSchedule:
          'Check-in: March 10, 2027, 8:00 AM to 10:00 AM (America/Chicago)\nShow date: March 11, 2027 • Check-out: March 12, 2027',
      entries: List.generate(
        18,
        (i) => {
          'entry_id': 'e$i',
          'exhibitor_label': 'Test Exhibitor',
          'exhibitor_number': '1001',
          'tattoo': 'W${i + 1}',
          'breed': i % 2 == 0 ? 'American' : 'Himalayan',
          'variety': 'Black',
          'class_name': 'Senior',
          'sex': 'Buck',
          'section_kind': i < 9 ? 'open' : 'youth',
          'section_letter': 'A',
          'section_display_name': i < 9 ? 'Open A' : 'Youth A',
          'balance_due_cents': 0,
        },
      ),
    );
    final pdf =
        await CheckInSheetReportPdfBuilder(
          assets: FileSystemReportAssetLoader(Directory('assets')),
        ).buildFile(
          data,
          ReportRequest(
            showId: 'show',
            reportName: 'checkin_sheet',
            finalizeRunId: 'run',
          ),
        );
    expect(pdf.bytes.length, greaterThan(5000));
    if (Platform.environment['WAVE_PDF_PREVIEW'] case final String output) {
      await File(output).writeAsBytes(pdf.bytes);
    }
  });
}
