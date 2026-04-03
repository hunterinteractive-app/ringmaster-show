// lib/screens/admin/show_closeout.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/arba_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/arba_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/registry/report_registry.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/closeout_runner.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/report_engine.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/report_upload_service.dart';
import 'package:ringmaster_show/services/report_email_service.dart';

import 'closeout/data/loaders/legs_report_loader.dart';
import 'closeout/pdf/builders/legs_report_pdf.dart';
import 'closeout/data/loaders/exhibitor_report_loader.dart';
import 'closeout/pdf/builders/exhibitor_report_pdf.dart';
import 'closeout/data/loaders/sweepstakes_report_loader.dart';
import 'closeout/pdf/builders/sweepstakes_report_pdf.dart';
import 'closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'closeout/pdf/builders/breed_results_detail_report_pdf.dart';

import '../../../utils/date_time_utils.dart';

final supabase = Supabase.instance.client;

class ShowCloseoutPage extends StatefulWidget {
  final String showId;
  final String showName;

  const ShowCloseoutPage({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<ShowCloseoutPage> createState() => _ShowCloseoutPageState();
}

class _ShowCloseoutPageState extends State<ShowCloseoutPage> {
  final _secretaryNameController = TextEditingController();
  final _secretaryAddressController = TextEditingController();
  final _secretaryEmailController = TextEditingController();
  final _secretaryPhoneController = TextEditingController();
  final _superintendentController = TextEditingController();
  final _superintendentNumberController = TextEditingController();
  final _sweepstakesClubController = TextEditingController();

  bool _sweepstakesIssue = false;
  bool _officialProtest = false;
  bool _arbaReportFiled = false;

  bool _loadingMissingPlacements = false;
  List<_MissingPlacementItem> _missingPlacementItems = [];
  bool _missingPlacementsLoaded = false;

  bool _loading = true;
  bool _generatingReport = false;
  String? _error;
  Uint8List? _reportLogoBytes;

  CloseoutDashboard? _dashboard;
  LegsReportPdfBuilder? _legsBuilder;
  ExhibitorReportPdfBuilder? _exhibitorBuilder;

  static const Set<String> _exhibitorReportKeys = {
    'exhibitor_report',
    'legs',
  };

    static const Set<String> _clubReportKeys = {
      //'cavy_points',
      //'commercial_points',
      //'details_by_breed',
      //'exh_by_breed',
      //'exh_total_points',
      //'fur_points',
      //'newsletter_show_report',
      'sweepstakes_report',
      'breed_results_detail_report',
    };

  static const Set<String> _arbaReportKeys = {
    'arba_report',
  };

    static const List<String> _reportDisplayOrder = [
      'arba_report',
      'exhibitor_report',
      'legs',
      'newsletter_show_report',
      'exh_total_points',
      'exh_by_breed',
      'details_by_breed',
      'fur_points',
      'sweepstakes_report',
      'breed_results_detail_report',
      'cavy_points',
      'commercial_points',
      'judge_report',
      'finalized_show_report',
      'show_statistics',
      'overall_standings',
      'group_standings',
      'variety_standings',
      'class_standings',
      'points_report_csv',
      'commercial_class_points',
      'newsletter',
    ];

    String _norm(String value) {
      return value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
    }

    String _fileNameOf(ReportArtifactSummary artifact) {
      return (artifact.fileName ?? '').trim();
    }

    String _artifactMatchText(ReportArtifactSummary artifact) {
      return _norm([
        artifact.reportName,
        artifact.fileName ?? '',
        artifact.storagePath ?? '',
      ].join(' '));
    }

    ReportArtifactSummary? _newestGeneratedArtifactWhere(
      String reportName,
      bool Function(ReportArtifactSummary artifact) test,
    ) {
      final matches = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
          .where((r) => r.reportName == reportName)
          .where((r) => r.artifactStatus == 'generated')
          .where((r) => (r.storageBucket?.isNotEmpty == true))
          .where((r) => (r.storagePath?.isNotEmpty == true))
          .where(test)
          .toList()
        ..sort((a, b) {
          final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDt.compareTo(aDt);
        });

      return matches.isEmpty ? null : matches.first;
    }

    bool _artifactMatchesExhibitor(
      ReportArtifactSummary artifact,
      _ExhibitorEmailTarget exhibitor,
    ) {
      final hay = _artifactMatchText(artifact);
      final exhibitorId = _norm(exhibitor.exhibitorId);
      final exhibitorName = _norm(exhibitor.exhibitorName);

      if (exhibitorId.isNotEmpty && hay.contains(exhibitorId)) return true;
      if (exhibitorName.isNotEmpty && hay.contains(exhibitorName)) return true;

      final nameParts = exhibitorName.split(' ').where((x) => x.isNotEmpty).toList();
      if (nameParts.length >= 2) {
        final first = nameParts.first;
        final last = nameParts.last;
        if (hay.contains(first) && hay.contains(last)) return true;
      }

      return false;
    }

    bool _artifactMatchesClubTarget(
      ReportArtifactSummary artifact,
      _ClubEmailTarget target,
    ) {
      final hay = _artifactMatchText(artifact);

      final breed = _norm(target.breedName);
      final scope = _norm(target.scope);
      final showLetter = _norm(target.showLetter);

      if (breed.isNotEmpty && !hay.contains(breed)) return false;
      if (scope.isNotEmpty && !hay.contains(scope)) return false;
      if (showLetter.isNotEmpty && showLetter != 'all' && !hay.contains(showLetter)) {
        return false;
      }

      return true;
    }

        Future<List<_ExhibitorEmailTarget>> _loadExhibitorEmailTargets() async {
          final rows = await supabase
              .from('entries')
              .select('''
                exhibitor_id,
                exhibitors (
                  id,
                  display_name,
                  first_name,
                  last_name,
                  email
                )
              ''')
              .eq('show_id', widget.showId);

          final out = <String, _ExhibitorEmailTarget>{};

          for (final raw in (rows as List)) {
            final row = Map<String, dynamic>.from(raw as Map);
            final exhibitorId = (row['exhibitor_id'] ?? '').toString().trim();
            final exhibitor = row['exhibitors'];

            if (exhibitorId.isEmpty || exhibitor is! Map) continue;

            final ex = Map<String, dynamic>.from(exhibitor);
            final email = (ex['email'] ?? '').toString().trim();
            if (email.isEmpty) continue;

            final displayName = (ex['display_name'] ?? '').toString().trim();
            final first = (ex['first_name'] ?? '').toString().trim();
            final last = (ex['last_name'] ?? '').toString().trim();

            final exhibitorName = displayName.isNotEmpty
                ? displayName
                : [first, last].where((x) => x.isNotEmpty).join(' ').trim();

            if (exhibitorName.isEmpty) continue;

            out[exhibitorId] = _ExhibitorEmailTarget(
              exhibitorId: exhibitorId,
              exhibitorName: exhibitorName,
              email: email,
            );
          }

          final list = out.values.toList()
            ..sort((a, b) => a.exhibitorName.toLowerCase().compareTo(
                  b.exhibitorName.toLowerCase(),
                ));

          return list;
        }

    Future<List<_ClubEmailTarget>> _loadClubEmailTargets() async {
      // IMPORTANT:
      // Adjust these selected field names if your show_sanctions table uses different names.
      final rows = await supabase
          .from('show_sanctions')
          .select('''
            club_name,
            breed_name,
            contact_email,
            sanctioning_body,
            section_id,
            show_sections!inner (
              id,
              kind,
              letter
            )
          ''')
          .eq('show_id', widget.showId);

      final out = <String, _ClubEmailTarget>{};

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);

        final sanctioningBody =
            (row['sanctioning_body'] ?? '').toString().trim().toUpperCase();

        // Skip ARBA here. This button is for breed/club reports.
        if (sanctioningBody == 'ARBA') continue;

        final clubName = (row['club_name'] ?? '').toString().trim();
        final breedName = (row['breed_name'] ?? '').toString().trim();
        final email = (row['contact_email'] ?? '').toString().trim();

        final section = row['show_sections'] is Map
            ? Map<String, dynamic>.from(row['show_sections'] as Map)
            : <String, dynamic>{};

        final scope = (section['kind'] ?? '').toString().trim().toUpperCase();
        final showLetter = (section['letter'] ?? '').toString().trim().toUpperCase();

        if (clubName.isEmpty ||
            breedName.isEmpty ||
            scope.isEmpty ||
            showLetter.isEmpty ||
            email.isEmpty) {
          continue;
        }

        final key = '$clubName|$breedName|$scope|$showLetter|$email';

        out[key] = _ClubEmailTarget(
          clubName: clubName,
          breedName: breedName,
          scope: scope,
          showLetter: showLetter,
          email: email,
        );
      }

      final list = out.values.toList()
        ..sort((a, b) {
          final clubCmp =
              a.clubName.toLowerCase().compareTo(b.clubName.toLowerCase());
          if (clubCmp != 0) return clubCmp;

          final breedCmp =
              a.breedName.toLowerCase().compareTo(b.breedName.toLowerCase());
          if (breedCmp != 0) return breedCmp;

          final scopeCmp = a.scope.compareTo(b.scope);
          if (scopeCmp != 0) return scopeCmp;

          return a.showLetter.compareTo(b.showLetter);
        });

      return list;
    }

