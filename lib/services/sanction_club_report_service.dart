import 'package:ringmaster_show/services/report_email_service.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';

class SanctionClubReportOption {
  SanctionClubReportOption.fromJson(Map<String, dynamic> row)
    : clubName = row['club_name'] as String,
      recipient = row['recipient'] as String,
      sections = List<String>.from(row['sections'] as List),
      sanctionIds = Set<String>.from(row['sanction_ids'] as List),
      reportCount = (row['report_count'] as num).toInt();

  final String clubName;
  final String recipient;
  final List<String> sections;
  final Set<String> sanctionIds;
  final int reportCount;
}

class SanctionClubReportService {
  SanctionClubReportService(this._client);

  final SupabaseClient _client;
  static const _requestTimeout = Duration(seconds: 45);

  Future<List<SanctionClubReportOption>> options(
    String showId,
    Map<String, String> changes,
  ) async {
    if (changes.isEmpty) return [];
    final rows = await _client
        .rpc(
          'get_sanction_club_report_options',
          params: {'p_show_id': showId, 'p_changes': changes},
        )
        .timeout(_requestTimeout);
    return List<Map<String, dynamic>>.from(
      rows as List,
    ).map(SanctionClubReportOption.fromJson).toList();
  }

  Future<void> generateAndSend({
    required String showId,
    required String showName,
    required Map<String, String> changes,
    required SanctionClubReportOption option,
    required void Function(String) onProgress,
  }) async {
    onProgress('Queuing ${option.reportCount} reports…');
    final prepared = await _client
        .rpc(
          'prepare_sanction_club_reports',
          params: {
            'p_show_id': showId,
            'p_changes': {
              for (final entry in changes.entries)
                if (option.sanctionIds.contains(entry.key))
                  entry.key: entry.value,
            },
            'p_club_name': option.clubName,
            'p_recipient': option.recipient,
            'p_report_count': option.reportCount,
          },
        )
        .timeout(_requestTimeout);
    final generations = <String, int>{
      for (final row in List<Map<String, dynamic>>.from(prepared as List))
        row['artifact_id'] as String: (row['generation'] as num).toInt(),
    };
    if (generations.isEmpty || generations.length != option.reportCount) {
      throw StateError('The report package could not be prepared.');
    }

    final timer = Stopwatch()..start();
    while (true) {
      final rows = await _client
          .from('show_report_artifacts')
          .select('id,generation,is_current,artifact_status')
          .eq('show_id', showId)
          .inFilter('id', generations.keys.toList())
          .timeout(_requestTimeout);
      if (rows.length != generations.length ||
          rows.any(
            (row) =>
                row['is_current'] != true ||
                row['generation'] != generations[row['id']],
          )) {
        throw StateError('The report package changed before it was ready.');
      }
      if (rows.any((row) => row['artifact_status'] == 'failed')) {
        throw StateError('A club report could not be generated.');
      }
      final ready = rows
          .where((row) => row['artifact_status'] == 'generated')
          .length;
      if (ready == generations.length) break;
      if (timer.elapsed >= const Duration(minutes: 3)) {
        throw StateError(
          'Report generation is still running. Try again shortly.',
        );
      }
      onProgress('Generating reports ($ready of ${generations.length} ready)…');
      await Future<void>.delayed(const Duration(seconds: 4));
    }

    onProgress('Sending reports to ${option.recipient}…');
    await ReportEmailService()
        .sendClubReportEmail(
          showId: showId,
          artifactIds: generations.keys.toList(),
          to: option.recipient,
          subject: '$showName - ${option.clubName} Reports',
          message:
              'Attached are the club reports for ${option.sections.join(', ')} '
              'with the updated sanction numbers.',
          sanctionGenerations: generations,
        )
        .timeout(_requestTimeout);
  }
}
