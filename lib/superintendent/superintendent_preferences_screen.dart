// lib/superintendent/superintendent_preferences_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/app_session.dart';

final supabase = Supabase.instance.client;

class SuperintendentPreferencesScreen extends StatefulWidget {
  const SuperintendentPreferencesScreen({super.key});

  @override
  State<SuperintendentPreferencesScreen> createState() =>
      _SuperintendentPreferencesScreenState();
}

class _SuperintendentPreferencesScreenState
    extends State<SuperintendentPreferencesScreen> {
  late Future<void> _future;

  String _openYouthMode = 'together';
  String _showOrder = 'open_first';
  String _autoFillPriority = 'balanced_head_count';
  bool _prioritizeSameBreedTogether = false;
  bool _avoidSameJudgeBreedAcrossLetters = true;
  final TextEditingController _warnHeadCountController =
      TextEditingController(text: '250');
  String _displayDensity = 'roomy';
  String _showCountsMode = 'always';
  String _defaultBreedSort = 'letter';

  bool _savingPreferences = false;
  List<Map<String, dynamic>> _judges = const <Map<String, dynamic>>[];
  String? _selectedJudgeId;
  Map<String, dynamic>? _selectedJudgeRating;
  bool _savingRating = false;
  List<Map<String, dynamic>> _judgeRatings = const <Map<String, dynamic>>[];

  double _speedRating = 5;
  double _overallQualityRating = 5;
  double _accuracyRating = 5;
  String _bestClassSystem = 'unknown';
  int _dailyHeadLimit = 250;
  bool _allowsOverage = true;
  double? _overageRatePer;
  final TextEditingController _overageRateController = TextEditingController();
  final TextEditingController _judgeNotesController = TextEditingController();
  final TextEditingController _judgeSearchController = TextEditingController();
  String _judgeSortMode = 'name';

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  @override
  void dispose() {
    _warnHeadCountController.dispose();
    _judgeNotesController.dispose();
    _judgeSearchController.dispose();
    _overageRateController.dispose();
    super.dispose();
  }

  String? get _userId => AppSession.effectiveUserId ?? supabase.auth.currentUser?.id;

  Future<void> _loadData() async {
    final userId = _userId;
    if (userId == null) return;

    final preferenceRows = await supabase
        .from('show_superintendent_user_preferences')
        .select()
        .eq('user_id', userId)
        .limit(1);

    final preferences = List<Map<String, dynamic>>.from(preferenceRows as List);
    if (preferences.isEmpty) {
      if (!AppSession.isSupportMode) {
        await supabase.from('show_superintendent_user_preferences').insert({
          'user_id': userId,
        });
      }
    } else {
      final row = preferences.first;
      _openYouthMode = (row['open_youth_mode'] ?? _openYouthMode).toString();
      _showOrder = (row['show_order'] ?? _showOrder).toString();
      _autoFillPriority =
          (row['auto_fill_priority'] ?? _autoFillPriority).toString();
      _prioritizeSameBreedTogether =
          row['prioritize_same_breed_together'] == true;
      _avoidSameJudgeBreedAcrossLetters =
          row['avoid_same_judge_breed_across_letters'] != false;
      _warnHeadCountController.text =
          (row['warn_head_count'] ?? 250).toString();
      _displayDensity = (row['display_density'] ?? _displayDensity).toString();
      _showCountsMode = (row['show_counts_mode'] ?? _showCountsMode).toString();
      _defaultBreedSort =
          (row['default_breed_sort'] ?? _defaultBreedSort).toString();
    }

    final judgeRows = await supabase
        .from('judges')
        .select('id, display_name, name, first_name, last_name, city, state, judge_type, is_active')
        .order('display_name', ascending: true);

    _judges = List<Map<String, dynamic>>.from(judgeRows as List);
    await _loadJudgeRatings();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  Future<void> _savePreferences() async {
    final userId = _userId;
    if (AppSession.isSupportMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferences are disabled while viewing as another user.'),
        ),
      );
      return;
    }
    if (userId == null || _savingPreferences) return;

    final warnHeadCount =
        int.tryParse(_warnHeadCountController.text.trim()) ?? 250;

    setState(() => _savingPreferences = true);

    try {
      await supabase.from('show_superintendent_user_preferences').upsert({
        'user_id': userId,
        'open_youth_mode': _openYouthMode,
        'show_order': _showOrder,
        'auto_fill_priority': _autoFillPriority,
        'prioritize_same_breed_together': _prioritizeSameBreedTogether,
        'avoid_same_judge_breed_across_letters':
            _avoidSameJudgeBreedAcrossLetters,
        'warn_head_count': warnHeadCount,
        'display_density': _displayDensity,
        'show_counts_mode': _showCountsMode,
        'default_breed_sort': _defaultBreedSort,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  String _judgeLabel(Map<String, dynamic> judge) {
    final display = (judge['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;

    final name = (judge['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final first = (judge['first_name'] ?? '').toString().trim();
    final last = (judge['last_name'] ?? '').toString().trim();
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? 'Unnamed Judge' : full;
  }

  String _judgeLocation(Map<String, dynamic> judge) {
    final city = (judge['city'] ?? '').toString().trim();
    final state = (judge['state'] ?? '').toString().trim();
    return [city, state].where((part) => part.isNotEmpty).join(', ');
  }

  Future<void> _loadJudgeRatings() async {
    final userId = _userId;
    if (userId == null || AppSession.isSupportMode) {
      _judgeRatings = const <Map<String, dynamic>>[];
      return;
    }

    final rows = await supabase.rpc('get_private_judge_ratings');

    _judgeRatings = (rows as List)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final payload = row['payload'];
          final payloadMap = payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{};

          return <String, dynamic>{
            'user_id': row['user_id'],
            'judge_id': row['judge_id'],
            'updated_at': row['updated_at'],
            ...payloadMap,
          };
        })
        .toList();
  }

  String _ratedJudgeLabel(Map<String, dynamic> rating) {
    final judge = rating['judges'];
    if (judge is Map) {
      return _judgeLabel(Map<String, dynamic>.from(judge));
    }

    final judgeId = (rating['judge_id'] ?? '').toString().trim();
    final match = _judges.where((j) => (j['id'] ?? '').toString() == judgeId);
    if (match.isNotEmpty) return _judgeLabel(match.first);

    return 'Unknown Judge';
  }

  String _ratedJudgeSubtitle(Map<String, dynamic> rating) {
    final speed = (rating['speed_rating'] ?? '').toString();
    final quality = (rating['overall_quality_rating'] ?? '').toString();
    final accuracy = (rating['accuracy_rating'] ?? '').toString();
    final bestClassSystem = (rating['best_class_system'] ?? '').toString().trim();
    final dailyHeadLimit = (rating['daily_head_limit'] ?? '').toString().trim();
    final overageRate = (
      rating['overage_rate_per_head'] ??
      rating['overage_rate_per_'] ??
      ''
    ).toString().trim();

    final parts = <String>[
      if (speed.isNotEmpty) 'Speed $speed',
      if (quality.isNotEmpty) 'Quality $quality',
      if (accuracy.isNotEmpty) 'Accuracy $accuracy',
      if (bestClassSystem.isNotEmpty && bestClassSystem != 'unknown') bestClassSystem,
      if (dailyHeadLimit.isNotEmpty) '$dailyHeadLimit head/day',
      if (overageRate.isNotEmpty) 'Overage $overageRate/head',
    ];

    return parts.isEmpty ? 'Tap to edit rating' : parts.join(' • ');
  }

  List<Map<String, dynamic>> _filteredJudgeOptions() {
    final query = _judgeSearchController.text.trim().toLowerCase();

    final rows = _judges.where((judge) {
      if (query.isEmpty) return true;

      final label = _judgeLabel(judge).toLowerCase();
      final location = _judgeLocation(judge).toLowerCase();
      final type = (judge['judge_type'] ?? '').toString().toLowerCase();

      return label.contains(query) ||
          location.contains(query) ||
          type.contains(query);
    }).toList();

    rows.sort((a, b) {
      if (_judgeSortMode == 'state') {
        final stateCompare = (a['state'] ?? '')
            .toString()
            .compareTo((b['state'] ?? '').toString());
        if (stateCompare != 0) return stateCompare;
      }

      if (_judgeSortMode == 'type') {
        final typeCompare = (a['judge_type'] ?? '')
            .toString()
            .compareTo((b['judge_type'] ?? '').toString());
        if (typeCompare != 0) return typeCompare;
      }

      return _judgeLabel(a).compareTo(_judgeLabel(b));
    });

    return rows;
  }

  Future<void> _selectJudge(String? judgeId) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _selectedJudgeId = judgeId;
      _selectedJudgeRating = null;
      _speedRating = 5;
      _overallQualityRating = 5;
      _accuracyRating = 5;
      _bestClassSystem = 'unknown';
      _judgeNotesController.clear();
      _dailyHeadLimit = 250;
      _allowsOverage = true;
      _overageRatePer = null;
      _overageRateController.clear();
    });

    if (judgeId == null || judgeId.isEmpty) return;

    if (AppSession.isSupportMode) return;

    final ratingPayload = await supabase.rpc(
      'get_private_judge_rating',
      params: {'p_judge_id': judgeId},
    );

    if (ratingPayload == null) return;

    final row = ratingPayload is Map
        ? Map<String, dynamic>.from(ratingPayload)
        : <String, dynamic>{};
    if (row.isEmpty) return;

    setState(() {
      _selectedJudgeRating = {
        'judge_id': judgeId,
        ...row,
      };
      _speedRating = ((row['speed_rating'] as num?)?.toDouble() ?? 5)
          .clamp(1, 10)
          .toDouble();
      _overallQualityRating =
          ((row['overall_quality_rating'] as num?)?.toDouble() ?? 5)
              .clamp(1, 10)
              .toDouble();
      _accuracyRating = ((row['accuracy_rating'] as num?)?.toDouble() ?? 5)
          .clamp(1, 10)
          .toDouble();
      _bestClassSystem =
          (row['best_class_system'] ?? _bestClassSystem).toString();
      _judgeNotesController.text = (row['notes'] ?? '').toString();
      _dailyHeadLimit = (row['daily_head_limit'] as num?)?.toInt() ?? 250;
      _allowsOverage = row['allows_overage'] != false;
      final rawOverageRate = row['overage_rate_per_head'] ?? row['overage_rate_per_'];
      _overageRatePer = rawOverageRate is num
          ? rawOverageRate.toDouble()
          : double.tryParse(rawOverageRate?.toString() ?? '');
      _overageRateController.text = _overageRatePer?.toString() ?? '';
    });
  }

  Future<void> _saveJudgeRating() async {
    final userId = _userId;
    final judgeId = _selectedJudgeId;
    if (AppSession.isSupportMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Judge ratings are disabled while viewing as another user.'),
        ),
      );
      return;
    }
    if (userId == null || judgeId == null || judgeId.isEmpty || _savingRating) {
      return;
    }

    setState(() => _savingRating = true);
    final parsedOverageRate = _overageRateController.text.trim().isEmpty
        ? null
        : double.tryParse(_overageRateController.text.trim());

    try {
      await supabase.rpc(
        'save_private_judge_rating',
        params: {
          'p_judge_id': judgeId,
          'p_payload': {
            'speed_rating': _speedRating.round(),
            'overall_quality_rating': _overallQualityRating.round(),
            'accuracy_rating': _accuracyRating.round(),
            'best_class_system': _bestClassSystem,
            'notes': _judgeNotesController.text.trim().isEmpty
                ? null
                : _judgeNotesController.text.trim(),
            'daily_head_limit': _dailyHeadLimit,
            'allows_overage': _allowsOverage,
            'overage_rate_per_head': parsedOverageRate,
            'overage_rate_per_': parsedOverageRate,
          },
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Judge rating saved privately.')),
      );
      await _selectJudge(judgeId);
      await _loadJudgeRatings();
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _savingRating = false);
    }
  }

  Future<void> _openJudgeRatingsDialog() async {
    if (AppSession.isSupportMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Judge ratings are disabled while viewing as another user.'),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final judgeOptions = _filteredJudgeOptions();
            final ratedJudges = _judgeRatings;

            Future<void> selectJudge(String? judgeId) async {
              await _selectJudge(judgeId);
              if (mounted) dialogSetState(() {});
            }

            Future<void> saveRating() async {
              await _saveJudgeRating();
              if (mounted) dialogSetState(() {});
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star_rate,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Private Judge Ratings',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'These ratings are private to your account and are stored as an encrypted payload.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Your rated judges',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (ratedJudges.isEmpty)
                          Text(
                            'No saved judge ratings yet.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: ratedJudges.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final rating = ratedJudges[index];
                                final judgeId = (rating['judge_id'] ?? '').toString();
                                final selected = judgeId == _selectedJudgeId;

                                return ListTile(
                                  dense: true,
                                  selected: selected,
                                  leading: Icon(
                                    selected ? Icons.edit : Icons.star_rate,
                                  ),
                                  title: Text(
                                    _ratedJudgeLabel(rating),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(_ratedJudgeSubtitle(rating)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => selectJudge(judgeId),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _judgeSearchController,
                          decoration: const InputDecoration(
                            labelText: 'Search judges',
                            hintText: 'Search by name, city, state, or type',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => dialogSetState(() {}),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'name',
                              icon: Icon(Icons.sort_by_alpha),
                              label: Text('Name'),
                            ),
                            ButtonSegment(
                              value: 'state',
                              icon: Icon(Icons.location_on_outlined),
                              label: Text('State'),
                            ),
                            ButtonSegment(
                              value: 'type',
                              icon: Icon(Icons.badge_outlined),
                              label: Text('Type'),
                            ),
                          ],
                          selected: {_judgeSortMode},
                          onSelectionChanged: (selection) {
                            setState(() => _judgeSortMode = selection.first);
                            dialogSetState(() {});
                          },
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: judgeOptions.isEmpty
                              ? Text(
                                  'No judges match your search.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: judgeOptions.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final judge = judgeOptions[index];
                                    final id = judge['id'].toString();
                                    final selected = id == _selectedJudgeId;
                                    final location = _judgeLocation(judge);
                                    final judgeType =
                                        (judge['judge_type'] ?? '').toString().trim();

                                    return ListTile(
                                      selected: selected,
                                      leading: Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.person_outline,
                                      ),
                                      title: Text(
                                        _judgeLabel(judge),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: [
                                        if (location.isNotEmpty) location,
                                        if (judgeType.isNotEmpty) judgeType,
                                      ].join(' • ').isEmpty
                                          ? null
                                          : Text([
                                              if (location.isNotEmpty) location,
                                              if (judgeType.isNotEmpty) judgeType,
                                            ].join(' • ')),
                                      onTap: () => selectJudge(id),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 18),
                        if (_selectedJudgeId == null)
                          Text(
                            'Select a judge to add your private rating.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        else ...[
                          _RatingSlider(
                            label: 'Speed',
                            value: _speedRating,
                            onChanged: (value) {
                              setState(() => _speedRating = value);
                              dialogSetState(() {});
                            },
                          ),
                          _RatingSlider(
                            label: 'Overall Quality',
                            value: _overallQualityRating,
                            onChanged: (value) {
                              setState(() => _overallQualityRating = value);
                              dialogSetState(() {});
                            },
                          ),
                          _RatingSlider(
                            label: 'Accuracy',
                            value: _accuracyRating,
                            onChanged: (value) {
                              setState(() => _accuracyRating = value);
                              dialogSetState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          _SegmentedPreference<String>(
                            label: 'Better with',
                            selected: _bestClassSystem,
                            segments: const [
                              ButtonSegment(
                                value: 'four_class',
                                label: Text('4-Class'),
                              ),
                              ButtonSegment(
                                value: 'six_class',
                                label: Text('6-Class'),
                              ),
                              ButtonSegment(value: 'both', label: Text('Both')),
                              ButtonSegment(
                                value: 'unknown',
                                label: Text('Unknown'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _bestClassSystem = value);
                              dialogSetState(() {});
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Capacity & Overages',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: _dailyHeadLimit.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Daily head limit',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null) {
                                setState(() => _dailyHeadLimit = parsed);
                                dialogSetState(() {});
                              }
                            },
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Allow overage'),
                            value: _allowsOverage,
                            onChanged: (value) {
                              setState(() => _allowsOverage = value);
                              dialogSetState(() {});
                            },
                          ),
                          TextField(
                            controller: _overageRateController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Overage rate per head (optional)',
                              hintText: 'e.g. 2.50',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _overageRatePer = value.trim().isEmpty
                                    ? null
                                    : double.tryParse(value.trim());
                              });
                              dialogSetState(() {});
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _judgeNotesController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Private notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _savingRating ? null : saveRating,
                              icon: const Icon(Icons.save),
                              label: Text(
                                _savingRating
                                    ? 'Saving...'
                                    : (_selectedJudgeRating == null
                                        ? 'Save Rating'
                                        : 'Update Rating'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Superintendent Preferences',
      subtitle: 'Private preferences for your superintendent tools.',
      actions: [
        TextButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
      ],
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 56),
                    const SizedBox(height: 12),
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final readOnly = AppSession.isSupportMode;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (readOnly) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text(
                    'Support Mode — Superintendent preferences are view-only while viewing as another user. Private judge ratings are hidden.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _PreferencesCard(
                title: 'Default table behavior',
                icon: Icons.table_chart,
                children: [
                  _SegmentedPreference<String>(
                    label: 'Open/Youth layout',
                    selected: _openYouthMode,
                    segments: const [
                      ButtonSegment(value: 'together', label: Text('Together')),
                      ButtonSegment(value: 'separate', label: Text('Separate')),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setState(() => _openYouthMode = value),
                  ),
                  const SizedBox(height: 16),
                  _SegmentedPreference<String>(
                    label: 'Show order',
                    selected: _showOrder,
                    segments: const [
                      ButtonSegment(value: 'open_first', label: Text('Open first')),
                      ButtonSegment(value: 'youth_first', label: Text('Youth first')),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setState(() => _showOrder = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PreferencesCard(
                title: 'Auto Fill behavior',
                icon: Icons.auto_fix_high,
                children: [
                  _SegmentedPreference<String>(
                    label: 'Primary priority',
                    selected: _autoFillPriority,
                    segments: const [
                      ButtonSegment(
                        value: 'balanced_head_count',
                        label: Text('Balanced'),
                      ),
                      ButtonSegment(
                        value: 'same_breed_together',
                        label: Text('Breed together'),
                      ),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setState(() => _autoFillPriority = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prioritize keeping same breed together'),
                    value: _prioritizeSameBreedTogether,
                    onChanged: readOnly
                        ? null
                        : (value) =>
                            setState(() => _prioritizeSameBreedTogether = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Avoid same judge/breed across show letters'),
                    value: _avoidSameJudgeBreedAcrossLetters,
                    onChanged: readOnly
                        ? null
                        : (value) => setState(
                              () => _avoidSameJudgeBreedAcrossLetters = value,
                            ),
                  ),
                  TextField(
                    controller: _warnHeadCountController,
                    readOnly: readOnly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Warn at head count',
                      helperText: 'ARBA recommendation defaults to 250 head/day.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PreferencesCard(
                title: 'Display preferences',
                icon: Icons.visibility,
                children: [
                  _SegmentedPreference<String>(
                    label: 'Card density',
                    selected: _displayDensity,
                    segments: const [
                      ButtonSegment(value: 'roomy', label: Text('Roomy')),
                      ButtonSegment(value: 'compact', label: Text('Compact')),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setState(() => _displayDensity = value),
                  ),
                  const SizedBox(height: 16),
                  _SegmentedPreference<String>(
                    label: 'Default breed sort',
                    selected: _defaultBreedSort,
                    segments: const [
                      ButtonSegment(value: 'letter', label: Text('Letter')),
                      ButtonSegment(value: 'count', label: Text('Count')),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setState(() => _defaultBreedSort = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: (_savingPreferences || readOnly) ? null : _savePreferences,
                  icon: const Icon(Icons.save),
                  label: Text(_savingPreferences ? 'Saving...' : 'Save Preferences'),
                ),
              ),
              if (!readOnly) ...[
                const SizedBox(height: 24),
                _PreferencesCard(
                  title: 'Private judge ratings',
                  icon: Icons.star_rate,
                  children: [
                    Text(
                      'Rate judges privately for your own future show superintendent planning.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _openJudgeRatingsDialog,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open Judge Ratings'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SegmentedPreference<T> extends StatelessWidget {
  const _SegmentedPreference({
    required this.label,
    required this.selected,
    required this.segments,
    required this.onChanged,
  });

  final String label;
  final T selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<T>(
          segments: segments,
          selected: {selected},
          onSelectionChanged: onChanged == null
              ? null
              : (selection) => onChanged!(selection.first),
        ),
      ],
    );
  }
}

class _RatingSlider extends StatelessWidget {
  const _RatingSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Text(value.round().toString()),
          ],
        ),
        Slider(
          value: value,
          min: 1,
          max: 10,
          divisions: 9,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}