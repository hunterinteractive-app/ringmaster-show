// lib/screens/admin/show_closeout.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
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
import 'package:ringmaster_show/screens/admin/closeout/utils/club_report_grouping.dart';
import 'package:ringmaster_show/services/report_email_service.dart';
import 'package:ringmaster_show/services/app_session.dart';

import 'results/admin_results_entry_screen.dart';

import 'closeout/data/loaders/legs_report_loader.dart';
import 'closeout/data/loaders/exhibitor_report_loader.dart';
import 'closeout/data/loaders/sweepstakes_report_loader.dart';
import 'closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'closeout/data/loaders/unpaid_balances_report_loader.dart';
import 'closeout/data/loaders/paid_exhibitor_report_loader.dart';
import 'closeout/data/loaders/entered_exhibitors_contact_report_loader.dart';
import 'closeout/data/loaders/ribbon_payout_report_loader.dart';
import 'closeout/data/loaders/judge_report_loader.dart';
import 'closeout/data/loaders/breed_judged_totals_report_loader.dart';
import 'closeout/data/loaders/best_display_report_loader.dart';
import 'closeout/data/loaders/payback_report_loader.dart';
import 'closeout/data/loaders/details_by_breed_report_loader.dart';
import 'closeout/data/loaders/exhibitor_by_breed_report_loader.dart';

