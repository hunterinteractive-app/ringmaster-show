// lib/screens/admin/closeout/data/loaders/legs_report_loader.dart

import '../../models/base/report_request.dart';
import '../../models/legs/legs_certificate_data.dart';
import '../closeout_repository.dart';

class LegsReportLoader {
  LegsReportLoader(this.repo);

  final CloseoutRepository repo;

  static const Map<int, String> legRuleDescriptions = {
    1: 'Wins First in a class providing there are 5 or more animals exhibited by 3 or more exhibitors.',
    2: 'Wins Best of Breed providing there are 5 or more animals exhibited in the breed by 3 or more exhibitors.',
    3: 'Wins Best Opposite Sex of Breed providing there are 5 or more of the same sex as the winner exhibited in the breed by 3 or more exhibitors.',
    4: 'Wins Best of Group providing there are 5 or more animals exhibited in the group by 3 or more exhibitors.',
    5: 'Wins Best Opposite Sex of Group providing there are 5 or more of the same sex as the winner exhibited in the group by 3 or more exhibitors.',
    6: 'Wins Best of Variety providing there are 5 or more animals exhibited in the variety by 3 or more exhibitors.',
    7: 'Wins Best Opposite Sex Variety providing there are 5 or more of the same sex as the winner exhibited in the variety by 3 or more exhibitors.',
    8: 'Wins Best in Show providing there are 5 or more animals exhibited in the show by 3 or more exhibitors.',
    9: 'Wins Best 6 Class / Best 4 Class providing there are 5 or more animals competing exhibited by 3 or more exhibitors.',
    10: 'Wins Reserve in Show providing there are 5 or more animals exhibited by 3 or more exhibitors.',
  };

