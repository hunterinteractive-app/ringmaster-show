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

import 'closeout/pdf/builders/legs_report_pdf.dart';
import 'closeout/pdf/builders/exhibitor_report_pdf.dart';
import 'closeout/pdf/builders/sweepstakes_report_pdf.dart';
import 'closeout/pdf/builders/breed_results_detail_report_pdf.dart';
import 'closeout/pdf/builders/unpaid_balances_report_pdf.dart';
import 'closeout/pdf/builders/paid_exhibitor_report_pdf.dart';
import 'closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart';
import 'closeout/pdf/builders/ribbon_payout_report_pdf.dart';

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
  bool _generatingReport = false;
  String? _error;
  Uint8List? _reportLogoBytes;

  CloseoutDashboard? _dashboard;
  LegsReportPdfBuilder? _legsBuilder;
  ExhibitorReportPdfBuilder? _exhibitorBuilder;
  UnpaidBalancesReportPdfBuilder? _unpaidBalancesBuilder;
  PaidExhibitorReportPdfBuilder? _paidExhibitorReportBuilder;
  EnteredExhibitorsContactReportPdf? _enteredExhibitorsContactBuilder;
  RibbonPayoutReportPdf? _ribbonPayoutBuilder;

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
      'unpaid_balances_report',
      'paid_exhibitor_report',
      'entered_exhibitors_contact_report',
      'legs',
      'newsletter_show_report',
      'ribbon_payout_report',
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
      return value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
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
          .where(_artifactIsUsableCurrent)
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

    List<ReportArtifactSummary> _currentArtifactsForReportGroup(
      String reportName,
    ) {
      final artifacts = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
          .where((artifact) => artifact.reportName == reportName)
          .where((artifact) => artifact.isCurrent)
          .where(_artifactMatchesSelectedScope)
          .toList()
        ..sort((a, b) {
          final aScope = (_artifactMetaString(a, 'scope') ?? '').toUpperCase();
          final bScope = (_artifactMetaString(b, 'scope') ?? '').toUpperCase();
          final scopeCmp = aScope.compareTo(bScope);
          if (scopeCmp != 0) return scopeCmp;

          final aLetter = (_artifactMetaString(a, 'show_letter') ?? '').toUpperCase();
          final bLetter = (_artifactMetaString(b, 'show_letter') ?? '').toUpperCase();
          final letterCmp = aLetter.compareTo(bLetter);
          if (letterCmp != 0) return letterCmp;

          final aGenerated = DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bGenerated = DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bGenerated.compareTo(aGenerated);
        });

      return artifacts;
    }

    bool _artifactMatchesSelectedScope(
      ReportArtifactSummary artifact,
    ) {
      if (_selectedCloseoutScopeIsEntireShow) {
        return true;
      }

      final artifactScope =
          (artifact.metadata['scope_label'] ?? '').toString().trim();

      return artifactScope == _selectedCloseoutScopeLabel;
    }

    bool _artifactMatchesExhibitor(
      ReportArtifactSummary artifact,
      _ExhibitorEmailTarget exhibitor,
    ) {
      final artifactExhibitorId =
          _artifactMetaString(artifact, 'exhibitor_id')?.trim();

      return artifactExhibitorId != null &&
          artifactExhibitorId == exhibitor.exhibitorId;
    }

    bool _artifactMatchesClubTarget(
      ReportArtifactSummary artifact,
      _ClubEmailTarget target,
    ) {
      final artifactBreed =
          (_artifactMetaString(artifact, 'breed_name') ?? '').trim().toLowerCase();
      final artifactScope =
          (_artifactMetaString(artifact, 'scope') ?? '').trim().toUpperCase();
      final artifactShowLetter =
          (_artifactMetaString(artifact, 'show_letter') ?? '').trim().toUpperCase();

      if (artifactScope != target.scope.trim().toUpperCase()) return false;
      if (artifactShowLetter != target.showLetter.trim().toUpperCase()) return false;

      // State clubs are section-wide, so they match all breeds in that section.
      if (target.sanctioningBody == 'STATE CLUB') {
        return true;
      }

      return artifactBreed == target.breedName.trim().toLowerCase();
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
            ..sort((a, b) => a.exhibitorName.toLowerCase().compareTo(
                  b.exhibitorName.toLowerCase(),
                ));

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

      final out = <String, _ClubEmailTarget>{};

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);

        final sanctioningBody =
            (row['sanctioning_body'] ?? '').toString().trim().toUpperCase();

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
        final showLetter = (section['letter'] ?? '').toString().trim().toUpperCase();

        if (clubName.isEmpty || scope.isEmpty || showLetter.isEmpty || email.isEmpty) {
          continue;
        }

        // Breed is required for national + state breed clubs, but not for state clubs.
        if (sanctioningBody != 'STATE CLUB' && breedName.isEmpty) {
          continue;
        }

        final key = sanctioningBody == 'STATE CLUB'
            ? '$sanctioningBody|$clubName|$scope|$showLetter|$email'
            : '$sanctioningBody|$clubName|$breedName|$scope|$showLetter|$email';

        out[key] = _ClubEmailTarget(
          clubName: clubName,
          breedName: breedName,
          scope: scope,
          showLetter: showLetter,
          email: email,
          sanctioningBody: sanctioningBody,
        );
      }

      final list = out.values.toList()
        ..sort((a, b) {
          final bodyCmp =
              a.sanctioningBody.toLowerCase().compareTo(b.sanctioningBody.toLowerCase());
          if (bodyCmp != 0) return bodyCmp;

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
            .map((raw) => _CloseoutSectionSummary.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ))
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

        final specialtySections =
            enabledSections.where((s) => s.isSpecialty).toList();

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
          final stillExists = currentType != null &&
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

    Future<void> _syncClubDeliveryMetadata() async {
      await supabase.rpc(
        'prepare_club_delivery_targets',
        params: {'p_show_id': widget.showId},
      );
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
          final judgeId =
              (row['judged_by_show_judge_id'] ?? '').toString().trim();

          final isEligible =
              scratchedAt.isEmpty && isShown && !isDisqualified;

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

          if (scratchedAt.isNotEmpty) return false;
          if (!isShown) return false;
          if (isDisqualified) return false;
          if (status == 'no show') return false;
          if (status.startsWith('disqualified')) return false;
          if (status == 'unworthy of award') return false;

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
            (a, b) => a.tattoo.toLowerCase().compareTo(
                  b.tattoo.toLowerCase(),
                ),
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
          final sectionCmp =
              a.sectionLabel.toLowerCase().compareTo(b.sectionLabel.toLowerCase());
          if (sectionCmp != 0) return sectionCmp;

          final breedCmp =
              a.breedName.toLowerCase().compareTo(b.breedName.toLowerCase());
          if (breedCmp != 0) return breedCmp;

          final varietyCmp = (a.varietyName ?? '')
              .toLowerCase()
              .compareTo((b.varietyName ?? '').toLowerCase());
          if (varietyCmp != 0) return varietyCmp;

          final classCmp =
              a.className.toLowerCase().compareTo(b.className.toLowerCase());
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

      return ExpansionTile(
        title: Text('$count missing judges'),
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
            const ListTile(
              title: Text('No missing judge rows found.'),
            )
          else
            ..._missingJudgeItems.map(
              (e) => ListTile(
                title: Text(e.tattoo.isEmpty ? '(No ear #)' : e.tattoo),
                subtitle: Text(
                  [
                    e.sectionLabel,
                    e.breedName,
                    if (e.varietyName != null && e.varietyName!.isNotEmpty)
                      e.varietyName!,
                    e.className,
                    e.sex,
                    if (e.exhibitorLabel.isNotEmpty) e.exhibitorLabel,
                  ].join(' • '),
                ),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.build, size: 18),
                  label: const Text('Fix'),
                  onPressed: () => _openResultsEntryFix(e.entryId),
                ),
                onTap: () => _openResultsEntryFix(e.entryId),
              ),
            ),
        ],
      );
    }
    
    Widget _buildDuplicatePlacementGroupsPanel() {
      final count =
          _dashboard?.resultsReadiness.duplicatePlacementGroupCount ?? 0;
      if (count <= 0) return const SizedBox.shrink();

      return ExpansionTile(
        title: Text('$count duplicate placements'),
        subtitle: const Text('Tap to view duplicated placements.'),
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
          else if (_duplicatePlacementsLoaded && _duplicatePlacementGroupItems.isEmpty)
            const ListTile(
              title: Text('No duplicate placement rows found.'),
              subtitle: Text(
                'The readiness count found duplicates, but the detail loader did not match them. Refresh the dashboard and confirm show_results_readiness uses the same row source as results entry.',
              ),
            )
          else
            ..._duplicatePlacementGroupItems.map((group) {
              final firstEntryId = group.entries.isEmpty ? '' : group.entries.first.entryId;

              return ListTile(
                title: Text(
                  [
                    group.sectionLabel,
                    group.breedName,
                    if (group.varietyName != null && group.varietyName!.isNotEmpty)
                      group.varietyName!,
                    group.className,
                    group.sex,
                    'Place ${group.placement}',
                  ].where((x) => x.trim().isNotEmpty).join(' • '),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: group.entries
                      .map((e) => Text('${e.tattoo.isEmpty ? '(No ear #)' : e.tattoo} • ${e.exhibitorLabel}'))
                      .toList(),
                ),
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
                      TextButton.icon(
                        onPressed: () => _openResultsEntryFix(item.entryId),
                        icon: const Icon(Icons.build, size: 18),
                        label: const Text('Fix'),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      );
    }

    Future<void> _refreshDashboardOnly() async {
      try {
        final dashboardResp = await supabase.rpc(
          'get_show_closeout_dashboard',
          params: {'p_show_id': widget.showId},
        );

        final dashboardJson = Map<String, dynamic>.from(dashboardResp as Map);
        final dashboard = CloseoutDashboard.fromJson(dashboardJson);

        final readinessResp = await supabase.rpc(
          'show_results_readiness',
          params: {'p_show_id': widget.showId},
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

          _missingPlacementsLoaded = false;
          _missingPlacementItems = [];

          _missingJudgesLoaded = false;
          _missingJudgeItems = [];

          _duplicatePlacementsLoaded = false;
          _duplicatePlacementGroupItems = [];
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed refreshing reports: $e')),
        );
      }
    }

    Future<void> _loadDataUntilFinalizeVisible({
      required String previousFinalizeId,
    }) async {
      for (var attempt = 0; attempt < 10; attempt++) {
        await _refreshDashboardOnly();

        final latestId = _dashboard?.latestFinalize.id;

        final hasNewFinalize = latestId != null && latestId != previousFinalizeId;

        final hasCurrentReports = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
            .any((r) => r.isCurrent);

        if (hasNewFinalize && hasCurrentReports) {
          return;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      await _refreshDashboardOnly();
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
        throw Exception('Select at least one section before finalizing this scope.');
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

      final breedResultsDetailReportLoader =
          BreedResultsDetailReportLoader(repository);
      final breedResultsDetailReportBuilder = BreedResultsDetailReportPdf(
        logoBytes: _reportLogoBytes,
      );

      final unpaidBalancesLoader = UnpaidBalancesReportLoader(repository);
      final paidExhibitorReportLoader = PaidExhibitorReportLoader(repository);

      final enteredExhibitorsContactLoader =
          EnteredExhibitorsContactReportLoader(supabase);

      final ribbonPayoutLoader = RibbonPayoutReportLoader(repository);

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
        unpaidBalancesLoader: unpaidBalancesLoader,
        unpaidBalancesBuilder: _unpaidBalancesBuilder!,
        paidExhibitorReportLoader: paidExhibitorReportLoader,
        paidExhibitorReportBuilder: _paidExhibitorReportBuilder!,
        enteredExhibitorsContactLoader: enteredExhibitorsContactLoader,
        enteredExhibitorsContactBuilder: _enteredExhibitorsContactBuilder!,
        ribbonPayoutLoader: ribbonPayoutLoader,
        ribbonPayoutBuilder: _ribbonPayoutBuilder!,
      );

      final engine = ReportEngine(registry);
      final uploadService = ReportUploadService(supabase);

      final runner = CloseoutRunner(
        engine: engine,
        uploadService: uploadService,
      );

      String artifactKey(ReportArtifactSummary artifact) {
        return '${artifact.reportName}::${artifact.id}';
      }

      Future<void> runSingle(ReportArtifactSummary artifact) async {
        final key = artifactKey(artifact);
        onStarted(key);

        final runId =
            artifact.finalizeRunId ?? _dashboard?.latestFinalize.id ?? 'manual-run';

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
              artifact.reportName == 'breed_results_detail_report') {
            final breedName = _artifactMetaString(artifact, 'breed_name');
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
            await runner.generateSingleReport(
              showId: widget.showId,
              finalizeRunId: runId,
              reportName: artifact.reportName,
              artifactId: artifact.id,
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
              'metadata': {
                ...artifact.metadata,
                'last_error': error.toString(),
              },
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
            a.reportName == 'breed_results_detail_report') {
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
          if (_artifactMetaString(artifact, 'scope') == null) missing.add('metadata.scope');
          if (_artifactMetaString(artifact, 'show_letter') == null) missing.add('metadata.show_letter');
        } else if (artifact.reportName == 'exhibitor_report') {
          if (_artifactMetaString(artifact, 'exhibitor_id') == null) missing.add('metadata.exhibitor_id');
        } else if (artifact.reportName == 'legs' || artifact.reportName == 'leg_report') {
          if (_artifactMetaString(artifact, 'exhibitor_id') == null) {
            missing.add('metadata.exhibitor_id');
          }
        } else if (artifact.reportName == 'sweepstakes_report' ||
            artifact.reportName == 'breed_results_detail_report') {
          if (_artifactMetaString(artifact, 'scope') == null) missing.add('metadata.scope');
          if (_artifactMetaString(artifact, 'show_letter') == null) missing.add('metadata.show_letter');
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
      _enteredExhibitorsContactBuilder ??=
          EnteredExhibitorsContactReportPdf();
    }

    Future<void> _ensureRibbonPayoutBuilder() async {
      _ribbonPayoutBuilder ??= RibbonPayoutReportPdf();
    }

  Future<void> _sendAllExhibitorReports() async {
    if (_isSupportMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Exhibitor email sending is disabled while viewing in support mode.',
          ),
        ),
      );
      return;
    }
    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      await _loadData();

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
        final exhibitorReport = _newestGeneratedArtifactWhere(
          'exhibitor_report',
          (a) =>
              _artifactMatchesExhibitor(a, exhibitor) &&
              _artifactMatchesSelectedScope(a),
        );

        final legsReport = _newestGeneratedArtifactWhere(
          'legs',
          (a) =>
              _artifactMatchesExhibitor(a, exhibitor) &&
              _artifactMatchesSelectedScope(a),
        );

        final artifacts = <ReportArtifactSummary>[
          if (exhibitorReport != null) exhibitorReport,
          if (legsReport != null) legsReport,
        ];

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
            sendErrors.add('${exhibitor.exhibitorName} <${exhibitor.email}>: $errorText');
          }
        }
      }

      if (!mounted) return;

      final summary =
          'Exhibitor report send complete. Sent: $sentCount, skipped: $skippedCount, failed: $failedCount';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(summary),
        ),
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
      if (_isSupportMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Club email sending is disabled while viewing in support mode.',
          ),
        ),
      );
      return;
    }
    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      await _loadData();
      await _syncClubDeliveryMetadata();
      await _loadData();

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
        final key = club.sanctioningBody == 'STATE CLUB'
            ? '${club.sanctioningBody.trim().toLowerCase()}|${club.clubName.trim().toLowerCase()}|${club.scope.trim().toUpperCase()}|${club.showLetter.trim().toUpperCase()}|${club.email.trim().toLowerCase()}'
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
        final artifactsById = <String, ReportArtifactSummary>{};

        for (final target in targets) {
          final sweepstakesArtifacts = _allGeneratedArtifactsWhere(
            'sweepstakes_report',
            (a) =>
                _artifactMatchesClubTarget(a, target) &&
                _artifactMatchesSelectedScope(a),
          );

          final breedDetailArtifacts = _allGeneratedArtifactsWhere(
            'breed_results_detail_report',
            (a) =>
                _artifactMatchesClubTarget(a, target) &&
                _artifactMatchesSelectedScope(a),
          );

          for (final a in sweepstakesArtifacts) {
            artifactsById[a.id] = a;
          }

          for (final a in breedDetailArtifacts) {
            artifactsById[a.id] = a;
          }
        }

        final artifacts = artifactsById.values.toList()
          ..sort((a, b) {
            final aScope =
                (_artifactMetaString(a, 'scope') ?? '').trim().toUpperCase();
            final bScope =
                (_artifactMetaString(b, 'scope') ?? '').trim().toUpperCase();

            final aLetter =
                (_artifactMetaString(a, 'show_letter') ?? '').trim().toUpperCase();
            final bLetter =
                (_artifactMetaString(b, 'show_letter') ?? '').trim().toUpperCase();

            final scopeCmp = aScope.compareTo(bScope);
            if (scopeCmp != 0) return scopeCmp;

            final letterCmp = aLetter.compareTo(bLetter);
            if (letterCmp != 0) return letterCmp;

            return a.reportName.compareTo(b.reportName);
          });

        final includedSanctionNumbers = artifacts
            .map((a) => (_artifactMetaString(a, 'sanction_number') ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        if (artifacts.isEmpty) {
          skippedCount++;
          continue;
        }

        try {
          final subject = first.sanctioningBody == 'STATE CLUB'
              ? '${widget.showName} - ${first.clubName} Club Reports'
              : '${widget.showName} - ${first.breedName} Club Reports';

          final message = first.sanctioningBody == 'STATE CLUB'
              ? 'Attached are the club reports for ${widget.showName} for ${first.scope} ${first.showLetter}.\n\n'
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

      if (parts.isEmpty) {
        return 'Results are ready for reports.';
      }

      return 'Reports are blocked until results are complete: ${parts.join(', ')}.';
    }

  Future<void> _sendAllLegsReports() async {
    if (_isSupportMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Leg email sending is disabled while viewing in support mode.',
          ),
        ),
      );
      return;
    }

    final ready = await _ensureResultsReadyForReports();
    if (!ready) return;

    setState(() {
      _generatingReport = true;
    });

    try {
      await _loadData();

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
            message: 'Attached are your earned ARBA legs from ${widget.showName}.',
            allowLegs: true,
          );
          sentCount++;
        } catch (e) {
          failedCount++;

          final errorText = e.toString().trim().isEmpty
              ? 'Unknown email send error. Check Supabase function logs for send-exhibitor-report-email.'
              : e.toString();

          if (sendErrors.length < 5) {
            sendErrors.add('${exhibitor.exhibitorName} <${exhibitor.email}>: $errorText');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed sending leg reports: $e')),
      );
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
  bool get _isSupportMode => AppSession.isSupportMode;

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

    final bytes = await rootBundle.load('assets/images/ringmaster_show_logo.png');
    _reportLogoBytes = bytes.buffer.asUint8List();
  }

  Future<void> _loadArbaDetails() async {
    final showRow = await supabase
        .from('shows')
        .select('secretary_name, secretary_address, secretary_email, secretary_phone')
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

      final readinessResp = await supabase.rpc(
        'show_results_readiness',
        params: {'p_show_id': widget.showId},
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

      await _loadArbaDetails();
      await _ensureLegsBuilder();
      await _ensureExhibitorBuilder();
      await _ensureUnpaidBalancesBuilder();
      await _ensurePaidExhibitorReportBuilder();
      await _ensureReportLogo();
      await _ensureEnteredExhibitorsContactBuilder();
      await _ensureRibbonPayoutBuilder();
      await _loadCloseoutScopes();

      if (!mounted) return;
      setState(() {
        _dashboard = dashboardWithFreshReadiness;

        _missingPlacementsLoaded = false;
        _missingPlacementItems = [];

        _missingJudgesLoaded = false;
        _missingJudgeItems = [];

        _duplicatePlacementsLoaded = false;
        _duplicatePlacementGroupItems = [];
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
      final secretaryName = _secretaryNameController.text.trim();
      final secretaryAddress = _secretaryAddressController.text.trim();
      final secretaryEmail = _secretaryEmailController.text.trim();
      final secretaryPhone = _secretaryPhoneController.text.trim();

      await supabase
          .from('shows')
          .update({
            'secretary_name': secretaryName.isEmpty ? null : secretaryName,
            'secretary_address': secretaryAddress.isEmpty ? null : secretaryAddress,
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

    Future<ReportArtifactSummary> _createManualReportArtifact({
      required String reportName,
      Map<String, dynamic>? metadata,
    }) async {
      final finalizeRunId = _dashboard?.latestFinalize.id;

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

      return ReportArtifactSummary.fromJson(
        Map<String, dynamic>.from(inserted),
      );
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

  Future<void> _generateCurrentReportGroupByName(String reportName) async {
    if (reportName != 'unpaid_balances_report' &&
        reportName != 'paid_exhibitor_report') {
      final ready = await _ensureResultsReadyForReports();
      if (!ready) return;
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

      await _refreshDashboardOnly();

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

        final breedResultsDetailReportLoader =
            BreedResultsDetailReportLoader(repository);
        final breedResultsDetailReportBuilder =
            BreedResultsDetailReportPdf(
          logoBytes: _reportLogoBytes,
        );

        final unpaidBalancesLoader = UnpaidBalancesReportLoader(repository);
        final paidExhibitorReportLoader = PaidExhibitorReportLoader(repository);

        final enteredExhibitorsContactLoader =
            EnteredExhibitorsContactReportLoader(supabase);

        final ribbonPayoutLoader = RibbonPayoutReportLoader(repository);

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
          unpaidBalancesLoader: unpaidBalancesLoader,
          unpaidBalancesBuilder: _unpaidBalancesBuilder!,
          paidExhibitorReportLoader: paidExhibitorReportLoader,
          paidExhibitorReportBuilder: _paidExhibitorReportBuilder!,
          enteredExhibitorsContactLoader: enteredExhibitorsContactLoader,
          enteredExhibitorsContactBuilder: _enteredExhibitorsContactBuilder!,
          ribbonPayoutLoader: ribbonPayoutLoader,
          ribbonPayoutBuilder: _ribbonPayoutBuilder!,
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
          artifact = reports.cast<ReportArtifactSummary?>().firstWhere(
            (r) {
              if (r == null) return false;
              final artExhibitorId =
                  (_artifactMetaString(r, 'exhibitor_id') ?? '').trim();
              return artExhibitorId == (exhibitorId ?? '').trim();
            },
            orElse: () => null,
          );
        } else if (reportName == 'sweepstakes_report' ||
            reportName == 'breed_results_detail_report') {
          artifact = reports.cast<ReportArtifactSummary?>().firstWhere(
            (r) {
              if (r == null) return false;

              final breed =
                  (_artifactMetaString(r, 'breed_name') ?? '').trim().toLowerCase();
              final artScope =
                  (_artifactMetaString(r, 'scope') ?? '').trim().toUpperCase();
              final artLetter =
                  (_artifactMetaString(r, 'show_letter') ?? '').trim().toUpperCase();

              return breed == (breedName ?? '').trim().toLowerCase() &&
                  artScope == (scope ?? '').trim().toUpperCase() &&
                  artLetter == (showLetter ?? '').trim().toUpperCase();
            },
            orElse: () => null,
          );
        } else {
          artifact = reports.cast<ReportArtifactSummary?>().firstWhere(
            (r) => r != null,
            orElse: () => null,
          );
        }

        final resolvedArtifact = artifact ??
            await _createManualReportArtifact(
              reportName: reportName,
              metadata: {
                if (breedName != null && breedName.trim().isNotEmpty)
                  'breed_name': breedName.trim(),
                if (scope != null && scope.trim().isNotEmpty)
                  'scope': scope.trim(),
                if (showLetter != null && showLetter.trim().isNotEmpty)
                  'show_letter': showLetter.trim(),
                if (exhibitorId != null && exhibitorId.trim().isNotEmpty)
                  'exhibitor_id': exhibitorId.trim(),
                if (exhibitorName != null && exhibitorName.trim().isNotEmpty)
                  'exhibitor_name': exhibitorName.trim(),
              },
            );

        await runner.generateSingleReport(
          showId: widget.showId,
          finalizeRunId: _dashboard?.latestFinalize.id ?? 'manual-run',
          reportName: reportName,
          artifactId: resolvedArtifact.id,
          breedName: breedName,
          scope: scope,
          showName: widget.showName,
          showDate: showDate,
          sanctionNumber: sanctionNumber,
          showLetter: showLetter,
          exhibitorId: exhibitorId,
          exhibitorName: exhibitorName,
          isNationalShow: isNationalShow,
        );

        await _refreshDashboardOnly();

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

  Future<void> _downloadReportByName(
    String reportName, {
    String? exhibitorId,
    String? breedName,
    String? scope,
    String? showLetter,
  }) async {
    try {
      final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

      var matches = reports.where((r) =>
          r.reportName == reportName &&
          r.isCurrent &&
          r.artifactStatus == 'generated' &&
          (r.storageBucket?.isNotEmpty == true) &&
          (r.storagePath?.isNotEmpty == true));

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
            const SnackBar(
              content: Text('No generated ARBA reports found.'),
            ),
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
          reportName == 'breed_results_detail_report') {
        matches = matches.where((r) {
          final artBreed =
              (r.metadata['breed_name'] ?? '').toString().trim().toLowerCase();
          final artScope =
              (r.metadata['scope'] ?? '').toString().trim().toUpperCase();
          final artLetter =
              (r.metadata['show_letter'] ?? '').toString().trim().toUpperCase();

          return artBreed == (breedName ?? '').trim().toLowerCase() &&
              artScope == (scope ?? '').trim().toUpperCase() &&
              artLetter == (showLetter ?? '').trim().toUpperCase();
        });
      }

      final list = matches.toList()
        ..sort((a, b) {
          final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDt.compareTo(aDt);
        });

      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No generated ${_friendlyReportName(reportName)} found.'),
          ),
        );
        return;
      }

      final newest = list.first;

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


  Future<void> _emailReportByName(
    String reportName, {
    String? exhibitorId,
    String? exhibitorEmail,
    String? breedName,
    String? scope,
    String? showLetter,
  }) async {
    if (_isSupportMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email sending is disabled while viewing in support mode.',
          ),
        ),
      );
      return;
    }
    try {
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

      final list = artifacts.toList()
        ..sort((a, b) {
          final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
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

      final isClubReport = reportName == 'sweepstakes_report' ||
          reportName == 'breed_results_detail_report';

      if (isClubReport) {
        final clubTargets = await _loadClubEmailTargets();

        final matchingTargets = clubTargets.where((target) {
          return target.breedName.trim().toLowerCase() ==
                  (breedName ?? '').trim().toLowerCase() &&
              target.scope.trim().toUpperCase() ==
                  (scope ?? '').trim().toUpperCase() &&
              target.showLetter.trim().toUpperCase() ==
                  (showLetter ?? '').trim().toUpperCase();
        }).toList();

        if (matchingTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No club email found for this report.')),
          );
          return;
        }

        await _sendClubArtifactsEmail(
          artifacts: [artifact],
          to: matchingTargets.first.email,
          subject: '${widget.showName} - ${matchingTargets.first.breedName} Club Report',
          message: 'Attached is the club report from ${widget.showName}.',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_friendlyReportName(reportName)} emailed.')),
        );
        return;
      }

      final email = (exhibitorEmail ??
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
        SnackBar(
          content: Text('${_friendlyReportName(reportName)} emailed.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email failed: $e')),
      );
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

  List<ReportArtifactSummary> _reportsForGroup(String groupKey) {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

    final filtered = switch (groupKey) {
      'arba' => reports.where((r) => _arbaReportKeys.contains(r.reportName)).toList(),
      'exhibitor' => reports
          .where((r) => _exhibitorReportKeys.contains(r.reportName))
          .toList(),
      'club' => reports.where((r) => _clubReportKeys.contains(r.reportName)).toList(),
      'other' => reports.where((r) {
          return !_arbaReportKeys.contains(r.reportName) &&
              !_exhibitorReportKeys.contains(r.reportName) &&
              !_clubReportKeys.contains(r.reportName);
        }).toList(),
      _ => reports,
    };

    final scoped = filtered.where((r) {
      return _artifactMatchesSelectedScope(r);
    }).toList();

    scoped.sort((a, b) {
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

    return scoped;
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
      } else if (groupKey == 'other') {
        const otherManualReports = <String>{
          'unpaid_balances_report',
          'paid_exhibitor_report',
          'entered_exhibitors_contact_report',
          'ribbon_payout_report',
        };

        for (final name in otherManualReports) {
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
                            if (_isSupportMode)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.amber.shade300,
                                  ),
                                ),
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.support_agent,
                                      color: Colors.orange,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Support Mode — You are managing closeout as an admin while viewing another user. Finalize, save, and report generation are allowed. Bulk email sending remains disabled.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            _ArbaCloseoutCard(
                              secretaryNameController: _secretaryNameController,
                              secretaryAddressController:
                                  _secretaryAddressController,
                              secretaryEmailController:
                                  _secretaryEmailController,
                              secretaryPhoneController:
                                  _secretaryPhoneController,
                              superintendentController:
                                  _superintendentController,
                              superintendentNumberController:
                                  _superintendentNumberController,
                              sweepstakesIssue: _sweepstakesIssue,
                              sweepstakesClubController:
                                  _sweepstakesClubController,
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
                                });
                              },
                              onCustomSectionChanged: (sectionId, selected) {
                                setState(() {
                                  if (selected) {
                                    _customCloseoutSectionIds.add(sectionId);
                                  } else {
                                    _customCloseoutSectionIds.remove(sectionId);
                                  }
                                });
                              },
                            ),

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
                              _buildMissingJudgesPanel(),
                              _buildDuplicatePlacementGroupsPanel(),
                              const SizedBox(height: 16),
                            ],

                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: reportsBlocked
                                        ? Colors.grey
                                        : (_dashboard?.dashboard.closeout
                                                    .isReportsStale ==
                                                true
                                            ? const Color(0xFFD4A623)
                                            : Colors.green),
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
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),
                                                          FilledButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                              context,
                                                              true,
                                                            ),
                                                            child: const Text(
                                                              'Finalize',
                                                            ),
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
                                                _dashboard?.latestFinalize.id ??
                                                    '';

                                            await _finalizeShow();

                                            await _loadDataUntilFinalizeVisible(
                                              previousFinalizeId:
                                                  previousFinalizeId,
                                            );

                                            final artifactCount =
                                                await _countQueuedArtifactsForShow();

                                            if (artifactCount == 0) {
                                              throw Exception(
                                                'Finalize completed but no report artifacts were created.',
                                              );
                                            }

                                            final List<ReportArtifactSummary> artifactsToGenerate =
                                                (_dashboard?.reports ?? const <ReportArtifactSummary>[])
                                                    .where((r) => r.isCurrent)
                                                    .where((r) {
                                                      if (_selectedCloseoutScopeIsEntireShow) return true;

                                                      return (r.metadata['scope_label'] ?? '').toString() ==
                                                          _selectedCloseoutScopeLabel;
                                                    })
                                                    .where(
                                                      (r) =>
                                                          r.artifactStatus == 'queued' ||
                                                          r.artifactStatus == 'failed',
                                                    )
                                                    .where(
                                                      (r) => {
                                                        'arba_report',
                                                        'exhibitor_report',
                                                        'legs',
                                                        'sweepstakes_report',
                                                        'breed_results_detail_report',
                                                      }.contains(r.reportName),
                                                    )
                                                    .toList();

                                            if (artifactsToGenerate.isEmpty) {
                                              await _refreshDashboardOnly();
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Finalize completed. No queued Flutter-rendered reports needed generation.',
                                                    ),
                                                  ),
                                                );
                                              }
                                              return;
                                            }

                                            final generatedOk =
                                                await showDialog<bool>(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) {
                                                return _GenerateAllReportsDialog(
                                                  artifacts: artifactsToGenerate,
                                                  onRun: (
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

                                            await _syncClubDeliveryMetadata();
                                            await _loadData();

                                            if (_dashboard?.dashboard.closeout
                                                    .isReportsStale ==
                                                true) {
                                              throw Exception(
                                                'Flutter generation completed, but reports are still marked stale.',
                                              );
                                            }

                                            if (!mounted) return;

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Finalize and report generation completed. Review reports, then use the send buttons when ready.',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            if (!mounted) return;

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
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
                                        : (_dashboard?.dashboard.closeout.isReportsStale == true
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
                                        (_dashboard?.reports ?? const <ReportArtifactSummary>[])
                                            .where((r) => r.isCurrent)
                                            .where(
                                              (r) =>
                                                  r.artifactStatus == 'queued' ||
                                                  r.artifactStatus == 'failed',
                                            )
                                            .toList();

                                    return OutlinedButton.icon(
                                      onPressed: _isBusy || queuedRemaining.isEmpty
                                          ? null
                                          : () async {
                                              await showDialog<bool>(
                                                context: context,
                                                barrierDismissible: false,
                                                builder: (context) {
                                                  return _GenerateAllReportsDialog(
                                                    artifacts: queuedRemaining,
                                                    onRun: (onStarted, onFinished, onFailed) {
                                                      return _runGenerateAllReportsLive(
                                                        queuedRemaining,
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
                                      label: Text('Generate Remaining (${queuedRemaining.length})'),
                                    );
                                  },
                                ),

                                OutlinedButton.icon(
                                  onPressed: _isBusy ? null : _sendAllExhibitorReports,
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
                                  onPressed:
                                      _isBusy ? null : _sendAllClubReports,
                                  icon: const Icon(Icons.group_outlined),
                                  label: Text(
                                    _selectedCloseoutScopeIsEntireShow
                                        ? 'Send All Club Reports'
                                        : 'Send $_selectedCloseoutScopeLabel Club Reports',
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            _ReportActionsCard(
                              showId: widget.showId,
                              reports: _dashboard?.reports ??
                                  const <ReportArtifactSummary>[],
                              groupedReportNames: {
                                'arba': _reportNamesForGroup('arba'),
                                'exhibitor': _reportNamesForGroup('exhibitor'),
                                'club': _reportNamesForGroup('club'),
                                'other': _reportNamesForGroup('other'),
                              },
                              onGenerate: (
                                reportName, {
                                String? breedName,
                                String? scope,
                                String? showLetter,
                                String? exhibitorId,
                                String? exhibitorName,
                              }) {
                                final isSingleTarget =
                                    breedName != null ||
                                    scope != null ||
                                    showLetter != null ||
                                    exhibitorId != null ||
                                    exhibitorName != null;

                                if (!isSingleTarget && reportName == 'arba_report') {
                                  return _generateCurrentReportGroupByName(reportName);
                                }

                                return _generateReportByName(
                                  reportName,
                                  breedName: breedName,
                                  scope: scope,
                                  showLetter: showLetter,
                                  exhibitorId: exhibitorId,
                                  exhibitorName: exhibitorName,
                                );
                              },
                              onDownload: (
                                reportName, {
                                String? exhibitorId,
                                String? breedName,
                                String? scope,
                                String? showLetter,
                              }) =>
                                  _downloadReportByName(
                                reportName,
                                exhibitorId: exhibitorId,
                                breedName: breedName,
                                scope: scope,
                                showLetter: showLetter,
                              ),
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
    String? exhibitorId,
    String? exhibitorName,
  }) onGenerate;
  final Future<void> Function(
    String reportName, {
    String? exhibitorId,
    String? breedName,
    String? scope,
    String? showLetter,
  }) onDownload;
  final Future<void> Function(
    String reportName, {
    String? exhibitorId,
    String? exhibitorEmail,
    String? breedName,
    String? scope,
    String? showLetter,
  }) onEmail;
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
  }

  List<String> _availableBreeds = [];
  bool _loadingBreeds = false;

  List<String> get _currentReports =>
      widget.groupedReportNames[_selectedGroup] ?? const [];

  ReportArtifactSummary? get _selectedArtifact {
    final reportName = _selectedReportName;
    if (reportName == null) return null;

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
        final breed = (r.metadata['breed_name'] ?? '').toString().trim().toLowerCase();
        final scope = (r.metadata['scope'] ?? '').toString().trim().toUpperCase();
        final letter = (r.metadata['show_letter'] ?? '').toString().trim().toUpperCase();

        return breed == _breedController.text.trim().toLowerCase() &&
            scope == _selectedScope.trim().toUpperCase() &&
            letter == _selectedShowLetter.trim().toUpperCase();
      });
    }

    final list = matches.toList()
      ..sort((a, b) {
        final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDt.compareTo(aDt);
      });

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
        _selectedReportName == 'breed_results_detail_report';
  }
  
  bool get _selectedReportBlocked =>
    widget.reportsBlocked && !_selectedReportIgnoresResultsReadiness;

  bool get _selectedReportNeedsBreedScope =>
    _selectedReportName == 'sweepstakes_report' ||
    _selectedReportName == 'breed_results_detail_report';

  bool get _selectedReportNeedsExhibitor =>
    _selectedReportName == 'exhibitor_report' ||
    _selectedReportName == 'legs';

  bool get _canDownload {
    final artifact = _selectedArtifact;
    return artifact != null &&
        artifact.artifactStatus == 'generated' &&
        (artifact.storageBucket?.isNotEmpty == true) &&
        (artifact.storagePath?.isNotEmpty == true);
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
        ..sort((a, b) =>
            a.exhibitorName.toLowerCase().compareTo(b.exhibitorName.toLowerCase()));

      if (!mounted) return;

      setState(() {
        _availableExhibitors = list;

        if (list.isNotEmpty) {
          final stillExists = list.any((e) => e.exhibitorId == _selectedExhibitorId);
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed loading exhibitors: $e')),
      );
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
          items: _currentReports
              .map(
                (reportName) {
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
                },
              )
              .toList(),
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

        if (_selectedReportNeedsExhibitor) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _availableExhibitors.any((e) => e.exhibitorId == _selectedExhibitorId)
                ? _selectedExhibitorId
                : (_availableExhibitors.isNotEmpty ? _availableExhibitors.first.exhibitorId : null),
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
                _ReportInfoTile(
                  reportName: _selectedReportName == null
                      ? '-'
                      : _friendlyReportName(_selectedReportName),
                  status: artifact?.artifactStatus ?? 'not_generated',
                  generatedAt: artifact?.generatedAt,
                ),

                if (_selectedReportBlocked) ...[
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              onPressed: widget.loading ||
                      _selectedReportBlocked ||
                      _selectedReportName == null ||
                      (_selectedReportNeedsExhibitor && _selectedExhibitorId == null) ||
                      (_selectedReportNeedsBreedScope &&
                          _breedController.text.trim().isEmpty)
                  ? null
                  : () => widget.onGenerate(
                        _selectedReportName!,
                        breedName: _selectedReportNeedsBreedScope
                            ? _breedController.text.trim()
                            : null,
                        scope: _selectedReportNeedsBreedScope ? _selectedScope : null,
                        showLetter:
                            _selectedReportNeedsBreedScope ? _selectedShowLetter : null,
                        exhibitorId:
                            _selectedReportNeedsExhibitor ? _selectedExhibitorId : null,
                        exhibitorName:
                            _selectedReportNeedsExhibitor ? _selectedExhibitorName : null,
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
                  ? () => widget.onDownload(
                        _selectedReportName!,
                        exhibitorId:
                            _selectedReportNeedsExhibitor ? _selectedExhibitorId : null,
                        breedName:
                            _selectedReportNeedsBreedScope ? _breedController.text.trim() : null,
                        scope: _selectedReportNeedsBreedScope ? _selectedScope : null,
                        showLetter:
                            _selectedReportNeedsBreedScope ? _selectedShowLetter : null,
                      )
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
            OutlinedButton.icon(
              onPressed: _selectedReportCanEmail &&
                      _canDownload &&
                      _selectedReportName != null
                  ? () => widget.onEmail(
                            _selectedReportName!,
                            exhibitorId: _selectedReportNeedsExhibitor
                                ? _selectedExhibitorId
                                : null,
                            exhibitorEmail: _selectedReportNeedsExhibitor
                                ? _selectedExhibitorEmail
                                : null,
                            breedName: _selectedReportNeedsBreedScope
                                ? _breedController.text.trim()
                                : null,
                            scope: _selectedReportNeedsBreedScope
                                ? _selectedScope
                                : null,
                            showLetter: _selectedReportNeedsBreedScope
                                ? _selectedShowLetter
                                : null,
                          )
                  : null,
              icon: const Icon(Icons.email_outlined),
              label: Text(
                _selectedReportName == 'arba_report' ? 'Email to ARBA' : 'Email',
              ),
            ),
          ],
        ),
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
    return '${artifact.reportName}::${artifact.id}';
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
        title: const Text('Generating Reports'),
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
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _finished ? 1 : _progress),
              const SizedBox(height: 12),
              Text(
                '${_completed.length + _failed.length} of ${widget.artifacts.length} reports processed',
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
                          subtitle: Text(
                            (artifact.metadata['exhibitor_name'] ?? artifact.metadata['breed_name'] ?? '')
                                    .toString()
                                    .trim()
                                    .isEmpty
                                ? _friendlyReportName(artifact.reportName)
                                : (artifact.metadata['exhibitor_name'] ?? artifact.metadata['breed_name'])
                                    .toString()
                                    .trim(),
                          ),
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
  final String sanctioningBody; // NATIONAL CLUB / STATE BREED CLUB / STATE CLUB

  const _ClubEmailTarget({
    required this.clubName,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.email,
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
      subtitle: 'Choose what part of the show you want to finalize, generate, or send.',
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
                color: const Color(0xFF11285A).withOpacity(.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF11285A).withOpacity(.12),
                ),
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
        .map((s) => s.displayName.isEmpty ? '${s.kind} ${s.letter}' : s.displayName)
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
          ? List<String>.from((json['species'] as List).map((e) => e.toString()))
          : const [],
      entryCount: ((json['entry_count'] ?? 0) as num).toInt(),
    );
  }
}