    Future<void> _loadMissingPlacements() async {
      if (_loadingMissingPlacements) return;

      setState(() {
        _loadingMissingPlacements = true;
      });

      try {
        final rows = await supabase.rpc(
          'report_results_entry_rows',
          params: {
            'p_show_id': widget.showId,
            'p_section_id': null,
            'p_show_letter': null,
          },
        );

        final items = <_MissingPlacementItem>[];

        for (final raw in (rows as List)) {
          final row = Map<String, dynamic>.from(raw as Map);

          final scratchedAt = (row['scratched_at'] ?? '').toString().trim();
          final isShown = row['is_shown'] != false;
          final isDisqualified = row['is_disqualified'] == true;
          final placement = (row['placement'] ?? '').toString().trim();

          final isEligibleForPlacement =
              scratchedAt.isEmpty && isShown && !isDisqualified;

          if (!isEligibleForPlacement) continue;
          if (placement.isNotEmpty) continue;

          items.add(
            _MissingPlacementItem(
              entryId: (row['entry_id'] ?? '').toString(),
              sectionLabel: (row['section_label'] ?? 'Section').toString().trim(),
              breedName: (row['breed_name'] ?? '').toString().trim(),
              groupName: (row['group_name'] ?? '').toString().trim().isEmpty
                  ? null
                  : (row['group_name'] ?? '').toString().trim(),
              varietyName: (row['variety_name'] ?? '').toString().trim().isEmpty
                  ? null
                  : (row['variety_name'] ?? '').toString().trim(),
              className: (row['class_name'] ?? '').toString().trim(),
              sex: (row['sex'] ?? '').toString().trim(),
              tattoo: (row['tattoo'] ?? '').toString().trim(),
              exhibitorLabel: (row['exhibitor_label'] ?? '').toString().trim(),
            ),
          );
        }

        items.sort((a, b) {
          final sectionCmp =
              a.sectionLabel.toLowerCase().compareTo(b.sectionLabel.toLowerCase());
          if (sectionCmp != 0) return sectionCmp;

          final breedCmp =
              a.breedName.toLowerCase().compareTo(b.breedName.toLowerCase());
          if (breedCmp != 0) return breedCmp;

          return a.tattoo.toLowerCase().compareTo(b.tattoo.toLowerCase());
        });

        if (!mounted) return;
        setState(() {
          _missingPlacementItems = items;
          _missingPlacementsLoaded = true;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed loading missing placements: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _loadingMissingPlacements = false;
          });
        }
      }
    }

    Future<void> _sendArtifactEmail({
      required ReportArtifactSummary artifact,
      required String to,
      String? subject,
      String? message,
    }) async {
      final service = ReportEmailService();

      await service.sendReportEmail(
        showId: widget.showId,
        artifactId: artifact.id,
        to: to,
        subject: subject,
        message: message,
      );
    }

    Widget _buildMissingPlacementsPanel() {
      final readiness = _dashboard?.resultsReadiness;
      final missingCount = readiness?.missingPlacementCount ?? 0;

      if (missingCount <= 0) return const SizedBox.shrink();

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.withOpacity(.22)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(
            Icons.format_list_numbered,
            color: Colors.orange,
          ),
          title: Text(
            '$missingCount missing placement${missingCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.orange,
            ),
          ),
          subtitle: const Text('Tap to view which entries are still missing.'),
          onExpansionChanged: (expanded) async {
            if (expanded && !_missingPlacementsLoaded) {
              await _loadMissingPlacements();
            }
          },
          children: [
            if (_loadingMissingPlacements)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_missingPlacementItems.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No missing placement rows found.'),
              )
            else
              ..._missingPlacementItems.map((item) {
                final parts = <String>[
                  item.sectionLabel,
                  item.breedName,
                  if (item.groupName != null && item.groupName!.isNotEmpty)
                    item.groupName!,
                  if (item.varietyName != null && item.varietyName!.isNotEmpty)
                    item.varietyName!,
                  item.className,
                  item.sex,
                  if (item.exhibitorLabel.isNotEmpty) item.exhibitorLabel,
                ];

                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.pets, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.tattoo.isEmpty ? '(No ear #)' : item.tattoo,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(parts.join(' • ')),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      );
    }

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _secretaryNameController.dispose();
    _secretaryAddressController.dispose();
    _secretaryEmailController.dispose();
    _secretaryPhoneController.dispose();
    _superintendentController.dispose();
    _superintendentNumberController.dispose();
    _sweepstakesClubController.dispose();
    super.dispose();
  }

    Future<void> _generateAllReports() async {
      final ready = await _ensureResultsReadyForReports();
      if (!ready) return;

      setState(() {
        _generatingReport = true;
      });

      try {
        final confirmed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Generate All Reports'),
                content: const Text(
                  'This will generate:\n'
                  '• ARBA report\n'
                  '• Individual exhibitor reports\n'
                  '• Individual legs reports\n'
                  '• Individual club sweepstakes reports\n'
                  '• Individual breed detail reports',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Generate'),
                  ),
                ],
              ),
            ) ??
            false;

        if (!confirmed) return;

        await _generateGlobalReportsOnly();
        await _generateAllExhibitorScopedReports();
        await _generateAllClubScopedReports();

        await supabase.rpc(
          'refresh_show_reports_state',
          params: {'p_show_id': widget.showId},
        );

        await _loadData();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All reports generated.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed generating reports: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _generatingReport = false;
          });
        }
      }
    }

    Future<CloseoutRunner> _buildCloseoutRunner() async {
      await _saveArbaDetails();
      await _ensureLegsBuilder();
      await _ensureExhibitorBuilder();
      await _ensureReportLogo();

      final repository = CloseoutRepository(supabase);
      final arbaLoader = ArbaReportLoader(repository);
      final arbaBuilder = ArbaReportPdfBuilder();

      final legsLoader = LegsReportLoader(repository);
      final exhibitorLoader = ExhibitorReportLoader(repository);

      final sweepstakesLoader = SweepstakesReportLoader(repository);
      final sweepstakesBuilder = SweepstakesReportPdf(
        logoBytes: _reportLogoBytes,
      );

      final breedResultsDetailReportLoader =
          BreedResultsDetailReportLoader(repository);
      final breedResultsDetailReportBuilder = BreedResultsDetailReportPdf(
        logoBytes: _reportLogoBytes,
      );

      final registry = ReportRegistry(
        arbaLoader: arbaLoader,
        arbaBuilder: arbaBuilder,
        legsLoader: legsLoader,
        legsBuilder: _legsBuilder!,
        exhibitorLoader: exhibitorLoader,
        exhibitorBuilder: _exhibitorBuilder!,
        sweepstakesLoader: sweepstakesLoader,
        sweepstakesBuilder: sweepstakesBuilder,
        breedResultsDetailReportLoader: breedResultsDetailReportLoader,
        breedResultsDetailReportBuilder: breedResultsDetailReportBuilder,
      );

      final engine = ReportEngine(registry);
      final uploadService = ReportUploadService(supabase);

      return CloseoutRunner(
        engine: engine,
        uploadService: uploadService,
      );
    }

    Future<({
      String finalizeRunId,
      String showDate,
      String sanctionNumber,
    })> _loadRunContext() async {
      final repository = CloseoutRepository(supabase);
      final showBasics = await repository.loadShowBasics(widget.showId);
      final showDate = _formatShowDate(showBasics['start_date']);
      final sanctionNumber = await _loadArbaSanctionNumber(widget.showId);

      return (
        finalizeRunId: _dashboard?.latestFinalize.id ?? 'manual-run',
        showDate: showDate,
        sanctionNumber: sanctionNumber,
      );
    }

    Future<void> _generateGlobalReportsOnly() async {
      final runner = await _buildCloseoutRunner();
      final ctx = await _loadRunContext();

      final artifact = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
          .where((r) => r.reportName == 'arba_report')
          .cast<ReportArtifactSummary?>()
          .firstWhere(
            (r) => r != null,
            orElse: () => null,
          );

      if (artifact == null) return;

      await runner.generateSingleReport(
        showId: widget.showId,
        finalizeRunId: ctx.finalizeRunId,
        reportName: 'arba_report',
        artifactId: artifact.id,
        showName: widget.showName,
        showDate: ctx.showDate,
        sanctionNumber: ctx.sanctionNumber,
      );
    }

    Future<void> _generateAllExhibitorScopedReports() async {
      final runner = await _buildCloseoutRunner();
      final ctx = await _loadRunContext();
      final exhibitors = await _loadExhibitorEmailTargets();

      for (final exhibitor in exhibitors) {
        final exhibitorArtifacts = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .where((r) =>
                r.reportName == 'exhibitor_report' ||
                r.reportName == 'legs')
            .toList();

        for (final artifact in exhibitorArtifacts) {
          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: ctx.finalizeRunId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            showName: widget.showName,
            showDate: ctx.showDate,
            sanctionNumber: ctx.sanctionNumber,

            // requires runner/engine support:
            exhibitorId: exhibitor.exhibitorId,
            exhibitorName: exhibitor.exhibitorName,
          );
        }
      }
    }

    Future<void> _generateAllClubScopedReports() async {
      final runner = await _buildCloseoutRunner();
      final ctx = await _loadRunContext();
      final clubs = await _loadClubEmailTargets();

      for (final club in clubs) {
        final matchingReports = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .where((r) =>
                r.reportName == 'sweepstakes_report' ||
                r.reportName == 'breed_results_detail_report')
            .toList();

        for (final artifact in matchingReports) {
          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: ctx.finalizeRunId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            breedName: club.breedName,
            scope: club.scope,
            showLetter: club.showLetter,
            showName: widget.showName,
            showDate: ctx.showDate,
            sanctionNumber: ctx.sanctionNumber,
          );
        }
      }
    }

  Future<void> _runGenerateAllReportsLive(
    List<ReportArtifactSummary> artifacts, {
    required void Function(String artifactKey) onStarted,
    required void Function(String artifactKey) onFinished,
    required void Function(String artifactKey, Object error) onFailed,
  }) async {
    await _saveArbaDetails();
    await _ensureLegsBuilder();
    await _ensureExhibitorBuilder();
    await _ensureReportLogo();

    final repository = CloseoutRepository(supabase);
    final arbaLoader = ArbaReportLoader(repository);
    final arbaBuilder = ArbaReportPdfBuilder();
    final showBasics = await repository.loadShowBasics(widget.showId);
    final showDate = _formatShowDate(showBasics['start_date']);
    final sanctionNumber = await _loadArbaSanctionNumber(widget.showId);

    final legsLoader = LegsReportLoader(repository);
    final exhibitorLoader = ExhibitorReportLoader(repository);
    final sweepstakesLoader = SweepstakesReportLoader(repository);
    final sweepstakesBuilder = SweepstakesReportPdf(
      logoBytes: _reportLogoBytes,
    );
    final breedResultsDetailReportLoader =
        BreedResultsDetailReportLoader(repository);
    final breedResultsDetailReportBuilder = BreedResultsDetailReportPdf(
      logoBytes: _reportLogoBytes,
    );

    final registry = ReportRegistry(
      arbaLoader: arbaLoader,
      arbaBuilder: arbaBuilder,
      legsLoader: legsLoader,
      legsBuilder: _legsBuilder!,
      exhibitorLoader: exhibitorLoader,
      exhibitorBuilder: _exhibitorBuilder!,
      sweepstakesLoader: sweepstakesLoader,
      sweepstakesBuilder: sweepstakesBuilder,
      breedResultsDetailReportLoader: breedResultsDetailReportLoader,
      breedResultsDetailReportBuilder: breedResultsDetailReportBuilder,
    );

    final engine = ReportEngine(registry);
    final uploadService = ReportUploadService(supabase);

    final runner = CloseoutRunner(
      engine: engine,
      uploadService: uploadService,
    );

    final latestFinalizeId = _dashboard?.latestFinalize.id ?? 'manual-run';

    String artifactKey(ReportArtifactSummary artifact) {
      final filePart = (artifact.fileName?.trim().isNotEmpty ?? false)
          ? ' • ${artifact.fileName!.trim()}'
          : '';
      return '${artifact.reportName}::${artifact.id}$filePart';
    }

    final needsScopedTargets = artifacts.any(
      (a) =>
          a.reportName == 'sweepstakes_report' ||
          a.reportName == 'breed_results_detail_report',
    );

    final scopedTargets =
        needsScopedTargets ? await _loadScopedReportTargets() : <_ScopedReportTarget>[];

    Future<void> runSingle(ReportArtifactSummary artifact) async {
      final key = artifactKey(artifact);
      onStarted(key);

      try {
        if (artifact.reportName == 'sweepstakes_report' ||
            artifact.reportName == 'breed_results_detail_report') {
          final lowerFileName = (artifact.fileName ?? '').toLowerCase();

          final matchingTarget = scopedTargets.firstWhere(
            (t) =>
                lowerFileName.contains(t.breedName.toLowerCase()) &&
                lowerFileName.contains(t.scope.toLowerCase()) &&
                lowerFileName.contains(t.showLetter.toLowerCase()),
          );

          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: latestFinalizeId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            breedName: matchingTarget.breedName,
            scope: matchingTarget.scope,
            showLetter: matchingTarget.showLetter,
            showName: widget.showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
          );
        } else {
          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: latestFinalizeId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            showName: widget.showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
          );
        }

        onFinished(key);
      } catch (e) {
        onFailed(key, e);
      }
    }

    await Future.wait(
      artifacts.map(runSingle),
      eagerError: false,
    );

    await supabase.rpc(
    'refresh_show_reports_state',
    params: {'p_show_id': widget.showId},
  );
}

  

  Future<void> _sendAllExhibitorReports() async {
    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      final exhibitors = await _loadExhibitorEmailTargets();

      if (exhibitors.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exhibitor email targets found.')),
        );
        return;
      }

      int sentCount = 0;
      int skippedCount = 0;
      int failedCount = 0;

      for (final exhibitor in exhibitors) {
        final exhibitorReport = _newestGeneratedArtifactWhere(
          'exhibitor_report',
          (a) => _artifactMatchesExhibitor(a, exhibitor),
        );

        final legsReport = _newestGeneratedArtifactWhere(
          'legs',
          (a) => _artifactMatchesExhibitor(a, exhibitor),
        );

        final artifacts = <ReportArtifactSummary>[
          if (exhibitorReport != null) exhibitorReport,
          if (legsReport != null) legsReport,
        ];

        if (artifacts.isEmpty) {
          skippedCount++;
          continue;
        }

        for (final artifact in artifacts) {
          try {
            await _sendArtifactEmail(
              artifact: artifact,
              to: exhibitor.email,
              subject: '${widget.showName} - ${_friendlyReportName(artifact.reportName)}',
              message:
                  'Attached is your ${_friendlyReportName(artifact.reportName).toLowerCase()} from ${widget.showName}.',
            );
            sentCount++;
          } catch (e) {
            failedCount++;
            debugPrint(
              'Failed sending ${artifact.reportName} to ${exhibitor.email}: $e',
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exhibitor report send complete. Sent: $sentCount, skipped: $skippedCount, failed: $failedCount',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed sending exhibitor reports: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

  Future<void> _sendAllClubReports() async {
    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      final clubs = await _loadClubEmailTargets();

      if (clubs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No club email targets found.')),
        );
        return;
      }

      int sentCount = 0;
      int skippedCount = 0;
      int failedCount = 0;

      for (final club in clubs) {
        final sweepstakesArtifact = _newestGeneratedArtifactWhere(
          'sweepstakes_report',
          (a) => _artifactMatchesClubTarget(a, club),
        );

        final breedDetailArtifact = _newestGeneratedArtifactWhere(
          'breed_results_detail_report',
          (a) => _artifactMatchesClubTarget(a, club),
        );

        final artifacts = <ReportArtifactSummary>[
          if (sweepstakesArtifact != null) sweepstakesArtifact,
          if (breedDetailArtifact != null) breedDetailArtifact,
        ];

        if (artifacts.isEmpty) {
          skippedCount++;
          continue;
        }

        for (final artifact in artifacts) {
          try {
            await _sendArtifactEmail(
              artifact: artifact,
              to: club.email,
              subject:
                  '${widget.showName} - ${club.breedName} - ${_friendlyReportName(artifact.reportName)}',
              message:
                  'Attached is the ${_friendlyReportName(artifact.reportName).toLowerCase()} for ${club.breedName} (${club.scope} ${club.showLetter}) from ${widget.showName}.',
            );
            sentCount++;
          } catch (e) {
            failedCount++;
            debugPrint(
              'Failed sending ${artifact.reportName} to ${club.email}: $e',
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Club report send complete. Sent: $sentCount, skipped: $skippedCount, failed: $failedCount',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed sending club reports: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

    bool get _resultsReadyForReports =>
        _dashboard?.resultsReadiness.ready == true;

    String _resultsReadinessMessage() {
      final readiness = _dashboard?.resultsReadiness;
      if (readiness == null) {
        return 'Results readiness could not be verified.';
      }

      final parts = <String>[];

      if (readiness.missingPlacementCount > 0) {
        parts.add(
          '${readiness.missingPlacementCount} missing placement${readiness.missingPlacementCount == 1 ? '' : 's'}',
        );
      }

      if (readiness.missingJudgeCount > 0) {
        parts.add(
          '${readiness.missingJudgeCount} missing judge${readiness.missingJudgeCount == 1 ? '' : 's'}',
        );
      }

      if (readiness.duplicatePlacementGroupCount > 0) {
        parts.add(
          '${readiness.duplicatePlacementGroupCount} duplicate placement group${readiness.duplicatePlacementGroupCount == 1 ? '' : 's'}',
        );
      }

      if (parts.isEmpty) {
        return 'Results are ready for reports.';
      }

      return 'Reports are blocked until results are complete: ${parts.join(', ')}.';
    }

    Future<bool> _ensureResultsReadyForReports() async {
      final resp = await supabase.rpc(
        'show_results_readiness',
        params: {'p_show_id': widget.showId},
      );

      final readiness = ResultsReadinessDto.fromJson(
        Map<String, dynamic>.from(resp as Map),
      );

      if (!mounted) return false;

      setState(() {
        if (_dashboard != null) {
          _dashboard = CloseoutDashboard(
            dashboard: _dashboard!.dashboard,
            resultsReadiness: readiness,
            latestFinalize: _dashboard!.latestFinalize,
            reports: _dashboard!.reports,
            deliveries: _dashboard!.deliveries,
            latestArchive: _dashboard!.latestArchive,
          );
        }
      });

      if (readiness.ready) return true;

      final parts = <String>[];

      if (readiness.missingPlacementCount > 0) {
        parts.add(
          '${readiness.missingPlacementCount} missing placement${readiness.missingPlacementCount == 1 ? '' : 's'}',
        );
      }

      if (readiness.missingJudgeCount > 0) {
        parts.add(
          '${readiness.missingJudgeCount} missing judge${readiness.missingJudgeCount == 1 ? '' : 's'}',
        );
      }

      if (readiness.duplicatePlacementGroupCount > 0) {
        parts.add(
          '${readiness.duplicatePlacementGroupCount} duplicate placement group${readiness.duplicatePlacementGroupCount == 1 ? '' : 's'}',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty
                ? 'Reports are blocked until results are complete.'
                : 'Reports are blocked until results are complete: ${parts.join(', ')}.',
          ),
        ),
      );

      return false;
    }

  bool get _isBusy => _loading || _generatingReport;

  Future<void> _ensureLegsBuilder() async {
    _legsBuilder ??= await LegsReportPdfBuilder.fromAssets();
  }

  Future<void> _ensureExhibitorBuilder() async {
    _exhibitorBuilder ??= await ExhibitorReportPdfBuilder.fromAssets();
  }

  Future<void> _ensureReportLogo() async {
    if (_reportLogoBytes != null) return;

    final bytes = await rootBundle.load('assets/images/ringmaster_show_logo.png');
    _reportLogoBytes = bytes.buffer.asUint8List();
  }

  Future<void> _loadArbaDetails() async {
    final row = await supabase
        .from('show_arba_report_details')
        .select('''
          secretary_name,
          secretary_address,
          secretary_email,
          secretary_phone,
          superintendent_name,
          superintendent_arba_number,
          sweepstakes_issue,
          sweepstakes_club,
          official_protest,
          arba_report_filed
        ''')
        .eq('show_id', widget.showId)
        .maybeSingle();

    if (row == null) return;

    _secretaryNameController.text = (row['secretary_name'] ?? '').toString();
    _secretaryAddressController.text =
        (row['secretary_address'] ?? '').toString();
    _secretaryEmailController.text = (row['secretary_email'] ?? '').toString();
    _secretaryPhoneController.text = (row['secretary_phone'] ?? '').toString();
    _superintendentController.text =
        (row['superintendent_name'] ?? '').toString();
    _superintendentNumberController.text =
        (row['superintendent_arba_number'] ?? '').toString();

    _sweepstakesIssue = row['sweepstakes_issue'] == true;
    _sweepstakesClubController.text =
        (row['sweepstakes_club'] ?? '').toString();
    _officialProtest = row['official_protest'] == true;
    _arbaReportFiled = _officialProtest && row['arba_report_filed'] == true;
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dashboardResp = await supabase.rpc(
        'get_show_closeout_dashboard',
        params: {'p_show_id': widget.showId},
      );

      final dashboardJson = Map<String, dynamic>.from(dashboardResp as Map);
      final dashboard = CloseoutDashboard.fromJson(dashboardJson);

      debugPrint('🔥🧪 isReportsStale = ${dashboard.dashboard.closeout.isReportsStale}');

      await _loadArbaDetails();
      await _ensureLegsBuilder();
      await _ensureExhibitorBuilder();
      await _ensureReportLogo();

      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveArbaDetails() async {
    try {
      await supabase.from('show_arba_report_details').upsert({
        'show_id': widget.showId,
        'secretary_name': _secretaryNameController.text.trim(),
        'secretary_address': _secretaryAddressController.text.trim(),
        'secretary_email': _secretaryEmailController.text.trim(),
        'secretary_phone': _secretaryPhoneController.text.trim(),
        'superintendent_name': _superintendentController.text.trim(),
        'superintendent_arba_number':
            _superintendentNumberController.text.trim(),
        'sweepstakes_issue': _sweepstakesIssue,
        'sweepstakes_club': _sweepstakesIssue
            ? _sweepstakesClubController.text.trim()
            : null,
        'official_protest': _officialProtest,
        'arba_report_filed': _officialProtest ? _arbaReportFiled : null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ARBA closeout details saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save ARBA details: $e')),
      );
      rethrow;
    }
  }

  Future<String> _loadArbaSanctionNumber(String showId) async {
    try {
      final row = await supabase
          .from('show_sanctions')
          .select('sanction_number')
          .eq('show_id', showId)
          .eq('sanctioning_body', 'ARBA')
          .limit(1)
          .maybeSingle();

      if (row == null) return '';
      return (row['sanction_number'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  String _formatShowDate(dynamic rawDate) {
    if (rawDate == null) return '';
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed == null) return rawDate.toString();
    return '${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}-${parsed.year}';
  }

  Future<List<_ScopedReportTarget>> _loadScopedReportTargets() async {
    final targets = <_ScopedReportTarget>[];

    final enabledSections = await supabase
        .from('show_sections')
        .select('id, kind, letter')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true);

    final seen = <String>{};

    for (final raw in (enabledSections as List)) {
      final row = Map<String, dynamic>.from(raw as Map);

      final sectionId = (row['id'] ?? '').toString();
      final kind = (row['kind'] ?? '').toString().trim().toUpperCase();
      final sectionLetter = (row['letter'] ?? '').toString().trim().toUpperCase();

      if (sectionId.isEmpty || kind.isEmpty) continue;

      final results = await supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': sectionId,
          'p_show_letter': sectionLetter.isEmpty ? null : sectionLetter,
        },
      );

      for (final rawResult in (results as List)) {
        final result = Map<String, dynamic>.from(rawResult as Map);
        final breedName = (result['breed_name'] ?? '').toString().trim();
        if (breedName.isEmpty) continue;

        final key = '$breedName|$kind|$sectionLetter';
        if (seen.add(key)) {
          targets.add(
            _ScopedReportTarget(
              breedName: breedName,
              scope: kind,
              showLetter: sectionLetter,
            ),
          );
        }
      }
    }

    targets.sort((a, b) {
      final breedCmp = a.breedName.compareTo(b.breedName);
      if (breedCmp != 0) return breedCmp;

      final scopeCmp = a.scope.compareTo(b.scope);
      if (scopeCmp != 0) return scopeCmp;

      return a.showLetter.compareTo(b.showLetter);
    });

    return targets;
  }

    Future<void> _generateReportByName(
      String reportName, {
      String? breedName,
      String? scope,
      String? showLetter,
    }) async {
      final ready = await _ensureResultsReadyForReports();
      if (!ready) return;

      try {
        setState(() {
          _generatingReport = true;
          _error = null;
        });

        await _saveArbaDetails();
        await _ensureLegsBuilder();
        await _ensureExhibitorBuilder();
        await _ensureReportLogo();

        final repository = CloseoutRepository(supabase);
        final arbaLoader = ArbaReportLoader(repository);
        final arbaBuilder = ArbaReportPdfBuilder();
        final showBasics = await repository.loadShowBasics(widget.showId);
        final showDate = _formatShowDate(showBasics['start_date']);
        final sanctionNumber = await _loadArbaSanctionNumber(widget.showId);

        final legsLoader = LegsReportLoader(repository);
        await _ensureLegsBuilder();

        final exhibitorLoader = ExhibitorReportLoader(repository);

        final sweepstakesLoader = SweepstakesReportLoader(repository);
        final sweepstakesBuilder = SweepstakesReportPdf(
          logoBytes: _reportLogoBytes,
        );

        final breedResultsDetailReportLoader =
            BreedResultsDetailReportLoader(repository);
        final breedResultsDetailReportBuilder =
            BreedResultsDetailReportPdf(
          logoBytes: _reportLogoBytes,
        );

        final registry = ReportRegistry(
          arbaLoader: arbaLoader,
          arbaBuilder: arbaBuilder,
          legsLoader: legsLoader,
          legsBuilder: _legsBuilder!,
          exhibitorLoader: exhibitorLoader,
          exhibitorBuilder: _exhibitorBuilder!,
          sweepstakesLoader: sweepstakesLoader,
          sweepstakesBuilder: sweepstakesBuilder,
          breedResultsDetailReportLoader: breedResultsDetailReportLoader,
          breedResultsDetailReportBuilder: breedResultsDetailReportBuilder,
        );

        final engine = ReportEngine(registry);
        final uploadService = ReportUploadService(supabase);

        final runner = CloseoutRunner(
          engine: engine,
          uploadService: uploadService,
        );

        final artifact = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .where((r) => r.reportName == reportName)
            .cast<ReportArtifactSummary?>()
            .firstWhere(
              (r) => r != null,
              orElse: () => null,
            );

        if (artifact == null) {
          throw Exception(
            'No record exists for report "$reportName".',
          );
        }

        await runner.generateSingleReport(
          showId: widget.showId,
          finalizeRunId: _dashboard?.latestFinalize.id ?? 'manual-run',
          reportName: reportName,
          artifactId: artifact.id,
          breedName: breedName,
          scope: scope,
          showName: widget.showName,
          showDate: showDate,
          sanctionNumber: sanctionNumber,
          showLetter: showLetter,
        );

        await _loadData();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_friendlyReportName(reportName)} generated.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _generatingReport = false;
          });
        }
      }
    }

  Future<void> _downloadReportByName(String reportName) async {
    try {
      final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

      final matches = reports
          .where((r) =>
              r.reportName == reportName &&
              r.artifactStatus == 'generated' &&
              (r.storageBucket?.isNotEmpty == true) &&
              (r.storagePath?.isNotEmpty == true))
          .toList()
        ..sort((a, b) {
          final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDt.compareTo(aDt);
        });

      if (matches.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('No generated ${_friendlyReportName(reportName)} found.'),
          ),
        );
        return;
      }

      final newest = matches.first;

      final signedUrl = await supabase.storage
          .from(newest.storageBucket!)
          .createSignedUrl(newest.storagePath!, 60 * 5);

      await launchUrlString(
        signedUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _emailReportByName(String reportName) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Email ${_friendlyReportName(reportName)} coming next.',
        ),
      ),
    );
  }

  List<ReportArtifactSummary> _reportsForGroup(String groupKey) {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

    final filtered = switch (groupKey) {
      'arba' => reports.where((r) => _arbaReportKeys.contains(r.reportName)),
      'exhibitor' =>
        reports.where((r) => _exhibitorReportKeys.contains(r.reportName)),
      'club' => reports.where((r) => _clubReportKeys.contains(r.reportName)),
      'other' => reports.where((r) {
          return !_arbaReportKeys.contains(r.reportName) &&
              !_exhibitorReportKeys.contains(r.reportName) &&
              !_clubReportKeys.contains(r.reportName);
        }),
      _ => reports,
    }.toList();

    filtered.sort((a, b) {
      final aIndex = _reportDisplayOrder.indexOf(a.reportName);
      final bIndex = _reportDisplayOrder.indexOf(b.reportName);

      if (aIndex == -1 && bIndex == -1) {
        return _friendlyReportName(a.reportName)
            .compareTo(_friendlyReportName(b.reportName));
      }
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    return filtered;
  }

  List<String> _reportNamesForGroup(String groupKey) {
    final reports = _reportsForGroup(groupKey);
    final names = reports.map((r) => r.reportName).toSet().toList();

    if (groupKey == 'arba') {
      for (final name in _arbaReportKeys) {
        if (!names.contains(name)) names.add(name);
      }
    } else if (groupKey == 'exhibitor') {
      for (final name in _exhibitorReportKeys) {
        if (!names.contains(name)) names.add(name);
      }
    } else if (groupKey == 'club') {
      for (final name in _clubReportKeys) {
        if (!names.contains(name)) names.add(name);
      }
    }

    names.sort((a, b) {
      final aIndex = _reportDisplayOrder.indexOf(a);
      final bIndex = _reportDisplayOrder.indexOf(b);

      if (aIndex == -1 && bIndex == -1) {
        return _friendlyReportName(a).compareTo(_friendlyReportName(b));
      }
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    return names;
  }

  @override
  Widget build(BuildContext context) {
    final reportsBlocked = !_resultsReadyForReports;
    final reportsBlockedMessage = _resultsReadinessMessage();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.showName} • Closeout'),
        actions: [
          IconButton(
            onPressed: (_loading || _generatingReport) ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _loadData)
              : _dashboard == null
                  ? const Center(child: Text('No closeout data found.'))
                  : RefreshIndicator(
                      onRefresh: _generatingReport ? () async {} : _loadData,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _ArbaCloseoutCard(
                            secretaryNameController: _secretaryNameController,
                            secretaryAddressController: _secretaryAddressController,
                            secretaryEmailController: _secretaryEmailController,
                            secretaryPhoneController: _secretaryPhoneController,
                            superintendentController: _superintendentController,
                            superintendentNumberController: _superintendentNumberController,
                            sweepstakesIssue: _sweepstakesIssue,
                            sweepstakesClubController: _sweepstakesClubController,
                            onSweepstakesChanged: (v) {
                              setState(() {
                                _sweepstakesIssue = v;
                                if (!v) {
                                  _sweepstakesClubController.clear();
                                }
                              });
                            },
                            onSweepstakesClubChanged: (_) {},
                            officialProtest: _officialProtest,
                            onOfficialProtestChanged: (v) {
                              setState(() {
                                _officialProtest = v;
                                if (!v) {
                                  _arbaReportFiled = false;
                                }
                              });
                            },
                            arbaReportFiled: _arbaReportFiled,
                            onArbaReportFiledChanged: (v) {
                              setState(() => _arbaReportFiled = v);
                            },
                            onSave: _saveArbaDetails,
                          ),
                          const SizedBox(height: 16),

                          // ✅ NEW BULK ACTION BUTTONS (ADD THIS BLOCK)
                          if (reportsBlocked) ...[
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(.22),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      reportsBlockedMessage,
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildMissingPlacementsPanel(),
                          ],

                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: reportsBlocked
                                      ? Colors.grey
                                      : (_dashboard?.dashboard.closeout.isReportsStale == true
                                          ? const Color(0xFFD4A623)
                                          : Colors.green),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: (_isBusy || reportsBlocked)
                                    ? null
                                    : _generateAllReports,
                                icon: const Icon(Icons.auto_awesome),
                                label: Text(
                                  reportsBlocked
                                      ? 'Finish Results Before Reports'
                                      : (_dashboard?.dashboard.closeout.isReportsStale == true
                                          ? 'Generate All Reports'
                                          : 'All Reports Fresh'),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isBusy ? null : _sendAllExhibitorReports,
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Send All Exhibitor Reports'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isBusy ? null : _sendAllClubReports,
                                icon: const Icon(Icons.group_outlined),
                                label: const Text('Send All Club Reports'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // ✅ EXISTING CARD (DO NOT CHANGE)
                          _ReportActionsCard(
                            showId: widget.showId,
                            reports: _dashboard?.reports ??
                                const <ReportArtifactSummary>[],
                            groupedReportNames: {
                              'arba': _reportNamesForGroup('arba'),
                              'exhibitor': _reportNamesForGroup('exhibitor'),
                              'club': _reportNamesForGroup('club'),
                              //'other': _reportNamesForGroup('other'),🧪
                            },
                            onGenerate: (
                              reportName, {
                              String? breedName,
                              String? scope,
                              String? showLetter,
                            }) =>
                                _generateReportByName(
                                  reportName,
                                  breedName: breedName,
                                  scope: scope,
                                  showLetter: showLetter,
                                ),
                            onDownload: _downloadReportByName,
                            onEmail: _emailReportByName,
                            loading: _generatingReport,
                            reportsBlocked: reportsBlocked,
                            reportsBlockedMessage: reportsBlockedMessage,
                          ),
                        ],
                      ),
                    ),
    );
  }
}
class _CloseoutSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _CloseoutSectionCard({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _MissingPlacementItem {
  final String entryId;
  final String sectionLabel;
  final String breedName;
  final String? groupName;
  final String? varietyName;
  final String className;
  final String sex;
  final String tattoo;
  final String exhibitorLabel;

  const _MissingPlacementItem({
    required this.entryId,
    required this.sectionLabel,
    required this.breedName,
    required this.groupName,
    required this.varietyName,
    required this.className,
    required this.sex,
    required this.tattoo,
    required this.exhibitorLabel,
  });
}

class _ArbaCloseoutCard extends StatelessWidget {
  final TextEditingController secretaryNameController;
  final TextEditingController secretaryAddressController;
  final TextEditingController secretaryEmailController;
  final TextEditingController secretaryPhoneController;
  final TextEditingController superintendentController;
  final TextEditingController superintendentNumberController;
  final TextEditingController sweepstakesClubController;

  final bool sweepstakesIssue;
  final ValueChanged<bool> onSweepstakesChanged;
  final ValueChanged<String> onSweepstakesClubChanged;

  final bool officialProtest;
  final ValueChanged<bool> onOfficialProtestChanged;

  final bool arbaReportFiled;
  final ValueChanged<bool> onArbaReportFiledChanged;

  final Future<void> Function() onSave;

  const _ArbaCloseoutCard({
    required this.secretaryNameController,
    required this.secretaryAddressController,
    required this.secretaryEmailController,
    required this.secretaryPhoneController,
    required this.superintendentController,
    required this.superintendentNumberController,
    required this.sweepstakesIssue,
    required this.sweepstakesClubController,
    required this.onSweepstakesChanged,
    required this.onSweepstakesClubChanged,
    required this.officialProtest,
    required this.onOfficialProtestChanged,
    required this.arbaReportFiled,
    required this.onArbaReportFiledChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _CloseoutSectionCard(
      title: 'ARBA Final Closeout Confirmation',
      subtitle: 'Complete the required show secretary and protest information before generating final reports.',
      children: [
        TextField(
          controller: secretaryNameController,
          decoration: const InputDecoration(
            labelText: 'Show Secretary Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: secretaryAddressController,
          decoration: const InputDecoration(
            labelText: 'Secretary Address',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: secretaryEmailController,
          decoration: const InputDecoration(
            labelText: 'Secretary Email',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: secretaryPhoneController,
          decoration: const InputDecoration(
            labelText: 'Secretary Phone',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: superintendentController,
          decoration: const InputDecoration(
            labelText: 'Superintendent Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: superintendentNumberController,
          decoration: const InputDecoration(
            labelText: 'Superintendent ARBA Number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF11285A).withOpacity(.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF11285A).withOpacity(.10),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sweepstakes Sanction Issues',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Did you have any trouble receiving sweepstakes sanctions from national specialty clubs?',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(sweepstakesIssue ? 'Yes' : 'No'),
                value: sweepstakesIssue,
                onChanged: onSweepstakesChanged,
              ),
              if (sweepstakesIssue)
                TextField(
                  controller: sweepstakesClubController,
                  decoration: const InputDecoration(
                    labelText: 'Which club(s)?',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: onSweepstakesClubChanged,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFD4A623).withOpacity(.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFD4A623).withOpacity(.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Official Protest',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Was there an official protest filed at this show?',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(officialProtest ? 'Yes' : 'No'),
                value: officialProtest,
                onChanged: onOfficialProtestChanged,
              ),
              if (officialProtest)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(arbaReportFiled ? 'Yes' : 'No'),
                  subtitle: const Text('Has a report been filed with ARBA?'),
                  value: arbaReportFiled,
                  onChanged: onArbaReportFiledChanged,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD4A623),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('Save ARBA Closeout Info'),
          ),
        ),
      ],
    );
  }
}
class _ReportActionsCard extends StatefulWidget {
  final List<ReportArtifactSummary> reports;
  final Map<String, List<String>> groupedReportNames;
  final Future<void> Function(
    String reportName, {
    String? breedName,
    String? scope,
    String? showLetter,
  }) onGenerate;
  final Future<void> Function(String reportName) onDownload;
  final Future<void> Function(String reportName) onEmail;
  final bool loading;
  final String showId;
  final bool reportsBlocked;
  final String? reportsBlockedMessage;

  const _ReportActionsCard({
    required this.showId,
    required this.reports,
    required this.groupedReportNames,
    required this.onGenerate,
    required this.onDownload,
    required this.onEmail,
    required this.loading,
    required this.reportsBlocked,
    this.reportsBlockedMessage,
  });

  @override
  State<_ReportActionsCard> createState() => _ReportActionsCardState();
}

class _ReportActionsCardState extends State<_ReportActionsCard> {
  String _selectedGroup = 'arba';
  String? _selectedReportName = 'arba_report';
  final TextEditingController _breedController = TextEditingController();
  String _selectedScope = 'OPEN';
  String _selectedShowLetter = 'ALL';
  List<String> _availableShowLetters = [];
  bool _loadingShowLetters = false;

  static const Map<String, String> _groupLabels = {
    'arba': 'ARBA Reports',
    'exhibitor': 'Exhibitor Reports',
    'club': 'Club Reports',
    //'other': 'Other Reports',
  };

  List<String> _availableBreeds = [];
  bool _loadingBreeds = false;

  List<String> get _currentReports =>
      widget.groupedReportNames[_selectedGroup] ?? const [];

  ReportArtifactSummary? get _selectedArtifact {
    final reportName = _selectedReportName;
    if (reportName == null) return null;

    final matches = widget.reports
        .where((r) => r.reportName == reportName)
        .toList()
      ..sort((a, b) {
        final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDt.compareTo(aDt);
      });

    if (matches.isEmpty) return null;
    return matches.first;
  }

  bool get _selectedReportNeedsBreedScope =>
    _selectedReportName == 'sweepstakes_report' ||
    _selectedReportName == 'breed_results_detail_report';

  bool get _canDownload {
    final artifact = _selectedArtifact;
    return artifact != null &&
        artifact.artifactStatus == 'generated' &&
        (artifact.storageBucket?.isNotEmpty == true) &&
        (artifact.storagePath?.isNotEmpty == true);
  }

  Future<void> _loadShowLetters() async {
    if (_loadingShowLetters) return;

    setState(() {
      _loadingShowLetters = true;
    });

    try {
      final rows = await supabase
          .from('show_sections')
          .select('letter')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true)
          .order('letter');

      final letters = <String>{};

      for (final row in (rows as List)) {
        final letter = (row['letter'] ?? '').toString().trim().toUpperCase();
        if (letter.isNotEmpty) {
          letters.add(letter);
        }
      }

      final sorted = letters.toList()..sort();

      if (!mounted) return;

      setState(() {
        _availableShowLetters = sorted;
        if (sorted.isNotEmpty) {
          if (_selectedShowLetter != 'ALL' &&
              !sorted.contains(_selectedShowLetter)) {
            _selectedShowLetter = sorted.first;
          }
        } else {
          _selectedShowLetter = 'ALL';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _availableShowLetters = [];
        _selectedShowLetter = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed loading show letters: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingShowLetters = false;
        });
      }
    }
  }

  Future<void> _loadBreedsForBreedScopedReports() async {
    if (_loadingBreeds) return;

    setState(() {
      _loadingBreeds = true;
    });

    try {
      final kind = _selectedScope == 'OPEN' ? 'open' : 'youth';

      final sections = await supabase
          .from('show_sections')
          .select('id, display_name, kind, sort_order')
          .eq('show_id', widget.showId)
          .eq('kind', kind)
          .eq('is_enabled', true)
          .order('sort_order');

      final breedSet = <String>{};

      for (final section in (sections as List)) {
        final sectionId = section['id'].toString();

        final rows = await supabase.rpc(
          'report_results_entry_rows',
          params: {
            'p_show_id': widget.showId,
            'p_section_id': sectionId,
            'p_show_letter': (_selectedShowLetter.isEmpty ||
                    _selectedShowLetter == 'ALL')
                ? null
                : _selectedShowLetter,
          },
        );

        for (final row in (rows as List)) {
          final breed = (row['breed_name'] ?? '').toString().trim();
          if (breed.isNotEmpty) {
            breedSet.add(breed);
          }
        }
      }

      final breeds = breedSet.toList()..sort();

      if (!mounted) return;

      setState(() {
        _availableBreeds = breeds;

        if (breeds.isNotEmpty) {
          final current = _breedController.text.trim();
          if (current.isEmpty || !breeds.contains(current)) {
            _breedController.text = breeds.first;
          }
        } else {
          _breedController.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _availableBreeds = [];
        _breedController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed loading breeds: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingBreeds = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _breedController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ReportActionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final reports = _currentReports;
    if (reports.isEmpty) {
      _selectedReportName = null;
      return;
    }

    if (_selectedReportName == null || !reports.contains(_selectedReportName)) {
      _selectedReportName = reports.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final artifact = _selectedArtifact;

    return _CloseoutSectionCard(
      title: 'Reports & Distribution',
      subtitle: 'Generate, download, and distribute closeout reports by category.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedGroup,
          decoration: const InputDecoration(
            labelText: 'Report Group',
            border: OutlineInputBorder(),
          ),
          items: _groupLabels.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (value) async {
            if (value == null) return;

            final reports = widget.groupedReportNames[value] ?? const [];
            final nextReport = reports.isEmpty ? null : reports.first;

            setState(() {
              _selectedGroup = value;
              _selectedReportName = nextReport;
            });

            if (nextReport == 'sweepstakes_report' ||
                nextReport == 'breed_results_detail_report') {
              await _loadShowLetters();
              await _loadBreedsForBreedScopedReports();
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _currentReports.contains(_selectedReportName)
              ? _selectedReportName
              : (_currentReports.isNotEmpty ? _currentReports.first : null),
          decoration: const InputDecoration(
            labelText: 'Report',
            border: OutlineInputBorder(),
          ),
          items: _currentReports
              .map(
                (reportName) => DropdownMenuItem<String>(
                  value: reportName,
                  child: Text(_friendlyReportName(reportName)),
                ),
              )
              .toList(),
          onChanged: _currentReports.isEmpty
              ? null
              : (value) async {
                  setState(() {
                    _selectedReportName = value;
                  });

                  if (value == 'sweepstakes_report' ||
                      value == 'breed_results_detail_report') {
                    await _loadShowLetters();
                    await _loadBreedsForBreedScopedReports();
                  }
                },
        ),

          if (_selectedReportNeedsBreedScope) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedShowLetter == 'ALL'
                ? 'ALL'
                : (_availableShowLetters.contains(_selectedShowLetter)
                    ? _selectedShowLetter
                    : (_availableShowLetters.isNotEmpty
                        ? _availableShowLetters.first
                        : 'ALL')),
            decoration: InputDecoration(
              labelText: 'Show Letter',
              border: const OutlineInputBorder(),
              suffixIcon: _loadingShowLetters
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            items: [
              const DropdownMenuItem<String>(
                value: 'ALL',
                child: Text('All Shows'),
              ),
              ..._availableShowLetters.map(
                (letter) => DropdownMenuItem<String>(
                  value: letter,
                  child: Text(letter),
                ),
              ),
            ],
            onChanged: _loadingShowLetters
                ? null
                : (value) async {
                    if (value == null) return;
                    setState(() {
                      _selectedShowLetter = value;
                    });
                    await _loadBreedsForBreedScopedReports();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _availableBreeds.contains(_breedController.text.trim())
                ? _breedController.text.trim()
                : (_availableBreeds.isNotEmpty ? _availableBreeds.first : null),
            decoration: InputDecoration(
              labelText: 'Breed Name',
              border: const OutlineInputBorder(),
              suffixIcon: _loadingBreeds
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            items: _availableBreeds
                .map(
                  (breed) => DropdownMenuItem<String>(
                    value: breed,
                    child: Text(breed),
                  ),
                )
                .toList(),
            onChanged: _loadingBreeds || _availableBreeds.isEmpty
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _breedController.text = value;
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedScope,
            decoration: const InputDecoration(
              labelText: 'Scope',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'OPEN', child: Text('Open')),
              DropdownMenuItem(value: 'YOUTH', child: Text('Youth')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() {
                _selectedScope = value;
              });
              await _loadShowLetters();
              await _loadBreedsForBreedScopedReports();
            },
          ),
        ],

                const SizedBox(height: 16),
                _ReportInfoTile(
                  reportName: _selectedReportName == null
                      ? '-'
                      : _friendlyReportName(_selectedReportName),
                  status: artifact?.artifactStatus ?? 'not_generated',
                  generatedAt: artifact?.generatedAt,
                ),

                if (widget.reportsBlocked) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.orange.withOpacity(.22),
                      ),
                    ),
                    child: Text(
                      widget.reportsBlockedMessage ??
                          'Reports are blocked until results are complete.',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              onPressed: widget.loading ||
                      widget.reportsBlocked ||
                      _selectedReportName == null ||
                      (_selectedReportNeedsBreedScope &&
                          _breedController.text.trim().isEmpty)
                  ? null
                  : () => widget.onGenerate(
                        _selectedReportName!,
                        breedName: _selectedReportNeedsBreedScope
                            ? _breedController.text.trim()
                            : null,
                        scope: _selectedReportNeedsBreedScope
                            ? _selectedScope
                            : null,
                        showLetter: _selectedReportNeedsBreedScope
                            ? _selectedShowLetter
                            : null,
                      ),
              icon: widget.loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(widget.loading ? 'Generating…' : 'Generate'),
            ),
            OutlinedButton.icon(
              onPressed: _canDownload && _selectedReportName != null
                  ? () => widget.onDownload(_selectedReportName!)
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
            OutlinedButton.icon(
              onPressed: _canDownload && _selectedReportName != null
                  ? () => widget.onEmail(_selectedReportName!)
                  : null,
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReportInfoTile extends StatelessWidget {
  final String reportName;
  final String status;
  final String? generatedAt;

  const _ReportInfoTile({
    required this.reportName,
    required this.status,
    required this.generatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final isGenerated = status == 'generated';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isGenerated
            ? Colors.green.withOpacity(.06)
            : const Color(0xFF11285A).withOpacity(.04),
        border: Border.all(
          color: isGenerated
              ? Colors.green.withOpacity(.25)
              : Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reportName, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('Status: ${_friendlyStatus(status)}'),
          const SizedBox(height: 4),
          Text('Last generated: ${_fmt(generatedAt)}'),
        ],
      ),
    );
  }
}

class ResultsReadinessDto {
  final bool ready;
  final int missingPlacementCount;
  final int missingJudgeCount;
  final int duplicatePlacementGroupCount;

  ResultsReadinessDto({
    required this.ready,
    required this.missingPlacementCount,
    required this.missingJudgeCount,
    required this.duplicatePlacementGroupCount,
  });

  factory ResultsReadinessDto.fromJson(Map<String, dynamic> json) {
    return ResultsReadinessDto(
      ready: (json['ready'] ?? false) == true,
      missingPlacementCount:
          ((json['missing_placement_count'] ?? 0) as num).toInt(),
      missingJudgeCount:
          ((json['missing_judge_count'] ?? 0) as num).toInt(),
      duplicatePlacementGroupCount:
          ((json['duplicate_placement_group_count'] ?? 0) as num).toInt(),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF11285A),
            Color(0xFF0B1C43),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A623),
                ),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerateAllReportsDialog extends StatefulWidget {
  final List<ReportArtifactSummary> artifacts;
  final Future<void> Function(
    void Function(String artifactKey) onStarted,
    void Function(String artifactKey) onFinished,
    void Function(String artifactKey, Object error) onFailed,
  ) onRun;

  const _GenerateAllReportsDialog({
    required this.artifacts,
    required this.onRun,
  });

  @override
  State<_GenerateAllReportsDialog> createState() =>
      _GenerateAllReportsDialogState();
}

class _GenerateAllReportsDialogState extends State<_GenerateAllReportsDialog> {
  bool _finished = false;
  String? _error;

  final Set<String> _completed = {};
  final Set<String> _running = {};
  final Map<String, String> _failed = {};

  double get _progress {
    final done = _completed.length + _failed.length;
    return widget.artifacts.isEmpty ? 0 : done / widget.artifacts.length;
  }

  String _artifactKey(ReportArtifactSummary artifact) {
    final filePart = (artifact.fileName?.trim().isNotEmpty ?? false)
        ? ' • ${artifact.fileName!.trim()}'
        : '';
    return '${artifact.reportName}::${artifact.id}$filePart';
  }

  String _artifactLabel(ReportArtifactSummary artifact) {
    if (artifact.fileName?.trim().isNotEmpty ?? false) {
      return artifact.fileName!.trim();
    }
    return _friendlyReportName(artifact.reportName);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await widget.onRun(
        (reportName) {
          if (!mounted) return;
          setState(() {
            _running.add(reportName);
            _failed.remove(reportName);
          });
        },
        (reportName) {
          if (!mounted) return;
          setState(() {
            _running.remove(reportName);
            _completed.add(reportName);
          });
        },
        (reportName, error) {
          if (!mounted) return;
          setState(() {
            _running.remove(reportName);
            _failed[reportName] = error.toString();
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _finished = true;
        if (_failed.isNotEmpty) {
          _error = '${_failed.length} report(s) failed.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finished = true;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generating Report Artifacts'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: _finished ? 1 : _progress),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_completed.length + _failed.length} of ${widget.artifacts.length} report artifacts processed'
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.artifacts.length,
                itemBuilder: (context, index) {
                  final artifact = widget.artifacts[index];
                  final key = _artifactKey(artifact);
                  final isDone = _completed.contains(key);
                  final isRunning = _running.contains(key);
                  final failedMessage = _failed[key];

                  IconData icon;
                  Color color;
                  String status;

                  if (failedMessage != null) {
                    icon = Icons.error;
                    color = Colors.red;
                    status = 'Failed';
                  } else if (isDone) {
                    icon = Icons.check_circle;
                    color = Colors.green;
                    status = 'Done';
                  } else if (isRunning) {
                    icon = Icons.autorenew;
                    color = const Color(0xFFD4A623);
                    status = 'Running';
                  } else {
                    icon = Icons.schedule;
                    color = Colors.grey;
                    status = 'Queued';
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon, color: color),
                        title: Text(_artifactLabel(artifact)),
                        subtitle: Text(_friendlyReportName(artifact.reportName)),
                        trailing: Text(status),
                      ),
                      if (failedMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 40, bottom: 8),
                          child: Text(
                            failedMessage,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _finished ? () => Navigator.of(context).pop(true) : null,
          child: Text(_finished ? 'Close' : 'Working...'),
        ),
      ],
    );
  }
}

class _ExhibitorEmailTarget {
  final String exhibitorId;
  final String exhibitorName;
  final String email;

  const _ExhibitorEmailTarget({
    required this.exhibitorId,
    required this.exhibitorName,
    required this.email,
  });
}

class _ClubEmailTarget {
  final String clubName;
  final String breedName;
  final String scope; // OPEN / YOUTH
  final String showLetter;
  final String email;

  const _ClubEmailTarget({
    required this.clubName,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.email,
  });
}

class _ScopedReportTarget {
  final String breedName;
  final String scope;
  final String showLetter;

  const _ScopedReportTarget({
    required this.breedName,
    required this.scope,
    required this.showLetter,
  });
}

String _fmt(String? value) {
  final formatted = formatLocalDateTime(value);
  return formatted == '(not set)' || formatted == '(invalid date)' ? '-' : formatted;
}

String _friendlyStatus(String status) {
  switch (status) {
    case 'generated':
      return 'Generated';
    case 'queued':
      return 'Queued';
    case 'failed':
      return 'Failed';
    case 'warning':
      return 'Warning';
    default:
      return status.isEmpty ? '-' : status;
  }
}

String _friendlyReportName(String? key) {
  switch (key) {
    case 'arba_report':
      return 'ARBA Report';
    case 'judge_report':
      return 'Judge Report';
    case 'finalized_show_report':
      return 'Finalized Show Report';
    case 'details_by_breed':
      return 'Details by Breed';
    case 'newsletter_show_report':
      return 'Newsletter Show Report';
    case 'show_statistics':
      return 'Show Statistics';
    case 'overall_standings':
      return 'Overall Standings';
    case 'group_standings':
      return 'Group Standings';
    case 'variety_standings':
      return 'Variety Standings';
    case 'class_standings':
      return 'Class Standings';
    case 'fur_points':
      return 'Fur Points';
    case 'sweepstakes_report':
      return 'Sweepstakes Report';
    case 'breed_results_detail_report':
      return 'Breed Results Detail Report';
    case 'cavy_points':
      return 'Cavy Points';
    case 'commercial_points':
      return 'Commercial Points';
    case 'points_report_csv':
      return 'Points Report CSV';
    case 'control_sheet':
      return 'Control Sheet';
    case 'checkin_sheet':
      return 'Check-In Sheet';
    case 'exhibitor_report':
      return 'Exhibitor Report';
    case 'legs':
      return 'Legs';
    case 'commercial_class_points':
      return 'Commercial Class Points';
    case 'exh_by_breed':
      return 'Exhibitor by Breed';
    case 'exh_total_points':
      return 'Exhibitor Total Points';
    case 'newsletter':
      return 'Newsletter';
    case null:
      return '-';
    default:
      return key
          .split('_')
          .map(
            (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
          )
          .join(' ');
  }
}

class CloseoutDashboard {
  final DashboardEnvelope dashboard;
  final ResultsReadinessDto resultsReadiness;
  final LatestFinalize latestFinalize;
  final List<ReportArtifactSummary> reports;
  final List<DeliveryRunSummary> deliveries;
  final ArchiveSummary? latestArchive;

  CloseoutDashboard({
    required this.dashboard,
    required this.resultsReadiness,
    required this.latestFinalize,
    required this.reports,
    required this.deliveries,
    required this.latestArchive,
  });

  factory CloseoutDashboard.fromJson(Map<String, dynamic> json) {
    return CloseoutDashboard(
      dashboard: DashboardEnvelope.fromJson(
        Map<String, dynamic>.from(json['dashboard'] ?? const {}),
      ),
      resultsReadiness: ResultsReadinessDto.fromJson(
        Map<String, dynamic>.from(json['results_readiness'] ?? const {}),
      ),
      latestFinalize: LatestFinalize.fromJson(
        Map<String, dynamic>.from(json['latest_finalize'] ?? const {}),
      ),
      reports: List<Map<String, dynamic>>.from(
        (json['reports'] ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      ).map(ReportArtifactSummary.fromJson).toList(),
      deliveries: List<Map<String, dynamic>>.from(
        (json['deliveries'] ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      ).map(DeliveryRunSummary.fromJson).toList(),
      latestArchive: json['latest_archive'] == null ||
              (json['latest_archive'] as Map).isEmpty
          ? null
          : ArchiveSummary.fromJson(
              Map<String, dynamic>.from(json['latest_archive'] as Map),
            ),
    );
  }
}

class DashboardEnvelope {
  final String showId;
  final String showName;
  final int resultsVersion;
  final String? resultsLastChangedAt;
  final CloseoutStateDto closeout;

  DashboardEnvelope({
    required this.showId,
    required this.showName,
    required this.resultsVersion,
    required this.resultsLastChangedAt,
    required this.closeout,
  });

  factory DashboardEnvelope.fromJson(Map<String, dynamic> json) {
    return DashboardEnvelope(
      showId: (json['show_id'] ?? '') as String,
      showName: (json['show_name'] ?? '') as String,
      resultsVersion: ((json['results_version'] ?? 0) as num).toInt(),
      resultsLastChangedAt: json['results_last_changed_at'] as String?,
      closeout: CloseoutStateDto.fromJson(
        Map<String, dynamic>.from(json['closeout'] ?? const {}),
      ),
    );
  }
}

class CloseoutStateDto {
  final String syncStatus;
  final bool isPointsStale;
  final bool isReportsStale;
  final bool hasWarnings;
  final bool hasBlockingErrors;
  final bool isArchived;
  final int warningCount;
  final int errorCount;
  final int blockingErrorCount;
  final int reportsGeneratedCount;
  final String? finalizedAt;
  final String? pointsGeneratedAt;
  final String? reportsGeneratedAt;
  final String? validationCheckedAt;
  final String? resultsLastChangedAt;
  final String? lastFinalizeMessage;

  CloseoutStateDto({
    required this.syncStatus,
    required this.isPointsStale,
    required this.isReportsStale,
    required this.hasWarnings,
    required this.hasBlockingErrors,
    required this.isArchived,
    required this.warningCount,
    required this.errorCount,
    required this.blockingErrorCount,
    required this.reportsGeneratedCount,
    required this.finalizedAt,
    required this.pointsGeneratedAt,
    required this.reportsGeneratedAt,
    required this.validationCheckedAt,
    required this.resultsLastChangedAt,
    required this.lastFinalizeMessage,
  });

  factory CloseoutStateDto.fromJson(Map<String, dynamic> json) {
    return CloseoutStateDto(
      syncStatus: (json['sync_status'] ?? 'not_ready') as String,
      isPointsStale: (json['is_points_stale'] ?? true) as bool,
      isReportsStale: (json['is_reports_stale'] ?? true) as bool,
      hasWarnings: (json['has_warnings'] ?? false) as bool,
      hasBlockingErrors: (json['has_blocking_errors'] ?? false) as bool,
      isArchived: (json['is_archived'] ?? false) as bool,
      warningCount: ((json['warning_count'] ?? 0) as num).toInt(),
      errorCount: ((json['error_count'] ?? 0) as num).toInt(),
      blockingErrorCount:
          ((json['blocking_error_count'] ?? 0) as num).toInt(),
      reportsGeneratedCount:
          ((json['reports_generated_count'] ?? 0) as num).toInt(),
      finalizedAt: json['finalized_at'] as String?,
      pointsGeneratedAt: json['points_generated_at'] as String?,
      reportsGeneratedAt: json['reports_generated_at'] as String?,
      validationCheckedAt: json['validation_checked_at'] as String?,
      resultsLastChangedAt: json['results_last_changed_at'] as String?,
      lastFinalizeMessage: json['last_finalize_message'] as String?,
    );
  }
}

class LatestFinalize {
  final String? id;
  final String? runStatus;
  final String? startedAt;
  final String? completedAt;

  LatestFinalize({
    this.id,
    this.runStatus,
    this.startedAt,
    this.completedAt,
  });

  factory LatestFinalize.fromJson(Map<String, dynamic> json) {
    return LatestFinalize(
      id: json['id'] as String?,
      runStatus: json['run_status'] as String?,
      startedAt: json['started_at'] as String?,
      completedAt: json['completed_at'] as String?,
    );
  }
}

class ReportArtifactSummary {
  final String id;
  final String reportName;
  final String artifactStatus;
  final String? fileName;
  final String? storageBucket;
  final String? storagePath;
  final String? generatedAt;

  ReportArtifactSummary({
    required this.id,
    required this.reportName,
    required this.artifactStatus,
    this.fileName,
    this.storageBucket,
    this.storagePath,
    this.generatedAt,
  });

  factory ReportArtifactSummary.fromJson(Map<String, dynamic> json) {
    return ReportArtifactSummary(
      id: (json['id'] ?? '') as String,
      reportName: (json['report_name'] ?? '') as String,
      artifactStatus: (json['artifact_status'] ?? 'queued') as String,
      fileName: json['file_name'] as String?,
      storageBucket: json['storage_bucket'] as String?,
      storagePath: json['storage_path'] as String?,
      generatedAt: json['generated_at'] as String?,
    );
  }
}

class DeliveryRunSummary {
  final String id;
  final String deliveryType;
  final String deliveryStatus;

  DeliveryRunSummary({
    required this.id,
    required this.deliveryType,
    required this.deliveryStatus,
  });

  factory DeliveryRunSummary.fromJson(Map<String, dynamic> json) {
    return DeliveryRunSummary(
      id: (json['id'] ?? '') as String,
      deliveryType: (json['delivery_type'] ?? '') as String,
      deliveryStatus: (json['delivery_status'] ?? '') as String,
    );
  }
}

class ArchiveSummary {
  final String id;
  final int archiveVersion;
  final String archiveStatus;

  ArchiveSummary({
    required this.id,
    required this.archiveVersion,
    required this.archiveStatus,
  });

  factory ArchiveSummary.fromJson(Map<String, dynamic> json) {
    return ArchiveSummary(
      id: (json['id'] ?? '') as String,
      archiveVersion: ((json['archive_version'] ?? 0) as num).toInt(),
      archiveStatus: (json['archive_status'] ?? '') as String,
    );
  }
}