import 'closeout/pdf/builders/judge_report_pdf.dart';
import 'closeout/pdf/builders/breed_judged_totals_report_pdf.dart';
import 'closeout/pdf/builders/best_display_report_pdf.dart';
import 'closeout/pdf/builders/legs_report_pdf.dart';
import 'closeout/pdf/builders/exhibitor_report_pdf.dart';
import 'closeout/pdf/builders/sweepstakes_report_pdf.dart';
import 'closeout/pdf/builders/breed_results_detail_report_pdf.dart';
import 'closeout/pdf/builders/unpaid_balances_report_pdf.dart';
import 'closeout/pdf/builders/paid_exhibitor_report_pdf.dart';
import 'closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart';
import 'closeout/pdf/builders/ribbon_payout_report_pdf.dart';
import 'closeout/pdf/builders/payback_report_pdf.dart';
import 'closeout/pdf/builders/details_by_breed_report_pdf.dart';
import 'closeout/pdf/builders/exhibitor_by_breed_report_pdf.dart';

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

  bool _loadingMissingJudges = false;
  List<_MissingJudgeItem> _missingJudgeItems = [];
  bool _missingJudgesLoaded = false;

  bool _loadingDuplicatePlacements = false;
  List<_DuplicatePlacementGroupItem> _duplicatePlacementGroupItems = [];
  bool _duplicatePlacementsLoaded = false;

  List<_CloseoutSectionSummary> _closeoutSections = [];
  List<_CloseoutScope> _closeoutScopes = [];
  _CloseoutScope? _selectedCloseoutScope;
  bool _loadingCloseoutScopes = false;

  final Set<String> _customCloseoutSectionIds = {};

  bool _loading = true;
  bool _loadingReports = false;
  bool _reportsLoaded = false;
  bool _reportsSectionOpen = false;
  bool _generatingReport = false;
  String? _error;
  String? _reportsError;
  Uint8List? _reportLogoBytes;

  CloseoutDashboard? _dashboard;
  Map<String, List<String>> _cachedReportNamesByGroup = const {};
  LegsReportPdfBuilder? _legsBuilder;
  ExhibitorReportPdfBuilder? _exhibitorBuilder;
  UnpaidBalancesReportPdfBuilder? _unpaidBalancesBuilder;
  PaidExhibitorReportPdfBuilder? _paidExhibitorReportBuilder;
  EnteredExhibitorsContactReportPdf? _enteredExhibitorsContactBuilder;
  RibbonPayoutReportPdf? _ribbonPayoutBuilder;
  PaybackReportPdfBuilder? _paybackReportBuilder;

  static const Set<String> _exhibitorReportKeys = {'exhibitor_report', 'legs'};

  static const Set<String> _breedClubReportKeys = {
    'sweepstakes_report',
    'breed_results_detail_report',
  };

  static const Set<String> _stateClubReportKeys = {
    'details_by_breed',
    'exh_by_breed',
    'best_display_report',
  };
  static const int _stateClubSpeciesSplitVersion = 1;
  static const int _entrySpeciesQueryChunkSize = 100;

  static const Set<String> _clubReportKeys = {
    ..._breedClubReportKeys,
    ..._stateClubReportKeys,
  };

  static const Set<String> _arbaReportKeys = {'arba_report'};

  static const List<String> _reportDisplayOrder = [
    'arba_report',
    'exhibitor_report',
    'unpaid_balances_report',
    'paid_exhibitor_report',
    'entered_exhibitors_contact_report',
    'legs',
    'newsletter_show_report',
    'ribbon_payout_report',
    'payback_report',
    'exh_total_points',
    'exh_by_breed',
    'details_by_breed',
    'fur_points',
    'sweepstakes_report',
    'breed_results_detail_report',
    'cavy_points',
    'commercial_points',
    'judge_report',
    'breed_judged_totals_report',
    'best_display_report',
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

  String? _artifactMetaString(ReportArtifactSummary artifact, String key) {
    final value = artifact.metadata[key];
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  bool _artifactIsUsableCurrent(ReportArtifactSummary artifact) {
    return artifact.isCurrent &&
        artifact.artifactStatus == 'generated' &&
        (artifact.storageBucket?.isNotEmpty == true) &&
        (artifact.storagePath?.isNotEmpty == true);
  }

  String _norm(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _fileNameOf(ReportArtifactSummary artifact) {
    return (artifact.fileName ?? '').trim();
  }

  String _artifactProgressSubtitle(ReportArtifactSummary artifact) {
    final exhibitorName = _artifactMetaString(artifact, 'exhibitor_name');
    if (exhibitorName != null) return exhibitorName;

    final breedName = _artifactMetaString(artifact, 'breed_name');
    final clubName = _artifactMetaString(artifact, 'club_name');
    final sanctioningBody = _artifactMetaString(artifact, 'sanctioning_body');
    final scope = _artifactMetaString(artifact, 'scope');
    final letter = _artifactMetaString(artifact, 'show_letter');

    return [
      if (breedName != null) breedName,
      if (breedName == null && clubName != null) clubName,
      if (breedName == null && clubName == null && sanctioningBody != null)
        sanctioningBody,
      if (scope != null || letter != null)
        [if (scope != null) scope, if (letter != null) letter].join(' '),
    ].where((x) => x.trim().isNotEmpty).join(' • ');
  }

  String _artifactMatchText(ReportArtifactSummary artifact) {
    return _norm(
      [
        artifact.reportName,
        artifact.fileName ?? '',
        artifact.storagePath ?? '',
      ].join(' '),
    );
  }

  ReportArtifactSummary? _newestGeneratedArtifactWhere(
    String reportName,
    bool Function(ReportArtifactSummary artifact) test,
  ) {
    final matches =
        (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .where((r) => r.reportName == reportName)
            .where(_artifactIsUsableCurrent)
            .where(test)
            .toList()
          ..sort((a, b) {
            final aDt =
                DateTime.tryParse(a.generatedAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDt =
                DateTime.tryParse(b.generatedAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDt.compareTo(aDt);
          });

    return matches.isEmpty ? null : matches.first;
  }

  List<ReportArtifactSummary> _currentArtifactsForReportGroup(
    String reportName,
  ) {
    final artifacts =
        (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .where((artifact) => artifact.reportName == reportName)
            .where((artifact) => artifact.isCurrent)
            .where(_artifactMatchesSelectedScope)
            .toList()
          ..sort((a, b) {
            final aScope = (_artifactMetaString(a, 'scope') ?? '')
                .toUpperCase();
            final bScope = (_artifactMetaString(b, 'scope') ?? '')
                .toUpperCase();
            final scopeCmp = aScope.compareTo(bScope);
            if (scopeCmp != 0) return scopeCmp;

            final aLetter = (_artifactMetaString(a, 'show_letter') ?? '')
                .toUpperCase();
            final bLetter = (_artifactMetaString(b, 'show_letter') ?? '')
                .toUpperCase();
            final letterCmp = aLetter.compareTo(bLetter);
            if (letterCmp != 0) return letterCmp;

            final aGenerated =
                DateTime.tryParse(a.generatedAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bGenerated =
                DateTime.tryParse(b.generatedAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bGenerated.compareTo(aGenerated);
          });

    return artifacts;
  }

  List<ReportArtifactSummary> _queuedRemainingReportArtifacts() {
    return (_dashboard?.reports ?? const <ReportArtifactSummary>[])
        .where((r) => r.isCurrent)
        .where(
          (r) => r.artifactStatus == 'queued' || r.artifactStatus == 'failed',
        )
        .toList();
  }

  bool _artifactMatchesSelectedScope(ReportArtifactSummary artifact) {
    if (_selectedCloseoutScopeIsEntireShow) {
      return true;
    }

    final artifactScope = (artifact.metadata['scope_label'] ?? '')
        .toString()
        .trim();

    return artifactScope == _selectedCloseoutScopeLabel;
  }

  bool _artifactMatchesExhibitor(
    ReportArtifactSummary artifact,
    _ExhibitorEmailTarget exhibitor,
  ) {
    final artifactExhibitorId = _artifactMetaString(
      artifact,
      'exhibitor_id',
    )?.trim();

    return artifactExhibitorId != null &&
        artifactExhibitorId == exhibitor.exhibitorId;
  }

  bool _artifactMatchesClubTarget(
    ReportArtifactSummary artifact,
    _ClubEmailTarget target,
  ) {
    final targetBody = target.sanctioningBody.trim().toUpperCase();
    final targetSpecies = target.species.trim().toLowerCase();
    final artifactBreed = (_artifactMetaString(artifact, 'breed_name') ?? '')
        .trim()
        .toLowerCase();
    final artifactClub = (_artifactMetaString(artifact, 'club_name') ?? '')
        .trim()
        .toLowerCase();
    final artifactSpecies = (_artifactMetaString(artifact, 'species') ?? '')
        .trim()
        .toLowerCase();
    final artifactBody =
        (_artifactMetaString(artifact, 'sanctioning_body') ?? '')
            .trim()
            .toUpperCase();
    final artifactScope = (_artifactMetaString(artifact, 'scope') ?? '')
        .trim()
        .toUpperCase();
    final artifactShowLetter =
        (_artifactMetaString(artifact, 'show_letter') ?? '')
            .trim()
            .toUpperCase();

    if (artifactScope != target.scope.trim().toUpperCase()) return false;
    if (artifactShowLetter != target.showLetter.trim().toUpperCase())
      return false;

    // State clubs are section-wide, so they match all reports in that section.
    if (targetBody == 'STATE CLUB') {
      if (!_stateClubReportKeys.contains(artifact.reportName)) return false;
      if (artifactClub.isNotEmpty &&
          artifactClub != target.clubName.trim().toLowerCase()) {
        return false;
      }

      if (targetSpecies == 'rabbit' || targetSpecies == 'cavy') {
        return artifactSpecies == targetSpecies;
      }

      return true;
    }

    if (!_breedClubReportKeys.contains(artifact.reportName)) return false;
    if (artifactBody.isNotEmpty && artifactBody != targetBody) return false;
    if (artifactClub.isNotEmpty &&
        artifactClub != target.clubName.trim().toLowerCase()) {
      return false;
    }

    final targetBreed = displayBreedNameForClubReport(
      reportName: artifact.reportName,
      breedName: target.breedName,
      species: target.species,
    ).toLowerCase();

    if (artifactSpecies == 'cavy' || targetSpecies == 'cavy') {
      return artifactBreed == cavyClubReportBreedName.toLowerCase() &&
          targetBreed == cavyClubReportBreedName.toLowerCase();
    }

    return artifactBreed == targetBreed;
  }

  Future<List<_ExhibitorEmailTarget>> _loadExhibitorEmailTargets() async {
    final rows = await supabase
        .from('entries')
        .select('''
                exhibitor_id,
                exhibitors!entries_exhibitor_id_fkey (
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
      ..sort(
        (a, b) => a.exhibitorName.toLowerCase().compareTo(
          b.exhibitorName.toLowerCase(),
        ),
      );

    return list;
  }

  List<String> get _selectedCloseoutSectionIds {
    final scope = _selectedCloseoutScope;
    if (scope == null) return const [];

    if (scope.isCustom) {
      return _customCloseoutSectionIds.toList();
    }

    return scope.sectionIds;
  }

  String get _selectedCloseoutScopeLabel {
    return _selectedCloseoutScope?.label ?? 'Selected Scope';
  }

  bool get _selectedCloseoutScopeIsEntireShow {
    return _selectedCloseoutScope?.type == _CloseoutScopeType.entireShow ||
        _selectedCloseoutScope == null;
  }

  Future<List<_ClubEmailTarget>> _loadClubEmailTargets() async {
    final rows = await supabase
        .from('show_sanctions')
        .select('''
            club_name,
            breed_name,
            sweepstakes_email,
            sanctioning_body,
            section_id,
            show_sections!inner (
              id,
              kind,
              letter
            )
          ''')
        .eq('show_id', widget.showId);

    final stateClubContactRows = await supabase
        .from('state_club_report_contacts')
        .select('club_name, species, email')
        .eq('is_active', true);

    final stateClubContactsByClub = <String, List<_StateClubReportContact>>{};

    for (final raw in (stateClubContactRows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final clubName = (row['club_name'] ?? '').toString().trim();
      final species = (row['species'] ?? 'combined')
          .toString()
          .trim()
          .toLowerCase();
      final email = (row['email'] ?? '').toString().trim();

      if (clubName.isEmpty || email.isEmpty) continue;
      if (species != 'combined' && species != 'rabbit' && species != 'cavy') {
        continue;
      }

      final key = clubName.toLowerCase();
      stateClubContactsByClub.putIfAbsent(key, () => []);
      stateClubContactsByClub[key]!.add(
        _StateClubReportContact(
          clubName: clubName,
          species: species,
          email: email,
        ),
      );
    }

    final sanctionRows = (rows as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final speciesByBreedName = await _loadSpeciesByBreedName(
      sanctionRows
          .map((row) => (row['breed_name'] ?? '').toString().trim())
          .where((breed) => breed.isNotEmpty)
          .toSet()
          .toList(),
    );

    final out = <String, _ClubEmailTarget>{};

    for (final row in sanctionRows) {
      final sanctioningBody = (row['sanctioning_body'] ?? '')
          .toString()
          .trim()
          .toUpperCase();

      if (sanctioningBody == 'ARBA') continue;

      if (sanctioningBody != 'NATIONAL CLUB' &&
          sanctioningBody != 'STATE BREED CLUB' &&
          sanctioningBody != 'STATE CLUB') {
        continue;
      }

      final clubName = (row['club_name'] ?? '').toString().trim();
      final breedName = (row['breed_name'] ?? '').toString().trim();
      final email = (row['sweepstakes_email'] ?? '').toString().trim();

      final section = row['show_sections'] is Map
          ? Map<String, dynamic>.from(row['show_sections'] as Map)
          : <String, dynamic>{};

      final scope = (section['kind'] ?? '').toString().trim().toUpperCase();
      final showLetter = (section['letter'] ?? '')
          .toString()
          .trim()
          .toUpperCase();

      if (clubName.isEmpty || scope.isEmpty || showLetter.isEmpty) {
        continue;
      }

      // Breed is required for national + state breed clubs, but not for state clubs.
      if (sanctioningBody != 'STATE CLUB' && breedName.isEmpty) {
        continue;
      }

      if (sanctioningBody == 'STATE CLUB') {
        final contacts = stateClubContactsByClub[clubName.toLowerCase()];

        if (contacts != null && contacts.isNotEmpty) {
          for (final contact in contacts) {
            final key =
                '$sanctioningBody|$clubName|$scope|$showLetter|${contact.species}|${contact.email}';

            out[key] = _ClubEmailTarget(
              clubName: clubName,
              breedName: breedName,
              scope: scope,
              showLetter: showLetter,
              email: contact.email,
              species: contact.species,
              sanctioningBody: sanctioningBody,
            );
          }
          continue;
        }
      }

      if (email.isEmpty) continue;

      final species = sanctioningBody == 'STATE CLUB'
          ? 'combined'
          : _speciesForBreedName(breedName, speciesByBreedName);
      final targetBreedName =
          isCavyClubReportTarget(species: species, breedName: breedName)
          ? cavyClubReportBreedName
          : breedName;
      final key = sanctioningBody == 'STATE CLUB'
          ? '$sanctioningBody|$clubName|$scope|$showLetter|$species|$email'
          : '$sanctioningBody|$clubName|$targetBreedName|$scope|$showLetter|$email';

      out[key] = _ClubEmailTarget(
        clubName: clubName,
        breedName: targetBreedName,
        scope: scope,
        showLetter: showLetter,
        email: email,
        species: species,
        sanctioningBody: sanctioningBody,
      );
    }

    final list = out.values.toList()
      ..sort((a, b) {
        final bodyCmp = a.sanctioningBody.toLowerCase().compareTo(
          b.sanctioningBody.toLowerCase(),
        );
        if (bodyCmp != 0) return bodyCmp;

        final clubCmp = a.clubName.toLowerCase().compareTo(
          b.clubName.toLowerCase(),
        );
        if (clubCmp != 0) return clubCmp;

        final breedCmp = a.breedName.toLowerCase().compareTo(
          b.breedName.toLowerCase(),
        );
        if (breedCmp != 0) return breedCmp;

        final scopeCmp = a.scope.compareTo(b.scope);
        if (scopeCmp != 0) return scopeCmp;

        return a.showLetter.compareTo(b.showLetter);
      });

    return list;
  }

  Future<Map<String, String>> _loadSpeciesByBreedName(
    List<String> breedNames,
  ) async {
    final names = breedNames
        .map((breed) => breed.trim())
        .where((breed) => breed.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return const <String, String>{};

    final output = <String, String>{};

    for (final breed in names) {
      if (isKnownCavyBreed(breed)) {
        output[breed.toLowerCase()] = 'cavy';
      }
    }

    try {
      const chunkSize = 100;

      for (var start = 0; start < names.length; start += chunkSize) {
        final end = start + chunkSize > names.length
            ? names.length
            : start + chunkSize;
        final chunk = names.sublist(start, end);

        final rows = await supabase
            .from('breeds')
            .select('name, species')
            .inFilter('name', chunk);

        for (final raw in (rows as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          final breedName = (row['name'] ?? '').toString().trim();
          final species = normalizeClubReportSpecies(
            (row['species'] ?? '').toString(),
          );
          if (breedName.isNotEmpty && species.isNotEmpty) {
            output[breedName.toLowerCase()] = species;
          }
        }
      }
    } catch (_) {
      // Fall back to the built-in cavy SOP list if the breed catalog is not
      // available in this installation.
    }

    return output;
  }

  String _speciesForBreedName(
    String breedName,
    Map<String, String> speciesByBreedName,
  ) {
    final normalized = breedName.trim().toLowerCase();
    final species = normalizeClubReportSpecies(speciesByBreedName[normalized]);
    if (species.isNotEmpty) return species;
    return isKnownCavyBreed(breedName) ? 'cavy' : '';
  }

  Future<String?> _loadArbaReportEmailTarget() async {
    final rows = await supabase
        .from('show_sanctions')
        .select('sweepstakes_email, sanctioning_body')
        .eq('show_id', widget.showId)
        .ilike('sanctioning_body', 'ARBA');

    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final email = (row['sweepstakes_email'] ?? '').toString().trim();
      if (email.isNotEmpty) return email;
    }

    return null;
  }

  Future<void> _loadCloseoutScopes() async {
    if (mounted) {
      setState(() {
        _loadingCloseoutScopes = true;
      });
    } else {
      _loadingCloseoutScopes = true;
    }
    try {
      final rows = await supabase.rpc(
        'get_closeout_scope_sections',
        params: {'p_show_id': widget.showId},
      );

      final sections = (rows as List)
          .map(
            (raw) => _CloseoutSectionSummary.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList();

      final enabledSections = sections.where((s) => s.isEnabled).toList();

      final scopes = <_CloseoutScope>[
        _CloseoutScope(
          type: _CloseoutScopeType.entireShow,
          label: 'Entire Show',
          description: 'Finalize and report all enabled sections.',
          sectionIds: enabledSections.map((s) => s.sectionId).toList(),
        ),
      ];

      final rabbitAllBreed = enabledSections
          .where((s) => s.isAllBreed && s.species.contains('rabbit'))
          .toList();

      if (rabbitAllBreed.isNotEmpty) {
        scopes.add(
          _CloseoutScope(
            type: _CloseoutScopeType.rabbitAllBreed,
            label: 'Rabbit All Breed',
            description:
                '${rabbitAllBreed.length} all-breed rabbit section${rabbitAllBreed.length == 1 ? '' : 's'}.',
            sectionIds: rabbitAllBreed.map((s) => s.sectionId).toList(),
          ),
        );
      }

      final cavyAllBreed = enabledSections
          .where((s) => s.isAllBreed && s.species.contains('cavy'))
          .toList();

      if (cavyAllBreed.isNotEmpty) {
        scopes.add(
          _CloseoutScope(
            type: _CloseoutScopeType.cavyAllBreed,
            label: 'Cavy All Breed',
            description:
                '${cavyAllBreed.length} all-breed cavy section${cavyAllBreed.length == 1 ? '' : 's'}.',
            sectionIds: cavyAllBreed.map((s) => s.sectionId).toList(),
          ),
        );
      }

      final specialtySections = enabledSections
          .where((s) => s.isSpecialty)
          .toList();

      if (specialtySections.isNotEmpty) {
        scopes.add(
          _CloseoutScope(
            type: _CloseoutScopeType.specialty,
            label: 'Single Breed / Specialty',
            description:
                '${specialtySections.length} limited-breed section${specialtySections.length == 1 ? '' : 's'}.',
            sectionIds: specialtySections.map((s) => s.sectionId).toList(),
          ),
        );
      }

      scopes.add(
        _CloseoutScope(
          type: _CloseoutScopeType.custom,
          label: 'Custom Sections',
          description: 'Choose exactly which sections to finalize or send.',
          sectionIds: const [],
        ),
      );

      if (!mounted) return;

      setState(() {
        _closeoutSections = sections;
        _closeoutScopes = scopes;
        _customCloseoutSectionIds.removeWhere(
          (id) => !enabledSections.any((section) => section.sectionId == id),
        );

        final currentType = _selectedCloseoutScope?.type;
        final stillExists =
            currentType != null &&
            scopes.any((scope) => scope.type == currentType);
        _selectedCloseoutScope = stillExists
            ? scopes.firstWhere((scope) => scope.type == currentType)
            : scopes.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _closeoutSections = [];
        _closeoutScopes = [
          const _CloseoutScope(
            type: _CloseoutScopeType.entireShow,
            label: 'Entire Show',
            description: 'Finalize and report all enabled sections.',
            sectionIds: [],
          ),
          const _CloseoutScope(
            type: _CloseoutScopeType.custom,
            label: 'Custom Sections',
            description: 'Choose exactly which sections to finalize or send.',
            sectionIds: [],
          ),
        ];
        _selectedCloseoutScope ??= _closeoutScopes.first;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed loading finalize scopes: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingCloseoutScopes = false;
        });
      } else {
        _loadingCloseoutScopes = false;
      }
    }
  }

  Future<T> _loadCloseoutStep<T>(
    String label,
    Future<T> Function() action,
  ) async {
    try {
      return await _timedCloseoutLoad(label, action);
    } catch (e, st) {
      Error.throwWithStackTrace(Exception('Failed loading $label: $e'), st);
    }
  }

  Future<T> _timedCloseoutLoad<T>(
    String label,
    Future<T> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      debugPrint(
        '[Closeout:${widget.showId}] $label loaded in ${stopwatch.elapsedMilliseconds}ms',
      );
      return result;
    } catch (e) {
      debugPrint(
        '[Closeout:${widget.showId}] $label failed after ${stopwatch.elapsedMilliseconds}ms: $e',
      );
      rethrow;
    }
  }

  Future<void> _syncClubDeliveryMetadata({String? latestFinalizeRunId}) async {
    await _loadCloseoutStep(
      'club delivery targets',
      () => supabase.rpc(
        'prepare_club_delivery_targets',
        params: {'p_show_id': widget.showId},
      ),
    );

    await _loadCloseoutStep(
      'combined cavy club report artifacts',
      () => _ensureCombinedCavyClubReportArtifacts(
        latestFinalizeRunId: latestFinalizeRunId,
      ),
    );

    await _loadCloseoutStep(
      'state club species artifact sync',
      () => _ensureStateClubSpeciesArtifacts(
        latestFinalizeRunId: latestFinalizeRunId,
      ),
    );

    await _loadCloseoutStep(
      'combined cavy club report artifact refresh',
      () => _ensureCombinedCavyClubReportArtifacts(
        latestFinalizeRunId: latestFinalizeRunId,
      ),
    );
  }

  Future<void> _ensureCombinedCavyClubReportArtifacts({
    String? latestFinalizeRunId,
  }) async {
    final rows = await supabase
        .from('show_report_artifacts')
        .select('id, finalize_run_id, report_name, artifact_status, metadata')
        .eq('show_id', widget.showId)
        .eq('is_current', true)
        .inFilter('report_name', _clubReportKeys.toList());

    final artifacts = (rows as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (artifacts.isEmpty) return;

    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final artifact in artifacts) {
      final reportName = (artifact['report_name'] ?? '').toString();
      final metadata = artifact['metadata'] is Map
          ? Map<String, dynamic>.from(artifact['metadata'] as Map)
          : <String, dynamic>{};
      final key = cavyClubReportGroupKey(
        reportName: reportName,
        metadata: metadata,
      );

      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(artifact);
    }

    for (final group in grouped.values) {
      if (group.isEmpty) continue;

      group.sort((a, b) {
        final rankCmp = _cavyClubArtifactKeepRank(
          a,
        ).compareTo(_cavyClubArtifactKeepRank(b));
        if (rankCmp != 0) return rankCmp;

        return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
      });

      final keep = group.first;
      await _resetCombinedCavyClubReportArtifactIfNeeded(
        keep,
        latestFinalizeRunId: latestFinalizeRunId,
      );

      for (final duplicate in group.skip(1)) {
        await supabase
            .from('show_report_artifacts')
            .update({
              'is_current': false,
              'superseded_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', (duplicate['id'] ?? '').toString());
      }
    }
  }

  int _cavyClubArtifactKeepRank(Map<String, dynamic> artifact) {
    final reportName = (artifact['report_name'] ?? '').toString();
    final metadata = artifact['metadata'] is Map
        ? Map<String, dynamic>.from(artifact['metadata'] as Map)
        : <String, dynamic>{};
    final normalized = isNormalizedCavyClubReportMetadata(
      reportName: reportName,
      metadata: metadata,
    );
    final status = (artifact['artifact_status'] ?? '').toString();

    if (normalized && status == 'generated') return 0;
    if (normalized && status == 'queued') return 1;
    if (normalized) return 2;
    if (status == 'generated') return 3;
    return 4;
  }

  Future<void> _resetCombinedCavyClubReportArtifactIfNeeded(
    Map<String, dynamic> artifact, {
    String? latestFinalizeRunId,
  }) async {
    final artifactId = (artifact['id'] ?? '').toString();
    if (artifactId.isEmpty) return;

    final reportName = (artifact['report_name'] ?? '').toString();
    final metadata = artifact['metadata'] is Map
        ? Map<String, dynamic>.from(artifact['metadata'] as Map)
        : <String, dynamic>{};
    final normalizedMetadata = normalizedClubReportMetadata(
      reportName: reportName,
      metadata: metadata,
    );

    final isAlreadyNormalized = isNormalizedCavyClubReportMetadata(
      reportName: reportName,
      metadata: metadata,
    );
    final needsRegeneration = !isAlreadyNormalized;
    final resolvedFinalizeRunId = _resolveStateClubFinalizeRunId(
      source: artifact,
      latestFinalizeRunId: latestFinalizeRunId,
    );

    await supabase
        .from('show_report_artifacts')
        .update({
          if (resolvedFinalizeRunId != null)
            'finalize_run_id': resolvedFinalizeRunId,
          if (needsRegeneration) ...{
            'artifact_status': 'queued',
            'storage_bucket': null,
            'storage_path': null,
            'file_name': null,
            'mime_type': null,
            'file_size_bytes': null,
            'generated_at': null,
            'superseded_at': null,
            'error_count': 0,
            'warning_count': 0,
          },
          'metadata': normalizedMetadata,
        })
        .eq('id', artifactId);
  }

  Future<void> _ensureStateClubSpeciesArtifacts({
    String? latestFinalizeRunId,
  }) async {
    final rows = await supabase
        .from('show_report_artifacts')
        .select('id, finalize_run_id, report_name, artifact_status, metadata')
        .eq('show_id', widget.showId)
        .eq('is_current', true)
        .inFilter('report_name', _stateClubReportKeys.toList());

    final artifacts = (rows as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (artifacts.isEmpty) return;

    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final artifact in artifacts) {
      final metadata = artifact['metadata'] is Map
          ? Map<String, dynamic>.from(artifact['metadata'] as Map)
          : <String, dynamic>{};
      final key = _stateClubArtifactBaseKey(
        (artifact['report_name'] ?? '').toString(),
        metadata,
      );

      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(artifact);
    }

    for (final group in grouped.values) {
      if (group.isEmpty) continue;

      final species = <String>{};
      for (final artifact in group) {
        final metadata = artifact['metadata'] is Map
            ? Map<String, dynamic>.from(artifact['metadata'] as Map)
            : <String, dynamic>{};
        species.addAll(await _loadStateClubSpeciesForArtifact(metadata));
      }

      final targetSpecies = [
        'rabbit',
        'cavy',
      ].where((value) => species.contains(value)).toList();

      if (targetSpecies.isEmpty) continue;

      final existingBySpecies = <String, Map<String, dynamic>>{};
      final withoutSpecies = <Map<String, dynamic>>[];

      for (final artifact in group) {
        final metadata = artifact['metadata'] is Map
            ? Map<String, dynamic>.from(artifact['metadata'] as Map)
            : <String, dynamic>{};
        final artifactSpecies = _normalizeStateClubSpecies(
          (metadata['species'] ?? '').toString(),
        );

        if (artifactSpecies.isEmpty) {
          withoutSpecies.add(artifact);
        } else {
          existingBySpecies.putIfAbsent(artifactSpecies, () => artifact);
        }
      }

      for (final species in targetSpecies) {
        final existingArtifact = existingBySpecies[species];
        if (existingArtifact != null) {
          if (_stateClubArtifactNeedsSpeciesSplitRefresh(existingArtifact)) {
            await _resetStateClubArtifactForSpecies(
              existingArtifact,
              species,
              latestFinalizeRunId: latestFinalizeRunId,
            );
          }
          continue;
        }

        await _insertStateClubArtifactForSpecies(
          group.first,
          species,
          latestFinalizeRunId: latestFinalizeRunId,
        );
      }

      for (final artifact in withoutSpecies) {
        await supabase
            .from('show_report_artifacts')
            .update({
              'is_current': false,
              'superseded_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', (artifact['id'] ?? '').toString());
      }

      for (final entry in existingBySpecies.entries) {
        if (targetSpecies.contains(entry.key)) continue;
        await supabase
            .from('show_report_artifacts')
            .update({
              'is_current': false,
              'superseded_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', (entry.value['id'] ?? '').toString());
      }
    }
  }

  String _stateClubArtifactBaseKey(
    String reportName,
    Map<String, dynamic> metadata,
  ) {
    final normalizedReportName = reportName.trim();
    if (!_stateClubReportKeys.contains(normalizedReportName)) return '';

    final scope = (metadata['scope'] ?? '').toString().trim().toUpperCase();
    final showLetter = (metadata['show_letter'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final clubName = (metadata['club_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final sectionId = (metadata['section_id'] ?? '').toString().trim();

    if (scope.isEmpty || showLetter.isEmpty) return '';

    return [
      normalizedReportName,
      scope,
      showLetter,
      clubName,
      sectionId,
    ].join('|');
  }

  Future<void> _resetStateClubArtifactForSpecies(
    Map<String, dynamic> artifact,
    String species, {
    String? latestFinalizeRunId,
  }) async {
    final artifactId = (artifact['id'] ?? '').toString();
    if (artifactId.isEmpty) return;

    final metadata = artifact['metadata'] is Map
        ? Map<String, dynamic>.from(artifact['metadata'] as Map)
        : <String, dynamic>{};
    final resolvedFinalizeRunId = _resolveStateClubFinalizeRunId(
      source: artifact,
      latestFinalizeRunId: latestFinalizeRunId,
    );

    await supabase
        .from('show_report_artifacts')
        .update({
          if (resolvedFinalizeRunId != null)
            'finalize_run_id': resolvedFinalizeRunId,
          'artifact_status': 'queued',
          'storage_bucket': null,
          'storage_path': null,
          'file_name': null,
          'mime_type': null,
          'file_size_bytes': null,
          'generated_at': null,
          'superseded_at': null,
          'error_count': 0,
          'warning_count': 0,
          'metadata': {
            ...metadata,
            'species': species,
            'species_split_version': _stateClubSpeciesSplitVersion,
          },
        })
        .eq('id', artifactId);
  }

  Future<void> _insertStateClubArtifactForSpecies(
    Map<String, dynamic> source,
    String species, {
    String? latestFinalizeRunId,
  }) async {
    final metadata = source['metadata'] is Map
        ? Map<String, dynamic>.from(source['metadata'] as Map)
        : <String, dynamic>{};
    final resolvedFinalizeRunId = _resolveStateClubFinalizeRunId(
      source: source,
      latestFinalizeRunId: latestFinalizeRunId,
    );

    await supabase.from('show_report_artifacts').insert({
      'show_id': widget.showId,
      'finalize_run_id': resolvedFinalizeRunId,
      'report_name': (source['report_name'] ?? '').toString(),
      'artifact_status': 'queued',
      'is_current': true,
      'metadata': {
        ...metadata,
        'species': species,
        'species_split_version': _stateClubSpeciesSplitVersion,
      },
    });
  }

  String? _resolveStateClubFinalizeRunId({
    required Map<String, dynamic> source,
    String? latestFinalizeRunId,
  }) {
    final latest = (latestFinalizeRunId ?? '').trim();
    if (latest.isNotEmpty) return latest;

    final sourceRunId = (source['finalize_run_id'] ?? '').toString().trim();
    return sourceRunId.isEmpty ? null : sourceRunId;
  }

  bool _stateClubArtifactNeedsSpeciesSplitRefresh(
    Map<String, dynamic> artifact,
  ) {
    final metadata = artifact['metadata'] is Map
        ? Map<String, dynamic>.from(artifact['metadata'] as Map)
        : <String, dynamic>{};
    final versionValue = metadata['species_split_version'];
    final version = versionValue is int
        ? versionValue
        : int.tryParse((versionValue ?? '').toString()) ?? 0;
    return version < _stateClubSpeciesSplitVersion;
  }

  Future<Set<String>> _loadStateClubSpeciesForArtifact(
    Map<String, dynamic> metadata,
  ) async {
    final scope = (metadata['scope'] ?? '').toString().trim().toUpperCase();
    final showLetter = (metadata['show_letter'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    if (scope.isEmpty || showLetter.isEmpty) return const <String>{};

    final sectionId =
        (metadata['section_id'] ?? '').toString().trim().isNotEmpty
        ? (metadata['section_id'] ?? '').toString().trim()
        : await _loadSectionIdForScope(scope, showLetter);

    if (sectionId.isEmpty) return const <String>{};

    final results = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': sectionId,
        'p_show_letter': showLetter,
      },
    );

    final rows = (results as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where(_stateClubSpeciesRowCounts)
        .toList();

    final species = <String>{};
    final missingSpeciesEntryIds = <String>{};

    for (final row in rows) {
      final rowSpecies = _normalizeStateClubSpecies(
        _firstRowText(row, const [
          'species',
          'animal_species',
          'entry_species',
        ]),
      );

      if (rowSpecies.isNotEmpty) {
        species.add(rowSpecies);
        continue;
      }

      final entryId = _firstRowText(row, const ['entry_id', 'id']);
      if (entryId.isNotEmpty) missingSpeciesEntryIds.add(entryId);
    }

    final entryRows = await _loadEntrySpeciesRowsByIds(
      missingSpeciesEntryIds.toList(),
    );

    for (final row in entryRows) {
      final entrySpecies = _normalizeStateClubSpecies(
        (row['species'] ?? '').toString(),
      );
      if (entrySpecies.isNotEmpty) species.add(entrySpecies);
    }

    return species;
  }

  Future<List<Map<String, dynamic>>> _loadEntrySpeciesRowsByIds(
    List<String> entryIds,
  ) async {
    final ids = entryIds.toSet().where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return const <Map<String, dynamic>>[];

    final allRows = <Map<String, dynamic>>[];

    for (
      var start = 0;
      start < ids.length;
      start += _entrySpeciesQueryChunkSize
    ) {
      final end = start + _entrySpeciesQueryChunkSize > ids.length
          ? ids.length
          : start + _entrySpeciesQueryChunkSize;
      final chunk = ids.sublist(start, end);

      final entryRows = await supabase
          .from('entries')
          .select('id, species')
          .eq('show_id', widget.showId)
          .inFilter('id', chunk);

      allRows.addAll(
        (entryRows as List).map((raw) => Map<String, dynamic>.from(raw as Map)),
      );
    }

    return allRows;
  }

  Future<String> _loadSectionIdForScope(String scope, String showLetter) async {
    final row = await supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', widget.showId)
        .eq('kind', scope.toLowerCase())
        .eq('letter', showLetter)
        .eq('is_enabled', true)
        .maybeSingle();

    if (row == null) return '';
    return (Map<String, dynamic>.from(row)['id'] ?? '').toString().trim();
  }

  bool _stateClubSpeciesRowCounts(Map<String, dynamic> row) {
    if (_rowBool(row['is_test'])) return false;
    if ((row['scratched_at'] ?? '').toString().trim().isNotEmpty) return false;
    if (_rowBool(row['is_disqualified'])) return false;
    if (!_rowBool(row['is_shown'], fallback: true)) return false;

    final status = _firstRowText(row, const [
      'result_status',
      'status',
    ]).toLowerCase();
    final dqReason = _firstRowText(row, const [
      'disqualified_reason',
    ]).toLowerCase();
    final combined = '$status $dqReason';

    if (combined.contains('no show') ||
        combined.contains('scratch') ||
        combined.contains('disqual') ||
        combined.contains('wrong sex') ||
        combined.contains('wrong variety') ||
        combined.contains('wrong class') ||
        combined.contains('overweight') ||
        combined.contains('unworthy')) {
      return false;
    }

    return true;
  }

  String _normalizeStateClubSpecies(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'rabbit' || normalized == 'cavy' ? normalized : '';
  }

  String _firstRowText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _rowBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text == 'true' || text == 't' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == 'f' || text == '0' || text == 'no') {
      return false;
    }
    return fallback;
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
        final status = (row['result_status'] ?? row['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final dqReason = (row['disqualified_reason'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final combinedStatus = '$status $dqReason';
        final excludedStatus =
            combinedStatus.contains('no show') ||
            combinedStatus.contains('scratch') ||
            combinedStatus.contains('disqual') ||
            combinedStatus.contains('wrong sex') ||
            combinedStatus.contains('wrong variety') ||
            combinedStatus.contains('wrong class') ||
            combinedStatus.contains('overweight') ||
            combinedStatus.contains('unworthy');
        final placement = (row['placement'] ?? '').toString().trim();

        final isEligibleForPlacement =
            scratchedAt.isEmpty &&
            isShown &&
            !isDisqualified &&
            !excludedStatus;

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
        final sectionCmp = a.sectionLabel.toLowerCase().compareTo(
          b.sectionLabel.toLowerCase(),
        );
        if (sectionCmp != 0) return sectionCmp;

        final breedCmp = a.breedName.toLowerCase().compareTo(
          b.breedName.toLowerCase(),
        );
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

  Future<void> _loadMissingJudges() async {
    if (_loadingMissingJudges) return;

    setState(() {
      _loadingMissingJudges = true;
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

      final items = <_MissingJudgeItem>[];

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);

        final scratchedAt = (row['scratched_at'] ?? '').toString().trim();
        final isShown = row['is_shown'] != false;
        final isDisqualified = row['is_disqualified'] == true;
        final status = (row['result_status'] ?? row['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final dqReason = (row['disqualified_reason'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final combinedStatus = '$status $dqReason';
        final excludedStatus =
            combinedStatus.contains('no show') ||
            combinedStatus.contains('scratch') ||
            combinedStatus.contains('disqual') ||
            combinedStatus.contains('wrong sex') ||
            combinedStatus.contains('wrong variety') ||
            combinedStatus.contains('wrong class') ||
            combinedStatus.contains('overweight') ||
            combinedStatus.contains('unworthy');
        final judgeId = (row['judged_by_show_judge_id'] ?? '')
            .toString()
            .trim();

        final isEligible =
            scratchedAt.isEmpty &&
            isShown &&
            !isDisqualified &&
            !excludedStatus;

        if (!isEligible) continue;
        if (judgeId.isNotEmpty) continue;

        items.add(
          _MissingJudgeItem(
            entryId: (row['entry_id'] ?? '').toString(),
            sectionLabel: (row['section_label'] ?? 'Section').toString(),
            breedName: (row['breed_name'] ?? '').toString(),
            groupName: null,
            varietyName: (row['variety_name'] ?? '').toString(),
            className: (row['class_name'] ?? '').toString(),
            sex: (row['sex'] ?? '').toString(),
            tattoo: (row['tattoo'] ?? '').toString(),
            exhibitorLabel: (row['exhibitor_label'] ?? '').toString(),
          ),
        );
      }

      setState(() {
        _missingJudgeItems = items;
        _missingJudgesLoaded = true;
      });
    } finally {
      setState(() {
        _loadingMissingJudges = false;
      });
    }
  }

  Future<void> _loadDuplicatePlacementGroups() async {
    if (_loadingDuplicatePlacements) return;

    setState(() {
      _loadingDuplicatePlacements = true;
    });

    try {
      const pageSize = 1000;
      final rows = <Map<String, dynamic>>[];
      var from = 0;

      while (true) {
        final batch = await supabase
            .rpc(
              'report_results_entry_rows',
              params: {
                'p_show_id': widget.showId,
                'p_section_id': null,
                'p_show_letter': null,
              },
            )
            .range(from, from + pageSize - 1);

        final page = (batch as List)
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();

        rows.addAll(page);

        if (page.length < pageSize) break;
        from += pageSize;
      }

      final grouped = <String, List<_DuplicatePlacementEntryItem>>{};
      final labels = <String, _DuplicatePlacementGroupItem>{};

      String clean(dynamic value) => (value ?? '').toString().trim();
      String norm(dynamic value) => clean(value).toLowerCase();

      String resolvedBreed(Map<String, dynamic> row) {
        final breed = clean(row['breed']);
        if (breed.isNotEmpty) return breed;
        return clean(row['breed_name']);
      }

      String resolvedVariety(Map<String, dynamic> row) {
        final variety = clean(row['variety']);
        if (variety.isNotEmpty) return variety;
        return clean(row['variety_name']);
      }

      String resolvedSectionLabel(Map<String, dynamic> row) {
        final label = clean(row['section_label']);
        if (label.isNotEmpty) return label;

        final kind = clean(row['section_kind']);
        final letter = clean(row['show_letter']);
        final parts = <String>[
          if (kind.isNotEmpty) kind[0].toUpperCase() + kind.substring(1),
          if (letter.isNotEmpty) letter.toUpperCase(),
        ];

        return parts.isEmpty ? 'Section' : parts.join(' ');
      }

      bool isEligibleForPlacement(Map<String, dynamic> row) {
        final scratchedAt = clean(row['scratched_at']);
        final isShown = row['is_shown'] != false;
        final isDisqualified = row['is_disqualified'] == true;
        final status = clean(row['result_status']).toLowerCase();
        final dqReason = clean(row['disqualified_reason']).toLowerCase();
        final combinedStatus = '$status $dqReason';

        if (scratchedAt.isNotEmpty) return false;
        if (!isShown) return false;
        if (isDisqualified) return false;
        if (combinedStatus.contains('no show')) return false;
        if (combinedStatus.contains('scratch')) return false;
        if (combinedStatus.contains('disqual')) return false;
        if (combinedStatus.contains('wrong sex')) return false;
        if (combinedStatus.contains('wrong variety')) return false;
        if (combinedStatus.contains('wrong class')) return false;
        if (combinedStatus.contains('overweight')) return false;
        if (combinedStatus.contains('unworthy')) return false;

        return true;
      }

      for (final row in rows) {
        final placement = clean(row['placement']);
        if (placement.isEmpty) continue;
        if (!isEligibleForPlacement(row)) continue;

        final sectionId = clean(row['section_id']);
        final sectionLabel = resolvedSectionLabel(row);
        final breedName = resolvedBreed(row);
        final varietyName = resolvedVariety(row);
        final className = clean(row['class_name']);
        final sex = clean(row['sex']);
        final resultTypeKey = row['is_fur'] == true ? 'fur_wool' : 'normal';

        final key = [
          norm(sectionId),
          norm(breedName),
          norm(varietyName),
          norm(className),
          norm(sex),
          resultTypeKey,
          norm(placement),
        ].join('|');

        final entryId = clean(row['entry_id']).isNotEmpty
            ? clean(row['entry_id'])
            : clean(row['id']);

        grouped.putIfAbsent(key, () => []);
        grouped[key]!.add(
          _DuplicatePlacementEntryItem(
            entryId: entryId,
            tattoo: clean(row['tattoo']),
            exhibitorLabel: clean(row['exhibitor_label']),
          ),
        );

        labels[key] = _DuplicatePlacementGroupItem(
          sectionLabel: sectionLabel,
          breedName: breedName,
          groupName: clean(row['group_name']).isEmpty
              ? null
              : clean(row['group_name']),
          varietyName: varietyName.isEmpty ? null : varietyName,
          className: resultTypeKey == 'fur_wool' && className.isEmpty
              ? 'Fur / Wool'
              : className,
          sex: sex,
          placement: placement,
          entries: const [],
        );
      }

      final items = <_DuplicatePlacementGroupItem>[];

      for (final entry in grouped.entries) {
        final uniqueByEntryId = <String, _DuplicatePlacementEntryItem>{};

        for (final item in entry.value) {
          final key = item.entryId.isNotEmpty
              ? item.entryId
              : '${item.tattoo}|${item.exhibitorLabel}';
          uniqueByEntryId[key] = item;
        }

        final uniqueEntries = uniqueByEntryId.values.toList();
        if (uniqueEntries.length <= 1) continue;

        final label = labels[entry.key];
        if (label == null) continue;

        uniqueEntries.sort(
          (a, b) => a.tattoo.toLowerCase().compareTo(b.tattoo.toLowerCase()),
        );

        items.add(
          _DuplicatePlacementGroupItem(
            sectionLabel: label.sectionLabel,
            breedName: label.breedName,
            groupName: label.groupName,
            varietyName: label.varietyName,
            className: label.className,
            sex: label.sex,
            placement: label.placement,
            entries: uniqueEntries,
          ),
        );
      }

      items.sort((a, b) {
        final sectionCmp = a.sectionLabel.toLowerCase().compareTo(
          b.sectionLabel.toLowerCase(),
        );
        if (sectionCmp != 0) return sectionCmp;

        final breedCmp = a.breedName.toLowerCase().compareTo(
          b.breedName.toLowerCase(),
        );
        if (breedCmp != 0) return breedCmp;

        final varietyCmp = (a.varietyName ?? '').toLowerCase().compareTo(
          (b.varietyName ?? '').toLowerCase(),
        );
        if (varietyCmp != 0) return varietyCmp;

        final classCmp = a.className.toLowerCase().compareTo(
          b.className.toLowerCase(),
        );
        if (classCmp != 0) return classCmp;

        final sexCmp = a.sex.toLowerCase().compareTo(b.sex.toLowerCase());
        if (sexCmp != 0) return sexCmp;

        return a.placement.compareTo(b.placement);
      });

      if (!mounted) return;
      setState(() {
        _duplicatePlacementGroupItems = items;
        _duplicatePlacementsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed loading duplicate placements: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingDuplicatePlacements = false;
        });
      }
    }
  }

  Future<void> _sendExhibitorArtifactsEmail({
    required List<ReportArtifactSummary> artifacts,
    required String to,
    String? subject,
    String? message,
    bool allowLegs = false, // 👈 Leg Change
  }) async {
    if (artifacts.isEmpty) {
      throw Exception('No reports provided for exhibitor email send.');
    }

    final service = ReportEmailService();

    await service.sendExhibitorReportEmail(
      showId: widget.showId,
      artifactIds: artifacts.map((a) => a.id).toList(),
      to: to,
      subject: subject,
      message: message,
      allowLegs: allowLegs,
    );
  }

  Future<void> _sendClubArtifactsEmail({
    required List<ReportArtifactSummary> artifacts,
    required String to,
    String? subject,
    String? message,
  }) async {
    if (artifacts.isEmpty) {
      throw Exception('No reports provided for club email send.');
    }

    final service = ReportEmailService();

    await service.sendClubReportEmail(
      showId: widget.showId,
      artifactIds: artifacts.map((a) => a.id).toList(),
      to: to,
      subject: subject,
      message: message,
    );
  }

  Future<void> _openResultsEntryFix(String entryId) async {
    final cleanEntryId = entryId.trim();
    if (cleanEntryId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminResultsEntryScreen(
          showId: widget.showId,
          showName: widget.showName,
          initialEntryId: cleanEntryId,
        ),
      ),
    );

    if (!mounted) return;
    await _refreshDashboardOnly();

    setState(() {
      _missingPlacementsLoaded = false;
      _missingPlacementItems = [];
      _missingJudgesLoaded = false;
      _missingJudgeItems = [];
      _duplicatePlacementsLoaded = false;
      _duplicatePlacementGroupItems = [];
    });
  }

  Widget _buildMissingJudgesPanel() {
    final count = _dashboard?.resultsReadiness.missingJudgeCount ?? 0;
    if (count <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .22)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: AppColors.gold,
        collapsedIconColor: AppColors.gold,
        textColor: AppColors.gold,
        collapsedTextColor: AppColors.gold,
        leading: const Icon(Icons.gavel_outlined, color: AppColors.gold),
        title: Text(
          '$count missing judges',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Tap to view entries without judges.',
          style: TextStyle(color: AppColors.gold.withValues(alpha: .82)),
        ),
        onExpansionChanged: (expanded) async {
          if (expanded && !_missingJudgesLoaded) {
            await _loadMissingJudges();
          }
        },
        children: [
          if (_loadingMissingJudges)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_missingJudgeItems.isEmpty)
            const _CloseoutWarningDetailTile(
              title: 'No missing judge rows found.',
            )
          else
            ..._missingJudgeItems.map(
              (e) => _CloseoutWarningDetailTile(
                title: e.tattoo.isEmpty ? '(No ear #)' : e.tattoo,
                subtitle: [
                  e.sectionLabel,
                  e.breedName,
                  if (e.varietyName != null && e.varietyName!.isNotEmpty)
                    e.varietyName!,
                  e.className,
                  e.sex,
                  if (e.exhibitorLabel.isNotEmpty) e.exhibitorLabel,
                ].join(' • '),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.build, size: 18),
                  label: const Text('Fix'),
                  onPressed: () => _openResultsEntryFix(e.entryId),
                ),
                onTap: () => _openResultsEntryFix(e.entryId),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDuplicatePlacementGroupsPanel() {
    final count =
        _dashboard?.resultsReadiness.duplicatePlacementGroupCount ?? 0;
    if (count <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .22)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: AppColors.gold,
        collapsedIconColor: AppColors.gold,
        textColor: AppColors.gold,
        collapsedTextColor: AppColors.gold,
        leading: const Icon(Icons.rule_folder_outlined, color: AppColors.gold),
        title: Text(
          '$count duplicate placements',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Tap to view duplicated placements.',
          style: TextStyle(color: AppColors.gold.withValues(alpha: .82)),
        ),
        onExpansionChanged: (expanded) async {
          if (expanded && !_duplicatePlacementsLoaded) {
            await _loadDuplicatePlacementGroups();
          }
        },
        children: [
          if (_loadingDuplicatePlacements)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_duplicatePlacementsLoaded &&
              _duplicatePlacementGroupItems.isEmpty)
            const _CloseoutWarningDetailTile(
              title: 'No duplicate placement rows found.',
              subtitle:
                  'The readiness count found duplicates, but the detail loader did not match them. Refresh the dashboard and confirm show_results_readiness uses the same row source as results entry.',
            )
          else
            ..._duplicatePlacementGroupItems.map((group) {
              final firstEntryId = group.entries.isEmpty
                  ? ''
                  : group.entries.first.entryId;

              return _CloseoutWarningDetailTile(
                title: [
                  group.sectionLabel,
                  group.breedName,
                  if (group.varietyName != null &&
                      group.varietyName!.isNotEmpty)
                    group.varietyName!,
                  group.className,
                  group.sex,
                  'Place ${group.placement}',
                ].where((x) => x.trim().isNotEmpty).join(' • '),
                subtitle: group.entries
                    .map(
                      (e) =>
                          '${e.tattoo.isEmpty ? '(No ear #)' : e.tattoo} • ${e.exhibitorLabel}',
                    )
                    .join('\n'),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.build, size: 18),
                  label: const Text('Fix'),
                  onPressed: firstEntryId.isEmpty
                      ? null
                      : () => _openResultsEntryFix(firstEntryId),
                ),
                onTap: firstEntryId.isEmpty
                    ? null
                    : () => _openResultsEntryFix(firstEntryId),
              );
            }),
        ],
      ),
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
        color: Colors.orange.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .22)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: AppColors.gold,
        collapsedIconColor: AppColors.gold,
        textColor: AppColors.gold,
        collapsedTextColor: AppColors.gold,
        leading: const Icon(Icons.format_list_numbered, color: AppColors.gold),
        title: Text(
          '$missingCount missing placement${missingCount == 1 ? '' : 's'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Tap to view which entries are still missing.',
          style: TextStyle(color: AppColors.gold.withValues(alpha: .82)),
        ),
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

              return AppTheme.surfaceTextScope(
                context,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.muted.withValues(alpha: .12),
                    ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(parts.join(' • ')),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openResultsEntryFix(item.entryId),
                        icon: const Icon(Icons.build, size: 18),
                        label: const Text('Fix'),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<CloseoutDashboard> _loadDashboardFromRpc() async {
    final dashboardResp = await _timedCloseoutLoad(
      'dashboard rpc',
      () => supabase.rpc(
        'get_show_closeout_dashboard',
        params: {'p_show_id': widget.showId},
      ),
    );

    return CloseoutDashboard.fromJson(
      Map<String, dynamic>.from(dashboardResp as Map),
    );
  }

  Future<CloseoutDashboard> _loadDashboardSummary() async {
    try {
      final showRow = await _timedCloseoutLoad(
        'show summary',
        () => supabase
            .from('shows')
            .select('id,name')
            .eq('id', widget.showId)
            .maybeSingle(),
      );

      final artifactRows = await _timedCloseoutLoad(
        'report status summary',
        () => supabase
            .from('show_report_artifacts')
            .select('artifact_status, generated_at, finalize_run_id')
            .eq('show_id', widget.showId)
            .eq('is_current', true),
      );

      Map<String, dynamic>? finalizeRow;
      try {
        finalizeRow = await _timedCloseoutLoad(
          'latest finalize summary',
          () => supabase
              .from('show_finalize_runs')
              .select('id, run_status, started_at, completed_at')
              .eq('show_id', widget.showId)
              .order('started_at', ascending: false)
              .limit(1)
              .maybeSingle(),
        );
      } catch (_) {
        finalizeRow = null;
      }

      final artifacts = (artifactRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final generated = artifacts
          .where((row) => (row['artifact_status'] ?? '') == 'generated')
          .toList();
      final stale = artifacts.any((row) {
        final status = (row['artifact_status'] ?? '').toString();
        return status == 'queued' || status == 'failed';
      });
      final generatedDates =
          generated
              .map((row) => DateTime.tryParse('${row['generated_at'] ?? ''}'))
              .whereType<DateTime>()
              .toList()
            ..sort();
      final lastGeneratedAt = generatedDates.isEmpty
          ? null
          : generatedDates.last.toUtc().toIso8601String();

      final show = showRow == null
          ? <String, dynamic>{'id': widget.showId, 'name': widget.showName}
          : Map<String, dynamic>.from(showRow as Map);
      final latestFinalize = finalizeRow == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(finalizeRow as Map);
      final fallbackFinalizeRunId = artifacts
          .map((row) => (row['finalize_run_id'] ?? '').toString().trim())
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');

      final readiness = _dashboard?.resultsReadiness;

      return CloseoutDashboard(
        dashboard: DashboardEnvelope.fromJson({
          'show_id': show['id'] ?? widget.showId,
          'show_name': show['name'] ?? widget.showName,
          'closeout': {
            'sync_status': generated.isNotEmpty ? 'ready' : 'not_ready',
            'is_points_stale': false,
            'is_reports_stale': stale || generated.isEmpty,
            'reports_generated_count': generated.length,
            'finalized_at': latestFinalize['completed_at'],
            'reports_generated_at': lastGeneratedAt,
          },
        }),
        resultsReadiness: readiness ?? ResultsReadinessDto.fromJson(const {}),
        latestFinalize: LatestFinalize.fromJson({
          ...latestFinalize,
          if ((latestFinalize['id'] ?? '').toString().trim().isEmpty &&
              fallbackFinalizeRunId.isNotEmpty)
            'id': fallbackFinalizeRunId,
        }),
        reports: _dashboard?.reports ?? const <ReportArtifactSummary>[],
        deliveries: _dashboard?.deliveries ?? const <DeliveryRunSummary>[],
        latestArchive: _dashboard?.latestArchive,
      );
    } catch (e) {
      debugPrint(
        '[Closeout:${widget.showId}] lightweight dashboard failed, falling back to dashboard rpc: $e',
      );
      final dashboard = await _loadDashboardFromRpc();
      _reportsLoaded = true;
      return dashboard;
    }
  }

  Future<List<ReportArtifactSummary>> _loadReportArtifacts() async {
    final rows = await _timedCloseoutLoad(
      'report artifacts',
      () => supabase
          .from('show_report_artifacts')
          .select('''
            id,
            finalize_run_id,
            report_name,
            artifact_status,
            file_name,
            storage_bucket,
            storage_path,
            generated_at,
            is_current,
            metadata
          ''')
          .eq('show_id', widget.showId)
          .eq('is_current', true)
          .order('report_name'),
    );

    return (rows as List)
        .map(
          (raw) =>
              ReportArtifactSummary.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList();
  }

  Future<List<DeliveryRunSummary>> _loadDeliveryRuns() async {
    try {
      final rows = await _timedCloseoutLoad(
        'delivery runs',
        () => supabase
            .from('show_report_deliveries')
            .select('id, delivery_type, delivery_status')
            .eq('show_id', widget.showId)
            .order('created_at', ascending: false)
            .limit(25),
      );

      return (rows as List)
          .map(
            (raw) =>
                DeliveryRunSummary.fromJson(Map<String, dynamic>.from(raw)),
          )
          .toList();
    } catch (_) {
      return const <DeliveryRunSummary>[];
    }
  }

  Future<ArchiveSummary?> _loadLatestArchive() async {
    try {
      final row = await _timedCloseoutLoad(
        'latest archive',
        () => supabase
            .from('show_report_archives')
            .select('id, archive_version, archive_status')
            .eq('show_id', widget.showId)
            .order('archive_version', ascending: false)
            .limit(1)
            .maybeSingle(),
      );

      return row == null
          ? null
          : ArchiveSummary.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureReportsLoaded({bool force = false}) async {
    if (_loadingReports) return;
    if (_reportsLoaded && !force) return;

    setState(() {
      _loadingReports = true;
      _reportsError = null;
    });

    try {
      final latestFinalizeRunId = _dashboard?.latestFinalize.id;
      await _syncClubDeliveryMetadata(latestFinalizeRunId: latestFinalizeRunId);

      final reports = await _loadReportArtifacts();
      final deliveries = await _loadDeliveryRuns();
      final latestArchive = await _loadLatestArchive();

      if (!mounted) return;
      setState(() {
        if (_dashboard != null) {
          final fallbackFinalizeRunId = reports
              .map((report) => (report.finalizeRunId ?? '').trim())
              .firstWhere((id) => id.isNotEmpty, orElse: () => '');
          final latestFinalize =
              _dashboard!.latestFinalize.id == null &&
                  fallbackFinalizeRunId.isNotEmpty
              ? LatestFinalize(id: fallbackFinalizeRunId)
              : _dashboard!.latestFinalize;

          _dashboard = CloseoutDashboard(
            dashboard: _dashboard!.dashboard,
            resultsReadiness: _dashboard!.resultsReadiness,
            latestFinalize: latestFinalize,
            reports: reports,
            deliveries: deliveries,
            latestArchive: latestArchive,
          );
        }
        _reportsLoaded = true;
        _rebuildReportCaches();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reportsError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingReports = false;
        });
      }
    }
  }

  Future<void> _refreshDashboardOnly({bool includeReports = false}) async {
    try {
      var dashboard = await _loadDashboardSummary();

      final readinessResp = await _timedCloseoutLoad(
        'results readiness refresh',
        () => supabase.rpc(
          'show_results_readiness',
          params: {'p_show_id': widget.showId},
        ),
      );

      final freshReadiness = ResultsReadinessDto.fromJson(
        Map<String, dynamic>.from(readinessResp as Map),
      );

      final dashboardWithFreshReadiness = CloseoutDashboard(
        dashboard: dashboard.dashboard,
        resultsReadiness: freshReadiness,
        latestFinalize: dashboard.latestFinalize,
        reports: dashboard.reports,
        deliveries: dashboard.deliveries,
        latestArchive: dashboard.latestArchive,
      );

      if (!mounted) return;
      setState(() {
        _dashboard = dashboardWithFreshReadiness;
        _rebuildReportCaches();

        _missingPlacementsLoaded = false;
        _missingPlacementItems = [];

        _missingJudgesLoaded = false;
        _missingJudgeItems = [];

        _duplicatePlacementsLoaded = false;
        _duplicatePlacementGroupItems = [];
      });

      if (includeReports || _reportsLoaded) {
        await _ensureReportsLoaded(force: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed refreshing reports: $e')));
    }
  }

  Future<void> _loadDataUntilFinalizeVisible({
    required String previousFinalizeId,
  }) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await _refreshDashboardOnly(includeReports: true);

      final latestId = _dashboard?.latestFinalize.id;

      final hasNewFinalize = latestId != null && latestId != previousFinalizeId;

      final hasCurrentReports =
          (_dashboard?.reports ?? const <ReportArtifactSummary>[]).any(
            (r) => r.isCurrent,
          );

      if (hasNewFinalize && hasCurrentReports) {
        await _syncClubDeliveryMetadata(latestFinalizeRunId: latestId);
        await _refreshDashboardOnly(includeReports: true);
        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    await _syncClubDeliveryMetadata(
      latestFinalizeRunId: _dashboard?.latestFinalize.id,
    );
    await _refreshDashboardOnly(includeReports: true);
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

  Future<void> _finalizeShow() async {
    final ready = await _ensureResultsReadyForReports();

    if (!ready) {
      throw Exception('Results are not ready for finalize.');
    }

    final selectedSectionIds = _selectedCloseoutSectionIds;

    if (!_selectedCloseoutScopeIsEntireShow && selectedSectionIds.isEmpty) {
      throw Exception(
        'Select at least one section before finalizing this scope.',
      );
    }

    final response = await supabase.functions.invoke(
      'run-closeout',
      body: {
        'show_id': widget.showId,
        'section_ids': _selectedCloseoutScopeIsEntireShow
            ? <String>[]
            : selectedSectionIds,
        'scope_label': _selectedCloseoutScopeLabel,
      },
    );

    if (response.status >= 400) {
      final data = response.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Server closeout failed with status ${response.status}.';
      throw Exception(message);
    }

    await _refreshDashboardOnly();
  }

  Future<int> _countQueuedArtifactsForShow() async {
    var query = supabase
        .from('show_report_artifacts')
        .select('id')
        .eq('show_id', widget.showId)
        .eq('is_current', true)
        .eq('artifact_status', 'queued');

    if (!_selectedCloseoutScopeIsEntireShow) {
      query = query.contains('metadata', {
        'scope_label': _selectedCloseoutScopeLabel,
      });
    }

    final rows = await query;
    return (rows as List).length;
  }

  Duration _reportGenerationTimeoutFor(ReportArtifactSummary artifact) {
    if (artifact.reportName == 'legs' || artifact.reportName == 'leg_report') {
      return const Duration(minutes: 8);
    }

    if (artifact.reportName == 'arba_report') {
      return const Duration(minutes: 5);
    }

    return const Duration(minutes: 3);
  }

  int _reportGenerationMaxAttemptsFor(ReportArtifactSummary artifact) {
    if (artifact.reportName == 'legs' || artifact.reportName == 'leg_report') {
      return 1;
    }

    return 3;
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
    await _ensureUnpaidBalancesBuilder();
    await _ensurePaidExhibitorReportBuilder();
    await _ensureReportLogo();
    await _ensureEnteredExhibitorsContactBuilder();
    await _ensureRibbonPayoutBuilder();
    await _ensurePaybackReportBuilder();

    final repository = CloseoutRepository(supabase);

    final arbaLoader = ArbaReportLoader(repository);
    final arbaBuilder = ArbaReportPdfBuilder();

    final showBasics = await repository.loadShowBasics(widget.showId);
    final isNationalShow = showBasics['is_national_show'] == true;
    final showDate = _formatShowDate(showBasics['start_date']);
    final sanctionNumber = await _loadArbaSanctionNumber(widget.showId);

    final legsLoader = LegsReportLoader(repository);
    final exhibitorLoader = ExhibitorReportLoader(repository);

    final sweepstakesLoader = SweepstakesReportLoader(repository);
    final sweepstakesBuilder = SweepstakesReportPdf(
      logoBytes: _reportLogoBytes,
    );

    final breedResultsDetailReportLoader = BreedResultsDetailReportLoader(
      repository,
    );
    final breedResultsDetailReportBuilder = BreedResultsDetailReportPdf(
      logoBytes: _reportLogoBytes,
    );

    final detailsByBreedReportLoader = DetailsByBreedReportLoader(repository);
    final detailsByBreedReportBuilder = DetailsByBreedReportPdf(
      logoBytes: _reportLogoBytes,
    );

    final exhibitorByBreedReportLoader = ExhibitorByBreedReportLoader(
      repository,
    );
    final exhibitorByBreedReportBuilder = ExhibitorByBreedReportPdf(
      logoBytes: _reportLogoBytes,
    );

    final unpaidBalancesLoader = UnpaidBalancesReportLoader(repository);
    final paidExhibitorReportLoader = PaidExhibitorReportLoader(repository);

    final enteredExhibitorsContactLoader = EnteredExhibitorsContactReportLoader(
      supabase,
    );

    final ribbonPayoutLoader = RibbonPayoutReportLoader(repository);

    final paybackReportLoader = PaybackReportLoader();
    final bestDisplayReportLoader = BestDisplayReportLoader();
    final bestDisplayReportBuilder = BestDisplayReportPdfBuilder();

    final registry = ReportRegistry(
      arbaLoader: arbaLoader,
      arbaBuilder: arbaBuilder,
      legsLoader: legsLoader,
      legsBuilder: _requiredReportDependency(
        _legsBuilder,
        'Legs report PDF builder',
      ),
      exhibitorLoader: exhibitorLoader,
      exhibitorBuilder: _requiredReportDependency(
        _exhibitorBuilder,
        'Exhibitor report PDF builder',
      ),
      sweepstakesLoader: sweepstakesLoader,
      sweepstakesBuilder: sweepstakesBuilder,
      breedResultsDetailReportLoader: breedResultsDetailReportLoader,
      breedResultsDetailReportBuilder: breedResultsDetailReportBuilder,
      unpaidBalancesLoader: unpaidBalancesLoader,
      unpaidBalancesBuilder: _requiredReportDependency(
        _unpaidBalancesBuilder,
        'Unpaid balances report PDF builder',
      ),
      paidExhibitorReportLoader: paidExhibitorReportLoader,
      paidExhibitorReportBuilder: _requiredReportDependency(
        _paidExhibitorReportBuilder,
        'Paid exhibitor report PDF builder',
      ),
      enteredExhibitorsContactLoader: enteredExhibitorsContactLoader,
      enteredExhibitorsContactBuilder: _requiredReportDependency(
        _enteredExhibitorsContactBuilder,
        'Entered exhibitors contact report PDF builder',
      ),
      ribbonPayoutLoader: ribbonPayoutLoader,
      ribbonPayoutBuilder: _requiredReportDependency(
        _ribbonPayoutBuilder,
        'Ribbon payout report PDF builder',
      ),
      paybackReportLoader: paybackReportLoader,
      paybackReportBuilder: _requiredReportDependency(
        _paybackReportBuilder,
        'Payback report PDF builder',
      ),
      judgeReportLoader: JudgeReportLoader(),
      judgeReportBuilder: JudgeReportPdfBuilder(),
      breedJudgedTotalsReportLoader: BreedJudgedTotalsReportLoader(),
      breedJudgedTotalsReportBuilder: BreedJudgedTotalsReportPdfBuilder(),
      bestDisplayReportLoader: bestDisplayReportLoader,
      bestDisplayReportBuilder: bestDisplayReportBuilder,
      detailsByBreedReportLoader: detailsByBreedReportLoader,
      detailsByBreedReportBuilder: detailsByBreedReportBuilder,
      exhibitorByBreedReportLoader: exhibitorByBreedReportLoader,
      exhibitorByBreedReportBuilder: exhibitorByBreedReportBuilder,
    );

    final engine = ReportEngine(registry);
    final uploadService = ReportUploadService(supabase);

    final runner = CloseoutRunner(engine: engine, uploadService: uploadService);

    String artifactKey(ReportArtifactSummary artifact) {
      final species = _stateClubReportKeys.contains(artifact.reportName)
          ? (_artifactMetaString(artifact, 'species') ?? '')
                .trim()
                .toLowerCase()
          : '';
      return [
        artifact.reportName,
        artifact.id,
        if (species.isNotEmpty) species,
      ].join('::');
    }

    Future<void> runSingle(ReportArtifactSummary artifact) async {
      final key = artifactKey(artifact);
      onStarted(key);

      final runId =
          artifact.finalizeRunId ??
          _dashboard?.latestFinalize.id ??
          'manual-run';

      Future<void> generateAttempt() async {
        if (artifact.reportName == 'arba_report') {
          final scope = _artifactMetaString(artifact, 'scope');
          final showLetter = _artifactMetaString(artifact, 'show_letter');

          if (scope == null || showLetter == null) {
            throw Exception(
              'Missing artifact metadata for ${artifact.reportName} (${artifact.id}). '
              'Expected scope and show_letter.',
            );
          }

          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: runId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            scope: scope,
            showLetter: showLetter,
            showName: widget.showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
            isNationalShow: isNationalShow,
          );
        } else if (artifact.reportName == 'sweepstakes_report' ||
            artifact.reportName == 'breed_results_detail_report' ||
            artifact.reportName == 'details_by_breed' ||
            artifact.reportName == 'exh_by_breed' ||
            artifact.reportName == 'best_display_report') {
          final artifactBreedName = _artifactMetaString(artifact, 'breed_name');
          final species = _artifactMetaString(artifact, 'species');
          final breedName = loaderBreedNameForClubReport(
            reportName: artifact.reportName,
            breedName: artifactBreedName,
            species: species,
          );
          final scope = _artifactMetaString(artifact, 'scope');
          final showLetter = _artifactMetaString(artifact, 'show_letter');

          if (scope == null || showLetter == null) {
            throw Exception(
              'Missing artifact metadata for ${artifact.reportName} (${artifact.id}). '
              'Expected scope and show_letter.',
            );
          }

          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: runId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            breedName: breedName,
            species: species,
            scope: scope,
            showLetter: showLetter,
            showName: widget.showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
            isNationalShow: isNationalShow,
          );
        } else if (artifact.reportName == 'exhibitor_report' ||
            artifact.reportName == 'legs' ||
            artifact.reportName == 'leg_report') {
          final exhibitorId = _artifactMetaString(artifact, 'exhibitor_id');
          final exhibitorName = _artifactMetaString(artifact, 'exhibitor_name');

          if (exhibitorId == null) {
            throw Exception(
              'Missing exhibitor_id metadata for ${artifact.reportName} (${artifact.id}).',
            );
          }

          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: runId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            exhibitorId: exhibitorId,
            exhibitorName: exhibitorName,
            showName: widget.showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
            isNationalShow: isNationalShow,
          );
        } else {
          final isBreedJudgedTotalsReport =
              artifact.reportName == 'breed_judged_totals_report';
          final scopeLabel = _artifactMetaString(artifact, 'scope_label');
          final sectionIds = _metadataSectionIds(artifact.metadata);

          debugPrint(
            '[Closeout:${widget.showId}] Generating queued report='
            '${artifact.reportName} artifact=${artifact.id} '
            'scopeLabel=${scopeLabel ?? ''} sectionIds=${sectionIds.join(',')}',
          );

          await runner.generateSingleReport(
            showId: widget.showId,
            finalizeRunId: runId,
            reportName: artifact.reportName,
            artifactId: artifact.id,
            scopeLabel: isBreedJudgedTotalsReport ? scopeLabel : null,
            sectionIds: isBreedJudgedTotalsReport ? sectionIds : null,
            showName: widget.showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
            isNationalShow: isNationalShow,
          );
        }
      }

      Object? lastError;
      StackTrace? lastStack;

      final timeout = _reportGenerationTimeoutFor(artifact);
      final maxAttempts = _reportGenerationMaxAttemptsFor(artifact);

      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await generateAttempt().timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException(
                'Report generation timed out after ${timeout.inMinutes} minutes for '
                '${artifact.reportName} (${artifact.id}).',
              );
            },
          );
          onFinished(key);
          return;
        } catch (e, st) {
          lastError = e;
          lastStack = st;

          debugPrint(
            'Report generation failed attempt $attempt/$maxAttempts for '
            '${artifact.reportName} (${artifact.id}): $e',
          );
          debugPrintStack(stackTrace: st);

          if (attempt < maxAttempts) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }
      }

      final error = lastError ?? Exception('Unknown report generation failure');

      debugPrint(
        'Report generation permanently failed for '
        '${artifact.reportName} (${artifact.id}): $error',
      );
      if (lastStack != null) {
        debugPrintStack(stackTrace: lastStack);
      }

      onFailed(key, error);

      await supabase
          .from('show_report_artifacts')
          .update({
            'artifact_status': 'failed',
            'error_count': 1,
            'metadata': {...artifact.metadata, 'last_error': error.toString()},
          })
          .eq('id', artifact.id);
    }

    bool isRunnableArtifact(ReportArtifactSummary a) {
      if (a.id.isEmpty || a.reportName.isEmpty) return false;

      if (a.reportName == 'arba_report') {
        return _artifactMetaString(a, 'scope') != null &&
            _artifactMetaString(a, 'show_letter') != null;
      }

      if (a.reportName == 'exhibitor_report') {
        return _artifactMetaString(a, 'exhibitor_id') != null;
      }

      if (a.reportName == 'legs' || a.reportName == 'leg_report') {
        return _artifactMetaString(a, 'exhibitor_id') != null;
      }

      if (a.reportName == 'sweepstakes_report' ||
          a.reportName == 'breed_results_detail_report' ||
          a.reportName == 'details_by_breed' ||
          a.reportName == 'exh_by_breed' ||
          a.reportName == 'best_display_report') {
        return _artifactMetaString(a, 'scope') != null &&
            _artifactMetaString(a, 'show_letter') != null;
      }

      return true;
    }

    final validArtifacts = <ReportArtifactSummary>[];

    for (final artifact in artifacts) {
      final key = artifactKey(artifact);

      if (isRunnableArtifact(artifact)) {
        validArtifacts.add(artifact);
        continue;
      }

      final missing = <String>[];
      if (artifact.id.isEmpty) missing.add('id');
      if (artifact.reportName.isEmpty) missing.add('reportName');

      if (artifact.reportName == 'arba_report') {
        if (_artifactMetaString(artifact, 'scope') == null)
          missing.add('metadata.scope');
        if (_artifactMetaString(artifact, 'show_letter') == null)
          missing.add('metadata.show_letter');
      } else if (artifact.reportName == 'exhibitor_report') {
        if (_artifactMetaString(artifact, 'exhibitor_id') == null)
          missing.add('metadata.exhibitor_id');
      } else if (artifact.reportName == 'legs' ||
          artifact.reportName == 'leg_report') {
        if (_artifactMetaString(artifact, 'exhibitor_id') == null) {
          missing.add('metadata.exhibitor_id');
        }
      } else if (artifact.reportName == 'sweepstakes_report' ||
          artifact.reportName == 'breed_results_detail_report' ||
          artifact.reportName == 'details_by_breed' ||
          artifact.reportName == 'exh_by_breed' ||
          artifact.reportName == 'best_display_report') {
        if (_artifactMetaString(artifact, 'scope') == null) {
          missing.add('metadata.scope');
        }
        if (_artifactMetaString(artifact, 'show_letter') == null) {
          missing.add('metadata.show_letter');
        }
      }

      final error = Exception(
        'Report artifact could not be generated because required metadata is missing: '
        '${missing.isEmpty ? 'unknown required metadata' : missing.join(', ')}.',
      );

      debugPrint(
        'Skipping invalid report artifact ${artifact.reportName} (${artifact.id}): $error',
      );

      onFailed(key, error);

      if (artifact.id.isNotEmpty) {
        await supabase
            .from('show_report_artifacts')
            .update({
              'artifact_status': 'failed',
              'error_count': 1,
              'metadata': {
                ...artifact.metadata,
                'last_error': error.toString(),
              },
            })
            .eq('id', artifact.id);
      }
    }

    debugPrint(
      'CLOSEOUT GENERATE queued ${validArtifacts.length} valid artifacts: '
      '${validArtifacts.map((a) => '${a.reportName}(${a.id})').join(', ')}',
    );

    final legArtifacts = validArtifacts
        .where((a) => a.reportName == 'legs' || a.reportName == 'leg_report')
        .toList();
    final nonLegArtifacts = validArtifacts
        .where((a) => a.reportName != 'legs' && a.reportName != 'leg_report')
        .toList();

    for (final artifact in legArtifacts) {
      await runSingle(artifact);
    }

    const batchSize = 4;

    for (var i = 0; i < nonLegArtifacts.length; i += batchSize) {
      final batch = nonLegArtifacts.skip(i).take(batchSize).toList();
      await Future.wait(batch.map(runSingle));
    }

    await supabase.rpc(
      'refresh_show_reports_state',
      params: {'p_show_id': widget.showId},
    );
  }

  Future<void> _ensureEnteredExhibitorsContactBuilder() async {
    _enteredExhibitorsContactBuilder ??= EnteredExhibitorsContactReportPdf();
  }

  Future<void> _ensureRibbonPayoutBuilder() async {
    _ribbonPayoutBuilder ??= RibbonPayoutReportPdf();
  }

  Future<void> _ensurePaybackReportBuilder() async {
    _paybackReportBuilder ??= await PaybackReportPdfBuilder.fromAssets();
  }

  T _requiredReportDependency<T>(T? value, String label) {
    if (value == null) {
      throw StateError('$label was not initialized before report generation.');
    }
    return value;
  }

  Future<void> _sendAllExhibitorReports() async {
    if (await _blockedBySupportModeForEmailSend('Exhibitor')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;
    if (!mounted) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      await _refreshDashboardOnly(includeReports: true);

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
      final sendErrors = <String>[];

      for (final exhibitor in exhibitors) {
        final artifactsById = <String, ReportArtifactSummary>{};

        final exhibitorReports = _allGeneratedArtifactsWhere(
          'exhibitor_report',
          (a) =>
              _artifactMatchesExhibitor(a, exhibitor) &&
              _artifactMatchesSelectedScope(a),
        );

        final legsReports = _allGeneratedArtifactsWhere(
          'legs',
          (a) =>
              _artifactMatchesExhibitor(a, exhibitor) &&
              _artifactMatchesSelectedScope(a),
        );

        for (final artifact in exhibitorReports) {
          artifactsById[artifact.id] = artifact;
        }

        for (final artifact in legsReports) {
          artifactsById[artifact.id] = artifact;
        }

        final artifacts = artifactsById.values.toList()
          ..sort((a, b) {
            final aReportRank = a.reportName == 'exhibitor_report' ? 0 : 1;
            final bReportRank = b.reportName == 'exhibitor_report' ? 0 : 1;

            final rankCmp = aReportRank.compareTo(bReportRank);
            if (rankCmp != 0) return rankCmp;

            final aGenerated =
                DateTime.tryParse(a.generatedAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bGenerated =
                DateTime.tryParse(b.generatedAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);

            return aGenerated.compareTo(bGenerated);
          });

        if (artifacts.isEmpty) {
          skippedCount++;
          continue;
        }

        try {
          await _sendExhibitorArtifactsEmail(
            artifacts: artifacts,
            to: exhibitor.email,
            subject: '${widget.showName} - Exhibitor Reports',
            message:
                'Attached are your exhibitor reports and any earned legs from ${widget.showName}.',
            allowLegs: true,
          );
          sentCount++;
        } catch (e, st) {
          failedCount++;

          final errorText = e.toString().trim().isEmpty
              ? 'Unknown email send error. Check Supabase function logs for send-exhibitor-report-email.'
              : e.toString();

          if (sendErrors.length < 5) {
            sendErrors.add(
              '${exhibitor.exhibitorName} <${exhibitor.email}>: $errorText',
            );
          }
        }
      }

      if (!mounted) return;

      final summary =
          'Exhibitor report send complete. Sent: $sentCount, skipped: $skippedCount, failed: $failedCount';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 8), content: Text(summary)),
      );

      if (failedCount > 0 && sendErrors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exhibitor email send errors'),
            content: SingleChildScrollView(
              child: Text(sendErrors.join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else if (failedCount > 0) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exhibitor email send failed'),
            content: const Text(
              'The email send failed, but no error message was returned to the app. Check the Supabase Edge Function logs for the exhibitor email function.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
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
    if (await _blockedBySupportModeForEmailSend('Club')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;
    if (!mounted) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      await _refreshDashboardOnly(includeReports: true);

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

      final grouped = <String, List<_ClubEmailTarget>>{};

      for (final club in clubs) {
        final isStateClub =
            club.sanctioningBody.trim().toUpperCase() == 'STATE CLUB';

        final key = isStateClub
            ? '${club.sanctioningBody.trim().toLowerCase()}|${club.clubName.trim().toLowerCase()}|${club.scope.trim().toUpperCase()}|${club.showLetter.trim().toUpperCase()}|${club.species.trim().toLowerCase()}|${club.email.trim().toLowerCase()}'
            : '${club.sanctioningBody.trim().toLowerCase()}|${club.clubName.trim().toLowerCase()}|${club.breedName.trim().toLowerCase()}|${club.scope.trim().toUpperCase()}|${club.showLetter.trim().toUpperCase()}|${club.email.trim().toLowerCase()}';

        grouped.putIfAbsent(key, () => []);
        grouped[key]!.add(club);
      }

      for (final entry in grouped.entries) {
        final targets = entry.value;
        if (targets.isEmpty) {
          skippedCount++;
          continue;
        }

        final first = targets.first;
        final isStateClub =
            first.sanctioningBody.trim().toUpperCase() == 'STATE CLUB';
        final artifactsById = <String, ReportArtifactSummary>{};

        final reportNames = isStateClub
            ? _stateClubReportKeys
            : _breedClubReportKeys;

        for (final target in targets) {
          for (final reportName in reportNames) {
            final matchingArtifacts = _allGeneratedArtifactsWhere(
              reportName,
              (a) =>
                  _artifactMatchesClubTarget(a, target) &&
                  _artifactMatchesSelectedScope(a),
            );

            for (final artifact in matchingArtifacts) {
              artifactsById[artifact.id] = artifact;
            }
          }
        }

        final artifacts = artifactsById.values.toList()
          ..sort((a, b) {
            final aScope = (_artifactMetaString(a, 'scope') ?? '')
                .trim()
                .toUpperCase();
            final bScope = (_artifactMetaString(b, 'scope') ?? '')
                .trim()
                .toUpperCase();

            final aLetter = (_artifactMetaString(a, 'show_letter') ?? '')
                .trim()
                .toUpperCase();
            final bLetter = (_artifactMetaString(b, 'show_letter') ?? '')
                .trim()
                .toUpperCase();

            final scopeCmp = aScope.compareTo(bScope);
            if (scopeCmp != 0) return scopeCmp;

            final letterCmp = aLetter.compareTo(bLetter);
            if (letterCmp != 0) return letterCmp;

            return a.reportName.compareTo(b.reportName);
          });

        final includedSanctionNumbers =
            artifacts
                .map(
                  (a) =>
                      (_artifactMetaString(a, 'sanction_number') ?? '').trim(),
                )
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        if (artifacts.isEmpty) {
          skippedCount++;
          continue;
        }

        try {
          final species = first.species.trim().toLowerCase();
          final speciesLabel = species == 'rabbit'
              ? 'Rabbit '
              : species == 'cavy'
              ? 'Cavy '
              : '';
          final speciesMessagePrefix = species == 'rabbit'
              ? 'rabbit '
              : species == 'cavy'
              ? 'cavy '
              : '';
          final subject = isStateClub
              ? '${widget.showName} - ${first.clubName} ${speciesLabel}Club Reports'
              : '${widget.showName} - ${first.breedName} Club Reports';

          final message = isStateClub
              ? 'Attached are the ${speciesMessagePrefix}Breed Totals, Breed Special Points, and Display Points reports for ${widget.showName} for ${first.scope} ${first.showLetter}.\n\n'
                    '${includedSanctionNumbers.isNotEmpty ? 'Included shows: ${includedSanctionNumbers.join(', ')}.' : ''}'
              : 'Attached are the sweepstakes and breed results detail reports for ${widget.showName}.\n\n'
                    '${includedSanctionNumbers.isNotEmpty ? 'Included shows: ${includedSanctionNumbers.join(', ')}.' : ''}';

          await _sendClubArtifactsEmail(
            artifacts: artifacts,
            to: first.email,
            subject: subject,
            message: message,
          );
          sentCount++;
        } catch (e, st) {
          failedCount++;
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
    } catch (e, st) {
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

    if (readiness.missingFinalAwardCount > 0) {
      parts.add(
        '${readiness.missingFinalAwardCount} missing final award${readiness.missingFinalAwardCount == 1 ? '' : 's'}',
      );
    }

    if (readiness.duplicateFinalAwardCount > 0) {
      parts.add(
        '${readiness.duplicateFinalAwardCount} duplicate final award${readiness.duplicateFinalAwardCount == 1 ? '' : 's'}',
      );
    }

    if (parts.isEmpty) {
      return 'Results are ready for reports.';
    }

    return 'Reports are blocked until results are complete: ${parts.join(', ')}.';
  }

  Future<void> _sendAllLegsReports() async {
    if (await _blockedBySupportModeForEmailSend('Leg')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      await _refreshDashboardOnly(includeReports: true);

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
      final sendErrors = <String>[];

      for (final exhibitor in exhibitors) {
        final legsReport = _newestGeneratedArtifactWhere(
          'legs',
          (a) =>
              _artifactMatchesExhibitor(a, exhibitor) &&
              _artifactMatchesSelectedScope(a),
        );

        if (legsReport == null) {
          skippedCount++;
          continue;
        }

        try {
          await _sendExhibitorArtifactsEmail(
            artifacts: [legsReport],
            to: exhibitor.email,
            subject: '${widget.showName} - ARBA Legs',
            message:
                'Attached are your earned ARBA legs from ${widget.showName}.',
            allowLegs: true,
          );
          sentCount++;
        } catch (e) {
          failedCount++;

          final errorText = e.toString().trim().isEmpty
              ? 'Unknown email send error. Check Supabase function logs for send-exhibitor-report-email.'
              : e.toString();

          if (sendErrors.length < 5) {
            sendErrors.add(
              '${exhibitor.exhibitorName} <${exhibitor.email}>: $errorText',
            );
          }
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Leg report send complete. Sent: $sentCount, skipped: $skippedCount, failed: $failedCount',
          ),
        ),
      );

      if (failedCount > 0 && sendErrors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leg email send errors'),
            content: SingleChildScrollView(
              child: Text(sendErrors.join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed sending leg reports: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
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
        '${readiness.missingPlacementCount} missing placement'
        '${readiness.missingPlacementCount == 1 ? '' : 's'}',
      );
    }

    if (readiness.missingJudgeCount > 0) {
      parts.add(
        '${readiness.missingJudgeCount} missing judge'
        '${readiness.missingJudgeCount == 1 ? '' : 's'}',
      );
    }

    if (readiness.duplicatePlacementGroupCount > 0) {
      parts.add(
        '${readiness.duplicatePlacementGroupCount} duplicate placement group'
        '${readiness.duplicatePlacementGroupCount == 1 ? '' : 's'}',
      );
    }

    if (readiness.missingFinalAwardCount > 0) {
      parts.add(
        '${readiness.missingFinalAwardCount} missing final award'
        '${readiness.missingFinalAwardCount == 1 ? '' : 's'}',
      );
    }

    if (readiness.duplicateFinalAwardCount > 0) {
      parts.add(
        '${readiness.duplicateFinalAwardCount} duplicate final award'
        '${readiness.duplicateFinalAwardCount == 1 ? '' : 's'}',
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
  bool get _isSupportMode => AppSession.isSupportMode;

  Future<bool> _currentUserIsShowSuperAdmin() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || userId.trim().isEmpty) return false;

    final rows = await supabase
        .from('role_assignments')
        .select('id')
        .eq('show_id', widget.showId)
        .eq('user_id', userId)
        .eq('role', 'super_admin')
        .limit(1);

    return (rows as List).isNotEmpty;
  }

  Future<bool> _blockedBySupportModeForEmailSend(String label) async {
    if (!_isSupportMode) return false;

    final isShowSuperAdmin = await _currentUserIsShowSuperAdmin();
    if (isShowSuperAdmin) return false;

    if (!mounted) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label email sending is disabled while viewing in support mode.',
        ),
      ),
    );

    return true;
  }

  Future<void> _ensureLegsBuilder() async {
    _legsBuilder ??= await LegsReportPdfBuilder.fromAssets();
  }

  Future<void> _ensureExhibitorBuilder() async {
    _exhibitorBuilder ??= await ExhibitorReportPdfBuilder.fromAssets();
  }

  Future<void> _ensureUnpaidBalancesBuilder() async {
    _unpaidBalancesBuilder ??=
        await UnpaidBalancesReportPdfBuilder.fromAssets();
  }

  Future<void> _ensurePaidExhibitorReportBuilder() async {
    _paidExhibitorReportBuilder ??=
        await PaidExhibitorReportPdfBuilder.fromAssets();
  }

  Future<void> _ensureReportLogo() async {
    if (_reportLogoBytes != null) return;

    final bytes = await rootBundle.load(
      'assets/images/ringmaster_show_logo.png',
    );
    _reportLogoBytes = bytes.buffer.asUint8List();
  }

  Future<void> _loadArbaDetails() async {
    final showRow = await supabase
        .from('shows')
        .select(
          'secretary_name, secretary_address, secretary_email, secretary_phone',
        )
        .eq('id', widget.showId)
        .maybeSingle();

    final arbaRow = await supabase
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

    final row = arbaRow ?? <String, dynamic>{};
    final show = showRow ?? <String, dynamic>{};

    String firstNonEmpty(List<dynamic> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    _secretaryNameController.text = firstNonEmpty([
      show['secretary_name'],
      row['secretary_name'],
    ]);
    _secretaryAddressController.text = firstNonEmpty([
      show['secretary_address'],
      row['secretary_address'],
    ]);
    _secretaryEmailController.text = firstNonEmpty([
      show['secretary_email'],
      row['secretary_email'],
    ]);
    _secretaryPhoneController.text = firstNonEmpty([
      show['secretary_phone'],
      row['secretary_phone'],
    ]);

    _superintendentController.text = (row['superintendent_name'] ?? '')
        .toString();
    _superintendentNumberController.text =
        (row['superintendent_arba_number'] ?? '').toString();

    _sweepstakesIssue = row['sweepstakes_issue'] == true;
    _sweepstakesClubController.text = (row['sweepstakes_club'] ?? '')
        .toString();
    _officialProtest = row['official_protest'] == true;
    _arbaReportFiled = _officialProtest && row['arba_report_filed'] == true;
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var dashboard = await _loadDashboardSummary();

      final readinessResp = await _timedCloseoutLoad(
        'results readiness',
        () => supabase.rpc(
          'show_results_readiness',
          params: {'p_show_id': widget.showId},
        ),
      );

      final freshReadiness = ResultsReadinessDto.fromJson(
        Map<String, dynamic>.from(readinessResp as Map),
      );

      final dashboardWithFreshReadiness = CloseoutDashboard(
        dashboard: dashboard.dashboard,
        resultsReadiness: freshReadiness,
        latestFinalize: dashboard.latestFinalize,
        reports: dashboard.reports,
        deliveries: dashboard.deliveries,
        latestArchive: dashboard.latestArchive,
      );

      await _timedCloseoutLoad('ARBA closeout details', _loadArbaDetails);

      if (!mounted) return;
      setState(() {
        _dashboard = dashboardWithFreshReadiness;
        _rebuildReportCaches();

        _missingPlacementsLoaded = false;
        _missingPlacementItems = [];

        _missingJudgesLoaded = false;
        _missingJudgeItems = [];

        _duplicatePlacementsLoaded = false;
        _duplicatePlacementGroupItems = [];
      });

      unawaited(_loadCloseoutScopes());
      if (_reportsLoaded) {
        unawaited(_ensureReportsLoaded(force: true));
      }
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
      final secretaryName = _secretaryNameController.text.trim();
      final secretaryAddress = _secretaryAddressController.text.trim();
      final secretaryEmail = _secretaryEmailController.text.trim();
      final secretaryPhone = _secretaryPhoneController.text.trim();

      await supabase
          .from('shows')
          .update({
            'secretary_name': secretaryName.isEmpty ? null : secretaryName,
            'secretary_address': secretaryAddress.isEmpty
                ? null
                : secretaryAddress,
            'secretary_email': secretaryEmail.isEmpty ? null : secretaryEmail,
            'secretary_phone': secretaryPhone.isEmpty ? null : secretaryPhone,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.showId);

      await supabase.from('show_arba_report_details').upsert({
        'show_id': widget.showId,
        'secretary_name': secretaryName,
        'secretary_address': secretaryAddress,
        'secretary_email': secretaryEmail,
        'secretary_phone': secretaryPhone,
        'superintendent_name': _superintendentController.text.trim(),
        'superintendent_arba_number': _superintendentNumberController.text
            .trim(),
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

  Future<ReportArtifactSummary> _createManualReportArtifact({
    required String reportName,
    Map<String, dynamic>? metadata,
  }) async {
    final finalizeRunId = _dashboard?.latestFinalize.id;
    debugPrint(
      '[Closeout:${widget.showId}] Creating manual artifact '
      'report=$reportName finalizeRunId=${finalizeRunId ?? ''} '
      'metadata=${metadata ?? <String, dynamic>{}}',
    );

    final inserted = await supabase
        .from('show_report_artifacts')
        .insert({
          'show_id': widget.showId,
          'finalize_run_id': finalizeRunId,
          'report_name': reportName,
          'artifact_status': 'queued',
          'is_current': true,
          'metadata': metadata ?? <String, dynamic>{},
        })
        .select('''
            id,
            finalize_run_id,
            report_name,
            artifact_status,
            file_name,
            storage_bucket,
            storage_path,
            generated_at,
            is_current,
            metadata
          ''')
        .single();

    return ReportArtifactSummary.fromJson(Map<String, dynamic>.from(inserted));
  }

  List<String> _metadataSectionIds(Map<String, dynamic> metadata) {
    final raw = metadata['section_ids'];
    if (raw is List) {
      return raw
          .map((value) => value?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  Map<String, dynamic> _internalShowLevelReportMetadata(String reportName) {
    if (reportName != 'breed_judged_totals_report') {
      return const <String, dynamic>{};
    }

    if (_selectedCloseoutScopeIsEntireShow) {
      return const <String, dynamic>{
        'report_scope': 'show',
        'internal_report': true,
      };
    }

    return {
      'report_scope': 'selected_sections',
      'internal_report': true,
      'scope_label': _selectedCloseoutScopeLabel,
      'section_ids': _selectedCloseoutSectionIds,
    };
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
      final sectionLetter = (row['letter'] ?? '')
          .toString()
          .trim()
          .toUpperCase();

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
        final rawBreedName = (result['breed_name'] ?? '').toString().trim();
        if (rawBreedName.isEmpty) continue;
        final species = normalizeClubReportSpecies(
          (result['species'] ?? result['animal_species'] ?? '')
              .toString()
              .trim(),
        );
        final breedName = displayBreedNameForClubReport(
          reportName: 'sweepstakes_report',
          breedName: rawBreedName,
          species: species,
        );

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

  Future<void> _generateCurrentReportGroupByName(String reportName) async {
    if (reportName != 'unpaid_balances_report' &&
        reportName != 'paid_exhibitor_report') {
      final ready = await _ensureResultsReadyForReports();
      if (!ready) return;
    }

    if (_stateClubReportKeys.contains(reportName)) {
      await _syncClubDeliveryMetadata(
        latestFinalizeRunId: _dashboard?.latestFinalize.id,
      );
      await _refreshDashboardOnly(includeReports: true);
    } else {
      await _ensureReportsLoaded();
    }

    final artifacts = _currentArtifactsForReportGroup(reportName);

    if (artifacts.isEmpty) {
      await _generateReportByName(reportName);
      return;
    }

    setState(() {
      _generatingReport = true;
      _error = null;
    });

    final started = <String>{};
    final finished = <String>{};
    final failed = <String, Object>{};

    try {
      await _runGenerateAllReportsLive(
        artifacts,
        onStarted: started.add,
        onFinished: finished.add,
        onFailed: (artifactKey, error) {
          failed[artifactKey] = error;
        },
      );

      await _refreshDashboardOnly(includeReports: true);

      if (!mounted) return;

      final generatedCount = finished.length;
      final failedCount = failed.length;
      final label = reportName.replaceAll('_', ' ');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            failedCount == 0
                ? 'Generated $generatedCount $label report${generatedCount == 1 ? '' : 's'}.'
                : 'Generated $generatedCount report${generatedCount == 1 ? '' : 's'}; $failedCount failed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed generating report group: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

  Future<void> _generateReportByName(
    String reportName, {
    String? breedName,
    String? clubName,
    String? scope,
    String? showLetter,
    String? exhibitorId,
    String? exhibitorName,
  }) async {
    if (reportName != 'unpaid_balances_report' &&
        reportName != 'paid_exhibitor_report') {
      final ready = await _ensureResultsReadyForReports();
      if (!ready) return;
    }

    await _ensureReportsLoaded();

    final isSectionScopedReport =
        reportName == 'sweepstakes_report' ||
        reportName == 'breed_results_detail_report' ||
        reportName == 'details_by_breed' ||
        reportName == 'exh_by_breed' ||
        reportName == 'best_display_report';
    final isStateClubReport =
        reportName == 'details_by_breed' ||
        reportName == 'exh_by_breed' ||
        reportName == 'best_display_report';

    final hasExplicitScope =
        (scope ?? '').trim().isNotEmpty && (showLetter ?? '').trim().isNotEmpty;

    if (isSectionScopedReport && !hasExplicitScope) {
      if (isStateClubReport) {
        await _syncClubDeliveryMetadata(
          latestFinalizeRunId: _dashboard?.latestFinalize.id,
        );
        await _refreshDashboardOnly(includeReports: true);
      }

      final scopedArtifacts = _currentArtifactsForReportGroup(reportName);

      if (scopedArtifacts.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No scoped artifacts are available for this report. '
              'Re-finalize the show to seed them.',
            ),
          ),
        );
        return;
      }

      await _generateCurrentReportGroupByName(reportName);
      return;
    }

    if (isStateClubReport && hasExplicitScope) {
      await _generateStateClubReportArtifactsForTarget(
        reportName: reportName,
        clubName: clubName,
        scope: scope,
        showLetter: showLetter,
      );
      return;
    }

    final targetSpecies = isCavyClubReportTarget(breedName: breedName)
        ? 'cavy'
        : '';
    final targetDisplayBreedName = displayBreedNameForClubReport(
      reportName: reportName,
      breedName: breedName,
      species: targetSpecies,
    );
    final targetLoaderBreedName = loaderBreedNameForClubReport(
      reportName: reportName,
      breedName: targetDisplayBreedName,
      species: targetSpecies,
    );

    if (isBreedClubReportName(reportName) && targetSpecies == 'cavy') {
      await _ensureCombinedCavyClubReportArtifacts(
        latestFinalizeRunId: _dashboard?.latestFinalize.id,
      );
      await _refreshDashboardOnly(includeReports: true);
    }

    final isBreedJudgedTotalsReport =
        reportName == 'breed_judged_totals_report';
    final internalReportMetadata = _internalShowLevelReportMetadata(reportName);
    final selectedReportScopeLabel = isBreedJudgedTotalsReport
        ? (internalReportMetadata['scope_label'] ?? '').toString().trim()
        : '';
    final selectedReportSectionIds = isBreedJudgedTotalsReport
        ? _metadataSectionIds(internalReportMetadata)
        : const <String>[];

    if (isBreedJudgedTotalsReport &&
        !_selectedCloseoutScopeIsEntireShow &&
        selectedReportSectionIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one section for $_selectedCloseoutScopeLabel before generating this report.',
          ),
        ),
      );
      return;
    }

    try {
      setState(() {
        _generatingReport = true;
        _error = null;
      });

      await _saveArbaDetails();
      await _ensureLegsBuilder();
      await _ensureExhibitorBuilder();
      await _ensureUnpaidBalancesBuilder();
      await _ensurePaidExhibitorReportBuilder();
      await _ensureReportLogo();
      await _ensureEnteredExhibitorsContactBuilder();
      await _ensureRibbonPayoutBuilder();
      await _ensurePaybackReportBuilder();

      final repository = CloseoutRepository(supabase);
      final arbaLoader = ArbaReportLoader(repository);
      final arbaBuilder = ArbaReportPdfBuilder();
      final showBasics = await repository.loadShowBasics(widget.showId);
      final showDate = _formatShowDate(showBasics['start_date']);
      final sanctionNumber = await _loadArbaSanctionNumber(widget.showId);
      final isNationalShow = showBasics['is_national_show'] == true;

      final legsLoader = LegsReportLoader(repository);
      final exhibitorLoader = ExhibitorReportLoader(repository);

      final sweepstakesLoader = SweepstakesReportLoader(repository);
      final sweepstakesBuilder = SweepstakesReportPdf(
        logoBytes: _reportLogoBytes,
      );

      final breedResultsDetailReportLoader = BreedResultsDetailReportLoader(
        repository,
      );
      final breedResultsDetailReportBuilder = BreedResultsDetailReportPdf(
        logoBytes: _reportLogoBytes,
      );

      final unpaidBalancesLoader = UnpaidBalancesReportLoader(repository);
      final paidExhibitorReportLoader = PaidExhibitorReportLoader(repository);

      final enteredExhibitorsContactLoader =
          EnteredExhibitorsContactReportLoader(supabase);

      final ribbonPayoutLoader = RibbonPayoutReportLoader(repository);

      final paybackReportLoader = PaybackReportLoader();

      final registry = ReportRegistry(
        arbaLoader: arbaLoader,
        arbaBuilder: arbaBuilder,
        legsLoader: legsLoader,
        legsBuilder: _requiredReportDependency(
          _legsBuilder,
          'Legs report PDF builder',
        ),
        exhibitorLoader: exhibitorLoader,
        exhibitorBuilder: _requiredReportDependency(
          _exhibitorBuilder,
          'Exhibitor report PDF builder',
        ),
        sweepstakesLoader: sweepstakesLoader,
        sweepstakesBuilder: sweepstakesBuilder,
        breedResultsDetailReportLoader: breedResultsDetailReportLoader,
        breedResultsDetailReportBuilder: breedResultsDetailReportBuilder,
        detailsByBreedReportLoader: DetailsByBreedReportLoader(repository),
        detailsByBreedReportBuilder: DetailsByBreedReportPdf(
          logoBytes: _reportLogoBytes,
        ),
        exhibitorByBreedReportLoader: ExhibitorByBreedReportLoader(repository),
        exhibitorByBreedReportBuilder: ExhibitorByBreedReportPdf(
          logoBytes: _reportLogoBytes,
        ),
        unpaidBalancesLoader: unpaidBalancesLoader,
        unpaidBalancesBuilder: _requiredReportDependency(
          _unpaidBalancesBuilder,
          'Unpaid balances report PDF builder',
        ),
        paidExhibitorReportLoader: paidExhibitorReportLoader,
        paidExhibitorReportBuilder: _requiredReportDependency(
          _paidExhibitorReportBuilder,
          'Paid exhibitor report PDF builder',
        ),
        enteredExhibitorsContactLoader: enteredExhibitorsContactLoader,
        enteredExhibitorsContactBuilder: _requiredReportDependency(
          _enteredExhibitorsContactBuilder,
          'Entered exhibitors contact report PDF builder',
        ),
        ribbonPayoutLoader: ribbonPayoutLoader,
        ribbonPayoutBuilder: _requiredReportDependency(
          _ribbonPayoutBuilder,
          'Ribbon payout report PDF builder',
        ),
        paybackReportLoader: paybackReportLoader,
        paybackReportBuilder: _requiredReportDependency(
          _paybackReportBuilder,
          'Payback report PDF builder',
        ),
        judgeReportLoader: JudgeReportLoader(),
        judgeReportBuilder: JudgeReportPdfBuilder(),
        breedJudgedTotalsReportLoader: BreedJudgedTotalsReportLoader(),
        breedJudgedTotalsReportBuilder: BreedJudgedTotalsReportPdfBuilder(),
        bestDisplayReportLoader: BestDisplayReportLoader(),
        bestDisplayReportBuilder: BestDisplayReportPdfBuilder(),
      );

      final engine = ReportEngine(registry);
      final uploadService = ReportUploadService(supabase);

      final runner = CloseoutRunner(
        engine: engine,
        uploadService: uploadService,
      );

      ReportArtifactSummary? artifact;

      final reports = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
          .where((r) => r.reportName == reportName)
          .where((r) => r.isCurrent)
          .toList();

      if (reportName == 'exhibitor_report' || reportName == 'legs') {
        artifact = reports.cast<ReportArtifactSummary?>().firstWhere((r) {
          if (r == null) return false;
          final artExhibitorId = (_artifactMetaString(r, 'exhibitor_id') ?? '')
              .trim();
          return artExhibitorId == (exhibitorId ?? '').trim();
        }, orElse: () => null);
      } else if (reportName == 'sweepstakes_report' ||
          reportName == 'breed_results_detail_report' ||
          reportName == 'details_by_breed' ||
          reportName == 'exh_by_breed' ||
          reportName == 'best_display_report') {
        artifact = reports.cast<ReportArtifactSummary?>().firstWhere((r) {
          if (r == null) return false;

          final breed = (_artifactMetaString(r, 'breed_name') ?? '')
              .trim()
              .toLowerCase();
          final club = (_artifactMetaString(r, 'club_name') ?? '')
              .trim()
              .toLowerCase();
          final artScope = (_artifactMetaString(r, 'scope') ?? '')
              .trim()
              .toUpperCase();
          final artLetter = (_artifactMetaString(r, 'show_letter') ?? '')
              .trim()
              .toUpperCase();

          final isBreedSpecific =
              reportName == 'sweepstakes_report' ||
              reportName == 'breed_results_detail_report';
          final isClubSpecific =
              reportName == 'details_by_breed' ||
              reportName == 'exh_by_breed' ||
              reportName == 'best_display_report';

          final targetMatches = isBreedSpecific
              ? breed == targetDisplayBreedName.trim().toLowerCase()
              : !isClubSpecific ||
                    club == (clubName ?? '').trim().toLowerCase();

          return targetMatches &&
              artScope == (scope ?? '').trim().toUpperCase() &&
              artLetter == (showLetter ?? '').trim().toUpperCase();
        }, orElse: () => null);
      } else if (isBreedJudgedTotalsReport) {
        artifact = reports.cast<ReportArtifactSummary?>().firstWhere((r) {
          if (r == null) return false;
          final artifactScopeLabel =
              (_artifactMetaString(r, 'scope_label') ?? '').trim();

          if (selectedReportScopeLabel.isEmpty) {
            return artifactScopeLabel.isEmpty ||
                artifactScopeLabel == 'Entire Show';
          }

          return artifactScopeLabel == selectedReportScopeLabel;
        }, orElse: () => null);
      } else {
        artifact = reports.cast<ReportArtifactSummary?>().firstWhere(
          (r) => r != null,
          orElse: () => null,
        );
      }

      final resolvedArtifact =
          artifact ??
          await _createManualReportArtifact(
            reportName: reportName,
            metadata: {
              if (targetDisplayBreedName.trim().isNotEmpty)
                'breed_name': targetDisplayBreedName.trim(),
              if (targetSpecies.isNotEmpty) 'species': targetSpecies,
              if (clubName != null && clubName.trim().isNotEmpty)
                'club_name': clubName.trim(),
              if (scope != null && scope.trim().isNotEmpty)
                'scope': scope.trim(),
              if (showLetter != null && showLetter.trim().isNotEmpty)
                'show_letter': showLetter.trim(),
              if (exhibitorId != null && exhibitorId.trim().isNotEmpty)
                'exhibitor_id': exhibitorId.trim(),
              if (exhibitorName != null && exhibitorName.trim().isNotEmpty)
                'exhibitor_name': exhibitorName.trim(),
              ...internalReportMetadata,
            },
          );

      final artifactMetadataSectionIds = _metadataSectionIds(
        resolvedArtifact.metadata,
      );
      final breedJudgedSectionIds = selectedReportSectionIds.isNotEmpty
          ? selectedReportSectionIds
          : artifactMetadataSectionIds;
      final breedJudgedScopeLabel = selectedReportScopeLabel.isNotEmpty
          ? selectedReportScopeLabel
          : (_artifactMetaString(resolvedArtifact, 'scope_label') ?? '');

      debugPrint(
        '[Closeout:${widget.showId}] Generating report=$reportName '
        'artifact=${resolvedArtifact.id} '
        'scopeLabel=$breedJudgedScopeLabel '
        'sectionIds=${breedJudgedSectionIds.join(',')}',
      );

      await runner.generateSingleReport(
        showId: widget.showId,
        finalizeRunId: _dashboard?.latestFinalize.id ?? 'manual-run',
        reportName: reportName,
        artifactId: resolvedArtifact.id,
        breedName: targetLoaderBreedName,
        species: _artifactMetaString(resolvedArtifact, 'species'),
        scope: scope,
        scopeLabel: isBreedJudgedTotalsReport ? breedJudgedScopeLabel : null,
        sectionIds: isBreedJudgedTotalsReport ? breedJudgedSectionIds : null,
        showName: widget.showName,
        showDate: showDate,
        sanctionNumber: sanctionNumber,
        showLetter: showLetter,
        exhibitorId: exhibitorId,
        exhibitorName: exhibitorName,
        isNationalShow: isNationalShow,
      );

      await _refreshDashboardOnly(includeReports: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_friendlyReportName(reportName)} generated.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

  Future<void> _generateStateClubReportArtifactsForTarget({
    required String reportName,
    String? clubName,
    String? scope,
    String? showLetter,
  }) async {
    if (!_stateClubReportKeys.contains(reportName)) {
      await _generateReportByName(
        reportName,
        clubName: clubName,
        scope: scope,
        showLetter: showLetter,
      );
      return;
    }

    await _syncClubDeliveryMetadata(
      latestFinalizeRunId: _dashboard?.latestFinalize.id,
    );
    await _refreshDashboardOnly();

    final targetClub = (clubName ?? '').trim().toLowerCase();
    final targetScope = (scope ?? '').trim().toUpperCase();
    final targetLetter = (showLetter ?? '').trim().toUpperCase();

    final matchingArtifacts =
        (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .where((artifact) => artifact.isCurrent)
            .where((artifact) => artifact.reportName == reportName)
            .where(_artifactMatchesSelectedScope)
            .where((artifact) {
              final artifactClub =
                  (_artifactMetaString(artifact, 'club_name') ?? '')
                      .trim()
                      .toLowerCase();
              final artifactScope =
                  (_artifactMetaString(artifact, 'scope') ?? '')
                      .trim()
                      .toUpperCase();
              final artifactLetter =
                  (_artifactMetaString(artifact, 'show_letter') ?? '')
                      .trim()
                      .toUpperCase();
              final artifactSpecies =
                  (_artifactMetaString(artifact, 'species') ?? '')
                      .trim()
                      .toLowerCase();

              final clubMatches =
                  targetClub.isEmpty ||
                  artifactClub.isEmpty ||
                  artifactClub == targetClub;

              return clubMatches &&
                  artifactScope == targetScope &&
                  artifactLetter == targetLetter &&
                  (artifactSpecies == 'rabbit' || artifactSpecies == 'cavy');
            })
            .toList()
          ..sort(_compareStateClubArtifactsForGeneration);

    final pendingArtifacts = matchingArtifacts
        .where(
          (artifact) =>
              artifact.artifactStatus == 'queued' ||
              artifact.artifactStatus == 'failed',
        )
        .toList();

    final artifactsToGenerate = pendingArtifacts.isNotEmpty
        ? pendingArtifacts
        : matchingArtifacts;

    if (artifactsToGenerate.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No species-specific ${_friendlyReportName(reportName)} artifacts found.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _generatingReport = true;
      _error = null;
    });

    final started = <String>{};
    final finished = <String>{};
    final failed = <String, Object>{};

    try {
      await _runGenerateAllReportsLive(
        artifactsToGenerate,
        onStarted: started.add,
        onFinished: finished.add,
        onFailed: (artifactKey, error) {
          failed[artifactKey] = error;
        },
      );

      await _refreshDashboardOnly();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            failed.isEmpty
                ? 'Generated ${finished.length} ${_friendlyReportName(reportName)} file${finished.length == 1 ? '' : 's'}.'
                : 'Generated ${finished.length} file${finished.length == 1 ? '' : 's'}; ${failed.length} failed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed generating state club report: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

  int _compareStateClubArtifactsForGeneration(
    ReportArtifactSummary a,
    ReportArtifactSummary b,
  ) {
    final scopeCompare = ((_artifactMetaString(a, 'scope') ?? '').toUpperCase())
        .compareTo((_artifactMetaString(b, 'scope') ?? '').toUpperCase());
    if (scopeCompare != 0) return scopeCompare;

    final letterCompare =
        ((_artifactMetaString(a, 'show_letter') ?? '').toUpperCase()).compareTo(
          (_artifactMetaString(b, 'show_letter') ?? '').toUpperCase(),
        );
    if (letterCompare != 0) return letterCompare;

    final clubCompare =
        ((_artifactMetaString(a, 'club_name') ?? '').toLowerCase()).compareTo(
          (_artifactMetaString(b, 'club_name') ?? '').toLowerCase(),
        );
    if (clubCompare != 0) return clubCompare;

    final speciesCompare = _speciesSortRank(
      _artifactMetaString(a, 'species'),
    ).compareTo(_speciesSortRank(_artifactMetaString(b, 'species')));
    if (speciesCompare != 0) return speciesCompare;

    return a.id.compareTo(b.id);
  }

  int _speciesSortRank(String? species) {
    final normalized = (species ?? '').trim().toLowerCase();
    if (normalized == 'rabbit') return 0;
    if (normalized == 'cavy') return 1;
    return 2;
  }

  Future<void> _generateReportArtifact(ReportArtifactSummary artifact) async {
    if (artifact.reportName != 'unpaid_balances_report' &&
        artifact.reportName != 'paid_exhibitor_report') {
      final ready = await _ensureResultsReadyForReports();
      if (!ready) return;
    }

    setState(() {
      _generatingReport = true;
      _error = null;
    });

    final finished = <String>{};
    final failed = <String, Object>{};

    try {
      await _runGenerateAllReportsLive(
        [artifact],
        onStarted: (_) {},
        onFinished: finished.add,
        onFailed: (artifactKey, error) {
          failed[artifactKey] = error;
        },
      );

      await _refreshDashboardOnly();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? '${_friendlyReportName(artifact.reportName)} generated.'
                : '${_friendlyReportName(artifact.reportName)} failed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

  Future<void> _downloadReportByName(
    String reportName, {
    String? exhibitorId,
    String? breedName,
    String? clubName,
    String? scope,
    String? showLetter,
  }) async {
    try {
      await _ensureReportsLoaded();

      final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

      var matches = reports.where(
        (r) =>
            r.reportName == reportName &&
            r.isCurrent &&
            r.artifactStatus == 'generated' &&
            (r.storageBucket?.isNotEmpty == true) &&
            (r.storagePath?.isNotEmpty == true),
      );

      if (reportName == 'arba_report' &&
          exhibitorId == null &&
          breedName == null &&
          scope == null &&
          showLetter == null) {
        final arbaArtifacts = matches.toList()
          ..sort((a, b) {
            final aLabel = (_artifactMetaString(a, 'section_label') ?? '')
                .toLowerCase();
            final bLabel = (_artifactMetaString(b, 'section_label') ?? '')
                .toLowerCase();
            final labelCmp = aLabel.compareTo(bLabel);
            if (labelCmp != 0) return labelCmp;

            final aLetter = (_artifactMetaString(a, 'show_letter') ?? '')
                .toLowerCase();
            final bLetter = (_artifactMetaString(b, 'show_letter') ?? '')
                .toLowerCase();
            return aLetter.compareTo(bLetter);
          });

        if (arbaArtifacts.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No generated ARBA reports found.')),
          );
          return;
        }

        for (final artifact in arbaArtifacts) {
          final signedUrl = await supabase.storage
              .from(artifact.storageBucket!)
              .createSignedUrl(artifact.storagePath!, 60 * 5);

          await launchUrlString(
            signedUrl,
            mode: LaunchMode.externalApplication,
          );
        }

        return;
      }

      if ((reportName == 'exhibitor_report' || reportName == 'legs') &&
          exhibitorId != null &&
          exhibitorId.trim().isNotEmpty) {
        matches = matches.where(
          (r) =>
              (r.metadata['exhibitor_id'] ?? '').toString().trim() ==
              exhibitorId.trim(),
        );
      }

      if (reportName == 'sweepstakes_report' ||
          reportName == 'breed_results_detail_report' ||
          reportName == 'details_by_breed' ||
          reportName == 'exh_by_breed' ||
          reportName == 'best_display_report') {
        final targetSpecies = isCavyClubReportTarget(breedName: breedName)
            ? 'cavy'
            : '';
        final targetBreedName = displayBreedNameForClubReport(
          reportName: reportName,
          breedName: breedName,
          species: targetSpecies,
        ).toLowerCase();

        matches = matches.where((r) {
          final artBreed = (r.metadata['breed_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final artScope = (r.metadata['scope'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          final artLetter = (r.metadata['show_letter'] ?? '')
              .toString()
              .trim()
              .toUpperCase();

          final artClub = (r.metadata['club_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final isBreedSpecific =
              reportName == 'sweepstakes_report' ||
              reportName == 'breed_results_detail_report';
          final isClubSpecific =
              reportName == 'details_by_breed' ||
              reportName == 'exh_by_breed' ||
              reportName == 'best_display_report';

          final targetMatches = isBreedSpecific
              ? artBreed == targetBreedName
              : !isClubSpecific ||
                    artClub == (clubName ?? '').trim().toLowerCase();

          return targetMatches &&
              artScope == (scope ?? '').trim().toUpperCase() &&
              artLetter == (showLetter ?? '').trim().toUpperCase();
        });
      }

      final list = matches.toList()
        ..sort((a, b) {
          final aDt =
              DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt =
              DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDt.compareTo(aDt);
        });

      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No generated ${_friendlyReportName(reportName)} found.',
            ),
          ),
        );
        return;
      }

      final newest = list.first;

      final signedUrl = await supabase.storage
          .from(newest.storageBucket!)
          .createSignedUrl(newest.storagePath!, 60 * 5);

      await launchUrlString(signedUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _downloadReportArtifact(ReportArtifactSummary artifact) async {
    try {
      if (artifact.artifactStatus != 'generated' ||
          artifact.storageBucket?.isNotEmpty != true ||
          artifact.storagePath?.isNotEmpty != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No generated ${_friendlyReportName(artifact.reportName)} found.',
            ),
          ),
        );
        return;
      }

      final signedUrl = await supabase.storage
          .from(artifact.storageBucket!)
          .createSignedUrl(artifact.storagePath!, 60 * 5);

      await launchUrlString(signedUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Map<String, dynamic> _normalizeFunctionData(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Future<void> _sendReportArtifactEmail({
    required ReportArtifactSummary artifact,
    required String mode, // exhibitor, club, single
  }) async {
    final response = await supabase.functions.invoke(
      'send-closeout-report-email',
      body: {
        'show_id': widget.showId,
        'show_name': widget.showName,
        'artifact_id': artifact.id,
        'report_name': artifact.reportName,
        'mode': mode,
      },
    );

    final data = _normalizeFunctionData(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        data['error']?.toString() ??
            data['message']?.toString() ??
            'Email failed.',
      );
    }
  }

  void _showCloseoutSnack(SnackBar snackBar) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  String _artifactScope(ReportArtifactSummary artifact) {
    return (_artifactMetaString(artifact, 'scope') ?? '').trim().toUpperCase();
  }

  String _artifactShowLetter(ReportArtifactSummary artifact) {
    return (_artifactMetaString(artifact, 'show_letter') ?? '')
        .trim()
        .toUpperCase();
  }

  bool _artifactHasSameScope(
    ReportArtifactSummary artifact,
    ReportArtifactSummary sourceArtifact,
  ) {
    final sourceScope = _artifactScope(sourceArtifact);
    return sourceScope.isNotEmpty && _artifactScope(artifact) == sourceScope;
  }

  bool _artifactHasSameLetter(
    ReportArtifactSummary artifact,
    ReportArtifactSummary sourceArtifact,
  ) {
    final sourceLetter = _artifactShowLetter(sourceArtifact);
    return sourceLetter.isNotEmpty &&
        _artifactShowLetter(artifact) == sourceLetter;
  }

  int _letterEmailReportRank(String reportName) {
    switch (reportName) {
      case 'exhibitor_report':
        return 0;
      case 'legs':
        return 1;
      case 'details_by_breed':
        return 0;
      case 'exh_by_breed':
        return 1;
      case 'best_display_report':
        return 2;
      case 'sweepstakes_report':
        return 0;
      case 'breed_results_detail_report':
        return 1;
      default:
        return 99;
    }
  }

  int _compareEmailArtifacts(ReportArtifactSummary a, ReportArtifactSummary b) {
    final scopeCmp = _artifactScope(a).compareTo(_artifactScope(b));
    if (scopeCmp != 0) return scopeCmp;

    final letterCmp = _artifactShowLetter(a).compareTo(_artifactShowLetter(b));
    if (letterCmp != 0) return letterCmp;

    final reportCmp = _letterEmailReportRank(
      a.reportName,
    ).compareTo(_letterEmailReportRank(b.reportName));
    if (reportCmp != 0) return reportCmp;

    final breedCmp = (_artifactMetaString(a, 'breed_name') ?? '')
        .toLowerCase()
        .compareTo((_artifactMetaString(b, 'breed_name') ?? '').toLowerCase());
    if (breedCmp != 0) return breedCmp;

    return a.reportName.compareTo(b.reportName);
  }

  int _compareClubEmailArtifacts(
    ReportArtifactSummary a,
    ReportArtifactSummary b,
  ) {
    final scopeCmp = _artifactScope(a).compareTo(_artifactScope(b));
    if (scopeCmp != 0) return scopeCmp;

    final letterCmp = _artifactShowLetter(a).compareTo(_artifactShowLetter(b));
    if (letterCmp != 0) return letterCmp;

    final reportCmp = a.reportName.compareTo(b.reportName);
    if (reportCmp != 0) return reportCmp;

    final speciesCmp = _speciesSortRank(
      _artifactMetaString(a, 'species'),
    ).compareTo(_speciesSortRank(_artifactMetaString(b, 'species')));
    if (speciesCmp != 0) return speciesCmp;

    final breedCmp = (_artifactMetaString(a, 'breed_name') ?? '')
        .toLowerCase()
        .compareTo((_artifactMetaString(b, 'breed_name') ?? '').toLowerCase());
    if (breedCmp != 0) return breedCmp;

    return a.id.compareTo(b.id);
  }

  List<ReportArtifactSummary> _allLetterExhibitorArtifactsFor({
    required ReportArtifactSummary sourceArtifact,
    required _ExhibitorEmailTarget exhibitor,
  }) {
    final artifacts =
        (_dashboard?.reports ?? const <ReportArtifactSummary>[]).where((
          artifact,
        ) {
          if (artifact.reportName != 'exhibitor_report' &&
              artifact.reportName != 'legs') {
            return false;
          }
          return _artifactIsUsableCurrent(artifact) &&
              _artifactHasSameScope(artifact, sourceArtifact) &&
              _artifactMatchesExhibitor(artifact, exhibitor);
        }).toList()..sort(_compareEmailArtifacts);

    return artifacts;
  }

  List<ReportArtifactSummary> _letterExhibitorArtifactsFor({
    required ReportArtifactSummary sourceArtifact,
    required _ExhibitorEmailTarget exhibitor,
  }) {
    final artifacts =
        _allLetterExhibitorArtifactsFor(
              sourceArtifact: sourceArtifact,
              exhibitor: exhibitor,
            )
            .where(
              (artifact) => _artifactHasSameLetter(artifact, sourceArtifact),
            )
            .toList()
          ..sort(_compareEmailArtifacts);

    return artifacts;
  }

  _ClubEmailTarget _clubTargetForArtifactLetter(
    _ClubEmailTarget target,
    ReportArtifactSummary artifact,
  ) {
    return _ClubEmailTarget(
      clubName: target.clubName,
      breedName: target.breedName,
      scope: target.scope,
      showLetter: _artifactShowLetter(artifact),
      email: target.email,
      species: target.species,
      sanctioningBody: target.sanctioningBody,
    );
  }

  List<ReportArtifactSummary> _allLetterClubArtifactsFor({
    required ReportArtifactSummary sourceArtifact,
    required _ClubEmailTarget target,
  }) {
    final isStateClub =
        target.sanctioningBody.trim().toUpperCase() == 'STATE CLUB';
    final reportNames = isStateClub
        ? _stateClubReportKeys
        : _breedClubReportKeys;
    final artifactsById = <String, ReportArtifactSummary>{};

    for (final reportName in reportNames) {
      for (final artifact in _allGeneratedArtifactsWhere(reportName, (
        artifact,
      ) {
        if (!_artifactHasSameScope(artifact, sourceArtifact)) return false;
        final targetForLetter = _clubTargetForArtifactLetter(target, artifact);
        return _artifactMatchesClubTarget(artifact, targetForLetter);
      })) {
        artifactsById[artifact.id] = artifact;
      }
    }

    final artifacts = artifactsById.values.toList()
      ..sort(_compareClubEmailArtifacts);
    return artifacts;
  }

  List<ReportArtifactSummary> _letterClubArtifactsFor({
    required ReportArtifactSummary sourceArtifact,
    required _ClubEmailTarget target,
  }) {
    final artifacts =
        _allLetterClubArtifactsFor(
              sourceArtifact: sourceArtifact,
              target: target,
            )
            .where(
              (artifact) => _artifactHasSameLetter(artifact, sourceArtifact),
            )
            .toList()
          ..sort(_compareClubEmailArtifacts);

    return artifacts;
  }

  _ExhibitorEmailTarget _exhibitorTargetForArtifact(
    ReportArtifactSummary sourceArtifact, {
    String? exhibitorId,
    String? exhibitorName,
    String? exhibitorEmail,
  }) {
    final resolvedId =
        (exhibitorId ??
                _artifactMetaString(sourceArtifact, 'exhibitor_id') ??
                '')
            .trim();
    final resolvedName =
        (exhibitorName ??
                _artifactMetaString(sourceArtifact, 'exhibitor_name') ??
                'Exhibitor')
            .trim();
    final resolvedEmail =
        (exhibitorEmail ??
                _artifactMetaString(sourceArtifact, 'exhibitor_email') ??
                _artifactMetaString(sourceArtifact, 'email') ??
                '')
            .trim();

    return _ExhibitorEmailTarget(
      exhibitorId: resolvedId,
      exhibitorName: resolvedName.isEmpty ? 'Exhibitor' : resolvedName,
      email: resolvedEmail,
    );
  }

  Future<_ClubEmailTarget?> _clubTargetForArtifact(
    ReportArtifactSummary sourceArtifact,
  ) async {
    final reportName = sourceArtifact.reportName;
    final isStateClubReport =
        reportName == 'details_by_breed' ||
        reportName == 'exh_by_breed' ||
        reportName == 'best_display_report';
    final isBreedClubReport =
        reportName == 'sweepstakes_report' ||
        reportName == 'breed_results_detail_report';

    if (!isStateClubReport && !isBreedClubReport) return null;

    final clubTargets = await _loadClubEmailTargets();
    final sourceScope = _artifactScope(sourceArtifact);
    final sourceLetter = _artifactShowLetter(sourceArtifact);

    final sourceSpecies = (_artifactMetaString(sourceArtifact, 'species') ?? '')
        .trim()
        .toLowerCase();

    final matches = clubTargets.where((target) {
      if (target.scope.trim().toUpperCase() != sourceScope) return false;
      if (target.showLetter.trim().toUpperCase() != sourceLetter) return false;
      if (isStateClubReport &&
          target.sanctioningBody.trim().toUpperCase() != 'STATE CLUB') {
        return false;
      }
      if (isBreedClubReport &&
          target.sanctioningBody.trim().toUpperCase() == 'STATE CLUB') {
        return false;
      }
      return _artifactMatchesClubTarget(sourceArtifact, target);
    }).toList();

    if (matches.isEmpty) return null;

    matches.sort((a, b) {
      int rank(_ClubEmailTarget target) {
        final targetSpecies = target.species.trim().toLowerCase();
        if (targetSpecies == sourceSpecies) return 0;
        if (targetSpecies == 'combined') return 1;
        return 2;
      }

      return rank(a).compareTo(rank(b));
    });

    final selected = matches.first;
    final selectedSpecies = selected.species.trim().toLowerCase();
    if (isStateClubReport &&
        selectedSpecies == 'combined' &&
        (sourceSpecies == 'rabbit' || sourceSpecies == 'cavy')) {
      return _ClubEmailTarget(
        clubName: selected.clubName,
        breedName: selected.breedName,
        scope: selected.scope,
        showLetter: selected.showLetter,
        email: selected.email,
        species: sourceSpecies,
        sanctioningBody: selected.sanctioningBody,
      );
    }

    return selected;
  }

  String _clubSpeciesLabel(_ClubEmailTarget target) {
    final species = target.species.trim().toLowerCase();
    if (species == 'rabbit') return 'Rabbit ';
    if (species == 'cavy') return 'Cavy ';
    return '';
  }

  String _clubEmailSubject({
    required _ClubEmailTarget target,
    required ReportArtifactSummary sourceArtifact,
    required bool allLetters,
  }) {
    final scope = _artifactScope(sourceArtifact);
    final letter = _artifactShowLetter(sourceArtifact);
    final suffix = allLetters ? 'All $scope Shows' : '$scope $letter';
    final isStateClub =
        target.sanctioningBody.trim().toUpperCase() == 'STATE CLUB';

    if (isStateClub) {
      return '${widget.showName} - ${target.clubName} ${_clubSpeciesLabel(target)}Club Reports - $suffix';
    }

    return '${widget.showName} - ${target.breedName} Club Reports - $suffix';
  }

  String _formatIncludedShowLetters(
    List<ReportArtifactSummary> artifacts, {
    bool includeScope = true,
  }) {
    final labels =
        artifacts
            .map((artifact) {
              final scope = _artifactScope(artifact);
              final letter = _artifactShowLetter(artifact);
              if (letter.isEmpty) return '';
              return includeScope && scope.isNotEmpty
                  ? '$scope $letter'
                  : letter;
            })
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    if (labels.isEmpty) return 'the selected show letters';
    if (labels.length == 1) return labels.first;
    if (labels.length == 2) return '${labels.first} and ${labels.last}';
    return '${labels.take(labels.length - 1).join(', ')}, and ${labels.last}';
  }

  Future<bool> _confirmEmailAllLetters({
    required String to,
    required String scope,
    required List<ReportArtifactSummary> artifacts,
  }) async {
    final letters = _formatIncludedShowLetters(artifacts, includeScope: true);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Email all show letters?'),
            content: Text(
              'You are about to email ${artifacts.length} file${artifacts.length == 1 ? '' : 's'} for $letters to $to.\n\nScope: $scope',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Send All Letters'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendExhibitorReportsForArtifactLetter({
    required ReportArtifactSummary sourceArtifact,
    required _ExhibitorEmailTarget exhibitor,
  }) async {
    if (await _blockedBySupportModeForEmailSend('Exhibitor')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;
    if (!mounted) return;

    try {
      if (exhibitor.email.trim().isEmpty) {
        _showCloseoutSnack(
          const SnackBar(content: Text('No email found for this exhibitor.')),
        );
        return;
      }

      final artifacts = _letterExhibitorArtifactsFor(
        sourceArtifact: sourceArtifact,
        exhibitor: exhibitor,
      );

      if (artifacts.isEmpty) {
        _showCloseoutSnack(
          const SnackBar(
            content: Text(
              'No generated exhibitor reports found for this letter.',
            ),
          ),
        );
        return;
      }

      final scope = _artifactScope(sourceArtifact);
      final showLetter = _artifactShowLetter(sourceArtifact);

      await _sendExhibitorArtifactsEmail(
        artifacts: artifacts,
        to: exhibitor.email,
        subject: '${widget.showName} - Exhibitor Reports - $scope $showLetter',
        message:
            'Attached are your exhibitor reports and any earned legs for ${widget.showName} - $scope $showLetter.',
        allowLegs: true,
      );

      if (!mounted) return;
      _showCloseoutSnack(
        SnackBar(content: Text('Emailed ${artifacts.length} file(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showCloseoutSnack(SnackBar(content: Text('Email failed: $e')));
    }
  }

  Future<void> _sendExhibitorReportsForAllLetters({
    required ReportArtifactSummary sourceArtifact,
    required _ExhibitorEmailTarget exhibitor,
  }) async {
    if (await _blockedBySupportModeForEmailSend('Exhibitor')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;
    if (!mounted) return;

    try {
      if (exhibitor.email.trim().isEmpty) {
        _showCloseoutSnack(
          const SnackBar(content: Text('No email found for this exhibitor.')),
        );
        return;
      }

      final artifacts = _allLetterExhibitorArtifactsFor(
        sourceArtifact: sourceArtifact,
        exhibitor: exhibitor,
      );

      if (artifacts.isEmpty) {
        _showCloseoutSnack(
          const SnackBar(
            content: Text(
              'No generated exhibitor reports found for all letters.',
            ),
          ),
        );
        return;
      }

      final scope = _artifactScope(sourceArtifact);
      final confirmed = await _confirmEmailAllLetters(
        to: exhibitor.email,
        scope: scope,
        artifacts: artifacts,
      );
      if (!confirmed) return;
      if (!mounted) return;

      await _sendExhibitorArtifactsEmail(
        artifacts: artifacts,
        to: exhibitor.email,
        subject: '${widget.showName} - Exhibitor Reports - All $scope Shows',
        message:
            'Attached are your exhibitor reports and any earned legs for all $scope show letters from ${widget.showName}.',
        allowLegs: true,
      );

      if (!mounted) return;
      _showCloseoutSnack(
        SnackBar(content: Text('Emailed ${artifacts.length} file(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showCloseoutSnack(SnackBar(content: Text('Email failed: $e')));
    }
  }

  Future<void> _sendClubReportsForArtifactLetter({
    required ReportArtifactSummary sourceArtifact,
    required _ClubEmailTarget target,
  }) async {
    if (await _blockedBySupportModeForEmailSend('Club')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;
    if (!mounted) return;

    try {
      final artifacts = _letterClubArtifactsFor(
        sourceArtifact: sourceArtifact,
        target: target,
      );

      if (artifacts.isEmpty) {
        _showCloseoutSnack(
          const SnackBar(
            content: Text('No generated club reports found for this letter.'),
          ),
        );
        return;
      }

      final scope = _artifactScope(sourceArtifact);
      final showLetter = _artifactShowLetter(sourceArtifact);

      await _sendClubArtifactsEmail(
        artifacts: artifacts,
        to: target.email,
        subject: _clubEmailSubject(
          target: target,
          sourceArtifact: sourceArtifact,
          allLetters: false,
        ),
        message:
            'Attached are the reports for ${widget.showName} - $scope $showLetter.',
      );

      if (!mounted) return;
      _showCloseoutSnack(
        SnackBar(content: Text('Emailed ${artifacts.length} file(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showCloseoutSnack(SnackBar(content: Text('Email failed: $e')));
    }
  }

  Future<void> _sendClubReportsForAllLetters({
    required ReportArtifactSummary sourceArtifact,
    required _ClubEmailTarget target,
  }) async {
    if (await _blockedBySupportModeForEmailSend('Club')) return;

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;
    if (!mounted) return;

    try {
      final artifacts = _allLetterClubArtifactsFor(
        sourceArtifact: sourceArtifact,
        target: target,
      );

      if (artifacts.isEmpty) {
        _showCloseoutSnack(
          const SnackBar(
            content: Text('No generated club reports found for all letters.'),
          ),
        );
        return;
      }

      final scope = _artifactScope(sourceArtifact);
      final confirmed = await _confirmEmailAllLetters(
        to: target.email,
        scope: scope,
        artifacts: artifacts,
      );
      if (!confirmed) return;
      if (!mounted) return;

      await _sendClubArtifactsEmail(
        artifacts: artifacts,
        to: target.email,
        subject: _clubEmailSubject(
          target: target,
          sourceArtifact: sourceArtifact,
          allLetters: true,
        ),
        message:
            'Attached are the reports for all $scope show letters from ${widget.showName}.',
      );

      if (!mounted) return;
      _showCloseoutSnack(
        SnackBar(content: Text('Emailed ${artifacts.length} file(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showCloseoutSnack(SnackBar(content: Text('Email failed: $e')));
    }
  }

  Future<void> _emailArtifactThisLetter(
    ReportArtifactSummary sourceArtifact, {
    String? exhibitorId,
    String? exhibitorName,
    String? exhibitorEmail,
  }) async {
    if (sourceArtifact.reportName == 'exhibitor_report' ||
        sourceArtifact.reportName == 'legs') {
      return _sendExhibitorReportsForArtifactLetter(
        sourceArtifact: sourceArtifact,
        exhibitor: _exhibitorTargetForArtifact(
          sourceArtifact,
          exhibitorId: exhibitorId,
          exhibitorName: exhibitorName,
          exhibitorEmail: exhibitorEmail,
        ),
      );
    }

    final target = await _clubTargetForArtifact(sourceArtifact);
    if (target == null) {
      if (!mounted) return;
      _showCloseoutSnack(
        const SnackBar(content: Text('No club email found for this report.')),
      );
      return;
    }

    return _sendClubReportsForArtifactLetter(
      sourceArtifact: sourceArtifact,
      target: target,
    );
  }

  Future<void> _emailArtifactAllLetters(
    ReportArtifactSummary sourceArtifact, {
    String? exhibitorId,
    String? exhibitorName,
    String? exhibitorEmail,
  }) async {
    if (sourceArtifact.reportName == 'exhibitor_report' ||
        sourceArtifact.reportName == 'legs') {
      return _sendExhibitorReportsForAllLetters(
        sourceArtifact: sourceArtifact,
        exhibitor: _exhibitorTargetForArtifact(
          sourceArtifact,
          exhibitorId: exhibitorId,
          exhibitorName: exhibitorName,
          exhibitorEmail: exhibitorEmail,
        ),
      );
    }

    final target = await _clubTargetForArtifact(sourceArtifact);
    if (target == null) {
      if (!mounted) return;
      _showCloseoutSnack(
        const SnackBar(content: Text('No club email found for this report.')),
      );
      return;
    }

    return _sendClubReportsForAllLetters(
      sourceArtifact: sourceArtifact,
      target: target,
    );
  }

  Future<void> _emailReportByName(
    String reportName, {
    String? exhibitorId,
    String? exhibitorEmail,
    String? breedName,
    String? clubName,
    String? scope,
    String? showLetter,
  }) async {
    if (await _blockedBySupportModeForEmailSend('Report')) return;

    try {
      await _ensureReportsLoaded();

      var artifacts = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
          .where((r) => r.reportName == reportName)
          .where(_artifactIsUsableCurrent);

      if ((reportName == 'exhibitor_report' || reportName == 'legs') &&
          exhibitorId != null &&
          exhibitorId.trim().isNotEmpty) {
        artifacts = artifacts.where(
          (r) =>
              (r.metadata['exhibitor_id'] ?? '').toString().trim() ==
              exhibitorId.trim(),
        );
      }

      if (reportName == 'sweepstakes_report' ||
          reportName == 'breed_results_detail_report' ||
          reportName == 'details_by_breed' ||
          reportName == 'exh_by_breed' ||
          reportName == 'best_display_report') {
        final targetSpecies = isCavyClubReportTarget(breedName: breedName)
            ? 'cavy'
            : '';
        final targetBreedName = displayBreedNameForClubReport(
          reportName: reportName,
          breedName: breedName,
          species: targetSpecies,
        ).toLowerCase();

        artifacts = artifacts.where((r) {
          final artifactBreed = (r.metadata['breed_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final artifactClub = (r.metadata['club_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final artifactScope = (r.metadata['scope'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          final artifactLetter = (r.metadata['show_letter'] ?? '')
              .toString()
              .trim()
              .toUpperCase();

          final isBreedSpecific =
              reportName == 'sweepstakes_report' ||
              reportName == 'breed_results_detail_report';
          final targetMatches = isBreedSpecific
              ? artifactBreed == targetBreedName
              : artifactClub == (clubName ?? '').trim().toLowerCase();

          return targetMatches &&
              artifactScope == (scope ?? '').trim().toUpperCase() &&
              artifactLetter == (showLetter ?? '').trim().toUpperCase();
        });
      }

      final list = artifacts.toList()
        ..sort((a, b) {
          final aDt =
              DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt =
              DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDt.compareTo(aDt);
        });

      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No generated ${_friendlyReportName(reportName)} found to email.',
            ),
          ),
        );
        return;
      }

      final artifact = list.first;

      if (reportName == 'arba_report') {
        final email = (await _loadArbaReportEmailTarget()) ?? '';

        if (email.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No ARBA email found for this report. Add the ARBA sweepstakes email to the ARBA sanction record first.',
              ),
            ),
          );
          return;
        }

        await _sendClubArtifactsEmail(
          artifacts: list,
          to: email,
          subject: '${widget.showName} - ARBA Show Report',
          message:
              'Attached ${list.length == 1 ? 'is the ARBA show report' : 'are the ARBA show reports'} for ${widget.showName}.',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              list.length == 1
                  ? 'ARBA Report emailed to ARBA at $email.'
                  : '${list.length} ARBA Reports emailed to ARBA at $email.',
            ),
          ),
        );
        return;
      }

      final isClubReport =
          reportName == 'sweepstakes_report' ||
          reportName == 'breed_results_detail_report' ||
          reportName == 'details_by_breed' ||
          reportName == 'exh_by_breed' ||
          reportName == 'best_display_report';

      if (isClubReport) {
        final clubTargets = await _loadClubEmailTargets();
        final targetSpecies = isCavyClubReportTarget(breedName: breedName)
            ? 'cavy'
            : '';
        final targetBreedName = displayBreedNameForClubReport(
          reportName: reportName,
          breedName: breedName,
          species: targetSpecies,
        ).toLowerCase();

        final matchingTargets = clubTargets.where((target) {
          final matchesSection =
              target.scope.trim().toUpperCase() ==
                  (scope ?? '').trim().toUpperCase() &&
              target.showLetter.trim().toUpperCase() ==
                  (showLetter ?? '').trim().toUpperCase();

          if (!matchesSection) return false;

          final isStateClubReport =
              reportName == 'details_by_breed' ||
              reportName == 'exh_by_breed' ||
              reportName == 'best_display_report';

          if (isStateClubReport) {
            return target.sanctioningBody.trim().toUpperCase() ==
                    'STATE CLUB' &&
                target.clubName.trim().toLowerCase() ==
                    (clubName ?? '').trim().toLowerCase();
          }

          return target.breedName.trim().toLowerCase() == targetBreedName;
        }).toList();

        if (matchingTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No club email found for this report.'),
            ),
          );
          return;
        }

        final target = matchingTargets.first;
        final isStateClub =
            target.sanctioningBody.trim().toUpperCase() == 'STATE CLUB';

        await _sendClubArtifactsEmail(
          artifacts: [artifact],
          to: target.email,
          subject: isStateClub
              ? '${widget.showName} - ${target.clubName} Club Report'
              : '${widget.showName} - ${target.breedName} Club Report',
          message: 'Attached is the club report from ${widget.showName}.',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_friendlyReportName(reportName)} emailed.'),
          ),
        );
        return;
      }

      final email =
          (exhibitorEmail ??
                  artifact.metadata['exhibitor_email'] ??
                  artifact.metadata['email'] ??
                  '')
              .toString()
              .trim();

      if (email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reportName == 'legs'
                  ? 'No email found for this legs recipient.'
                  : 'No email found for this exhibitor.',
            ),
          ),
        );
        return;
      }

      final response = await supabase.functions.invoke(
        'send-exhibitor-report-email',
        body: {
          'show_id': widget.showId,
          'artifact_ids': [artifact.id],
          'to': email,
        },
      );

      final data = _normalizeFunctionData(response.data);

      if (response.status < 200 || response.status >= 300) {
        throw Exception(
          data['error']?.toString() ??
              data['message']?.toString() ??
              'Email failed.',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_friendlyReportName(reportName)} emailed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Email failed: $e')));
    }
  }

  List<ReportArtifactSummary> _allGeneratedArtifactsWhere(
    String reportName,
    bool Function(ReportArtifactSummary artifact) test,
  ) {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

    return reports
        .where((a) => a.reportName == reportName)
        .where(_artifactIsUsableCurrent)
        .where(test)
        .toList();
  }

  void _rebuildReportCaches() {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];
    final namesByGroup = <String, List<String>>{};

    for (final groupKey in const ['arba', 'exhibitor', 'club', 'other']) {
      final filtered = switch (groupKey) {
        'arba' =>
          reports.where((r) => _arbaReportKeys.contains(r.reportName)).toList(),
        'exhibitor' =>
          reports
              .where((r) => _exhibitorReportKeys.contains(r.reportName))
              .toList(),
        'club' =>
          reports.where((r) => _clubReportKeys.contains(r.reportName)).toList(),
        'other' => reports.where((r) {
          return !_arbaReportKeys.contains(r.reportName) &&
              !_exhibitorReportKeys.contains(r.reportName) &&
              !_clubReportKeys.contains(r.reportName);
        }).toList(),
        _ => reports,
      };

      final scoped = filtered.where(_artifactMatchesSelectedScope).toList()
        ..sort(_compareReportsForDisplay);

      final names = scoped.map((r) => r.reportName).toSet().toList();
      _addManualReportNames(groupKey, names);
      names.sort(_compareReportNamesForDisplay);
      namesByGroup[groupKey] = names;
    }

    _cachedReportNamesByGroup = namesByGroup;
  }

  int _compareReportsForDisplay(
    ReportArtifactSummary a,
    ReportArtifactSummary b,
  ) {
    return _compareReportNamesForDisplay(a.reportName, b.reportName);
  }

  int _compareReportNamesForDisplay(String a, String b) {
    final aIndex = _reportDisplayOrder.indexOf(a);
    final bIndex = _reportDisplayOrder.indexOf(b);

    if (aIndex == -1 && bIndex == -1) {
      return _friendlyReportName(a).compareTo(_friendlyReportName(b));
    }
    if (aIndex == -1) return 1;
    if (bIndex == -1) return -1;
    return aIndex.compareTo(bIndex);
  }

  void _addManualReportNames(String groupKey, List<String> names) {
    final manualNames = switch (groupKey) {
      'arba' => _arbaReportKeys,
      'exhibitor' => _exhibitorReportKeys,
      'club' => _clubReportKeys,
      'other' => const <String>{
        'unpaid_balances_report',
        'paid_exhibitor_report',
        'entered_exhibitors_contact_report',
        'ribbon_payout_report',
        'judge_report',
        'breed_judged_totals_report',
        'best_display_report',
        'payback_report',
      },
      _ => const <String>{},
    };

    for (final name in manualNames) {
      if (!names.contains(name)) names.add(name);
    }
  }

  List<String> _reportNamesForGroup(String groupKey) {
    return _cachedReportNamesByGroup[groupKey] ?? const <String>[];
  }

  Widget _buildReportActionsSection({
    required bool reportsBlocked,
    required String? reportsBlockedMessage,
  }) {
    return AppTheme.surfaceTextScope(
      context,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.muted.withValues(alpha: .18)),
        ),
        child: ExpansionTile(
          initiallyExpanded: _reportsSectionOpen,
          onExpansionChanged: (expanded) {
            setState(() {
              _reportsSectionOpen = expanded;
            });
            if (expanded) {
              unawaited(_ensureReportsLoaded());
            }
          },
          title: const Text('Reports'),
          subtitle: Text(
            _reportsLoaded
                ? 'Generate, download, and distribute closeout reports.'
                : 'Open to load generated reports and delivery history.',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (_loadingReports && !_reportsLoaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_reportsError != null && !_reportsLoaded)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Failed loading reports: $_reportsError',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _ensureReportsLoaded(force: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (!_reportsLoaded)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: () => _ensureReportsLoaded(),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Load Reports'),
                ),
              )
            else
              Column(
                children: [
                  if (_loadingReports) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 12),
                  ],
                  _ReportActionsCard(
                    key: ValueKey('report-actions-${widget.showId}'),
                    showId: widget.showId,
                    reports:
                        _dashboard?.reports ?? const <ReportArtifactSummary>[],
                    groupedReportNames: {
                      'arba': _reportNamesForGroup('arba'),
                      'exhibitor': _reportNamesForGroup('exhibitor'),
                      'club': _reportNamesForGroup('club'),
                      'other': _reportNamesForGroup('other'),
                    },
                    onGenerate:
                        (
                          reportName, {
                          String? breedName,
                          String? clubName,
                          String? scope,
                          String? showLetter,
                          String? exhibitorId,
                          String? exhibitorName,
                        }) {
                          final isSingleTarget =
                              breedName != null ||
                              clubName != null ||
                              scope != null ||
                              showLetter != null ||
                              exhibitorId != null ||
                              exhibitorName != null;

                          if (!isSingleTarget && reportName == 'arba_report') {
                            return _generateCurrentReportGroupByName(
                              reportName,
                            );
                          }

                          return _generateReportByName(
                            reportName,
                            breedName: breedName,
                            clubName: clubName,
                            scope: scope,
                            showLetter: showLetter,
                            exhibitorId: exhibitorId,
                            exhibitorName: exhibitorName,
                          );
                        },
                    onDownload:
                        (
                          reportName, {
                          String? exhibitorId,
                          String? breedName,
                          String? clubName,
                          String? scope,
                          String? showLetter,
                        }) => _downloadReportByName(
                          reportName,
                          exhibitorId: exhibitorId,
                          breedName: breedName,
                          clubName: clubName,
                          scope: scope,
                          showLetter: showLetter,
                        ),
                    onGenerateArtifact: _generateReportArtifact,
                    onDownloadArtifact: _downloadReportArtifact,
                    onEmail: _emailReportByName,
                    onEmailThisLetter: _emailArtifactThisLetter,
                    onEmailAllLetters: _emailArtifactAllLetters,
                    loading: _generatingReport,
                    reportsBlocked: reportsBlocked,
                    reportsBlockedMessage: reportsBlockedMessage,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
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
                  if (_isSupportMode)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.support_agent, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Support Mode — You are managing closeout as an admin while viewing another user. Finalize, save, and report generation are allowed. Email sending is disabled unless your account has the super_admin role for this show.',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),

                  _ArbaCloseoutCard(
                    secretaryNameController: _secretaryNameController,
                    secretaryAddressController: _secretaryAddressController,
                    secretaryEmailController: _secretaryEmailController,
                    secretaryPhoneController: _secretaryPhoneController,
                    superintendentController: _superintendentController,
                    superintendentNumberController:
                        _superintendentNumberController,
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

                  _CloseoutScopeCard(
                    loading: _loadingCloseoutScopes,
                    scopes: _closeoutScopes,
                    sections: _closeoutSections,
                    selectedScope: _selectedCloseoutScope,
                    customSectionIds: _customCloseoutSectionIds,
                    onChanged: (scope) {
                      setState(() {
                        _selectedCloseoutScope = scope;
                        _rebuildReportCaches();
                      });
                    },
                    onCustomSectionChanged: (sectionId, selected) {
                      setState(() {
                        if (selected) {
                          _customCloseoutSectionIds.add(sectionId);
                        } else {
                          _customCloseoutSectionIds.remove(sectionId);
                        }
                        _rebuildReportCaches();
                      });
                    },
                  ),

                  if (reportsBlocked) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: .22),
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
                    _buildMissingJudgesPanel(),
                    _buildDuplicatePlacementGroupsPanel(),
                    const SizedBox(height: 16),
                  ],

                  AppTheme.surfaceTextScope(
                    context,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.muted.withValues(alpha: .18),
                        ),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: reportsBlocked
                                  ? Colors.grey
                                  : (_dashboard
                                                ?.dashboard
                                                .closeout
                                                .isReportsStale ==
                                            true
                                        ? AppColors.gold
                                        : Colors.green),
                              foregroundColor: AppColors.text,
                              disabledForegroundColor: AppColors.text
                                  .withValues(alpha: .62),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            onPressed: (_isBusy || reportsBlocked)
                                ? null
                                : () async {
                                    final confirmed =
                                        await showDialog<bool>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: const Text(
                                                'Finalize & Generate Reports',
                                              ),
                                              content: const Text(
                                                'This will finalize the show and generate all closeout reports.\n\n'
                                                'By continuing, you confirm that all results — including any submitted via QR Code '
                                                'have been reviewed for accuracy and completeness.\n\n'
                                                'Once finalized, results can be emailed. Emails will not be sent automatically.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: const Text('Finalize'),
                                                ),
                                              ],
                                            );
                                          },
                                        ) ??
                                        false;

                                    if (!confirmed) return;

                                    setState(() {
                                      _generatingReport = true;
                                    });

                                    try {
                                      final previousFinalizeId =
                                          _dashboard?.latestFinalize.id ?? '';

                                      await _finalizeShow();

                                      await _loadDataUntilFinalizeVisible(
                                        previousFinalizeId: previousFinalizeId,
                                      );

                                      final artifactCount =
                                          await _countQueuedArtifactsForShow();

                                      if (artifactCount == 0) {
                                        throw Exception(
                                          'Finalize completed but no report artifacts were created.',
                                        );
                                      }

                                      final List<ReportArtifactSummary>
                                      artifactsToGenerate =
                                          (_dashboard?.reports ??
                                                  const <
                                                    ReportArtifactSummary
                                                  >[])
                                              .where((r) => r.isCurrent)
                                              .where((r) {
                                                if (_selectedCloseoutScopeIsEntireShow)
                                                  return true;

                                                return (r.metadata['scope_label'] ??
                                                            '')
                                                        .toString() ==
                                                    _selectedCloseoutScopeLabel;
                                              })
                                              .where(
                                                (r) =>
                                                    r.artifactStatus ==
                                                        'queued' ||
                                                    r.artifactStatus ==
                                                        'failed',
                                              )
                                              .where(
                                                (r) => {
                                                  'arba_report',
                                                  'exhibitor_report',
                                                  'legs',
                                                  'sweepstakes_report',
                                                  'breed_results_detail_report',
                                                  'details_by_breed',
                                                  'exh_by_breed',
                                                  'best_display_report',
                                                }.contains(r.reportName),
                                              )
                                              .toList();

                                      if (artifactsToGenerate.isEmpty) {
                                        await _refreshDashboardOnly();
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Finalize completed. No queued Flutter-rendered reports needed generation.',
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }

                                      final generatedOk = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (context) {
                                          return _GenerateAllReportsDialog(
                                            artifacts: artifactsToGenerate,
                                            onRun:
                                                (
                                                  onStarted,
                                                  onFinished,
                                                  onFailed,
                                                ) {
                                                  return _runGenerateAllReportsLive(
                                                    artifactsToGenerate,
                                                    onStarted: onStarted,
                                                    onFinished: onFinished,
                                                    onFailed: onFailed,
                                                  );
                                                },
                                          );
                                        },
                                      );

                                      if (generatedOk != true) {
                                        throw Exception(
                                          'Report generation was cancelled or did not finish cleanly.',
                                        );
                                      }

                                      await _syncClubDeliveryMetadata(
                                        latestFinalizeRunId:
                                            _dashboard?.latestFinalize.id,
                                      );
                                      await _loadData();

                                      if (_dashboard
                                              ?.dashboard
                                              .closeout
                                              .isReportsStale ==
                                          true) {
                                        throw Exception(
                                          'Flutter generation completed, but reports are still marked stale.',
                                        );
                                      }

                                      if (!mounted) return;

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Finalize and report generation completed. Review reports, then use the send buttons when ready.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Finalize flow failed: $e',
                                          ),
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _generatingReport = false;
                                        });
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.auto_awesome),
                            label: Text(
                              reportsBlocked
                                  ? 'Finish Results Before Finalize'
                                  : (_dashboard
                                                ?.dashboard
                                                .closeout
                                                .isReportsStale ==
                                            true
                                        ? (_selectedCloseoutScopeIsEntireShow
                                              ? 'Finalize Show'
                                              : 'Finalize $_selectedCloseoutScopeLabel')
                                        : (_selectedCloseoutScopeIsEntireShow
                                              ? 'Re-Finalize Show'
                                              : 'Re-Finalize $_selectedCloseoutScopeLabel')),
                            ),
                          ),

                          Builder(
                            builder: (context) {
                              final queuedRemaining =
                                  _queuedRemainingReportArtifacts();

                              return OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.secondaryButton,
                                  disabledForegroundColor: AppColors.muted
                                      .withValues(alpha: .72),
                                  side: BorderSide(
                                    color: AppColors.secondaryButton.withValues(
                                      alpha: .78,
                                    ),
                                    width: 1.4,
                                  ),
                                ),
                                onPressed: _isBusy || queuedRemaining.isEmpty
                                    ? null
                                    : () async {
                                        await _refreshDashboardOnly();
                                        final latestQueuedRemaining =
                                            _queuedRemainingReportArtifacts();

                                        if (latestQueuedRemaining.isEmpty) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'No queued reports found.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        if (!context.mounted) return;
                                        await showDialog<bool>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) {
                                            return _GenerateAllReportsDialog(
                                              artifacts: latestQueuedRemaining,
                                              onRun:
                                                  (
                                                    onStarted,
                                                    onFinished,
                                                    onFailed,
                                                  ) {
                                                    return _runGenerateAllReportsLive(
                                                      latestQueuedRemaining,
                                                      onStarted: onStarted,
                                                      onFinished: onFinished,
                                                      onFailed: onFailed,
                                                    );
                                                  },
                                            );
                                          },
                                        );

                                        await _refreshDashboardOnly();
                                      },
                                icon: const Icon(Icons.play_circle_outline),
                                label: Text(
                                  'Generate Remaining (${queuedRemaining.length})',
                                ),
                              );
                            },
                          ),

                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.secondaryButton,
                              disabledForegroundColor: AppColors.muted
                                  .withValues(alpha: .72),
                              side: BorderSide(
                                color: AppColors.secondaryButton.withValues(
                                  alpha: .78,
                                ),
                                width: 1.4,
                              ),
                            ),
                            onPressed: _isBusy
                                ? null
                                : _sendAllExhibitorReports,
                            icon: const Icon(Icons.send_outlined),
                            label: Text(
                              _selectedCloseoutScopeIsEntireShow
                                  ? 'Send All Exhibitor Reports'
                                  : 'Send $_selectedCloseoutScopeLabel Exhibitor Reports',
                            ),
                          ),
                          /*
                                ElevatedButton.icon(
                                  onPressed: _isBusy || _isSupportMode ? null : _sendAllLegsReports,
                                  icon: const Icon(Icons.pets),
                                  label: const Text('Send All Legs'),
                                ),
                                */
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.secondaryButton,
                              disabledForegroundColor: AppColors.muted
                                  .withValues(alpha: .72),
                              side: BorderSide(
                                color: AppColors.secondaryButton.withValues(
                                  alpha: .78,
                                ),
                                width: 1.4,
                              ),
                            ),
                            onPressed: _isBusy ? null : _sendAllClubReports,
                            icon: const Icon(Icons.group_outlined),
                            label: Text(
                              _selectedCloseoutScopeIsEntireShow
                                  ? 'Send All Club Reports'
                                  : 'Send $_selectedCloseoutScopeLabel Club Reports',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _buildReportActionsSection(
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
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _CloseoutWarningDetailTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _CloseoutWarningDetailTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppTheme.surfaceTextScope(
      context,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.muted.withValues(alpha: .12)),
        ),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          title: Text(title),
          subtitle: subtitle == null || subtitle!.trim().isEmpty
              ? null
              : Text(subtitle!),
          trailing: trailing,
          onTap: onTap,
        ),
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
      subtitle:
          'Complete the required show secretary and protest information before generating final reports.',
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
            color: AppColors.navy.withOpacity(.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.navy.withOpacity(.10)),
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
            color: AppColors.gold.withOpacity(.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withOpacity(.25)),
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
              backgroundColor: AppColors.primaryButton,
              foregroundColor: AppColors.primaryButtonText,
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
    String? clubName,
    String? scope,
    String? showLetter,
    String? exhibitorId,
    String? exhibitorName,
  })
  onGenerate;
  final Future<void> Function(
    String reportName, {
    String? exhibitorId,
    String? breedName,
    String? clubName,
    String? scope,
    String? showLetter,
  })
  onDownload;
  final Future<void> Function(ReportArtifactSummary artifact)
  onGenerateArtifact;
  final Future<void> Function(ReportArtifactSummary artifact)
  onDownloadArtifact;
  final Future<void> Function(
    String reportName, {
    String? exhibitorId,
    String? exhibitorEmail,
    String? breedName,
    String? clubName,
    String? scope,
    String? showLetter,
  })
  onEmail;
  final Future<void> Function(
    ReportArtifactSummary sourceArtifact, {
    String? exhibitorId,
    String? exhibitorName,
    String? exhibitorEmail,
  })
  onEmailThisLetter;
  final Future<void> Function(
    ReportArtifactSummary sourceArtifact, {
    String? exhibitorId,
    String? exhibitorName,
    String? exhibitorEmail,
  })
  onEmailAllLetters;
  final bool loading;
  final String showId;
  final bool reportsBlocked;
  final String? reportsBlockedMessage;

  const _ReportActionsCard({
    super.key,
    required this.showId,
    required this.reports,
    required this.groupedReportNames,
    required this.onGenerate,
    required this.onDownload,
    required this.onGenerateArtifact,
    required this.onDownloadArtifact,
    required this.onEmail,
    required this.onEmailThisLetter,
    required this.onEmailAllLetters,
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
  final TextEditingController _clubController = TextEditingController();
  String _selectedScope = 'OPEN';
  String _selectedShowLetter = 'ALL';
  List<String> _availableShowLetters = [];
  bool _loadingShowLetters = false;
  String? _selectedExhibitorId;
  String? _selectedExhibitorName;
  String? _selectedExhibitorEmail;
  List<_ExhibitorPickItem> _availableExhibitors = [];
  bool _loadingExhibitors = false;

  static const Map<String, String> _groupLabels = {
    'arba': 'ARBA Reports',
    'exhibitor': 'Exhibitor Reports',
    'club': 'Club Reports',
    'other': 'Other Reports',
  };

  @override
  void initState() {
    super.initState();

    if (_selectedReportName == 'exhibitor_report' ||
        _selectedReportName == 'legs') {
      unawaited(_loadExhibitors());
    }

    if (_selectedReportName == 'sweepstakes_report' ||
        _selectedReportName == 'breed_results_detail_report') {
      unawaited(_loadShowLetters());
      unawaited(_loadBreedsForBreedScopedReports());
    }

    if (_selectedReportNeedsClubScope) {
      unawaited(_loadShowLetters());
      unawaited(_loadClubsForStateClubReports());
    }
  }

  List<String> _availableBreeds = [];
  bool _loadingBreeds = false;
  List<String> _availableClubs = [];
  bool _loadingClubs = false;

  List<String> get _currentReports =>
      widget.groupedReportNames[_selectedGroup] ?? const [];

  bool get _selectedReportIsStateClub =>
      _selectedReportName == 'details_by_breed' ||
      _selectedReportName == 'exh_by_breed' ||
      _selectedReportName == 'best_display_report';

  List<ReportArtifactSummary> get _selectedArtifacts {
    final reportName = _selectedReportName;
    if (reportName == null) return const <ReportArtifactSummary>[];

    var matches = widget.reports
        .where((r) => r.reportName == reportName)
        .where((r) => r.isCurrent);

    if (_selectedReportNeedsExhibitor && _selectedExhibitorId != null) {
      matches = matches.where(
        (r) =>
            (r.metadata['exhibitor_id'] ?? '').toString().trim() ==
            _selectedExhibitorId,
      );
    }

    if (_selectedReportNeedsBreedScope) {
      matches = matches.where((r) {
        final breed = (r.metadata['breed_name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final species = (r.metadata['species'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final targetBreed = displayBreedNameForClubReport(
          reportName: reportName,
          breedName: _breedController.text.trim(),
          species:
              isCavyClubReportTarget(
                species: species,
                breedName: _breedController.text.trim(),
              )
              ? 'cavy'
              : '',
        ).toLowerCase();
        final scope = (r.metadata['scope'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final letter = (r.metadata['show_letter'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        return breed == targetBreed &&
            scope == _selectedScope.trim().toUpperCase() &&
            letter == _selectedShowLetter.trim().toUpperCase();
      });
    }

    if (_selectedReportNeedsClubScope) {
      matches = matches.where((r) {
        final club = (r.metadata['club_name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final scope = (r.metadata['scope'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final letter = (r.metadata['show_letter'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        return club == _clubController.text.trim().toLowerCase() &&
            scope == _selectedScope.trim().toUpperCase() &&
            letter == _selectedShowLetter.trim().toUpperCase();
      });
    }

    final list = matches.toList()
      ..sort((a, b) {
        if (_selectedReportIsStateClub) {
          final speciesCmp = _artifactSpeciesRank(
            _artifactSpecies(a),
          ).compareTo(_artifactSpeciesRank(_artifactSpecies(b)));
          if (speciesCmp != 0) return speciesCmp;
        }

        final aDt =
            DateTime.tryParse(a.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDt =
            DateTime.tryParse(b.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDt.compareTo(aDt);
      });

    return list;
  }

  ReportArtifactSummary? get _selectedArtifact {
    final list = _selectedArtifacts;
    return list.isEmpty ? null : list.first;
  }

  bool get _selectedReportIgnoresResultsReadiness =>
      _selectedReportName == 'unpaid_balances_report' ||
      _selectedReportName == 'paid_exhibitor_report';

  bool get _selectedReportCanEmail {
    return _selectedReportName == 'arba_report' ||
        _selectedReportName == 'exhibitor_report' ||
        _selectedReportName == 'legs' ||
        _selectedReportName == 'sweepstakes_report' ||
        _selectedReportName == 'breed_results_detail_report' ||
        _selectedReportName == 'details_by_breed' ||
        _selectedReportName == 'exh_by_breed' ||
        _selectedReportName == 'best_display_report';
  }

  bool get _selectedReportBlocked =>
      widget.reportsBlocked && !_selectedReportIgnoresResultsReadiness;

  bool get _selectedReportNeedsBreedScope =>
      _selectedReportName == 'sweepstakes_report' ||
      _selectedReportName == 'breed_results_detail_report';

  bool get _selectedReportNeedsClubScope =>
      _selectedReportName == 'details_by_breed' ||
      _selectedReportName == 'exh_by_breed' ||
      _selectedReportName == 'best_display_report';

  bool get _selectedReportNeedsExhibitor =>
      _selectedReportName == 'exhibitor_report' ||
      _selectedReportName == 'legs';

  bool _artifactCanDownload(ReportArtifactSummary? artifact) {
    return artifact != null &&
        artifact.artifactStatus == 'generated' &&
        (artifact.storageBucket?.isNotEmpty == true) &&
        (artifact.storagePath?.isNotEmpty == true);
  }

  String _artifactSpecies(ReportArtifactSummary? artifact) {
    final species = (artifact?.metadata['species'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (species == 'rabbit' || species == 'cavy') return species;
    return 'combined';
  }

  int _artifactSpeciesRank(String species) {
    if (species == 'rabbit') return 0;
    if (species == 'cavy') return 1;
    return 2;
  }

  String _speciesLabel(ReportArtifactSummary? artifact) {
    final species = _artifactSpecies(artifact);
    if (species == 'rabbit') return 'Rabbit';
    if (species == 'cavy') return 'Cavy';
    return 'Combined';
  }

  String _stateClubTitleForArtifact(ReportArtifactSummary artifact) {
    final base = switch (artifact.reportName) {
      'details_by_breed' => 'Breed Totals',
      'exh_by_breed' => 'Exhibitor by Breed',
      'best_display_report' => 'Display Points',
      _ => _friendlyReportName(artifact.reportName),
    };
    return '$base - ${_speciesLabel(artifact)}';
  }

  Future<void> _loadExhibitors() async {
    if (_loadingExhibitors) return;

    setState(() {
      _loadingExhibitors = true;
    });

    try {
      final rows = await supabase
          .from('entries')
          .select('''
            exhibitor_id,
            exhibitors!entries_exhibitor_id_fkey (
              id,
              display_name,
              first_name,
              last_name,
              email
            )
          ''')
          .eq('show_id', widget.showId);

      final map = <String, _ExhibitorPickItem>{};

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final exhibitorId = (row['exhibitor_id'] ?? '').toString().trim();
        final exhibitorRaw = row['exhibitors'];

        if (exhibitorId.isEmpty || exhibitorRaw is! Map) continue;

        final exhibitor = Map<String, dynamic>.from(exhibitorRaw);
        final displayName = (exhibitor['display_name'] ?? '').toString().trim();
        final first = (exhibitor['first_name'] ?? '').toString().trim();
        final last = (exhibitor['last_name'] ?? '').toString().trim();
        final email = (exhibitor['email'] ?? '').toString().trim();

        final name = displayName.isNotEmpty
            ? displayName
            : [first, last].where((x) => x.isNotEmpty).join(' ').trim();

        if (name.isEmpty) continue;

        map[exhibitorId] = _ExhibitorPickItem(
          exhibitorId: exhibitorId,
          exhibitorName: name,
          email: email,
        );
      }

      final list = map.values.toList()
        ..sort(
          (a, b) => a.exhibitorName.toLowerCase().compareTo(
            b.exhibitorName.toLowerCase(),
          ),
        );

      if (!mounted) return;

      setState(() {
        _availableExhibitors = list;

        if (list.isNotEmpty) {
          final stillExists = list.any(
            (e) => e.exhibitorId == _selectedExhibitorId,
          );
          if (!stillExists) {
            _selectedExhibitorId = list.first.exhibitorId;
            _selectedExhibitorName = list.first.exhibitorName;
            _selectedExhibitorEmail = list.first.email;
          }
        } else {
          _selectedExhibitorId = null;
          _selectedExhibitorName = null;
          _selectedExhibitorEmail = null;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _availableExhibitors = [];
        _selectedExhibitorId = null;
        _selectedExhibitorName = null;
        _selectedExhibitorEmail = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed loading exhibitors: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingExhibitors = false;
        });
      }
    }
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
          if (!sorted.contains(_selectedShowLetter)) {
            _selectedShowLetter = sorted.first;
          }
        } else {
          _selectedShowLetter = '';
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
          .select('id, display_name, kind, letter, sort_order')
          .eq('show_id', widget.showId)
          .eq('kind', kind)
          .eq('is_enabled', true)
          .order('sort_order');

      final selectedLetter = _selectedShowLetter.trim().toUpperCase();
      final matchingSections = (sections as List).where((raw) {
        final section = Map<String, dynamic>.from(raw as Map);
        final letter = (section['letter'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        return selectedLetter.isEmpty ||
            selectedLetter == 'ALL' ||
            letter == selectedLetter;
      }).toList();

      final breedSet = <String>{};
      final sectionIds = <String>[];

      for (final rawSection in matchingSections) {
        final section = Map<String, dynamic>.from(rawSection as Map);
        final sectionId = (section['id'] ?? '').toString().trim();
        if (sectionId.isEmpty) continue;

        sectionIds.add(sectionId);

        final rows = await supabase.rpc(
          'report_results_entry_rows',
          params: {
            'p_show_id': widget.showId,
            'p_section_id': sectionId,
            'p_show_letter': selectedLetter.isEmpty || selectedLetter == 'ALL'
                ? null
                : selectedLetter,
          },
        );

        for (final rawRow in (rows as List)) {
          final row = Map<String, dynamic>.from(rawRow as Map);
          final rawBreed = (row['breed_name'] ?? '').toString().trim();
          final species = normalizeClubReportSpecies(
            (row['species'] ?? row['animal_species'] ?? '').toString(),
          );
          final breed = displayBreedNameForClubReport(
            reportName: _selectedReportName ?? 'sweepstakes_report',
            breedName: rawBreed,
            species: species,
          );
          if (breed.isNotEmpty) {
            breedSet.add(breed);
          }
        }
      }

      // Club reports must also include sanctioned breeds that had no entries
      // or no animals shown. Those breeds will not be returned by the results RPC.
      if (sectionIds.isNotEmpty) {
        final sanctionMaps = <Map<String, dynamic>>[];
        const chunkSize = 100;

        for (var start = 0; start < sectionIds.length; start += chunkSize) {
          final end = start + chunkSize > sectionIds.length
              ? sectionIds.length
              : start + chunkSize;
          final chunk = sectionIds.sublist(start, end);

          final sanctionRows = await supabase
              .from('show_sanctions')
              .select('breed_name, section_id')
              .eq('show_id', widget.showId)
              .inFilter('section_id', chunk);

          sanctionMaps.addAll(
            (sanctionRows as List).map(
              (raw) => Map<String, dynamic>.from(raw as Map),
            ),
          );
        }

        for (final row in sanctionMaps) {
          final rawBreed = (row['breed_name'] ?? '').toString().trim();
          final species = isKnownCavyBreed(rawBreed) ? 'cavy' : '';
          final breed = displayBreedNameForClubReport(
            reportName: _selectedReportName ?? 'sweepstakes_report',
            breedName: rawBreed,
            species: species,
          );
          if (breed.isNotEmpty) {
            breedSet.add(breed);
          }
        }
      }

      // Also merge current artifact metadata so newly queued/generated empty
      // reports remain selectable even if sanction data changes later.
      for (final artifact in widget.reports.where((r) => r.isCurrent)) {
        if (artifact.reportName != 'sweepstakes_report' &&
            artifact.reportName != 'breed_results_detail_report') {
          continue;
        }

        final artifactScope = (artifact.metadata['scope'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final artifactLetter = (artifact.metadata['show_letter'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final artifactBreed = (artifact.metadata['breed_name'] ?? '')
            .toString()
            .trim();

        final scopeMatches = artifactScope == _selectedScope.toUpperCase();
        final letterMatches =
            selectedLetter.isEmpty ||
            selectedLetter == 'ALL' ||
            artifactLetter == selectedLetter;

        if (scopeMatches && letterMatches && artifactBreed.isNotEmpty) {
          breedSet.add(artifactBreed);
        }
      }

      final breeds = breedSet.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;

      setState(() {
        _availableBreeds = breeds;

        if (breeds.isNotEmpty) {
          final current = _breedController.text.trim();
          final matchingCurrent = breeds.where(
            (breed) => breed.toLowerCase() == current.toLowerCase(),
          );

          _breedController.text = matchingCurrent.isNotEmpty
              ? matchingCurrent.first
              : breeds.first;
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed loading breeds: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingBreeds = false;
        });
      }
    }
  }

  Future<void> _loadClubsForStateClubReports() async {
    if (_loadingClubs) return;

    setState(() {
      _loadingClubs = true;
    });

    try {
      final selectedLetter = _selectedShowLetter.trim().toUpperCase();
      final selectedScope = _selectedScope.trim().toUpperCase();
      final clubs = <String>{};

      for (final artifact in widget.reports.where((r) => r.isCurrent)) {
        if (artifact.reportName != 'details_by_breed' &&
            artifact.reportName != 'exh_by_breed' &&
            artifact.reportName != 'best_display_report') {
          continue;
        }

        final artifactScope = (artifact.metadata['scope'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final artifactLetter = (artifact.metadata['show_letter'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final clubName = (artifact.metadata['club_name'] ?? '')
            .toString()
            .trim();

        if (artifactScope == selectedScope &&
            artifactLetter == selectedLetter &&
            clubName.isNotEmpty) {
          clubs.add(clubName);
        }
      }

      if (clubs.isEmpty) {
        final kind = selectedScope == 'OPEN' ? 'open' : 'youth';
        final sections = await supabase
            .from('show_sections')
            .select('id, letter')
            .eq('show_id', widget.showId)
            .eq('kind', kind)
            .eq('is_enabled', true);

        final sectionIds = (sections as List)
            .where((raw) {
              final section = Map<String, dynamic>.from(raw as Map);
              return (section['letter'] ?? '')
                      .toString()
                      .trim()
                      .toUpperCase() ==
                  selectedLetter;
            })
            .map(
              (raw) => (Map<String, dynamic>.from(raw as Map)['id'] ?? '')
                  .toString()
                  .trim(),
            )
            .where((id) => id.isNotEmpty)
            .toList();

        if (sectionIds.isNotEmpty) {
          final sanctionRows = <Map<String, dynamic>>[];
          const chunkSize = 100;

          for (var start = 0; start < sectionIds.length; start += chunkSize) {
            final end = start + chunkSize > sectionIds.length
                ? sectionIds.length
                : start + chunkSize;
            final chunk = sectionIds.sublist(start, end);

            final rows = await supabase
                .from('show_sanctions')
                .select('club_name, sanctioning_body, section_id')
                .eq('show_id', widget.showId)
                .inFilter('section_id', chunk)
                .eq('sanctioning_body', 'STATE CLUB');

            sanctionRows.addAll(
              (rows as List).map(
                (raw) => Map<String, dynamic>.from(raw as Map),
              ),
            );
          }

          for (final row in sanctionRows) {
            final clubName = (row['club_name'] ?? '').toString().trim();
            if (clubName.isNotEmpty) clubs.add(clubName);
          }
        }
      }

      final sorted = clubs.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;

      setState(() {
        _availableClubs = sorted;
        if (sorted.isNotEmpty) {
          final current = _clubController.text.trim();
          final matching = sorted.where(
            (club) => club.toLowerCase() == current.toLowerCase(),
          );
          _clubController.text = matching.isNotEmpty
              ? matching.first
              : sorted.first;
        } else {
          _clubController.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableClubs = [];
        _clubController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed loading state clubs: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingClubs = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _breedController.dispose();
    _clubController.dispose();
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

    if (_selectedReportName != null && reports.contains(_selectedReportName)) {
      return;
    }

    String? matchingGroup;
    for (final entry in widget.groupedReportNames.entries) {
      if (entry.value.isNotEmpty && entry.value.contains(_selectedReportName)) {
        matchingGroup = entry.key;
        break;
      }
    }

    if (matchingGroup != null) {
      _selectedGroup = matchingGroup;
      return;
    }

    _selectedReportName = reports.first;
  }

  Widget _buildArtifactActions({
    required ReportArtifactSummary? artifact,
    bool stateClubSpeciesCard = false,
  }) {
    final reportName = artifact?.reportName ?? _selectedReportName;
    final canDownload = _artifactCanDownload(artifact);
    final speciesLabel = stateClubSpeciesCard ? _speciesLabel(artifact) : '';
    final emailShowLetter =
        (artifact?.metadata['show_letter'] ?? _selectedShowLetter)
            .toString()
            .trim()
            .toUpperCase();
    final emailThisShowLabel = stateClubSpeciesCard
        ? (emailShowLetter.isEmpty
              ? 'Email $speciesLabel Show'
              : 'Email $speciesLabel Show $emailShowLetter')
        : (emailShowLetter.isEmpty
              ? 'Email This Show'
              : 'Email Show $emailShowLetter');
    final emailAllShowsLabel = stateClubSpeciesCard
        ? 'Email $speciesLabel All Shows'
        : 'Email All Shows';
    final emailThisShowTooltip = emailShowLetter.isEmpty
        ? 'Sends reports for this show only.'
        : 'Sends reports for Show $emailShowLetter only.';
    final downloadLabel = stateClubSpeciesCard
        ? 'Download $speciesLabel'
        : 'Download';

    final canGenerate =
        !widget.loading &&
        !_selectedReportBlocked &&
        reportName != null &&
        (_selectedReportNeedsExhibitor ? _selectedExhibitorId != null : true) &&
        (_selectedReportNeedsBreedScope
            ? _breedController.text.trim().isNotEmpty
            : true) &&
        (_selectedReportNeedsClubScope
            ? _clubController.text.trim().isNotEmpty
            : true);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryButton,
            foregroundColor: AppColors.primaryButtonText,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          onPressed: canGenerate
              ? () async {
                  if (stateClubSpeciesCard && artifact != null) {
                    await widget.onGenerateArtifact(artifact);
                    return;
                  }
                  await widget.onGenerate(
                    reportName,
                    breedName: _selectedReportNeedsBreedScope
                        ? _breedController.text.trim()
                        : null,
                    clubName: _selectedReportNeedsClubScope
                        ? _clubController.text.trim()
                        : null,
                    scope:
                        _selectedReportNeedsBreedScope ||
                            _selectedReportNeedsClubScope
                        ? _selectedScope
                        : null,
                    showLetter:
                        _selectedReportNeedsBreedScope ||
                            _selectedReportNeedsClubScope
                        ? _selectedShowLetter
                        : null,
                    exhibitorId: _selectedReportNeedsExhibitor
                        ? _selectedExhibitorId
                        : null,
                    exhibitorName: _selectedReportNeedsExhibitor
                        ? _selectedExhibitorName
                        : null,
                  );
                }
              : null,
          icon: widget.loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
          label: Text(widget.loading ? 'Generating...' : 'Generate'),
        ),
        OutlinedButton.icon(
          onPressed: canDownload && reportName != null
              ? () async {
                  if (stateClubSpeciesCard && artifact != null) {
                    await widget.onDownloadArtifact(artifact);
                    return;
                  }
                  await widget.onDownload(
                    reportName,
                    exhibitorId: _selectedReportNeedsExhibitor
                        ? _selectedExhibitorId
                        : null,
                    breedName: _selectedReportNeedsBreedScope
                        ? _breedController.text.trim()
                        : null,
                    clubName: _selectedReportNeedsClubScope
                        ? _clubController.text.trim()
                        : null,
                    scope:
                        _selectedReportNeedsBreedScope ||
                            _selectedReportNeedsClubScope
                        ? _selectedScope
                        : null,
                    showLetter:
                        _selectedReportNeedsBreedScope ||
                            _selectedReportNeedsClubScope
                        ? _selectedShowLetter
                        : null,
                  );
                }
              : null,
          icon: const Icon(Icons.download),
          label: Text(downloadLabel),
        ),
        if (reportName == 'arba_report')
          OutlinedButton.icon(
            onPressed:
                _selectedReportCanEmail && canDownload && reportName != null
                ? () => widget.onEmail(reportName)
                : null,
            icon: const Icon(Icons.email_outlined),
            label: const Text('Email to ARBA'),
          )
        else ...[
          Tooltip(
            message: emailThisShowTooltip,
            child: OutlinedButton.icon(
              onPressed:
                  _selectedReportCanEmail && canDownload && artifact != null
                  ? () => widget.onEmailThisLetter(
                      artifact,
                      exhibitorId: _selectedReportNeedsExhibitor
                          ? _selectedExhibitorId
                          : null,
                      exhibitorName: _selectedReportNeedsExhibitor
                          ? _selectedExhibitorName
                          : null,
                      exhibitorEmail: _selectedReportNeedsExhibitor
                          ? _selectedExhibitorEmail
                          : null,
                    )
                  : null,
              icon: const Icon(Icons.email_outlined),
              label: Text(emailThisShowLabel),
            ),
          ),
          Tooltip(
            message: "Sends this target's reports for all shows in one email.",
            child: OutlinedButton.icon(
              onPressed:
                  _selectedReportCanEmail && canDownload && artifact != null
                  ? () => widget.onEmailAllLetters(
                      artifact,
                      exhibitorId: _selectedReportNeedsExhibitor
                          ? _selectedExhibitorId
                          : null,
                      exhibitorName: _selectedReportNeedsExhibitor
                          ? _selectedExhibitorName
                          : null,
                      exhibitorEmail: _selectedReportNeedsExhibitor
                          ? _selectedExhibitorEmail
                          : null,
                    )
                  : null,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: Text(emailAllShowsLabel),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildReportStatusAndActions() {
    if (_selectedReportIsStateClub) {
      final artifacts = _selectedArtifacts;
      if (artifacts.isEmpty) {
        return [
          _ReportInfoTile(
            reportName: _selectedReportName == null
                ? '-'
                : _friendlyReportName(_selectedReportName),
            status: 'not_generated',
            generatedAt: null,
          ),
          const SizedBox(height: 16),
          _buildArtifactActions(artifact: null, stateClubSpeciesCard: true),
        ];
      }

      return [
        for (var index = 0; index < artifacts.length; index++) ...[
          if (index > 0) const SizedBox(height: 16),
          _ReportInfoTile(
            reportName: _stateClubTitleForArtifact(artifacts[index]),
            status: artifacts[index].artifactStatus,
            generatedAt: artifacts[index].generatedAt,
          ),
          const SizedBox(height: 12),
          _buildArtifactActions(
            artifact: artifacts[index],
            stateClubSpeciesCard: true,
          ),
        ],
      ];
    }

    final artifact = _selectedArtifact;
    return [
      _ReportInfoTile(
        reportName: _selectedReportName == null
            ? '-'
            : _friendlyReportName(_selectedReportName),
        status: artifact?.artifactStatus ?? 'not_generated',
        generatedAt: artifact?.generatedAt,
      ),
      const SizedBox(height: 16),
      _buildArtifactActions(artifact: artifact),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return _CloseoutSectionCard(
      title: 'Reports & Distribution',
      subtitle:
          'Generate, download, and distribute closeout reports by category.',
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

              if (nextReport != 'exhibitor_report' && nextReport != 'legs') {
                _selectedExhibitorId = null;
                _selectedExhibitorName = null;
                _availableExhibitors = [];
                _selectedExhibitorEmail = null;
              }
            });

            if (nextReport == 'sweepstakes_report' ||
                nextReport == 'breed_results_detail_report') {
              await _loadShowLetters();
              await _loadBreedsForBreedScopedReports();
            }

            if (nextReport == 'details_by_breed' ||
                nextReport == 'exh_by_breed' ||
                nextReport == 'best_display_report') {
              await _loadShowLetters();
              await _loadClubsForStateClubReports();
            }

            if (nextReport == 'exhibitor_report' || nextReport == 'legs') {
              await _loadExhibitors();
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
          items: _currentReports.map((reportName) {
            final count = reportName == 'arba_report'
                ? widget.reports
                      .where((r) => r.reportName == reportName)
                      .where((r) => r.isCurrent)
                      .where((r) => r.artifactStatus == 'generated')
                      .length
                : 0;

            return DropdownMenuItem<String>(
              value: reportName,
              child: Text(
                count > 1
                    ? '${_friendlyReportName(reportName)} ($count)'
                    : _friendlyReportName(reportName),
              ),
            );
          }).toList(),
          onChanged: _currentReports.isEmpty
              ? null
              : (value) async {
                  setState(() {
                    _selectedReportName = value;

                    if (value != 'exhibitor_report' && value != 'legs') {
                      _selectedExhibitorId = null;
                      _selectedExhibitorName = null;
                      _availableExhibitors = [];
                      _selectedExhibitorEmail = null;
                    }
                  });

                  if (value == 'sweepstakes_report' ||
                      value == 'breed_results_detail_report') {
                    await _loadShowLetters();
                    await _loadBreedsForBreedScopedReports();
                  }

                  if (value == 'details_by_breed' ||
                      value == 'exh_by_breed' ||
                      value == 'best_display_report') {
                    await _loadShowLetters();
                    await _loadClubsForStateClubReports();
                  }

                  if (value == 'exhibitor_report' || value == 'legs') {
                    await _loadExhibitors();
                  }
                },
        ),

        if (_selectedReportNeedsBreedScope) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _availableShowLetters.contains(_selectedShowLetter)
                ? _selectedShowLetter
                : (_availableShowLetters.isNotEmpty
                      ? _availableShowLetters.first
                      : null),
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
            items: _availableShowLetters
                .map(
                  (letter) => DropdownMenuItem<String>(
                    value: letter,
                    child: Text(letter),
                  ),
                )
                .toList(),
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
            initialValue:
                _availableBreeds.contains(_breedController.text.trim())
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

        if (_selectedReportNeedsClubScope) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _availableShowLetters.contains(_selectedShowLetter)
                ? _selectedShowLetter
                : (_availableShowLetters.isNotEmpty
                      ? _availableShowLetters.first
                      : null),
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
            items: _availableShowLetters
                .map(
                  (letter) => DropdownMenuItem<String>(
                    value: letter,
                    child: Text(letter),
                  ),
                )
                .toList(),
            onChanged: _loadingShowLetters
                ? null
                : (value) async {
                    if (value == null) return;
                    setState(() {
                      _selectedShowLetter = value;
                    });
                    await _loadClubsForStateClubReports();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _availableClubs.contains(_clubController.text.trim())
                ? _clubController.text.trim()
                : (_availableClubs.isNotEmpty ? _availableClubs.first : null),
            decoration: InputDecoration(
              labelText: 'Club Name',
              border: const OutlineInputBorder(),
              suffixIcon: _loadingClubs
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
            items: _availableClubs
                .map(
                  (club) =>
                      DropdownMenuItem<String>(value: club, child: Text(club)),
                )
                .toList(),
            onChanged: _loadingClubs || _availableClubs.isEmpty
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _clubController.text = value;
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
              await _loadClubsForStateClubReports();
            },
          ),
        ],

        if (_selectedReportNeedsExhibitor) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                _availableExhibitors.any(
                  (e) => e.exhibitorId == _selectedExhibitorId,
                )
                ? _selectedExhibitorId
                : (_availableExhibitors.isNotEmpty
                      ? _availableExhibitors.first.exhibitorId
                      : null),
            decoration: InputDecoration(
              labelText: 'Exhibitor',
              border: const OutlineInputBorder(),
              suffixIcon: _loadingExhibitors
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
            items: _availableExhibitors
                .map(
                  (ex) => DropdownMenuItem<String>(
                    value: ex.exhibitorId,
                    child: Text(ex.exhibitorName),
                  ),
                )
                .toList(),
            onChanged: _loadingExhibitors || _availableExhibitors.isEmpty
                ? null
                : (value) {
                    if (value == null) return;
                    final selected = _availableExhibitors.firstWhere(
                      (e) => e.exhibitorId == value,
                    );
                    setState(() {
                      _selectedExhibitorId = selected.exhibitorId;
                      _selectedExhibitorName = selected.exhibitorName;
                      _selectedExhibitorEmail = selected.email;
                    });
                  },
          ),
        ],

        const SizedBox(height: 16),
        ..._buildReportStatusAndActions(),

        if (_selectedReportBlocked) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withValues(alpha: .22)),
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
      ],
    );
  }
}

class _ExhibitorPickItem {
  final String exhibitorId;
  final String exhibitorName;
  final String email;

  const _ExhibitorPickItem({
    required this.exhibitorId,
    required this.exhibitorName,
    required this.email,
  });
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
            : AppColors.navy.withOpacity(.04),
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
  final int missingFinalAwardCount;
  final int duplicateFinalAwardCount;

  ResultsReadinessDto({
    required this.ready,
    required this.missingPlacementCount,
    required this.missingJudgeCount,
    required this.duplicatePlacementGroupCount,
    required this.missingFinalAwardCount,
    required this.duplicateFinalAwardCount,
  });

  factory ResultsReadinessDto.fromJson(Map<String, dynamic> json) {
    return ResultsReadinessDto(
      ready: (json['ready'] ?? false) == true,
      missingPlacementCount: ((json['missing_placement_count'] ?? 0) as num)
          .toInt(),
      missingJudgeCount: ((json['missing_judge_count'] ?? 0) as num).toInt(),
      duplicatePlacementGroupCount:
          ((json['duplicate_placement_group_count'] ?? 0) as num).toInt(),
      missingFinalAwardCount:
          (json['missing_final_award_count'] as num?)?.toInt() ?? 0,
      duplicateFinalAwardCount:
          (json['duplicate_final_award_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.page),
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
                  backgroundColor: AppColors.primaryButton,
                  foregroundColor: AppColors.primaryButtonText,
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
  )
  onRun;

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
  Timer? _progressRefreshTimer;

  final Set<String> _completed = {};
  final Set<String> _running = {};
  final Map<String, String> _failed = {};

  double get _progress {
    final done = _completed.length + _failed.length;
    return widget.artifacts.isEmpty ? 0 : done / widget.artifacts.length;
  }

  String _artifactKey(ReportArtifactSummary artifact) {
    final species =
        {
          'details_by_breed',
          'exh_by_breed',
          'best_display_report',
        }.contains(artifact.reportName)
        ? (artifact.metadata['species'] ?? '').toString().trim().toLowerCase()
        : '';

    return [
      artifact.reportName,
      artifact.id,
      if (species.isNotEmpty) species,
    ].join('::');
  }

  String _artifactLabel(ReportArtifactSummary artifact) {
    if (artifact.fileName?.trim().isNotEmpty ?? false) {
      return artifact.fileName!.trim();
    }
    final species = (artifact.metadata['species'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final speciesLabel = species == 'rabbit'
        ? ' Rabbit'
        : species == 'cavy'
        ? ' Cavy'
        : '';
    return '${_friendlyReportName(artifact.reportName)}$speciesLabel';
  }

  void _scheduleProgressRefresh() {
    if (_progressRefreshTimer?.isActive == true) return;

    _progressRefreshTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _progressRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await widget.onRun(
        (reportName) {
          _running.add(reportName);
          _failed.remove(reportName);
          _scheduleProgressRefresh();
        },
        (reportName) {
          _running.remove(reportName);
          _completed.add(reportName);
          _scheduleProgressRefresh();
        },
        (reportName, error) {
          if (!mounted) return;
          _progressRefreshTimer?.cancel();
          setState(() {
            _running.remove(reportName);
            _failed[reportName] = error.toString();
          });
        },
      );

      if (!mounted) return;
      _progressRefreshTimer?.cancel();
      setState(() {
        _finished = true;
        if (_failed.isNotEmpty) {
          _error = '${_failed.length} report(s) failed.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      _progressRefreshTimer?.cancel();
      setState(() {
        _finished = true;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const dialogBackground = Color(0xFF3D1B78);
    const primaryText = Colors.white;
    const secondaryText = Color(0xFFD8CCF4);
    const warningText = Color(0xFFFFB4AB);
    const successText = Color(0xFF8BE28B);
    const queuedText = Color(0xFFC6B8E8);

    return AlertDialog(
      backgroundColor: dialogBackground,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Generating Reports',
        style: TextStyle(color: primaryText, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please do not leave this window while reports are generating. This could take several minutes.',
              style: TextStyle(
                fontSize: 13,
                color: warningText,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _finished ? 1 : _progress,
              backgroundColor: Colors.white24,
              color: AppColors.gold,
            ),
            const SizedBox(height: 12),
            Text(
              '${_completed.length + _failed.length} of ${widget.artifacts.length} reports processed',
              style: const TextStyle(
                color: primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              width: double.maxFinite,
              child: ListView.builder(
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
                    color = warningText;
                    status = 'Failed';
                  } else if (isDone) {
                    icon = Icons.check_circle;
                    color = successText;
                    status = 'Done';
                  } else if (isRunning) {
                    icon = Icons.autorenew;
                    color = AppColors.gold;
                    status = 'Running';
                  } else {
                    icon = Icons.schedule;
                    color = queuedText;
                    status = 'Queued';
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon, color: color),
                        title: Text(
                          _artifactLabel(artifact),
                          style: const TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          (artifact.metadata['exhibitor_name'] ??
                                      artifact.metadata['breed_name'] ??
                                      '')
                                  .toString()
                                  .trim()
                                  .isEmpty
                              ? _friendlyReportName(artifact.reportName)
                              : (artifact.metadata['exhibitor_name'] ??
                                        artifact.metadata['breed_name'])
                                    .toString()
                                    .trim(),
                          style: const TextStyle(color: secondaryText),
                        ),
                        trailing: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (failedMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 40, bottom: 8),
                          child: Text(
                            failedMessage,
                            style: const TextStyle(
                              color: warningText,
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
              Text(_error!, style: const TextStyle(color: warningText)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _finished ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(
            foregroundColor: primaryText,
            disabledForegroundColor: secondaryText,
          ),
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

class _StateClubReportContact {
  final String clubName;
  final String species;
  final String email;

  const _StateClubReportContact({
    required this.clubName,
    required this.species,
    required this.email,
  });
}

class _ClubEmailTarget {
  final String clubName;
  final String breedName;
  final String scope; // OPEN / YOUTH
  final String showLetter;
  final String email;
  final String species;
  final String sanctioningBody; // NATIONAL CLUB / STATE BREED CLUB / STATE CLUB

  const _ClubEmailTarget({
    required this.clubName,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.email,
    required this.species,
    required this.sanctioningBody,
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
  return formatted == '(not set)' || formatted == '(invalid date)'
      ? '-'
      : formatted;
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
    case 'breed_judged_totals_report':
      return 'Breed Judged Totals Report';
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
    case 'unpaid_balances_report':
      return 'Unpaid Exhibitor Balances';
    case 'paid_exhibitor_report':
      return 'Paid Exhibitor Report';
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
    case 'entered_exhibitors_contact_report':
      return 'Entered Exhibitors Contact Report';
    case 'ribbon_payout_report':
      return 'Ribbon Report';
    case 'payback_report':
      return 'Paybacks Report';
    case null:
      return '-';
    default:
      return key
          .split('_')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
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
        (json['reports'] ?? const []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      ).map(ReportArtifactSummary.fromJson).toList(),
      deliveries: List<Map<String, dynamic>>.from(
        (json['deliveries'] ?? const []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      ).map(DeliveryRunSummary.fromJson).toList(),
      latestArchive:
          json['latest_archive'] == null ||
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
      blockingErrorCount: ((json['blocking_error_count'] ?? 0) as num).toInt(),
      reportsGeneratedCount: ((json['reports_generated_count'] ?? 0) as num)
          .toInt(),
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

  LatestFinalize({this.id, this.runStatus, this.startedAt, this.completedAt});

  factory LatestFinalize.fromJson(Map<String, dynamic> json) {
    return LatestFinalize(
      id: json['id'] as String?,
      runStatus: json['run_status'] as String?,
      startedAt: json['started_at'] as String?,
      completedAt: json['completed_at'] as String?,
    );
  }
}

class _CustomSectionPicker extends StatelessWidget {
  final List<_CloseoutSectionSummary> sections;
  final Set<String> selectedSectionIds;
  final void Function(String sectionId, bool selected) onChanged;

  const _CustomSectionPicker({
    required this.sections,
    required this.selectedSectionIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Text(
        'No enabled sections available.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final selectedCount = sections
        .where((section) => selectedSectionIds.contains(section.sectionId))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$selectedCount of ${sections.length} section${sections.length == 1 ? '' : 's'} selected.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ...sections.map((section) {
          final selected = selectedSectionIds.contains(section.sectionId);

          return CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: selected,
            title: Text(section.displayLabel),
            subtitle: Text(section.summaryLabel),
            onChanged: (value) {
              onChanged(section.sectionId, value == true);
            },
          );
        }),
      ],
    );
  }
}

class _CloseoutScopeCard extends StatelessWidget {
  final bool loading;
  final List<_CloseoutScope> scopes;
  final List<_CloseoutSectionSummary> sections;
  final _CloseoutScope? selectedScope;
  final ValueChanged<_CloseoutScope> onChanged;
  final Set<String> customSectionIds;
  final void Function(String sectionId, bool selected) onCustomSectionChanged;

  const _CloseoutScopeCard({
    required this.loading,
    required this.scopes,
    required this.sections,
    required this.selectedScope,
    required this.onChanged,
    required this.customSectionIds,
    required this.onCustomSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _CloseoutSectionCard(
      title: 'Finalize Scope',
      subtitle:
          'Choose what part of the show you want to finalize, generate, or send.',
      children: [
        if (loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: scopes.map((scope) {
              final selected = selectedScope?.type == scope.type;

              return ChoiceChip(
                selected: selected,
                label: Text(scope.label),
                onSelected: (_) => onChanged(scope),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (selectedScope != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.navy.withOpacity(.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.navy.withOpacity(.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedScope!.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(selectedScope!.description),
                  const SizedBox(height: 8),
                  if (selectedScope!.isCustom)
                    _CustomSectionPicker(
                      sections: sections.where((s) => s.isEnabled).toList(),
                      selectedSectionIds: customSectionIds,
                      onChanged: onCustomSectionChanged,
                    )
                  else
                    Text(
                      'Included sections: ${_sectionLabelsForScope(selectedScope!, sections).join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  List<String> _sectionLabelsForScope(
    _CloseoutScope scope,
    List<_CloseoutSectionSummary> sections,
  ) {
    final labels = sections
        .where((s) => scope.sectionIds.contains(s.sectionId))
        .map(
          (s) =>
              s.displayName.isEmpty ? '${s.kind} ${s.letter}' : s.displayName,
        )
        .toList();

    return labels.isEmpty ? ['None'] : labels;
  }
}

class ReportArtifactSummary {
  final String id;
  final String? finalizeRunId;
  final String reportName;
  final String artifactStatus;
  final String? fileName;
  final String? storageBucket;
  final String? storagePath;
  final String? generatedAt;
  final bool isCurrent;
  final Map<String, dynamic> metadata;

  ReportArtifactSummary({
    required this.id,
    this.finalizeRunId,
    required this.reportName,
    required this.artifactStatus,
    this.fileName,
    this.storageBucket,
    this.storagePath,
    this.generatedAt,
    required this.isCurrent,
    required this.metadata,
  });

  factory ReportArtifactSummary.fromJson(Map<String, dynamic> json) {
    return ReportArtifactSummary(
      id: (json['id'] ?? '') as String,
      finalizeRunId: json['finalize_run_id'] as String?,
      reportName: (json['report_name'] ?? '') as String,
      artifactStatus: (json['artifact_status'] ?? 'queued') as String,
      fileName: json['file_name'] as String?,
      storageBucket: json['storage_bucket'] as String?,
      storagePath: json['storage_path'] as String?,
      generatedAt: json['generated_at'] as String?,
      isCurrent: (json['is_current'] ?? false) == true,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : <String, dynamic>{},
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

enum _CloseoutScopeType {
  entireShow,
  rabbitAllBreed,
  cavyAllBreed,
  specialty,
  custom,
}

class _MissingJudgeItem {
  final String entryId;
  final String sectionLabel;
  final String breedName;
  final String? groupName;
  final String? varietyName;
  final String className;
  final String sex;
  final String tattoo;
  final String exhibitorLabel;

  const _MissingJudgeItem({
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

class _DuplicatePlacementGroupItem {
  final String sectionLabel;
  final String breedName;
  final String? groupName;
  final String? varietyName;
  final String className;
  final String sex;
  final String placement;
  final List<_DuplicatePlacementEntryItem> entries;

  const _DuplicatePlacementGroupItem({
    required this.sectionLabel,
    required this.breedName,
    required this.groupName,
    required this.varietyName,
    required this.className,
    required this.sex,
    required this.placement,
    required this.entries,
  });
}

class _DuplicatePlacementEntryItem {
  final String entryId;
  final String tattoo;
  final String exhibitorLabel;

  const _DuplicatePlacementEntryItem({
    required this.entryId,
    required this.tattoo,
    required this.exhibitorLabel,
  });
}

class _CloseoutScope {
  final _CloseoutScopeType type;
  final String label;
  final String description;
  final List<String> sectionIds;

  const _CloseoutScope({
    required this.type,
    required this.label,
    required this.description,
    required this.sectionIds,
  });

  bool get isCustom => type == _CloseoutScopeType.custom;
}

class _CloseoutSectionSummary {
  final String sectionId;
  final String kind;
  final String letter;
  final String displayName;
  final String breedScope;
  final List<String> allowedBreedIds;
  final bool isEnabled;
  final int sortOrder;
  final List<String> species;
  final int entryCount;

  const _CloseoutSectionSummary({
    required this.sectionId,
    required this.kind,
    required this.letter,
    required this.displayName,
    required this.breedScope,
    required this.allowedBreedIds,
    required this.isEnabled,
    required this.sortOrder,
    required this.species,
    required this.entryCount,
  });

  bool get isAllBreed => breedScope.trim().toLowerCase() == 'all';

  bool get isSpecialty =>
      breedScope.trim().toLowerCase() != 'all' || allowedBreedIds.isNotEmpty;

  String get displayLabel {
    if (displayName.trim().isNotEmpty) return displayName.trim();

    final kindLabel = kind.trim().isEmpty
        ? 'Section'
        : '${kind[0].toUpperCase()}${kind.substring(1)}';

    return '$kindLabel ${letter.trim()}'.trim();
  }

  String get summaryLabel {
    final parts = <String>[
      if (kind.trim().isNotEmpty) kind.toUpperCase(),
      if (letter.trim().isNotEmpty) 'Show ${letter.toUpperCase()}',
      if (breedScope.trim().isNotEmpty) breedScope,
      if (species.isNotEmpty) species.join(', '),
      '$entryCount entr${entryCount == 1 ? 'y' : 'ies'}',
    ];

    return parts.join(' • ');
  }

  factory _CloseoutSectionSummary.fromJson(Map<String, dynamic> json) {
    return _CloseoutSectionSummary(
      sectionId: (json['section_id'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      letter: (json['letter'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      breedScope: (json['breed_scope'] ?? '').toString(),
      allowedBreedIds: json['allowed_breed_ids'] is List
          ? List<String>.from(
              (json['allowed_breed_ids'] as List).map((e) => e.toString()),
            )
          : const [],
      isEnabled: json['is_enabled'] == true,
      sortOrder: ((json['sort_order'] ?? 0) as num).toInt(),
      species: json['species'] is List
          ? List<String>.from(
              (json['species'] as List).map((e) => e.toString()),
            )
          : const [],
      entryCount: ((json['entry_count'] ?? 0) as num).toInt(),
    );
  }
}