    Future<List<LegsCertificateData>> load(ReportRequest request) async {
      final showId = request.showId;
      final requestedExhibitorId = _str(request.exhibitorId);
      final requestedExhibitorName = _str(request.exhibitorName);

      final show = await repo.loadShowBasics(showId);
      final arbaDetails = await _loadArbaDetails(showId);

      final showName = _str(show['name']);
      final clubName = _firstNonEmpty([
        _str(show['club_name']),
        await _loadClubName(showId),
      ]);
      final sanctionNumbersBySection = await _loadSanctionNumbersBySection(showId);
      final showDate = _tryParseDate(show['start_date']);

      final location = [
        _str(show['location_name']),
        _str(show['location_address']),
      ].where((e) => e.isNotEmpty).join(', ');

      final secretaryName = _firstNonEmpty([
        _str(arbaDetails?['secretary_name']),
        _str(show['secretary_name']),
      ]);

      final secretaryEmail = _firstNonEmpty([
        _str(arbaDetails?['secretary_email']),
        _str(show['secretary_email']),
      ]);

      final entryContext = await _loadShownEntryContext(showId);
      if (entryContext.isEmpty) return const [];

      final contextEntryIds = entryContext.keys
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();

      final awards = <Map<String, dynamic>>[];
      for (var i = 0; i < contextEntryIds.length; i += 100) {
        final chunk = contextEntryIds.skip(i).take(100).toList();
        final awardChunkRows = await repo.supabase
            .from('entry_awards')
            .select('''
              id,
              show_id,
              entry_id,
              award_code,
              entries!entry_awards_entry_id_fkey (
                id,
                show_id,
                exhibitor_id,
                tattoo,
                breed,
                class_name,
                sex,
                species,
                is_shown
              )
            ''')
            .inFilter('entry_id', chunk);

        awards.addAll(List<Map<String, dynamic>>.from(awardChunkRows as List));
      }

      final judgeRefs = entryContext.values
          .map((e) => e.showJudgeRowId)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final judgeNamesByRef = await _loadJudgeNamesByShowJudgeId(judgeRefs);

      final candidates = <_LegCandidate>[];
      

      // Add synthetic FIRST-place leg checks because 1st place is stored on entries.placement,
      // not usually in entry_awards.
      for (final ctxEntry in entryContext.entries) {
        final entryId = ctxEntry.key;
        final ctx = ctxEntry.value;

        if (requestedExhibitorId.isNotEmpty &&
            ctx.exhibitorId != requestedExhibitorId) {
          continue;
        }

        if (ctx.isDisqualified || ctx.placement != 1) continue;

        final ruleMatch = _determineLegRule(
          awardCode: 'FIRST',
          ctx: ctx,
        );

        if (ruleMatch == null) continue;

        // This candidate will be deduped against higher awards like BOB/BOV/BIS later.
        candidates.add(
          _LegCandidate(
            priority: ruleMatch.priority,
            dedupeKey: _legDedupeKey(ctx, entryId),
            data: LegsCertificateData(
              certificateId:
                  'leg_${showId}_${ctx.sectionLetter}_${entryId}_r${ruleMatch.rule}_first',
              showId: showId,
              exhibitorId: ctx.exhibitorId,
              exhibitorNumber: _safeShowExhibitorNumber(ctx),
              exhibitorName: _safeExhibitorName(ctx),
              ownerAddress: _formatOwnerAddress(ctx),
              entryId: entryId,
              earNumber: ctx.tattoo,
              breed: ctx.breed,
              variety: ctx.varietyDisplay,
              className: ctx.className,
              sex: ctx.sex,
              showName: showName,
              clubName: clubName.isNotEmpty ? clubName : showName,
              sanctionNumber: _sanctionNumberForContext(ctx, sanctionNumbersBySection),
              showDate: showDate,
              location: location,
              secretaryName: secretaryName,
              secretaryEmail: secretaryEmail,
              judgeName: judgeNamesByRef[ctx.showJudgeRowId] ?? 'Judge Not Available',
              winCode: 'FIRST',
              legRule: ruleMatch.rule,
              legRuleDescription: legRuleDescriptions[ruleMatch.rule] ?? '',
              animalsCount: ruleMatch.animalsCount,
              exhibitorsCount: ruleMatch.exhibitorsCount,
              barcodeValue:
                  'RMLEG|show=$showId|section=${ctx.sectionLetter}|entry=$entryId|rule=${ruleMatch.rule}|ear=${ctx.tattoo}',
              qrValue:
                  'https://ringmasterone.com/verify/leg/leg_${showId}_${ctx.sectionLetter}_${entryId}_r${ruleMatch.rule}_first',
            ),
          ),
        );
      }

      for (final row in awards) {
        final rawAwardCode = _str(row['award_code']);
        final awardCode = _normalizeAwardCode(rawAwardCode);

        final entryRaw = row['entries'];
        if (entryRaw is! Map) continue;

        final entry = Map<String, dynamic>.from(entryRaw);

        final species = _str(entry['species']).toLowerCase();
        if (species != 'rabbit' && species != 'cavy') continue;
        // Treat null as shown. Older rows may not have is_shown explicitly set,
        // and report_results_entry_rows treats null as shown as well.
        if (entry['is_shown'] == false) continue;

        final entryId = _str(entry['id']);
        final exhibitorId = _str(entry['exhibitor_id']);
        if (entryId.isEmpty || exhibitorId.isEmpty) continue;

        if (requestedExhibitorId.isNotEmpty && exhibitorId != requestedExhibitorId) {
          continue;
        }

        final ctx = entryContext[entryId];
        if (ctx == null || ctx.isDisqualified) continue;

        final ruleMatch = _determineLegRule(
          awardCode: awardCode,
          ctx: ctx,
        );
        if (ruleMatch == null) continue;

        final judgeName = _firstNonEmpty([
          judgeNamesByRef[ctx.showJudgeRowId] ?? '',
          'Judge Not Available',
        ]);

        final exhibitorName = _safeExhibitorName(ctx);

        final ownerAddress = _formatOwnerAddress(ctx);

        final earNumber = _firstNonEmpty([
          _str(entry['tattoo']),
          ctx.tattoo,
        ]);

        final exhibitorNumber = _safeShowExhibitorNumber(ctx);

        final showLetter = ctx.sectionLetter.toUpperCase();

        final certificateId =
            'leg_${showId}_${showLetter}_${entryId}_r${ruleMatch.rule}_${awardCode.toLowerCase()}';

        final barcodeValue =
            'RMLEG|show=$showId|section=$showLetter|entry=$entryId|rule=${ruleMatch.rule}|ear=$earNumber';

        final qrValue = 'https://ringmasterone.com/verify/leg/$certificateId';

        candidates.add(
          _LegCandidate(
            priority: ruleMatch.priority,
            dedupeKey: _legDedupeKey(ctx, entryId),
            data: LegsCertificateData(
              certificateId: certificateId,
              showId: showId,
              exhibitorId: exhibitorId,
              exhibitorNumber: exhibitorNumber,
              exhibitorName: exhibitorName,
              ownerAddress: ownerAddress,
              entryId: entryId,
              earNumber: earNumber,
              breed: _str(entry['breed']),
              variety: ctx.varietyDisplay,
              className: _str(entry['class_name']),
              sex: _str(entry['sex']),
              showName: showName,
              clubName: clubName.isNotEmpty ? clubName : showName,
              sanctionNumber: _sanctionNumberForContext(ctx, sanctionNumbersBySection),
              showDate: showDate,
              location: location,
              secretaryName: secretaryName,
              secretaryEmail: secretaryEmail,
              judgeName: judgeName,
              winCode: awardCode,
              legRule: ruleMatch.rule,
              legRuleDescription: legRuleDescriptions[ruleMatch.rule] ?? '',
              animalsCount: ruleMatch.animalsCount,
              exhibitorsCount: ruleMatch.exhibitorsCount,
              barcodeValue: barcodeValue,
              qrValue: qrValue,
            ),
          ),
        );
      }

      // Keep only the best qualifying leg per exhibitor/animal/section.
      // This prevents one animal from receiving separate certificates for BOB and RIS/BIS in the same show.
      final bestByEntryAndShow = <String, _LegCandidate>{};
      for (final candidate in candidates) {
        final key = candidate.dedupeKey;
        final existing = bestByEntryAndShow[key];
        if (existing == null || candidate.priority < existing.priority) {
          bestByEntryAndShow[key] = candidate;
        }
      }

      var output = <LegsCertificateData>[
        ...bestByEntryAndShow.values.map((e) => e.data),
      ];

      if (requestedExhibitorId.isEmpty && requestedExhibitorName.isNotEmpty) {
        final targetName = requestedExhibitorName.toLowerCase();
        output = output.where((row) {
          return row.exhibitorName.toLowerCase() == targetName;
        }).toList();
      }

      output.sort((a, b) {
        final nameCompare = a.exhibitorName.compareTo(b.exhibitorName);
        if (nameCompare != 0) return nameCompare;

        final aShow = _sectionFromCertificateId(a.certificateId);
        final bShow = _sectionFromCertificateId(b.certificateId);
        final showCompare = aShow.compareTo(bShow);
        if (showCompare != 0) return showCompare;

        return a.earNumber.compareTo(b.earNumber);
      });

      return output;
    }

  Future<Map<String, dynamic>?> _loadArbaDetails(String showId) async {
    try {
      final row = await repo.supabase
          .from('show_arba_report_details')
          .select('secretary_name, secretary_email')
          .eq('show_id', showId)
          .maybeSingle();

      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _loadSanctionNumbersBySection(String showId) async {
    try {
      final rows = await repo.supabase
          .from('show_sanctions')
          .select('section_id, sanction_number')
          .eq('show_id', showId)
          .eq('sanctioning_body', 'ARBA');

      final bySection = <String, String>{};

      for (final raw in List<Map<String, dynamic>>.from(rows as List)) {
        final sectionId = _str(raw['section_id']);
        final sanctionNumber = _str(raw['sanction_number']);

        if (sectionId.isNotEmpty && sanctionNumber.isNotEmpty) {
          bySection[sectionId] = sanctionNumber;
        }
      }

      return bySection;
    } catch (_) {
      return {};
    }
  }

  String _sanctionNumberForContext(
    _EntryLegContext ctx,
    Map<String, String> sanctionNumbersBySection,
  ) {
    return sanctionNumbersBySection[ctx.sectionId] ?? '';
  }

  Future<String> _loadClubName(String showId) async {
    try {
      final showRow = await repo.supabase
          .from('shows')
          .select('club_name')
          .eq('id', showId)
          .maybeSingle();

      if (showRow != null) {
        final showMap = Map<String, dynamic>.from(showRow as Map);
        final clubName = _str(showMap['club_name']);
        if (clubName.isNotEmpty) return clubName;
      }
    } catch (_) {
      // Fall through to the sanction table fallback below.
    }

    try {
      final row = await repo.supabase
          .from('show_sanctions')
          .select('club_name')
          .eq('show_id', showId)
          .neq('club_name', 'ARBA')
          .limit(1)
          .maybeSingle();

      if (row == null) return '';
      return _str(row['club_name']);
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, String>> _loadJudgeNamesByShowJudgeId(
    List<String> rawJudgeRefs,
  ) async {
    if (rawJudgeRefs.isEmpty) return {};

    try {
      final refs = rawJudgeRefs
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (refs.isEmpty) return {};

      final resolvedByRef = <String, String>{};

      // First pass:
      // report_entry_base_v.judged_by_show_judge_id may already equal judges.id
      final directJudgeRows = await repo.supabase
          .from('judges')
          .select('id, name, first_name, last_name')
          .inFilter('id', refs);

      for (final row in List<Map<String, dynamic>>.from(directJudgeRows)) {
        final judgeId = _str(row['id']);
        final judgeName = _firstNonEmpty([
          _str(row['name']),
          [
            _str(row['first_name']),
            _str(row['last_name']),
          ].where((e) => e.isNotEmpty).join(' '),
        ]);

        if (judgeId.isNotEmpty && judgeName.isNotEmpty) {
          resolvedByRef[judgeId] = judgeName;
        }
      }

      // Second pass:
      // if the ref is actually show_judges.id, resolve to show_judges.judge_id -> judges.id
      final unresolvedRefs = refs
          .where((ref) => !resolvedByRef.containsKey(ref))
          .toList();

      if (unresolvedRefs.isNotEmpty) {
        final showJudgeRows = await repo.supabase
            .from('show_judges')
            .select('id, judge_id')
            .inFilter('id', unresolvedRefs);

        final showJudgeList = List<Map<String, dynamic>>.from(showJudgeRows);

        final fallbackJudgeIds = showJudgeList
            .map((e) => _str(e['judge_id']))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        if (fallbackJudgeIds.isNotEmpty) {
          final fallbackJudgeRows = await repo.supabase
              .from('judges')
              .select('id, name, first_name, last_name')
              .inFilter('id', fallbackJudgeIds);

          final fallbackJudgeNameById = <String, String>{};
          for (final row in List<Map<String, dynamic>>.from(fallbackJudgeRows)) {
            final judgeId = _str(row['id']);
            final judgeName = _firstNonEmpty([
              _str(row['name']),
              [
                _str(row['first_name']),
                _str(row['last_name']),
              ].where((e) => e.isNotEmpty).join(' '),
            ]);

            if (judgeId.isNotEmpty && judgeName.isNotEmpty) {
              fallbackJudgeNameById[judgeId] = judgeName;
            }
          }

          for (final row in showJudgeList) {
            final showJudgeId = _str(row['id']);
            final judgeId = _str(row['judge_id']);
            final judgeName = fallbackJudgeNameById[judgeId] ?? '';

            if (showJudgeId.isNotEmpty && judgeName.isNotEmpty) {
              resolvedByRef[showJudgeId] = judgeName;
            }
          }
        }
      }

      return resolvedByRef;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, _EntryLegContext>> _loadShownEntryContext(
    String showId,
  ) async {
    final sectionRows = await repo.supabase
        .from('show_sections')
        .select('id, letter, kind, sort_order')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('sort_order');

    final allRows = <Map<String, dynamic>>[];

    for (final rawSection in List<Map<String, dynamic>>.from(sectionRows)) {
      final sectionId = _str(rawSection['id']);
      final showLetter = _str(rawSection['letter']).toUpperCase();

      final rows = await repo.supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': showId,
          'p_section_id': sectionId,
          'p_show_letter': showLetter.isEmpty ? null : showLetter,
        },
      );

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);


        final scratchedAt = _str(row['scratched_at']);
        final isShown = row['is_shown'] != false;

        // Animals that were exhibited and judged still count toward leg
        // population totals even when disqualified. No-shows and scratched
        // entries do not count.
        if (!isShown || scratchedAt.isNotEmpty) {
          continue;
        }

        row['resolved_section_id'] = sectionId;
        row['resolved_section_letter'] = showLetter;
        allRows.add(row);
      }

    }

    // A regular entry may also be represented by a separate fur/wool result
    // row. Count the animal only once for ARBA leg eligibility, preferring the
    // regular row when both exist. Older/manual entries may have is_fur or
    // is_wool set on the only row, so those rows must not be discarded.
    final dedupedRowsByAnimalAndSection = <String, Map<String, dynamic>>{};

    for (final row in allRows) {
      final sectionId = _str(row['resolved_section_id']);
      final animalId = _str(row['animal_id']);
      final exhibitorId = _str(row['exhibitor_id']);
      final tattoo = _str(row['tattoo']).toLowerCase();
      final breed = _str(row['breed_name']).toLowerCase();

      final animalKey = animalId.isNotEmpty
          ? animalId
          : [exhibitorId, breed, tattoo].join('|');
      final dedupeKey = '$sectionId|$animalKey';

      final existing = dedupedRowsByAnimalAndSection[dedupeKey];
      if (existing == null) {
        dedupedRowsByAnimalAndSection[dedupeKey] = row;
        continue;
      }

      final existingIsFurOrWool =
          existing['is_fur'] == true || existing['is_wool'] == true;
      final currentIsFurOrWool =
          row['is_fur'] == true || row['is_wool'] == true;

      if (existingIsFurOrWool && !currentIsFurOrWool) {
        dedupedRowsByAnimalAndSection[dedupeKey] = row;
      }
    }

    allRows
      ..clear()
      ..addAll(dedupedRowsByAnimalAndSection.values);

    final exhibitorIds = allRows
        .map((e) => _str(e['exhibitor_id']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final exhibitorProfiles = await _loadExhibitorProfiles(exhibitorIds);

    final byEntryId = <String, _EntryLegContext>{};

    for (final row in allRows) {
      final entryId = _str(row['entry_id']);
      if (entryId.isEmpty) continue;

      final exhibitorId = _str(row['exhibitor_id']);
      final exhibitorProfile = exhibitorProfiles[exhibitorId];

      final sectionLetter = _str(row['resolved_section_letter']).toUpperCase();
      final breed = _str(row['breed_name']);
      final varietyDisplay = _str(row['variety_name']);
      final usesGroupAwards = row['uses_group_awards'] == true;
      // Some result rows do not return uses_group_awards or group_name even
      // though a BOG/BOSG award was entered. Use the displayed variety as the
      // group key fallback so those legitimate group awards can still be
      // evaluated. This does not create a leg by itself; only an actual BOG or
      // BOSG award code is checked against these counts.
      final groupName = _firstNonEmpty([
        _str(row['group_name']),
        varietyDisplay,
      ]);
      final className = _str(row['class_name']);
      final sex = _str(row['sex']);
      final showJudgeRowId = _str(row['judged_by_show_judge_id']);

      final sectionId = _str(row['resolved_section_id']);

      final sameShowRows = allRows.where((e) {
        return _str(e['resolved_section_id']) == sectionId;
      }).toList();

      final showCountRows = sameShowRows.where(_countsForShow).toList();
      final showAnimals = showCountRows.length;
      final showExhibitors = showCountRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final breedRows = sameShowRows.where((e) {
        return _countsForBreed(e) &&
            _str(e['breed_name']).trim().toLowerCase() ==
                breed.trim().toLowerCase();
      }).toList();
      final breedAnimals = breedRows.length;
      final breedExhibitors = breedRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final normalizedSexForCounts = _normalizeSex(sex);
      final breedSameSexRows = breedRows.where((e) {
        return _normalizeSex(_str(e['sex'])) == normalizedSexForCounts;
      }).toList();
      final breedSameSexAnimals = breedSameSexRows.length;
      final breedSameSexExhibitors = breedSameSexRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final normalizedVariety = varietyDisplay.trim().toLowerCase();
      final varietyRows = sameShowRows.where((e) {
        return _countsForVariety(e) &&
            _str(e['breed_name']).trim().toLowerCase() ==
                breed.trim().toLowerCase() &&
            _str(e['variety_name']).trim().toLowerCase() == normalizedVariety;
      }).toList();

      final varietyAnimals = varietyRows.length;
      final varietyExhibitors = varietyRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final varietySameSexRows = varietyRows.where((e) {
        return _normalizeSex(_str(e['sex'])) == normalizedSexForCounts;
      }).toList();
      final varietySameSexAnimals = varietySameSexRows.length;
      final varietySameSexExhibitors = varietySameSexRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final normalizedBreed = breed.trim().toLowerCase();
      final normalizedGroupName = groupName.trim().toLowerCase();

      // Group awards are scoped to the breed and group within this show
      // section. Do not require uses_group_awards to be true on every row,
      // because older/imported result rows may contain a valid group_name
      // while that flag is null or false.
      final groupRows = normalizedGroupName.isNotEmpty
          ? sameShowRows.where((e) {
              final rowGroupName = _firstNonEmpty([
                _str(e['group_name']),
                _str(e['variety_name']),
              ]).trim().toLowerCase();

              return _countsForGroup(e) &&
                  _str(e['breed_name']).trim().toLowerCase() ==
                      normalizedBreed &&
                  rowGroupName == normalizedGroupName;
            }).toList()
          : <Map<String, dynamic>>[];

      final groupAnimals = groupRows.length;
      final groupExhibitors = groupRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final normalizedSex = _normalizeSex(sex);
      final groupSameSexRows = groupRows.where((e) {
        return _normalizeSex(_str(e['sex'])) == normalizedSex;
      }).toList();
      final groupSameSexAnimals = groupSameSexRows.length;
      final groupSameSexExhibitors = groupSameSexRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;


      final normalizedClassName = className.trim().toLowerCase();
      final classRows = sameShowRows.where((e) {
        return _countsForClass(e) &&
            _str(e['breed_name']).trim().toLowerCase() ==
                breed.trim().toLowerCase() &&
            _str(e['variety_name']).trim().toLowerCase() == normalizedVariety &&
            _str(e['class_name']).trim().toLowerCase() == normalizedClassName &&
            _normalizeSex(_str(e['sex'])) == normalizedSexForCounts;
      }).toList();

      final classAnimals = classRows.length;
      final classExhibitors = classRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      byEntryId[entryId] = _EntryLegContext(
        sectionId: sectionId,
        sectionLetter: sectionLetter,
        varietyDisplay: varietyDisplay,
        groupName: groupName,
        usesGroupAwards: usesGroupAwards,
        showJudgeRowId: showJudgeRowId,
        tattoo: _str(row['tattoo']),
        exhibitorId: exhibitorId,
        animalId: _str(row['animal_id']),
        breed: breed,
        className: className,
        sex: sex,
        placement: int.tryParse(_str(row['placement'])) ?? 0,
        isDisqualified: row['is_disqualified'] == true,
        exhibitorLabel: _firstNonEmpty([
          exhibitorProfile?.displayName ?? '',
          exhibitorProfile?.showingName ?? '',
          _str(row['exhibitor_label']),
        ]),
        exhibitorNumber: _firstNonEmpty([
          exhibitorProfile?.exhibitorNumber ?? '',
          _str(row['exhibitor_number']),
        ]),
        exhibitorShowingName: _firstNonEmpty([
          exhibitorProfile?.showingName ?? '',
          _str(row['exhibitor_showing_name']),
        ]),
        exhibitorFirstName: _firstNonEmpty([
          exhibitorProfile?.firstName ?? '',
          _str(row['exhibitor_first_name']),
        ]),
        exhibitorLastName: _firstNonEmpty([
          exhibitorProfile?.lastName ?? '',
          _str(row['exhibitor_last_name']),
        ]),
        exhibitorAddressLine1: _firstNonEmpty([
          exhibitorProfile?.addressLine1 ?? '',
          _str(row['exhibitor_address_line1']),
        ]),
        exhibitorAddressLine2: _firstNonEmpty([
          exhibitorProfile?.addressLine2 ?? '',
          _str(row['exhibitor_address_line2']),
        ]),
        exhibitorCity: _firstNonEmpty([
          exhibitorProfile?.city ?? '',
          _str(row['exhibitor_city']),
        ]),
        exhibitorState: _firstNonEmpty([
          exhibitorProfile?.state ?? '',
          _str(row['exhibitor_state']),
        ]),
        exhibitorZip: _firstNonEmpty([
          exhibitorProfile?.zip ?? '',
          _str(row['exhibitor_zip']),
        ]),
        breedAnimals: breedAnimals,
        breedExhibitors: breedExhibitors,
        breedSameSexAnimals: breedSameSexAnimals,
        breedSameSexExhibitors: breedSameSexExhibitors,
        varietyAnimals: varietyAnimals,
        varietyExhibitors: varietyExhibitors,
        varietySameSexAnimals: varietySameSexAnimals,
        varietySameSexExhibitors: varietySameSexExhibitors,
        groupAnimals: groupAnimals,
        groupExhibitors: groupExhibitors,
        groupSameSexAnimals: groupSameSexAnimals,
        groupSameSexExhibitors: groupSameSexExhibitors,
        classAnimals: classAnimals,
        classExhibitors: classExhibitors,
        showAnimals: showAnimals,
        showExhibitors: showExhibitors,
      );
    }

    return byEntryId;
  }
  String _normalizedDisqualificationType(Map<String, dynamic> row) {
    final combined = [
      _str(row['disqualified_reason']),
      _str(row['result_status']),
    ].join(' ').trim().toLowerCase();

    if (combined.contains('wrong sex')) return 'wrong_sex';
    if (combined.contains('wrong variety')) return 'wrong_variety';
    if (combined.contains('wrong class')) return 'wrong_class';
    if (combined.contains('no show')) return 'no_show';
    if (combined.contains('unworthy')) return 'unworthy';
    if (combined.contains('other')) return 'other';
    return row['is_disqualified'] == true ? 'other' : '';
  }

  bool _countsForShow(Map<String, dynamic> row) {
    final type = _normalizedDisqualificationType(row);
    return type != 'no_show';
  }

  bool _countsForBreed(Map<String, dynamic> row) {
    final type = _normalizedDisqualificationType(row);
    return type != 'no_show' && type != 'wrong_variety';
  }

  bool _countsForGroup(Map<String, dynamic> row) {
    final type = _normalizedDisqualificationType(row);
    return type != 'no_show' &&
        type != 'wrong_variety' &&
        type != 'wrong_sex';
  }

  bool _countsForVariety(Map<String, dynamic> row) {
    final type = _normalizedDisqualificationType(row);
    return type != 'no_show' &&
        type != 'wrong_variety' &&
        type != 'wrong_sex';
  }

  bool _countsForClass(Map<String, dynamic> row) {
    final type = _normalizedDisqualificationType(row);
    return type != 'no_show' &&
        type != 'wrong_variety' &&
        type != 'wrong_class' &&
        type != 'wrong_sex';
  }

  String _normalizeSex(String value) {
    final compact = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]+'), '');

    // Some RPC rows return combined values such as "Junior Doe",
    // "Senior Buck", or other labels containing the sex. Detect the
    // canonical sex anywhere in the normalized value instead of requiring
    // an exact match.
    if (compact == 'D' ||
        compact == 'F' ||
        compact.contains('DOE') ||
        compact.contains('FEMALE')) {
      return 'doe';
    }

    if (compact == 'B' ||
        compact == 'M' ||
        compact.contains('BUCK') ||
        compact.contains('MALE')) {
      return 'buck';
    }

    return compact.toLowerCase();
  }

  Future<Map<String, _ExhibitorProfile>> _loadExhibitorProfiles(
    List<String> exhibitorIds,
  ) async {
    if (exhibitorIds.isEmpty) return {};

    final profiles = <String, _ExhibitorProfile>{};

    for (var i = 0; i < exhibitorIds.length; i += 100) {
      final chunk = exhibitorIds.skip(i).take(100).toList();

      try {
        final rows = await repo.supabase
            .from('exhibitors')
            .select('''
              id,
              exhibitor_number,
              display_name,
              showing_name,
              first_name,
              last_name,
              address_line1,
              address_line2,
              city,
              state,
              zip
            ''')
            .inFilter('id', chunk);

        for (final raw in List<Map<String, dynamic>>.from(rows as List)) {
          final id = _str(raw['id']);
          if (id.isEmpty) continue;

          profiles[id] = _ExhibitorProfile(
            exhibitorNumber: _str(raw['exhibitor_number']),
            displayName: _str(raw['display_name']),
            showingName: _str(raw['showing_name']),
            firstName: _str(raw['first_name']),
            lastName: _str(raw['last_name']),
            addressLine1: _str(raw['address_line1']),
            addressLine2: _str(raw['address_line2']),
            city: _str(raw['city']),
            state: _str(raw['state']),
            zip: _str(raw['zip']),
          );
        }
      } catch (e) {
        // If exhibitor_number has not been added yet, retry without it so the
        // address still hydrates for ARBA verification.
        final rows = await repo.supabase
            .from('exhibitors')
            .select('''
              id,
              display_name,
              showing_name,
              first_name,
              last_name,
              address_line1,
              address_line2,
              city,
              state,
              zip
            ''')
            .inFilter('id', chunk);

        for (final raw in List<Map<String, dynamic>>.from(rows as List)) {
          final id = _str(raw['id']);
          if (id.isEmpty) continue;

          profiles[id] = _ExhibitorProfile(
            exhibitorNumber: '',
            displayName: _str(raw['display_name']),
            showingName: _str(raw['showing_name']),
            firstName: _str(raw['first_name']),
            lastName: _str(raw['last_name']),
            addressLine1: _str(raw['address_line1']),
            addressLine2: _str(raw['address_line2']),
            city: _str(raw['city']),
            state: _str(raw['state']),
            zip: _str(raw['zip']),
          );
        }
      }
    }

    return profiles;
  }

  bool _isBestInShowAward(String normalized) {
    final compact = normalized
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '')
        .toUpperCase();

    return compact == 'BIS' ||
        compact == 'BESTINSHOW' ||
        compact == 'BESTOFSHOW' ||
        compact == 'BESTINSHOWRABBIT' ||
        compact == 'BESTINSHOWCAVY' ||
        compact.startsWith('BIS') ||
        compact.endsWith('BIS') ||
        (compact.contains('BEST') && compact.contains('SHOW'));
  }

  bool _isReserveInShowAward(String normalized) {
    final compact = normalized
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '')
        .toUpperCase();

    // This club format awards BIS / 1st RIS / 2nd RIS. The 1st RIS is treated
    // as the normal ARBA Reserve in Show award for leg purposes, while 2nd RIS
    // is recognition-only and must never generate a leg.
    if (compact == '2RIS' ||
        compact == '2NDRIS' ||
        compact == 'SECONDRIS' ||
        compact == '2NDRESERVEINSHOW' ||
        compact == 'SECONDRESERVEINSHOW') {
      return false;
    }

    return compact == 'RIS' ||
        compact == '1RIS' ||
        compact == '1STRIS' ||
        compact == 'FIRSTRIS' ||
        compact == 'RESERVEINSHOW' ||
        compact == 'RESERVEOFSHOW' ||
        compact == 'RESERVEBESTINSHOW' ||
        compact == '1STRESERVEINSHOW' ||
        compact == 'FIRSTRESERVEINSHOW';
  }

  String _normalizeAwardCode(String value) {
    final compact = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '');

    switch (compact) {
      case 'BOG':
      case 'BESTOFGROUP':
      case 'BESTGROUP':
        return 'BOG';
      case 'BOSG':
      case 'BESTOPPOSITESEXOFGROUP':
      case 'BESTOPPOSITESEXGROUP':
      case 'BESTOPPOSITEGROUP':
        return 'BOSG';
      case 'BOV':
      case 'BESTOFVARIETY':
      case 'BESTVARIETY':
        return 'BOV';
      case 'BOSV':
      case 'BESTOPPOSITESEXOFVARIETY':
      case 'BESTOPPOSITESEXVARIETY':
      case 'BESTOPPOSITEVARIETY':
        return 'BOSV';
      case 'BOB':
      case 'BESTOFBREED':
      case 'BESTBREED':
        return 'BOB';
      case 'BOSB':
      case 'BOS':
      case 'BESTOPPOSITESEXOFBREED':
      case 'BESTOPPOSITESEXBREED':
      case 'BESTOPPOSITEBREED':
        return 'BOSB';
      default:
        return value.trim().toUpperCase();
    }
  }

  _LegRuleMatch? _determineLegRule({
    required String awardCode,
    required _EntryLegContext ctx,
  }) {
    final normalized = _normalizeAwardCode(awardCode);

    if (_isBestInShowAward(normalized) &&
        ctx.showAnimals >= 5 &&
        ctx.showExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 8,
        priority: 1,
        animalsCount: ctx.showAnimals,
        exhibitorsCount: ctx.showExhibitors,
      );
    }

    if (_isReserveInShowAward(normalized) &&
        ctx.showAnimals >= 5 &&
        ctx.showExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 10,
        priority: 2,
        animalsCount: ctx.showAnimals,
        exhibitorsCount: ctx.showExhibitors,
      );
    }

    if (normalized == 'BOB' &&
        ctx.breedAnimals >= 5 &&
        ctx.breedExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 2,
        priority: 3,
        animalsCount: ctx.breedAnimals,
        exhibitorsCount: ctx.breedExhibitors,
      );
    }

    if ((normalized == 'BOSB' || normalized == 'BOS') &&
        ctx.breedSameSexAnimals >= 5 &&
        ctx.breedSameSexExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 3,
        priority: 4,
        animalsCount: ctx.breedSameSexAnimals,
        exhibitorsCount: ctx.breedSameSexExhibitors,
      );
    }

    if (normalized == 'BOG' &&
        ctx.groupAnimals >= 5 &&
        ctx.groupExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 4,
        priority: 5,
        animalsCount: ctx.groupAnimals,
        exhibitorsCount: ctx.groupExhibitors,
      );
    }

    if (normalized == 'BOSG' &&
        ctx.groupSameSexAnimals >= 5 &&
        ctx.groupSameSexExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 5,
        priority: 6,
        animalsCount: ctx.groupSameSexAnimals,
        exhibitorsCount: ctx.groupSameSexExhibitors,
      );
    }

    if (normalized == 'BOV' &&
        ctx.varietyAnimals >= 5 &&
        ctx.varietyExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 6,
        priority: 7,
        animalsCount: ctx.varietyAnimals,
        exhibitorsCount: ctx.varietyExhibitors,
      );
    }

    if (normalized == 'BOSV' &&
        ctx.varietySameSexAnimals >= 5 &&
        ctx.varietySameSexExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 7,
        priority: 8,
        animalsCount: ctx.varietySameSexAnimals,
        exhibitorsCount: ctx.varietySameSexExhibitors,
      );
    }

    if ((normalized == 'BEST_4_CLASS' ||
            normalized == 'BEST_6_CLASS' ||
            normalized == 'BEST4CLASS' ||
            normalized == 'BEST6CLASS' ||
            normalized == 'B4C' ||
            normalized == 'B6C') &&
        ctx.showAnimals >= 5 &&
        ctx.showExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 9,
        priority: 9,
        animalsCount: ctx.showAnimals,
        exhibitorsCount: ctx.showExhibitors,
      );
    }

    if ((normalized == '1' || normalized == '1ST' || normalized == 'FIRST') &&
        ctx.classAnimals >= 5 &&
        ctx.classExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 1,
        priority: 10,
        animalsCount: ctx.classAnimals,
        exhibitorsCount: ctx.classExhibitors,
      );
    }


    return null;
  }

  String _legDedupeKey(_EntryLegContext ctx, String entryId) {
    final animalId = ctx.animalId.trim();
    final entryKey = entryId.trim();
    final animalFallbackKey = [
      ctx.breed.trim().toLowerCase(),
      ctx.tattoo.trim().toLowerCase(),
    ].where((e) => e.isNotEmpty).join('::');

    final animalKey = animalId.isNotEmpty
        ? animalId
        : animalFallbackKey.isNotEmpty
            ? animalFallbackKey
            : entryKey;

    final sectionKey = ctx.sectionId.trim().isNotEmpty
        ? ctx.sectionId.trim()
        : ctx.sectionLetter.trim().toUpperCase();

    return [
      ctx.exhibitorId.trim(),
      animalKey,
      sectionKey,
    ].join('|');
  }

  String _safeExhibitorName(_EntryLegContext ctx) {
    final memberName = [
      ctx.exhibitorFirstName,
      ctx.exhibitorLastName,
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    return _firstNonEmpty([
      memberName,
      ctx.exhibitorShowingName,
      ctx.exhibitorLabel,
      'UNKNOWN EXHIBITOR',
    ]);
  }

  String _safeShowExhibitorNumber(_EntryLegContext ctx) {
    final showNumber = ctx.exhibitorNumber.trim();
    final label = ctx.exhibitorLabel.trim();
    final memberName = _safeExhibitorName(ctx).trim();

    // EXH# must be the show-specific exhibitor number. Guard against the RPC
    // accidentally returning the exhibitor label/name as the number.
    if (showNumber.isNotEmpty &&
        showNumber.toLowerCase() != label.toLowerCase() &&
        showNumber.toLowerCase() != memberName.toLowerCase()) {
      return showNumber;
    }

    return 'UNASSIGNED';
  }

  String _formatOwnerAddress(_EntryLegContext ctx) {
    final streetLines = [
      ctx.exhibitorAddressLine1,
      ctx.exhibitorAddressLine2,
    ].where((e) => e.trim().isNotEmpty).toList();

    final cityStateZip = [
      ctx.exhibitorCity,
      [
        ctx.exhibitorState,
        ctx.exhibitorZip,
      ].where((e) => e.trim().isNotEmpty).join(' '),
    ].where((e) => e.trim().isNotEmpty).join(', ');

    final formatted = [
      ...streetLines,
      cityStateZip,
    ].where((e) => e.trim().isNotEmpty).join('\n');

    return formatted.isNotEmpty ? formatted : 'ADDRESS NOT PROVIDED';
  }

  String _sectionFromCertificateId(String value) {
    final parts = value.split('_');
    if (parts.length >= 4) {
      return parts[3].toUpperCase();
    }
    return '';
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _str(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class _ExhibitorProfile {
  final String exhibitorNumber;
  final String displayName;
  final String showingName;
  final String firstName;
  final String lastName;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String zip;

  const _ExhibitorProfile({
    required this.exhibitorNumber,
    required this.displayName,
    required this.showingName,
    required this.firstName,
    required this.lastName,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    required this.zip,
  });
}

class _LegCandidate {
  final int priority;
  final String dedupeKey;
  final LegsCertificateData data;

  const _LegCandidate({
    required this.priority,
    required this.dedupeKey,
    required this.data,
  });
}

class _LegRuleMatch {
  final int rule;
  final int priority;
  final int animalsCount;
  final int exhibitorsCount;

  const _LegRuleMatch({
    required this.rule,
    required this.priority,
    required this.animalsCount,
    required this.exhibitorsCount,
  });
}

class _EntryLegContext {
  final String sectionId;
  final String sectionLetter;
  final String varietyDisplay;
  final String groupName;
  final bool usesGroupAwards;
  final bool isDisqualified;
  final String showJudgeRowId;
  final String tattoo;
  final String exhibitorId;
  final String animalId;
  final String breed;
  final String className;
  final String sex;
  final int placement;

  final String exhibitorLabel;
  final String exhibitorNumber;
  final String exhibitorShowingName;
  final String exhibitorFirstName;
  final String exhibitorLastName;
  final String exhibitorAddressLine1;
  final String exhibitorAddressLine2;
  final String exhibitorCity;
  final String exhibitorState;
  final String exhibitorZip;

  final int breedAnimals;
  final int breedExhibitors;
  final int breedSameSexAnimals;
  final int breedSameSexExhibitors;

  final int varietyAnimals;
  final int varietyExhibitors;
  final int varietySameSexAnimals;
  final int varietySameSexExhibitors;

  final int groupAnimals;
  final int groupExhibitors;
  final int groupSameSexAnimals;
  final int groupSameSexExhibitors;

  final int classAnimals;
  final int classExhibitors;

  final int showAnimals;
  final int showExhibitors;

  const _EntryLegContext({
    required this.sectionId,
    required this.sectionLetter,
    required this.varietyDisplay,
    required this.groupName,
    required this.usesGroupAwards,
    required this.isDisqualified,
    required this.showJudgeRowId,
    required this.tattoo,
    required this.exhibitorId,
    required this.animalId,
    required this.breed,
    required this.className,
    required this.sex,
    required this.placement,
    required this.exhibitorLabel,
    required this.exhibitorNumber,
    required this.exhibitorShowingName,
    required this.exhibitorFirstName,
    required this.exhibitorLastName,
    required this.exhibitorAddressLine1,
    required this.exhibitorAddressLine2,
    required this.exhibitorCity,
    required this.exhibitorState,
    required this.exhibitorZip,
    required this.breedAnimals,
    required this.breedExhibitors,
    required this.breedSameSexAnimals,
    required this.breedSameSexExhibitors,
    required this.varietyAnimals,
    required this.varietyExhibitors,
    required this.varietySameSexAnimals,
    required this.varietySameSexExhibitors,
    required this.groupAnimals,
    required this.groupExhibitors,
    required this.groupSameSexAnimals,
    required this.groupSameSexExhibitors,
    required this.classAnimals,
    required this.classExhibitors,
    required this.showAnimals,
    required this.showExhibitors,
  });
}