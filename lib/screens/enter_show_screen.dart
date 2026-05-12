// lib/screens/enter_show_screen.dart

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/widgets/exhibitor_builder_dialog.dart';
import 'package:ringmaster_show/utils/cavy/cavy_sop_order.dart';
import 'package:ringmaster_show/widgets/animal_editor/open_animal_editor_dialog.dart';
import 'package:ringmaster_show/services/app_session.dart';

import 'cart_screen.dart';

final supabase = Supabase.instance.client;

class EnterShowScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const EnterShowScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<EnterShowScreen> createState() => _EnterShowScreenState();
}

class _EnterShowScreenState extends State<EnterShowScreen> {
  final Map<String, bool> _selected = {};
  final Map<String, TextEditingController> _classControllers = {};

  String? _msg;
  bool _submitting = false;
  bool get _hasCommercialClasses => _commercialByCode.isNotEmpty;

  DateTime? _showDate;

  bool _furEntriesEnabled = false;

  final Map<String, String> _rabbitBreedClassSystem = {};

  final Map<String, Map<String, dynamic>> _rabbitBreedMeta = {};

  bool _sectionAllowsMeatClasses(String? sectionId) {
    final id = (sectionId ?? '').trim();
    if (id.isEmpty) return false;
    return _sectionById[id]?['allow_meat_classes'] == true;
  }

  bool _sectionIsMeatOnly(String? sectionId) {
    final id = (sectionId ?? '').trim();
    if (id.isEmpty) return false;
    return _sectionById[id]?['breed_scope'] == 'meat_only';
  }

  bool get _selectedSectionsAllowMeatClasses {
    if (_selectedSectionIds.isEmpty) return false;
    return _selectedSectionIds.any((id) {
      final s = _sectionById[id];
      if (s == null) return false;
      return s['breed_scope'] == 'meat_only' || s['allow_meat_classes'] == true;
    });
  }

  List<String> get _selectedMeatAllowedSectionIds {
    return _selectedSectionIds.where((id) {
      final s = _sectionById[id];
      if (s == null) return false;

      final isMeatOnly = s['breed_scope'] == 'meat_only';
      final allowsToggle = s['allow_meat_classes'] == true;

      return isMeatOnly || allowsToggle;
    }).toList();
  }

  bool _showHasBreedRows = false;
  final Set<String> _enabledRabbitBreeds = {};
  final Set<String> _enabledCavyBreeds = {};

  final Set<String> _breedHasVarietyOverrides = {};
  final Map<String, Set<String>> _allowedVarietiesByBreedLower = {};

  final Set<String> _selectedSectionIds = {};
  final Map<String, Map<String, dynamic>> _sectionById = {};
  final Map<String, Set<String>> _furSectionIdsByAnimal = {};
  final Map<String, Map<String, String>> _furVarietyByAnimalSection = {};

  List<Map<String, dynamic>> _exhibitors = [];
  String? _selectedExhibitorId;

  String? _activeCartId;
  final Set<String> _animalIdsInCart = {};
  final Map<String, Set<String>> _enteredAnimalIdsBySection = {};
  final Map<String, Set<String>> _enteredSectionsByAnimal = {};
  final Map<String, Map<String, dynamic>> _commercialByCode = {};

  final List<Map<String, String>> _commercialDefaults = const [
    {
      'class_code': 'single_fryer',
      'display_name': 'Single Fryers',
    },
    {
      'class_code': 'roaster',
      'display_name': 'Roasters',
    },
    {
      'class_code': 'stewer',
      'display_name': 'Stewers',
    },
    {
      'class_code': 'meat_pen',
      'display_name': 'Meat Pens',
    },
  ];

  static const double _singleFryerMinWeight = 3.5;
  static const double _singleFryerMaxWeight = 5.5;
  static const int _singleFryerMaxAgeDays = 70;

  static const double _roasterMinWeightExclusive = 5.5;
  static const double _roasterMaxWeight = 8.0;
  static const int _roasterMaxAgeDaysExclusive = 180; // under 6 months

  static const double _stewerMinWeightExclusive = 8.0;
  static const int _stewerMinAgeDays = 180; // 6 months and over

  Future<_EnterShowLoadBundle>? _loadFuture;

  Future<void> _loadCommercialClasses() async {
    final rows = await supabase
        .from('show_commercial_classes')
        .select('class_code,display_name,is_enabled,sort_order')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true)
        .order('sort_order');

    _commercialByCode.clear();
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final code = (row['class_code'] ?? '').toString().trim();
      if (code.isEmpty) continue;
      _commercialByCode[code] = row;
    }
  }

  String _commercialLabel(String classCode) {
    final row = _commercialByCode[classCode];
    if (row != null) {
      final label = (row['display_name'] ?? '').toString().trim();
      if (label.isNotEmpty) return label;
    }

    final fallback = _commercialDefaults.where(
      (x) => x['class_code'] == classCode,
    );
    if (fallback.isNotEmpty) {
      return fallback.first['display_name']!;
    }

    return classCode;
  }

  TextEditingController _classControllerFor(String animalId) {
    return _classControllers.putIfAbsent(
      animalId,
      () => TextEditingController(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadAll();
  }

  @override
  void dispose() {
    for (final c in _classControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reloadAll() async {
    setState(() {
      _loadFuture = _loadAll();
    });
  }

  bool get _hasUnsubmittedCart =>
      _activeCartId != null && _animalIdsInCart.isNotEmpty;

  bool get _selectionIncludesYouth => _selectedSectionIds.any(
        (id) => _sectionKindForId(id) == 'youth',
      );

  Future<bool> _confirmLeaveIfNeeded() async {
    if (!_hasUnsubmittedCart) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Entry Not Submitted'),
        content: const Text(
          'Your entry has not been submitted yet. If you leave now, your animals will not be entered in the show.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay and Review Entry'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave Without Submitting'),
          ),
        ],
      ),
    );

    return shouldLeave ?? false;
  }

  Future<void> _openAddAnimalDialog() async {
    if (AppSession.isSupportMode) {
      setState(() => _msg = 'Adding animals is disabled while viewing in support mode.');
      return;
    }
    final saved = await openAnimalEditorDialog(context);

    if (saved == true) {
      await _reloadAll();
    }
  }

  Future<void> _openAddExhibitorDialog() async {
    if (AppSession.isSupportMode) {
      setState(() => _msg = 'Adding exhibitors is disabled while viewing in support mode.');
      return;
    }
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const ExhibitorBuilderDialog(),
    );

    if (saved == null || !mounted) return;

    final exhibitors = await _loadActiveExhibitors();
    final savedId = (saved['id'] ?? '').toString();

    setState(() {
      _exhibitors = exhibitors;
      if (savedId.isNotEmpty) {
        _selectedExhibitorId = savedId;
      }
      _msg = null;
    });
  }

  bool _hasSectionConflictForAnimal(String animalId) {
    final existingSectionIds = _enteredSectionsByAnimal[animalId];
    if (existingSectionIds == null || existingSectionIds.isEmpty) return false;

    for (final selectedSectionId in _selectedSectionIds) {
      final selectedKind = _sectionKindForId(selectedSectionId);
      final selectedLetter = _sectionLetterForId(selectedSectionId);

      if (selectedKind.isEmpty || selectedLetter.isEmpty) continue;

      for (final existingSectionId in existingSectionIds) {
        final existingKind = _sectionKindForId(existingSectionId);
        final existingLetter = _sectionLetterForId(existingSectionId);

        if (existingKind.isEmpty || existingLetter.isEmpty) continue;

        if (selectedLetter == existingLetter && selectedKind != existingKind) {
          return true;
        }
      }
    }

    return false;
  }

  String _sectionConflictLabelForAnimal(String animalId) {
    final existingSectionIds = _enteredSectionsByAnimal[animalId];
    if (existingSectionIds == null || existingSectionIds.isEmpty) return '';

    for (final selectedSectionId in _selectedSectionIds) {
      final selectedKind = _sectionKindForId(selectedSectionId);
      final selectedLetter = _sectionLetterForId(selectedSectionId);

      if (selectedKind.isEmpty || selectedLetter.isEmpty) continue;

      for (final existingSectionId in existingSectionIds) {
        final existingKind = _sectionKindForId(existingSectionId);
        final existingLetter = _sectionLetterForId(existingSectionId);

        if (existingKind.isEmpty || existingLetter.isEmpty) continue;

        if (selectedLetter == existingLetter && selectedKind != existingKind) {
          return _sectionLabelForId(existingSectionId);
        }
      }
    }

    return '';
  }

  bool _isSixClassBreed(String breedName) {
    final classSystem =
        _rabbitBreedClassSystem[breedName.trim().toLowerCase()] ?? 'four';
    return classSystem == 'six';
  }

  Map<String, dynamic>? _rabbitBreedRule(String breedName) {
    final key = breedName.trim().toLowerCase();
    if (key.isEmpty) return null;
    return _rabbitBreedMeta[key];
  }

  bool _breedHasPreJunior(String breedName) {
    return _rabbitBreedRule(breedName)?['has_prejunior'] == true;
  }

  bool _breedUsesWhiteColoredFur(String breedName) {
    final mode =
        (_rabbitBreedRule(breedName)?['fur_entry_variety_mode'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    return mode == 'white_colored';
  }

  bool _isGiantChinchilla(String breedName) {
    return breedName.trim().toLowerCase() == 'giant chinchilla';
  }

  String _normalizedRabbitSex(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'buck' || s.startsWith('b')) return 'buck';
    if (s == 'doe' || s.startsWith('d')) return 'doe';
    return '';
  }

  List<String> _allowedClassOptionsForAnimal(Map<String, dynamic> animal) {
    final species = (animal['species'] ?? '').toString().trim().toLowerCase();
    final breed = (animal['breed'] ?? '').toString().trim();

    if (species == 'rabbit') {
      final isSixClass = _isSixClassBreed(breed);
      final hasPreJunior = _breedHasPreJunior(breed);

      if (_isGiantChinchilla(breed) && hasPreJunior) {
        return const ['Pre-Junior', 'Junior', 'Intermediate', 'Senior'];
      }

      if (isSixClass) {
        if (hasPreJunior) {
          return const ['Pre-Junior', 'Junior', 'Intermediate', 'Senior'];
        }
        return const ['Junior', 'Intermediate', 'Senior'];
      }

      if (hasPreJunior) {
        return const ['Pre-Junior', 'Junior', 'Senior'];
      }
      return const ['Junior', 'Senior'];
    }

    if (species == 'cavy') {
      return const ['Junior', 'Intermediate', 'Senior'];
    }

    return const [];
  }

  Future<void> _viewCart() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    final cartId = AppSession.isSupportMode
        ? await _getActiveCartIdIfExists(
            showId: widget.showId,
            userId: userId,
          )
        : await _getOrCreateActiveCartId(
            showId: widget.showId,
            userId: userId,
          );

    if (cartId == null) {
      setState(() => _msg = 'No active cart found for this user.');
      return;
    }

    _activeCartId = cartId;
    await _refreshAnimalsInCart();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CartScreen(
          cartId: cartId,
          showId: widget.showId,
          showName: widget.showName,
        ),
      ),
    );

    await _loadActiveCartIdIfExists();
    await _refreshAnimalsInCart();

    if (mounted) {
      setState(() {});
    }
  }

  Future<_EnterShowLoadBundle> _loadAll() async {
    await _loadShowContext();
    await _loadPaymentSettings();
    await _loadCommercialClasses();
    final animals = await _loadAnimals();
    final sections = await _loadEnabledSections();
    final exhibitors = await _loadActiveExhibitors();

    if (exhibitors.isNotEmpty && _selectedExhibitorId == null) {
      _selectedExhibitorId = exhibitors.first['id'].toString();
    }

    await _loadActiveCartIdIfExists();
    await _refreshAnimalsInCart();
    await _refreshAnimalsAlreadyEnteredForShow(animals);

    return _EnterShowLoadBundle(
      animals: animals,
      sections: sections,
      exhibitors: exhibitors,
    );
  }

  Future<List<Map<String, dynamic>>> _loadActiveExhibitors() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final rows = await supabase
        .from('exhibitors')
        .select('id,showing_name,display_name,type,is_active,created_at')
        .eq('owner_user_id', userId)
        .eq('is_active', true)
        .order('created_at', ascending: true);

    final list = (rows as List).cast<Map<String, dynamic>>();
    _exhibitors = list;
    return list;
  }

  String _exhibitorLabel(Map<String, dynamic> e) {
    final sn = (e['showing_name'] ?? '').toString().trim();
    if (sn.isNotEmpty) return sn;
    final dn = (e['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    return '(Unnamed Exhibitor)';
  }

  String _exhibitorType(Map<String, dynamic> e) {
    return (e['type'] ?? '').toString().trim().toLowerCase();
  }

  bool _isYouthExhibitor(Map<String, dynamic> e) {
    final type = _exhibitorType(e);
    return type == 'youth';
  }

  bool _isExhibitorAllowedForCurrentSelection(
    Map<String, dynamic> exhibitor,
  ) {
    if (_selectionIncludesYouth) {
      return _isYouthExhibitor(exhibitor);
    }
    return true;
  }

  List<Map<String, dynamic>> _allowedExhibitorsForCurrentSelection(
    List<Map<String, dynamic>> exhibitors,
  ) {
    return exhibitors
        .where((e) => _isExhibitorAllowedForCurrentSelection(e))
        .toList();
  }

  Map<String, dynamic>? _selectedExhibitorRecord() {
    if (_selectedExhibitorId == null) return null;
    try {
      return _exhibitors.firstWhere(
        (e) => e['id'].toString() == _selectedExhibitorId,
      );
    } catch (_) {
      return null;
    }
  }

  void _ensureSelectedExhibitorStillAllowed() {
    if (_selectedExhibitorId == null) return;

    final exhibitor = _selectedExhibitorRecord();
    if (exhibitor == null) {
      _selectedExhibitorId = null;
      return;
    }

    if (!_isExhibitorAllowedForCurrentSelection(exhibitor)) {
      _selectedExhibitorId = null;
    }
  }

  Future<void> _loadActiveCartIdIfExists() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      _activeCartId = null;
      return;
    }

    _activeCartId = await _getActiveCartIdIfExists(
      showId: widget.showId,
      userId: userId,
    );
  }

  Future<String?> _getActiveCartIdIfExists({
    required String showId,
    required String userId,
  }) async {
    final existing = await supabase
        .from('entry_carts')
        .select('id')
        .eq('show_id', showId)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    return existing == null ? null : existing['id'].toString();
  }

  Future<String> _getOrCreateActiveCartId({
    required String showId,
    required String userId,
  }) async {
    final existing = await supabase
        .from('entry_carts')
        .select('id')
        .eq('show_id', showId)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (existing != null) return existing['id'].toString();

    final created = await supabase
        .from('entry_carts')
        .insert({
          'show_id': showId,
          'user_id': userId,
          'status': 'active',
        })
        .select('id')
        .single();

    return created['id'].toString();
  }

  Future<void> _refreshAnimalsInCart() async {
    _animalIdsInCart.clear();

    final cartId = _activeCartId;
    if (cartId == null) return;

    final rows = await supabase
        .from('entry_cart_items')
        .select('animal_id')
        .eq('cart_id', cartId);

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final aid = r['animal_id']?.toString();
      if (aid != null && aid.isNotEmpty) {
        _animalIdsInCart.add(aid);
      }
    }
  }

  Future<void> _refreshAnimalsAlreadyEnteredForShow(
    List<Map<String, dynamic>> animals,
  ) async {
    _enteredAnimalIdsBySection.clear();
    _enteredSectionsByAnimal.clear();

    final animalIds = animals
        .map((a) => (a['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (animalIds.isEmpty) return;

    final rows = await supabase
        .from('entries')
        .select('animal_id,section_id')
        .eq('show_id', widget.showId)
        .inFilter('animal_id', animalIds);

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final animalId = r['animal_id']?.toString();
      final sectionId = r['section_id']?.toString();

      if (animalId == null || animalId.isEmpty) continue;
      if (sectionId == null || sectionId.isEmpty) continue;

      _enteredAnimalIdsBySection.putIfAbsent(sectionId, () => <String>{});
      _enteredAnimalIdsBySection[sectionId]!.add(animalId);

      _enteredSectionsByAnimal.putIfAbsent(animalId, () => <String>{});
      _enteredSectionsByAnimal[animalId]!.add(sectionId);
    }
  }

  bool _isAnimalInCart(String animalId) => _animalIdsInCart.contains(animalId);

  bool _isAnimalAlreadyEnteredInAnySelectedSection(String animalId) {
    for (final sectionId in _selectedSectionIds) {
      final enteredIds = _enteredAnimalIdsBySection[sectionId];
      if (enteredIds != null && enteredIds.contains(animalId)) {
        return true;
      }
    }
    return false;
  }

  String _alreadyEnteredSectionLabel(String animalId) {
    for (final sectionId in _selectedSectionIds) {
      final enteredIds = _enteredAnimalIdsBySection[sectionId];
      if (enteredIds != null && enteredIds.contains(animalId)) {
        return _sectionLabelForId(sectionId);
      }
    }
    return '';
  }

  Future<void> _loadPaymentSettings() async {
    _furEntriesEnabled = false;

    try {
      final row = await supabase
          .from('show_payment_settings')
          .select()
          .eq('show_id', widget.showId)
          .maybeSingle();

      if (row == null) return;

      double readPrice(String key) {
        final value = row[key];
        if (value == null) return 0;
        if (value is num) return value.toDouble();
        return double.tryParse(value.toString()) ?? 0;
      }

      final possibleFurPrices = <double>[
        readPrice('fur_entry_fee'),
        readPrice('fur_fee'),
        readPrice('fur_wool_fee'),
        readPrice('fur_price'),
        readPrice('fur_wool_price'),
      ];

      _furEntriesEnabled = possibleFurPrices.any((price) => price > 0);
    } catch (_) {
      _furEntriesEnabled = false;
    }
  }

  Future<void> _loadShowContext() async {
    final show = await supabase
        .from('shows')
        .select('start_date')
        .eq('id', widget.showId)
        .single();

    final sd = show['start_date']?.toString();
    _showDate = sd == null ? null : DateTime.tryParse(sd);

    final breeds = await supabase
        .from('breeds')
        .select(
          'id,name,species,class_system,is_active,'
          'has_prejunior,prejunior_age_max_months,prejunior_weight_min,prejunior_weight_max,'
          'prejunior_buck_age_max_months,prejunior_buck_weight_min,prejunior_buck_weight_max,'
          'prejunior_doe_age_max_months,prejunior_doe_weight_min,prejunior_doe_weight_max,'
          'fur_entry_variety_mode',
        )
        .eq('is_active', true)
        .order('name');

    final breedRows = (breeds as List).cast<Map<String, dynamic>>();
    final Map<String, Map<String, dynamic>> breedById = {
      for (final b in breedRows) (b['id'] as String): b,
    };

    _rabbitBreedClassSystem.clear();
    _rabbitBreedMeta.clear();
    for (final b in breedRows) {
      final species = (b['species'] ?? '').toString();
      if (species != 'rabbit') continue;

      final name = (b['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final lower = name.toLowerCase();
      final cs = (b['class_system'] ?? 'four').toString();

      _rabbitBreedClassSystem[lower] = cs;
      _rabbitBreedMeta[lower] = Map<String, dynamic>.from(b);
    }

    final showBreeds = await supabase
        .from('show_breeds')
        .select('breed_id,is_enabled,class_system_override')
        .eq('show_id', widget.showId);

    final showBreedRows = (showBreeds as List).cast<Map<String, dynamic>>();
    _showHasBreedRows = showBreedRows.isNotEmpty;

    _enabledRabbitBreeds.clear();
    _enabledCavyBreeds.clear();

    if (!_showHasBreedRows) {
      for (final b in breedRows) {
        final species = (b['species'] ?? '').toString();
        final name = (b['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        if (species == 'rabbit') _enabledRabbitBreeds.add(name.toLowerCase());
        if (species == 'cavy') _enabledCavyBreeds.add(name.toLowerCase());
      }
    } else {
      for (final r in showBreedRows) {
        final breedId = r['breed_id'] as String;
        final enabled = r['is_enabled'] == true;
        final b = breedById[breedId];
        if (b == null) continue;

        final species = (b['species'] ?? '').toString();
        final name = (b['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        if (enabled) {
          if (species == 'rabbit') _enabledRabbitBreeds.add(name.toLowerCase());
          if (species == 'cavy') _enabledCavyBreeds.add(name.toLowerCase());
        }

        final override = r['class_system_override'];
        if (override != null && species == 'rabbit') {
          _rabbitBreedClassSystem[name.toLowerCase()] = override.toString();
        }
      }
    }

    final showVars = await supabase
        .from('show_varieties')
        .select('breed_id,variety_id,custom_name,is_enabled')
        .eq('show_id', widget.showId);

    _breedHasVarietyOverrides.clear();
    _allowedVarietiesByBreedLower.clear();

    final showVarRows = (showVars as List).cast<Map<String, dynamic>>();
    if (showVarRows.isNotEmpty) {
      final allVarieties = await supabase
          .from('varieties')
          .select('id,breed_id,name,is_active')
          .eq('is_active', true);

      final varietyRows = (allVarieties as List).cast<Map<String, dynamic>>();
      final Map<String, String> varietyNameById = {
        for (final v in varietyRows)
          (v['id'] as String): (v['name'] ?? '').toString().trim(),
      };

      for (final r in showVarRows) {
        final breedId = r['breed_id'] as String;
        final b = breedById[breedId];
        if (b == null) continue;

        final breedName = (b['name'] ?? '').toString().trim();
        if (breedName.isEmpty) continue;
        final breedLower = breedName.toLowerCase();

        _breedHasVarietyOverrides.add(breedLower);
        _allowedVarietiesByBreedLower.putIfAbsent(
          breedLower,
          () => <String>{},
        );

        final enabled = r['is_enabled'] == true;
        if (!enabled) continue;

        final varietyId = r['variety_id'];
        final customName = r['custom_name'];

        if (varietyId != null) {
          final vn = varietyNameById[varietyId as String];
          if (vn != null && vn.isNotEmpty) {
            _allowedVarietiesByBreedLower[breedLower]!.add(vn.toLowerCase());
          }
        } else if (customName != null) {
          final cn = customName.toString().trim();
          if (cn.isNotEmpty) {
            _allowedVarietiesByBreedLower[breedLower]!.add(cn.toLowerCase());
          }
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadEnabledSections() async {
    final List rows = await supabase
        .from('show_sections')
        .select('id,kind,letter,display_name,sort_order,allow_meat_classes,breed_scope')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true);

    final sections = rows.cast<Map<String, dynamic>>();

    int kindRank(String kind) {
      switch (kind.trim().toLowerCase()) {
        case 'youth':
          return 0;
        case 'open':
          return 1;
        default:
          return 99;
      }
    }

    int letterRank(String letter) {
      switch (letter.trim().toUpperCase()) {
        case 'A':
          return 0;
        case 'B':
          return 1;
        case 'C':
          return 2;
        default:
          return 99;
      }
    }

    sections.sort((a, b) {
      final kindCmp = kindRank((a['kind'] ?? '').toString())
          .compareTo(kindRank((b['kind'] ?? '').toString()));
      if (kindCmp != 0) return kindCmp;

      final letterCmp = letterRank((a['letter'] ?? '').toString())
          .compareTo(letterRank((b['letter'] ?? '').toString()));
      if (letterCmp != 0) return letterCmp;

      return ((a['display_name'] ?? '').toString())
          .compareTo((b['display_name'] ?? '').toString());
    });

    _sectionById
      ..clear()
      ..addEntries(
        sections.map(
          (s) => MapEntry((s['id'] ?? '').toString(), s),
        ),
      );

    return sections;
  }

  Future<List<Map<String, dynamic>>> _loadAnimals() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final res = await supabase
        .from('animals')
        .select(
          'id,species,name,tattoo,breed,variety,sex,birth_date,is_dob_unknown',
        )
        .eq('owner_user_id', userId)
        .order('created_at', ascending: false);

    return (res as List).cast<Map<String, dynamic>>();
  }

  String _sectionKindForId(String? sectionId) {
    final id = (sectionId ?? '').trim();
    if (id.isEmpty) return '';
    return (_sectionById[id]?['kind'] ?? '').toString().trim().toLowerCase();
  }

  String _sectionLetterForId(String? sectionId) {
    final id = (sectionId ?? '').trim();
    if (id.isEmpty) return '';
    return (_sectionById[id]?['letter'] ?? '').toString().trim().toUpperCase();
  }

  String _sectionChipLabel(Map<String, dynamic> s) {
    final display = (s['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;

    final kind = (s['kind'] ?? '').toString().trim().toLowerCase();
    final letter = (s['letter'] ?? '').toString().trim().toUpperCase();

    final kindLabel = kind == 'youth'
        ? 'Youth'
        : kind == 'open'
            ? 'Open'
            : 'Section';

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  String _sectionLabelForId(String sectionId) {
    final section = _sectionById[sectionId];
    if (section == null) return 'Unknown Section';
    return _sectionChipLabel(section);
  }

  bool _breedAllowed(String species, String breedName) {
    final b = breedName.trim().toLowerCase();
    final s = species.trim().toLowerCase();
    if (b.isEmpty) return false;
    if (s == 'rabbit') return _enabledRabbitBreeds.contains(b);
    if (s == 'cavy') return _enabledCavyBreeds.contains(b);
    return false;
  }

  bool _varietyAllowed(String breedName, String varietyName) {
    final b = breedName.trim().toLowerCase();
    final v = varietyName.trim().toLowerCase();
    if (b.isEmpty || v.isEmpty) return false;

    if (_breedHasVarietyOverrides.contains(b)) {
      return (_allowedVarietiesByBreedLower[b] ?? const <String>{}).contains(v);
    }
    return true;
  }

  int _ageInDays(DateTime birthDate, DateTime showDate) {
    final bd = DateTime(birthDate.year, birthDate.month, birthDate.day);
    final sd = DateTime(showDate.year, showDate.month, showDate.day);
    return sd.difference(bd).inDays;
  }

  double _ageInMonthsApprox(DateTime birthDate, DateTime showDate) {
    final days = _ageInDays(birthDate, showDate);
    return days / 30.4375;
  }

  String _sexLabel(String species, String? sexRaw) {
    final s = (sexRaw ?? '').trim().toLowerCase();

    if (species == 'rabbit') {
      if (s == 'buck') return 'Buck';
      if (s == 'doe') return 'Doe';
      if (s.startsWith('b')) return 'Buck';
      if (s.startsWith('d')) return 'Doe';
      return 'Buck/Doe';
    } else {
      if (s == 'boar') return 'Boar';
      if (s == 'sow') return 'Sow';
      if (s.startsWith('b')) return 'Boar';
      if (s.startsWith('s')) return 'Sow';
      return 'Boar/Sow';
    }
  }

  String _suggestRabbitDivision({
    required String breedName,
    required String sex,
    required DateTime birthDate,
    required DateTime showDate,
  }) {
    final months = _ageInMonthsApprox(birthDate, showDate);
    final breedKey = breedName.trim().toLowerCase();
    final classSystem = _rabbitBreedClassSystem[breedKey] ?? 'four';
    final meta = _rabbitBreedMeta[breedKey];

    if (meta != null && meta['has_prejunior'] == true) {
      if (_isGiantChinchilla(breedName)) {
        if (sex == 'buck') {
          final maxAge =
              (meta['prejunior_buck_age_max_months'] as num?)?.toDouble();
          if (maxAge != null && months < maxAge) {
            return 'Pre-Junior';
          }
        } else if (sex == 'doe') {
          final maxAge =
              (meta['prejunior_doe_age_max_months'] as num?)?.toDouble();
          if (maxAge != null && months < maxAge) {
            return 'Pre-Junior';
          }
        }
      } else {
        final maxAge =
            (meta['prejunior_age_max_months'] as num?)?.toDouble();
        if (maxAge != null && months < maxAge) {
          return 'Pre-Junior';
        }
      }
    }

    if (months < 6.0) return 'Junior';
    if (classSystem == 'six') {
      if (months <= 8.0) return 'Intermediate';
      return 'Senior';
    }
    return 'Senior';
  }

  String? _suggestClassForAnimal(Map<String, dynamic> a) {
    final species = (a['species'] ?? '').toString();
    if (_showDate == null) return null;

    final isDobUnknown = a['is_dob_unknown'] == true;
    if (isDobUnknown) return null;

    final bdRaw = a['birth_date']?.toString();
    final birthDate = bdRaw == null ? null : DateTime.tryParse(bdRaw);
    if (birthDate == null) return null;

    final sex = _normalizedRabbitSex(a['sex']?.toString());

    if (species == 'rabbit') {
      final breed = (a['breed'] ?? '').toString();
      if (breed.trim().isEmpty) return null;

      return _suggestRabbitDivision(
        breedName: breed,
        sex: sex,
        birthDate: birthDate,
        showDate: _showDate!,
      );
    }

    if (species == 'cavy') {
      final months = _ageInMonthsApprox(birthDate, _showDate!);

      if (months < 4.0) return 'Junior';
      if (months < 6.0) return 'Intermediate';
      return 'Senior';
    }

    return null;
  }

  String? _selectedOrSuggestedClassForAnimal(Map<String, dynamic> animal) {
    final animalId = (animal['id'] ?? '').toString();
    final controller = _classControllerFor(animalId);
    final manualValue = controller.text.trim();

    if (manualValue.isNotEmpty) {
      return manualValue;
    }

    final suggested = _suggestClassForAnimal(animal);
    if (suggested != null && suggested.isNotEmpty) {
      controller.text = suggested;
      return suggested;
    }

    return null;
  }

  void _toggleSelected(Map<String, dynamic> animal, bool isSelected) {
    final id = animal['id'] as String;

    if (_isAnimalInCart(id) ||
        _isAnimalAlreadyEnteredInAnySelectedSection(id) ||
        _hasSectionConflictForAnimal(id)) {
      return;
    }

    setState(() {
      _selected[id] = isSelected;
      if (!isSelected) {
        _furSectionIdsByAnimal.remove(id);
        _furVarietyByAnimalSection.remove(id);
      }
      _msg = null;
    });

    if (isSelected) {
      final ctrl = _classControllerFor(id);
      if (ctrl.text.trim().isEmpty) {
        final suggestion = _suggestClassForAnimal(animal);
        if (suggestion != null && suggestion.isNotEmpty) {
          ctrl.text = suggestion;
        }
      }
    }
  }

  void _clearSectionSelection() {
    setState(() {
      _selectedSectionIds.clear();
      _furSectionIdsByAnimal.clear();
      _furVarietyByAnimalSection.clear();
      _msg = null;
    });
  }

  bool _isFurSelectedForAnimalSection(String animalId, String sectionId) {
    return _furSectionIdsByAnimal[animalId]?.contains(sectionId) ?? false;
  }

  void _toggleFurForAnimalSection({
    required String animalId,
    required String sectionId,
    required bool value,
  }) {
    setState(() {
      final set = _furSectionIdsByAnimal.putIfAbsent(
        animalId,
        () => <String>{},
      );

      if (value) {
        set.add(sectionId);
      } else {
        set.remove(sectionId);
        if (set.isEmpty) {
          _furSectionIdsByAnimal.remove(animalId);
        }

        _furVarietyByAnimalSection[animalId]?.remove(sectionId);
        if (_furVarietyByAnimalSection[animalId]?.isEmpty ?? false) {
          _furVarietyByAnimalSection.remove(animalId);
        }
      }
    });
  }

  String? _furVarietyForAnimalSection(String animalId, String sectionId) {
    return _furVarietyByAnimalSection[animalId]?[sectionId];
  }

  void _setFurVarietyForAnimalSection({
    required String animalId,
    required String sectionId,
    required String? value,
  }) {
    setState(() {
      if (value == null || value.trim().isEmpty) {
        _furVarietyByAnimalSection[animalId]?.remove(sectionId);
        if (_furVarietyByAnimalSection[animalId]?.isEmpty ?? false) {
          _furVarietyByAnimalSection.remove(animalId);
        }
        return;
      }

      final bySection = _furVarietyByAnimalSection.putIfAbsent(
        animalId,
        () => <String, String>{},
      );
      bySection[sectionId] = value.trim();
    });
  }

  void _toggleSection({
    required String sectionId,
    required String kind,
  }) {
    setState(() {
      _msg = null;

      if (_selectedSectionIds.contains(sectionId)) {
        _selectedSectionIds.remove(sectionId);

        for (final animalId in _furSectionIdsByAnimal.keys.toList()) {
          final set = _furSectionIdsByAnimal[animalId];
          set?.remove(sectionId);
          if (set == null || set.isEmpty) {
            _furSectionIdsByAnimal.remove(animalId);
          }

          _furVarietyByAnimalSection[animalId]?.remove(sectionId);
          if (_furVarietyByAnimalSection[animalId]?.isEmpty ?? false) {
            _furVarietyByAnimalSection.remove(animalId);
          }
        }
      } else {
        _selectedSectionIds.add(sectionId);
      }

      if (!_furEntriesEnabled) {
        _furSectionIdsByAnimal.clear();
        _furVarietyByAnimalSection.clear();
      }

      _ensureSelectedExhibitorStillAllowed();

      if (_selectionIncludesYouth && _selectedExhibitorId == null) {
        _msg = 'Youth sections selected. Please choose a youth exhibitor.';
      }
    });
  }

  List<String> _collectImmediateSelectionErrors({
    required List<Map<String, dynamic>> chosen,
    required Map<String, dynamic> exhibitor,
  }) {
    final errors = <String>[];

    if (_selectionIncludesYouth && !_isYouthExhibitor(exhibitor)) {
      errors.add(
        'Only youth exhibitors can be used when any youth section is selected.',
      );
    }

    final selectedKindsByLetter = <String, Set<String>>{};
    for (final sectionId in _selectedSectionIds) {
      final letter = _sectionLetterForId(sectionId);
      final kind = _sectionKindForId(sectionId);
      if (letter.isEmpty || kind.isEmpty) continue;

      selectedKindsByLetter.putIfAbsent(letter, () => <String>{}).add(kind);
    }

    for (final entry in selectedKindsByLetter.entries) {
      if (entry.value.length > 1) {
        errors.add(
          'You cannot enter the same rabbit in both Open and Youth. Remove one of the ${entry.key} sections.',
        );
      }
    }

    if (chosen.isEmpty) {
      errors.add('Select at least one animal.');
      return errors;
    }

    for (final a in chosen) {
      final animalId = (a['id'] ?? '').toString();
      final title = _displayAnimalTitle(a);
      final species = _safeString(a, 'species');
      final breed = _safeString(a, 'breed');
      final variety = _safeString(a, 'variety');
      final className = _classControllerFor(animalId).text.trim();

      if (className.isEmpty) {
        errors.add('$title must have a class selected.');
      } else if (!_allowedClassOptionsForAnimal(a).contains(className)) {
        errors.add('$title has an invalid class selection: $className.');
      }

      if (!_breedAllowed(species, breed)) {
        errors.add(
          '$title is not eligible because "$breed" is not enabled for this show.',
        );
      }

      if (variety.isEmpty) {
        errors.add('$title is missing a variety.');
      } else if (!_varietyAllowed(breed, variety)) {
        errors.add(
          '$title is not eligible because "$variety" is not an allowed variety for $breed at this show.',
        );
      }
      for (final sectionId in _selectedSectionIds) {
        if (!_furEntriesEnabled ||
            !_isFurSelectedForAnimalSection(animalId, sectionId)) {
          continue;
        }

        if (_breedUsesWhiteColoredFur(breed)) {
          final furVariety = _furVarietyForAnimalSection(animalId, sectionId);
          if (furVariety == null ||
              (furVariety != 'White' && furVariety != 'Colored')) {
            errors.add(
              '$title must have a Fur/Wool class of White or Colored for ${_sectionLabelForId(sectionId)}.',
            );
          }
        }
      }

      if (_isAnimalInCart(animalId)) {
        errors.add('$title is already in the cart.');
      }

      if (_isAnimalAlreadyEnteredInAnySelectedSection(animalId)) {
        final sectionLabel = _alreadyEnteredSectionLabel(animalId);
        errors.add(
          sectionLabel.isEmpty
              ? '$title is already entered in one of the selected sections.'
              : '$title is already entered in $sectionLabel.',
        );
      }

      if (_hasSectionConflictForAnimal(animalId)) {
        final conflictLabel = _sectionConflictLabelForAnimal(animalId);
        errors.add(
          conflictLabel.isEmpty
              ? '$title cannot be entered in both Open and Youth for the same letter.'
              : '$title conflicts with existing $conflictLabel. The same letter cannot be entered in both Open and Youth.',
        );
      }
    }

    return errors;
  }

  Future<List<String>> _collectCrossEntryErrors({
    required List<Map<String, dynamic>> chosen,
  }) async {
    final errors = <String>[];
    final animalIds = chosen
        .map((a) => (a['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (animalIds.isEmpty) return errors;

    final selectedPairs = <String, List<Map<String, String>>>{};
    for (final a in chosen) {
      final animalId = (a['id'] ?? '').toString();
      for (final sectionId in _selectedSectionIds) {
        selectedPairs.putIfAbsent(animalId, () => []).add({
          'kind': _sectionKindForId(sectionId),
          'letter': _sectionLetterForId(sectionId),
          'label': _sectionLabelForId(sectionId),
        });
      }
    }

    List<Map<String, dynamic>> cartRows = [];
    if (_activeCartId != null) {
      final res = await supabase
          .from('entry_cart_items')
          .select('animal_id,section_id')
          .eq('cart_id', _activeCartId!)
          .inFilter('animal_id', animalIds);
      cartRows = (res as List).cast<Map<String, dynamic>>();
    }

    final entryRes = await supabase
        .from('entries')
        .select('animal_id,section_id')
        .eq('show_id', widget.showId)
        .inFilter('animal_id', animalIds);
    final entryRows = (entryRes as List).cast<Map<String, dynamic>>();

    final existingByAnimal = <String, List<Map<String, String>>>{};

    for (final row in [...cartRows, ...entryRows]) {
      final animalId = (row['animal_id'] ?? '').toString();
      final sectionId = (row['section_id'] ?? '').toString();
      if (animalId.isEmpty || sectionId.isEmpty) continue;

      existingByAnimal.putIfAbsent(animalId, () => []).add({
        'kind': _sectionKindForId(sectionId),
        'letter': _sectionLetterForId(sectionId),
        'label': _sectionLabelForId(sectionId),
      });
    }

    for (final a in chosen) {
      final animalId = (a['id'] ?? '').toString();
      final title = _displayAnimalTitle(a);
      final pending = selectedPairs[animalId] ?? const <Map<String, String>>[];
      final existing = existingByAnimal[animalId] ?? const <Map<String, String>>[];

      for (final p in pending) {
        final pLetter = (p['letter'] ?? '').trim().toUpperCase();
        final pKind = (p['kind'] ?? '').trim().toLowerCase();
        if (pLetter.isEmpty || pKind.isEmpty) continue;

        for (final e in existing) {
          final eLetter = (e['letter'] ?? '').trim().toUpperCase();
          final eKind = (e['kind'] ?? '').trim().toLowerCase();
          final eLabel = (e['label'] ?? '').trim();

          if (eLetter == pLetter && eKind.isNotEmpty && eKind != pKind) {
            errors.add(
              '$title conflicts with existing $eLabel. The same letter cannot be entered in both Open and Youth.',
            );
          }
        }
      }
    }

    return errors.toSet().toList();
  }

  Future<bool> _showValidationSummaryDialog(List<String> errors) async {
    final acknowledged = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Entry Validation Issues'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: errors
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('• $e'),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Review'),
          ),
        ],
      ),
    );

    return acknowledged == true;
  }

  Future<bool> _confirmEntrySummary({
    required List<Map<String, dynamic>> chosen,
    required Map<String, dynamic> exhibitor,
  }) async {
    final animalCount = chosen.length;
    final sectionCount = _selectedSectionIds.length;
    final lineCount = animalCount * sectionCount;
    final sectionLabels = _selectedSectionIds.map(_sectionLabelForId).toList()
      ..sort();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Review Entry Summary'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Exhibitor: ${_exhibitorLabel(exhibitor)}'),
                const SizedBox(height: 8),
                Text('Animals selected: $animalCount'),
                Text('Sections selected: $sectionCount'),
                Text('Entry lines to add: $lineCount'),
                const SizedBox(height: 12),
                const Text(
                  'Sections',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...sectionLabels.map((s) => Text('• $s')),
                const SizedBox(height: 12),
                const Text(
                  'Animals',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...chosen.map(
                  (a) {
                    final animalId = (a['id'] ?? '').toString();

                    final furDescriptions = _furEntriesEnabled
                        ? (_selectedSectionIds
                            .where((sectionId) =>
                                _isFurSelectedForAnimalSection(animalId, sectionId))
                            .map((sectionId) {
                              final sectionLabel = _sectionLabelForId(sectionId);
                              final furVariety =
                                  _furVarietyForAnimalSection(animalId, sectionId);
                              if (furVariety != null && furVariety.isNotEmpty) {
                                return '$sectionLabel ($furVariety)';
                              }
                              return sectionLabel;
                            }).toList()
                          ..sort())
                        : <String>[];

                    final furText = furDescriptions.isEmpty
                        ? ''
                        : ' • Fur/Wool: ${furDescriptions.join(', ')}';

                    return Text(
                      '• ${_displayAnimalTitle(a)} — ${_classControllerFor(animalId).text.trim()}$furText',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add to Cart'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _addSelectedToCart(
    List<Map<String, dynamic>> eligibleAnimals,
  ) async {
    if (AppSession.isSupportMode) {
      setState(() => _msg = 'Adding to cart is disabled while viewing in support mode.');
      return;
    }
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    if (_exhibitors.isEmpty) {
      setState(() => _msg =
          'No active exhibitors found. Click Add Exhibitor first.');
      return;
    }

    if (_selectedExhibitorId == null) {
      setState(() => _msg = 'Select an exhibitor.');
      return;
    }

    final selectedExhibitor = _selectedExhibitorRecord();
    if (selectedExhibitor == null) {
      setState(() => _msg = 'Selected exhibitor could not be found.');
      return;
    }

    final chosen =
        eligibleAnimals.where((a) => _selected[a['id']] == true).toList();

    final immediateErrors = _collectImmediateSelectionErrors(
      chosen: chosen,
      exhibitor: selectedExhibitor,
    );

    if (immediateErrors.isNotEmpty) {
      if (mounted) {
        setState(() => _msg = immediateErrors.first);
        await _showValidationSummaryDialog(immediateErrors);
      }
      return;
    }

    final crossEntryErrors = await _collectCrossEntryErrors(chosen: chosen);
    if (crossEntryErrors.isNotEmpty) {
      if (mounted) {
        setState(() => _msg = crossEntryErrors.first);
        await _showValidationSummaryDialog(crossEntryErrors);
      }
      return;
    }

    final confirmed = await _confirmEntrySummary(
      chosen: chosen,
      exhibitor: selectedExhibitor,
    );

    if (!confirmed) return;

    setState(() {
      _submitting = true;
      _msg = null;
    });

    try {
      final cartId = await _getOrCreateActiveCartId(
        showId: widget.showId,
        userId: userId,
      );
      _activeCartId = cartId;

      final List<Map<String, dynamic>> itemsToAdd = [];
      for (final a in chosen) {
        final String animalId = a['id'] as String;
        final String className = _classControllerFor(animalId).text.trim();

        for (final sectionId in _selectedSectionIds) {
          if (_sectionIsMeatOnly(sectionId)) continue;
          final isFur = _furEntriesEnabled &&
              _isFurSelectedForAnimalSection(animalId, sectionId);
          final breedName = (a['breed'] ?? '').toString().trim();

          itemsToAdd.add({
            'cart_id': cartId,
            'section_id': sectionId,
            'animal_id': animalId,
            'exhibitor_id': _selectedExhibitorId,
            'species': a['species'],
            'tattoo': a['tattoo'],
            'animal_name': (a['name'] ?? '').toString().trim().isEmpty
                ? null
                : (a['name'] ?? '').toString().trim(),
            'breed': a['breed'],
            'variety': a['variety'],
            'fur_variety': isFur && _breedUsesWhiteColoredFur(breedName)
                ? _furVarietyForAnimalSection(animalId, sectionId)
                : null,
            'sex': a['sex'],
            'class_name': className.isNotEmpty ? className : null,
            'is_fur': isFur,
          });
        }
      }

      final chosenAnimalIds = chosen.map((a) => (a['id'] as String)).toList();
      final chosenSectionIds = _selectedSectionIds.toList();

      await supabase
          .from('entry_cart_items')
          .delete()
          .eq('cart_id', cartId)
          .inFilter('animal_id', chosenAnimalIds)
          .inFilter('section_id', chosenSectionIds);

      await supabase.from('entry_cart_items').insert(itemsToAdd);

      await _refreshAnimalsInCart();

      if (!mounted) return;

      setState(() {
        for (final a in chosen) {
          final animalId = a['id'] as String;
          _selected[animalId] = false;
          _furSectionIdsByAnimal.remove(animalId);
          _furVarietyByAnimalSection.remove(animalId);
        }
        _selectedSectionIds.clear();
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CartScreen(
            cartId: cartId,
            showId: widget.showId,
            showName: widget.showName,
          ),
        ),
      );

      await _loadActiveCartIdIfExists();
      await _refreshAnimalsInCart();
      await _refreshAnimalsAlreadyEnteredForShow(eligibleAnimals);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Add to cart failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _safeString(Map<String, dynamic> a, String key) {
    return (a[key] ?? '').toString().trim();
  }

  String _displayAnimalTitle(Map<String, dynamic> a) {
    final name = _safeString(a, 'name');
    final tattoo = _safeString(a, 'tattoo');

    if (name.isNotEmpty && tattoo.isNotEmpty) return '$name ($tattoo)';
    if (name.isNotEmpty) return name;
    if (tattoo.isNotEmpty) return tattoo;
    return _safeString(a, 'breed');
  }

  int _speciesRank(String species) {
    switch (species.toLowerCase()) {
      case 'rabbit':
        return 0;
      case 'cavy':
        return 1;
      default:
        return 99;
    }
  }

  List<Map<String, dynamic>> _sortAnimals(List<Map<String, dynamic>> animals) {
    final list = List<Map<String, dynamic>>.from(animals);

    list.sort((a, b) {
      final speciesA = _safeString(a, 'species').toLowerCase();
      final speciesB = _safeString(b, 'species').toLowerCase();

      final speciesCmp =
          _speciesRank(speciesA).compareTo(_speciesRank(speciesB));
      if (speciesCmp != 0) return speciesCmp;

      if (speciesA == 'cavy' && speciesB == 'cavy') {
        final breedCmp = cavyBreedSortIndex(_safeString(a, 'breed'))
            .compareTo(cavyBreedSortIndex(_safeString(b, 'breed')));
        if (breedCmp != 0) return breedCmp;

        final varietyCmp = cavyVarietySortIndex(
          _safeString(a, 'breed'),
          _safeString(a, 'variety'),
        ).compareTo(
          cavyVarietySortIndex(
            _safeString(b, 'breed'),
            _safeString(b, 'variety'),
          ),
        );
        if (varietyCmp != 0) return varietyCmp;
      } else {
        final breedCmp = _safeString(a, 'breed')
            .toLowerCase()
            .compareTo(_safeString(b, 'breed').toLowerCase());
        if (breedCmp != 0) return breedCmp;

        final varietyCmp = _safeString(a, 'variety')
            .toLowerCase()
            .compareTo(_safeString(b, 'variety').toLowerCase());
        if (varietyCmp != 0) return varietyCmp;
      }

      final titleCmp = _displayAnimalTitle(a)
          .toLowerCase()
          .compareTo(_displayAnimalTitle(b).toLowerCase());
      if (titleCmp != 0) return titleCmp;

      return _safeString(a, 'tattoo')
          .toLowerCase()
          .compareTo(_safeString(b, 'tattoo').toLowerCase());
    });

    return list;
  }

    Widget _buildAnimalTile(Map<String, dynamic> a) {
      final id = a['id'] as String;
      final checked = _selected[id] ?? false;
      final inCart = _isAnimalInCart(id);
      final alreadyEnteredInSelectedSection =
          _isAnimalAlreadyEnteredInAnySelectedSection(id);
      final hasSectionConflict = _hasSectionConflictForAnimal(id);
      final disabled =
          inCart || alreadyEnteredInSelectedSection || hasSectionConflict;

      final alreadyEnteredLabel = _alreadyEnteredSectionLabel(id);
      final conflictLabel = _sectionConflictLabelForAnimal(id);

      final classOptions = _allowedClassOptionsForAnimal(a);
      final selectedClass = _selectedOrSuggestedClassForAnimal(a);
      final needsValidation = selectedClass == null || selectedClass.isEmpty;

      final tile = ListTile(
        leading: Checkbox(
          value: checked,
          onChanged: (_submitting || disabled)
              ? null
              : (v) => _toggleSelected(a, v ?? false),
        ),
        title: Text(_displayAnimalTitle(a)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_safeString(a, 'species').toUpperCase()} • ${_safeString(a, 'breed')} • ${_safeString(a, 'variety')} • ${_safeString(a, 'sex')}',
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: classOptions.contains(selectedClass) ? selectedClass : null,
              decoration: InputDecoration(
                labelText: 'Class',
                helperText: needsValidation
                    ? 'Select the class for this animal.'
                    : 'Projected class selected.',
                helperStyle: TextStyle(
                  color: needsValidation ? Colors.red : null,
                  fontWeight: needsValidation ? FontWeight.w600 : null,
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: classOptions
                  .map(
                    (opt) => DropdownMenuItem<String>(
                      value: opt,
                      child: Text(opt),
                    ),
                  )
                  .toList(),
              onChanged: (_submitting || disabled)
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _classControllerFor(id).text = value;
                        _msg = null;
                      });
                    },
            ),
            if (_furEntriesEnabled &&
                _selected[id] == true &&
                _selectedSectionIds.isNotEmpty &&
                _safeString(a, 'species').toLowerCase() != 'cavy') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedSectionIds
                    .where((sectionId) => !_sectionIsMeatOnly(sectionId))
                  .map((sectionId) {
                    final label = _sectionLabelForId(sectionId);
                    final furSelected =
                        _isFurSelectedForAnimalSection(id, sectionId);
                    final breedName = _safeString(a, 'breed');
                    final needsWhiteColored =
                        _breedUsesWhiteColoredFur(breedName);
                    final selectedFurVariety =
                        _furVarietyForAnimalSection(id, sectionId);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilterChip(
                          label: Text('$label Fur/Wool'),
                          selected: furSelected,
                          onSelected: (_submitting || disabled)
                              ? null
                              : (value) => _toggleFurForAnimalSection(
                                    animalId: id,
                                    sectionId: sectionId,
                                    value: value,
                                  ),
                        ),
                        if (furSelected && needsWhiteColored) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String>(
                              value: (selectedFurVariety == 'White' ||
                                      selectedFurVariety == 'Colored')
                                  ? selectedFurVariety
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Fur/Wool Class',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'White',
                                  child: Text('White'),
                                ),
                                DropdownMenuItem(
                                  value: 'Colored',
                                  child: Text('Colored'),
                                ),
                              ],
                              onChanged: (_submitting || disabled)
                                  ? null
                                  : (value) {
                                      _setFurVarietyForAnimalSection(
                                        animalId: id,
                                        sectionId: sectionId,
                                        value: value,
                                      );
                                    },
                            ),
                          ),
                        ],
                      ],
                    );
                  }).toList(),
            ),
          ],
            if (alreadyEnteredInSelectedSection || hasSectionConflict || inCart) ...[
              const SizedBox(height: 8),
              Text(
                alreadyEnteredInSelectedSection
                    ? (alreadyEnteredLabel.isEmpty
                        ? 'Already entered in one of the selected sections'
                        : 'Already entered in $alreadyEnteredLabel')
                    : hasSectionConflict
                        ? (conflictLabel.isEmpty
                            ? 'Cannot enter the same letter in both Open and Youth'
                            : 'Conflicts with existing $conflictLabel')
                        : 'Already in cart',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
        isThreeLine: false,
      );

      return Column(
        children: [
          Opacity(
            opacity: disabled ? 0.45 : 1.0,
            child: tile,
          ),
          const Divider(height: 1),
        ],
      );
    }

  bool _animalHasExactDob(Map<String, dynamic> animal) {
    if (_showDate == null) return false;
    if (animal['is_dob_unknown'] == true) return false;
    final raw = animal['birth_date']?.toString();
    if (raw == null || raw.trim().isEmpty) return false;
    return DateTime.tryParse(raw) != null;
  }

  int? _animalAgeDaysOnShowDate(Map<String, dynamic> animal) {
    if (!_animalHasExactDob(animal) || _showDate == null) return null;
    final raw = animal['birth_date']?.toString();
    final birthDate = raw == null ? null : DateTime.tryParse(raw);
    if (birthDate == null) return null;
    return _ageInDays(birthDate, _showDate!);
  }

  String _formatWeight(double value) {
    return value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 1,
    );
  }

  String _commercialRuleText(String classCode) {
    switch (classCode) {
      case 'single_fryer':
        return 'Single Fryer: not over 70 days old and ${_formatWeight(_singleFryerMinWeight)}–${_formatWeight(_singleFryerMaxWeight)} lb.';
      case 'roaster':
        return 'Roaster: under 6 months old and over ${_formatWeight(_roasterMinWeightExclusive)} lb up to ${_formatWeight(_roasterMaxWeight)} lb.';
      case 'stewer':
        return 'Stewer: 6 months of age or older and over ${_formatWeight(_stewerMinWeightExclusive)} lb.';
      case 'meat_pen':
        return 'Meat Pen: special 3-rabbit entry with 3 tattoos.';
      default:
        return '';
    }
  }

  _CommercialValidationResult _validateCommercialAnimal({
    required Map<String, dynamic> animal,
    required String classCode,
  }) {
    final ageDays = _animalAgeDaysOnShowDate(animal);

    if (ageDays == null) {
      return const _CommercialValidationResult(
        ok: true,
        dobMissing: true,
        message: 'DOB missing.',
      );
    }

    switch (classCode) {
      case 'single_fryer':
        if (ageDays > _singleFryerMaxAgeDays) {
          return _CommercialValidationResult(
            ok: false,
            ageDays: ageDays,
            message:
                'Single Fryer failed age check. Rabbit is $ageDays days old and must be not over $_singleFryerMaxAgeDays days.',
          );
        }
        return _CommercialValidationResult(
          ok: true,
          ageDays: ageDays,
        );

      case 'roaster':
        if (ageDays >= _roasterMaxAgeDaysExclusive) {
          return _CommercialValidationResult(
            ok: false,
            ageDays: ageDays,
            message:
                'Roaster failed age check. Rabbit is $ageDays days old and must be under 6 months.',
          );
        }
        return _CommercialValidationResult(
          ok: true,
          ageDays: ageDays,
        );

      case 'stewer':
        if (ageDays < _stewerMinAgeDays) {
          return _CommercialValidationResult(
            ok: false,
            ageDays: ageDays,
            message:
                'Stewer failed age check. Rabbit is $ageDays days old and must be 6 months of age or older.',
          );
        }
        return _CommercialValidationResult(
          ok: true,
          ageDays: ageDays,
        );

      default:
        return const _CommercialValidationResult(
          ok: false,
          message: 'Unknown commercial class.',
        );
    }
  }

  Future<_CommercialSingleEntryInput?> _openCommercialSingleAnimalDialog({
    required Map<String, dynamic> animal,
    required String classCode,
  }) async {
    String? localError;

    final result = await showDialog<_CommercialSingleEntryInput>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) {
          final title = _commercialLabel(classCode);
          final animalTitle = _displayAnimalTitle(animal);
          final ageDays = _animalAgeDaysOnShowDate(animal);

          return AlertDialog(
            title: Text('Add $title'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rabbit: $animalTitle'),
                  const SizedBox(height: 6),
                  Text(
                    _commercialRuleText(classCode),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ageDays == null
                        ? 'DOB missing'
                        : 'Age validated for this class',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ageDays == null ? Colors.orange : null,
                      fontWeight: ageDays == null ? FontWeight.w600 : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Weight will be verified at show.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      localError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final validation = _validateCommercialAnimal(
                    animal: animal,
                    classCode: classCode,
                  );

                  if (!validation.ok) {
                    setLocalState(() {
                      localError = validation.message;
                    });
                    return;
                  }

                  final detailLabel = validation.dobMissing
                      ? '$title • DOB verify'
                      : title;

                  Navigator.pop(
                    context,
                    _CommercialSingleEntryInput(
                      ageDays: validation.ageDays,
                      dobMissing: validation.dobMissing,
                      detailLabel: detailLabel,
                    ),
                  );
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    return result;
  }

  Future<_MeatPenInput?> _openMeatPenDialog() {
    return showDialog<_MeatPenInput>(
      context: context,
      builder: (_) => _MeatPenDialog(),
    );
  }

  Future<void> _addCommercialSingleAnimalToCart({
    required Map<String, dynamic> animal,
    required String classCode,
  }) async {
    if (AppSession.isSupportMode) {
      setState(() => _msg = 'Commercial entries are disabled while viewing in support mode.');
      return;
    }
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    if (_selectedSectionIds.isEmpty) {
      setState(() => _msg = 'Select at least one show section first.');
      return;
    }

    if (_selectedExhibitorId == null || _selectedExhibitorId!.isEmpty) {
      setState(() => _msg = 'Select an exhibitor first.');
      return;
    }

    final animalId = (animal['id'] ?? '').toString();
    if (animalId.isEmpty) {
      setState(() => _msg = 'Invalid animal.');
      return;
    }

    if (_isAnimalInCart(animalId)) {
      setState(() => _msg = 'That animal is already in the cart.');
      return;
    }

    if (_isAnimalAlreadyEnteredInAnySelectedSection(animalId)) {
      setState(() {
        _msg = 'That animal is already entered in one of the selected sections.';
      });
      return;
    }

    if (_hasSectionConflictForAnimal(animalId)) {
      setState(() {
        _msg = 'That animal conflicts with an existing Open/Youth section.';
      });
      return;
    }

    final commercialInput = await _openCommercialSingleAnimalDialog(
      animal: animal,
      classCode: classCode,
    );

    if (commercialInput == null) return;

    setState(() {
      _submitting = true;
      _msg = null;
    });

    try {
      final cartId = await _getOrCreateActiveCartId(
        showId: widget.showId,
        userId: userId,
      );
      _activeCartId = cartId;

      final label = _commercialLabel(classCode);
      final detailLabel = commercialInput.detailLabel;

      final allowedSectionIds = _selectedMeatAllowedSectionIds;
      if (allowedSectionIds.isEmpty) {
        setState(() {
          _msg = 'Select at least one section that allows Meat Classes first.';
        });
        return;
      }

      final rows = allowedSectionIds.map((sectionId) {
        return {
          'cart_id': cartId,
          'section_id': sectionId,
          'animal_id': animalId,
          'exhibitor_id': _selectedExhibitorId,
          'species': animal['species'],
          'tattoo': animal['tattoo'],
          'animal_name': (animal['name'] ?? '').toString().trim().isEmpty
              ? null
              : (animal['name'] ?? '').toString().trim(),
          'breed': 'Commercial',
          'variety': label,
          'sex': animal['sex'],
          'class_name': detailLabel,
          'is_fur': false,
        };
      }).toList();

      await supabase.from('entry_cart_items').insert(rows);

      await _refreshAnimalsInCart();

      if (!mounted) return;
      setState(() {
        _selected[animalId] = false;
        _furSectionIdsByAnimal.remove(animalId);
        _msg = '${_commercialLabel(classCode)} entry added to cart.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Commercial entry failed: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _addMeatPenToCart() async {
    if (AppSession.isSupportMode) {
      setState(() => _msg = 'Meat Pen entries are disabled while viewing in support mode.');
      return;
    }
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    if (_selectedSectionIds.isEmpty) {
      setState(() => _msg = 'Select at least one show section first.');
      return;
    }

    if (_selectedExhibitorId == null || _selectedExhibitorId!.isEmpty) {
      setState(() => _msg = 'Select an exhibitor first.');
      return;
    }

    final allowedSectionIds = _selectedMeatAllowedSectionIds;
    if (allowedSectionIds.isEmpty) {
      setState(() => _msg = 'Select at least one section that allows Meat Classes first.');
      return;
    }

    final meatPenInput = await _openMeatPenDialog();
    if (meatPenInput == null) return;

    setState(() {
      _submitting = true;
      _msg = null;
    });

    try {
      final cartId = await _getOrCreateActiveCartId(
        showId: widget.showId,
        userId: userId,
      );
      _activeCartId = cartId;

      final tattooText = meatPenInput.tattoos.join(' / ');

      final allowedSectionIds = _selectedMeatAllowedSectionIds;
      if (allowedSectionIds.isEmpty) {
        setState(() => _msg = 'Select at least one section that allows Meat Classes first.');
        return;
      }

      final rows = allowedSectionIds.map((sectionId) {
        return {
          'cart_id': cartId,
          'section_id': sectionId,
          'animal_id': null,
          'exhibitor_id': _selectedExhibitorId,
          'species': 'rabbit',
          'tattoo': tattooText,
          'breed': meatPenInput.breed,
          'variety': meatPenInput.variety,
          'sex': null,
          'class_name': 'Meat Pen',
          'is_fur': false,
        };
      }).toList();

      await supabase.from('entry_cart_items').insert(rows);

      if (!mounted) return;
      setState(() {
        _msg = 'Meat Pen added to cart.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Meat Pen entry failed: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildCommercialCard(List<Map<String, dynamic>> animals) {
    final rabbitAnimals = animals
        .where((a) => _safeString(a, 'species').toLowerCase() == 'rabbit')
        .toList();

    if (!_hasCommercialClasses || !_selectedSectionsAllowMeatClasses) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Commercial Entries',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use these for Single Fryers, Roasters, Stewers, and Meat Pens.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ..._commercialByCode.keys.map((classCode) {
            final label = _commercialLabel(classCode);

            if (classCode == 'meat_pen') {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (_submitting || AppSession.isSupportMode)
                        ? null
                        : _addMeatPenToCart,
                    icon: const Icon(Icons.set_meal),
                    label: Text('Add $label'),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PopupMenuButton<String>(
                enabled: !AppSession.isSupportMode &&
                    !_submitting &&
                    rabbitAnimals.isNotEmpty,
                tooltip: 'Select rabbit for $label',
                onSelected: (animalId) {
                  final animal = rabbitAnimals.firstWhere(
                    (a) => (a['id'] ?? '').toString() == animalId,
                  );
                  _addCommercialSingleAnimalToCart(
                    animal: animal,
                    classCode: classCode,
                  );
                },
                itemBuilder: (_) => rabbitAnimals.map((a) {
                  final animalId = (a['id'] ?? '').toString();
                  final ageDays = _animalAgeDaysOnShowDate(a);

                  return PopupMenuItem<String>(
                    value: animalId,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_displayAnimalTitle(a)),
                        const SizedBox(height: 2),
                        Text(
                          ageDays == null
                              ? 'DOB missing'
                              : 'Age eligible for this class',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black.withOpacity(.12)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pets),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add $label Using Rabbit'),
                            const SizedBox(height: 2),
                            Text(
                              _commercialRuleText(classCode),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EnterShowLoadBundle>(
      future: _loadFuture,
      builder: (context, snap) {
        return RingMasterPageShell(
          title: widget.showName,
          subtitle: 'Enter Show',
          showBackButton: true,
          useScrollView: false,
          actions: [
            IconButton(
              tooltip: AppSession.isSupportMode
                  ? 'Add animal disabled in support mode'
                  : 'Add Animal',
              icon: const Icon(Icons.add),
              onPressed: (_submitting || AppSession.isSupportMode)
                  ? null
                  : _openAddAnimalDialog,
            ),
            IconButton(
              tooltip: 'View Cart',
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: _submitting ? null : _viewCart,
            ),
          ],
          body: Builder(
            builder: (context) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }

              final bundle = snap.data!;
              final allAnimals = bundle.animals;
              final sections = bundle.sections;

              _exhibitors = bundle.exhibitors;

              final allowedExhibitors =
                  _allowedExhibitorsForCurrentSelection(_exhibitors);

              final selectedStillAllowed = _selectedExhibitorId != null &&
                  allowedExhibitors.any(
                    (e) => e['id'].toString() == _selectedExhibitorId,
                  );

              if (!selectedStillAllowed) {
                _selectedExhibitorId = allowedExhibitors.isNotEmpty
                    ? allowedExhibitors.first['id'].toString()
                    : null;
              }

              final showDateText = _showDate == null
                  ? '(show date missing)'
                  : _showDate!.toIso8601String().substring(0, 10);

              final animals = _sortAnimals(allAnimals);

              return WillPopScope(
                onWillPop: _confirmLeaveIfNeeded,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.05),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Show Date: $showDateText',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: allowedExhibitors.any(
                                            (e) =>
                                                e['id'].toString() ==
                                                _selectedExhibitorId)
                                        ? _selectedExhibitorId
                                        : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Exhibitor',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: allowedExhibitors.map((e) {
                                      return DropdownMenuItem<String>(
                                        value: e['id'].toString(),
                                        child: Text(_exhibitorLabel(e)),
                                      );
                                    }).toList(),
                                    onChanged: _submitting
                                        ? null
                                        : (v) {
                                            setState(() {
                                              _selectedExhibitorId = v;
                                              _msg = null;
                                            });
                                          },
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _submitting
                                            ? null
                                            : _openAddExhibitorDialog,
                                        icon:
                                            const Icon(Icons.person_add_alt_1),
                                        label: const Text('Add Exhibitor'),
                                      ),
                                    ],
                                  ),
                                  if (_selectionIncludesYouth) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Youth sections selected. Only youth exhibitors may be used.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (_selectedSectionIds.isNotEmpty)
                                        OutlinedButton.icon(
                                          onPressed: _submitting
                                              ? null
                                              : _clearSectionSelection,
                                          icon: const Icon(Icons.clear_all),
                                          label: const Text('Clear Sections'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.05),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select show(s) to enter',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Choose the section(s) you want to enter for this show, such as Youth A, Youth B, Open A, or Open B.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: sections.map((s) {
                                        final id = s['id'].toString();
                                        final selected =
                                            _selectedSectionIds.contains(id);

                                        return FilterChip(
                                          label: Text(_sectionChipLabel(s)),
                                          selected: selected,
                                          onSelected: _submitting
                                              ? null
                                              : (_) => _toggleSection(
                                                    sectionId: id,
                                                    kind: (s['kind'] ?? '')
                                                        .toString(),
                                                  ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildCommercialCard(animals),
                          if (_msg != null)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(.25),
                                  ),
                                ),
                                child: Text(
                                  _msg!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (animals.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 48),
                              child: Center(child: Text('No animals found.')),
                            )
                          else
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: animals.map((a) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(.04),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: _buildAnimalTile(a),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting
                              ? null
                              : () => _addSelectedToCart(animals),
                          child: Text(
                            _submitting ? 'Saving…' : 'Add Selected to Cart',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EnterShowLoadBundle {
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> exhibitors;

  _EnterShowLoadBundle({
    required this.animals,
    required this.sections,
    required this.exhibitors,
  });
}

class _CommercialValidationResult {
  final bool ok;
  final bool dobMissing;
  final String? message;
  final int? ageDays;

  const _CommercialValidationResult({
    required this.ok,
    this.dobMissing = false,
    this.message,
    this.ageDays,
  });
}

class _CommercialSingleEntryInput {
  final int? ageDays;
  final bool dobMissing;
  final String detailLabel;

  const _CommercialSingleEntryInput({
    required this.ageDays,
    required this.dobMissing,
    required this.detailLabel,
  });
}

class _MeatPenInput {
  final String breed;
  final String variety;
  final List<String> tattoos;

  const _MeatPenInput({
    required this.breed,
    required this.variety,
    required this.tattoos,
  });
}

class _MeatPenDialog extends StatefulWidget {
  const _MeatPenDialog({super.key});

  @override
  State<_MeatPenDialog> createState() => _MeatPenDialogState();
}

class _MeatPenDialogState extends State<_MeatPenDialog> {
  final _breedText = TextEditingController();
  final _varietyText = TextEditingController();

  final _breedFocus = FocusNode();
  final _varietyFocus = FocusNode();

  final _tattoo1 = TextEditingController();
  final _tattoo2 = TextEditingController();
  final _tattoo3 = TextEditingController();

  List<Map<String, dynamic>> _breedOptions = [];
  List<Map<String, dynamic>> _varietyOptions = [];

  String? _breedId;
  String? _msg;

  bool _loadingBreeds = true;
  bool _loadingVarieties = false;

  bool _isLopBreedName(String breedName) {
    return breedName.trim().toLowerCase().endsWith('lop');
  }

  bool get _hasValidBreedSelection {
    if (_breedId == null) return false;
    final breedName = _breedText.text.trim().toLowerCase();

    return _breedOptions.any((b) {
      return (b['id']?.toString() == _breedId) &&
          ((b['name'] ?? '').toString().trim().toLowerCase() == breedName);
    });
  }

  bool get _hasValidVarietySelection {
    final varietyName = _varietyText.text.trim().toLowerCase();
    if (varietyName.isEmpty) return false;

    return _varietyOptions.any((v) {
      return ((v['name'] ?? '').toString().trim().toLowerCase() ==
          varietyName);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadBreeds();

    _breedText.addListener(() {
      final typed = _breedText.text.trim().toLowerCase();

      if (typed.isEmpty) {
        if (_breedId != null ||
            _varietyText.text.isNotEmpty ||
            _varietyOptions.isNotEmpty) {
          setState(() {
            _breedId = null;
            _varietyOptions = [];
            _varietyText.clear();
            _msg = null;
          });
        }
        return;
      }

      final match = _breedOptions.where((b) {
        final name = (b['name'] ?? '').toString().trim().toLowerCase();
        return name == typed;
      }).toList();

      if (match.isNotEmpty) {
        final newId = (match.first['id'] ?? '').toString();
        if (newId.isNotEmpty && newId != _breedId) {
          _breedId = newId;
          _varietyText.clear();
          _loadVarietiesForBreed(newId);
        }
      } else {
        if (_breedId != null ||
            _varietyText.text.isNotEmpty ||
            _varietyOptions.isNotEmpty) {
          setState(() {
            _breedId = null;
            _varietyOptions = [];
            _varietyText.clear();
            _msg = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _breedText.dispose();
    _varietyText.dispose();
    _breedFocus.dispose();
    _varietyFocus.dispose();
    _tattoo1.dispose();
    _tattoo2.dispose();
    _tattoo3.dispose();
    super.dispose();
  }

  Future<void> _loadBreeds() async {
    setState(() {
      _loadingBreeds = true;
    });

    final res = await supabase
        .from('breeds')
        .select('id,name,species')
        .eq('species', 'rabbit')
        .order('name');

    if (!mounted) return;

    setState(() {
      _breedOptions = (res as List).cast<Map<String, dynamic>>();
      _loadingBreeds = false;
    });
  }

  Future<void> _loadVarietiesForBreed(String breedId) async {
    setState(() {
      _loadingVarieties = true;
      _varietyOptions = [];
    });

    final matchedBreed = _breedOptions.firstWhere(
      (b) => (b['id'] ?? '').toString() == breedId,
      orElse: () => <String, dynamic>{},
    );

    final breedName = (matchedBreed['name'] ?? '').toString().trim();

    if (_isLopBreedName(breedName)) {
      if (!mounted) return;
      setState(() {
        _loadingVarieties = false;
        _varietyOptions = const [
          {'id': 'lop_broken', 'name': 'Broken'},
          {'id': 'lop_solid', 'name': 'Solid'},
        ];
      });
      return;
    }

    final res = await supabase
        .from('varieties')
        .select('id,name')
        .eq('breed_id', breedId)
        .order('name');

    if (!mounted) return;
    setState(() {
      _varietyOptions = (res as List).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      _loadingVarieties = false;
    });
  }

  Future<void> _save() async {
    final breed = _breedText.text.trim();
    final variety = _varietyText.text.trim();
    final t1 = _tattoo1.text.trim().toUpperCase();
    final t2 = _tattoo2.text.trim().toUpperCase();
    final t3 = _tattoo3.text.trim().toUpperCase();

    if (breed.isEmpty) {
      setState(() => _msg = 'Breed is required.');
      return;
    }

    if (!_hasValidBreedSelection) {
      setState(() => _msg = 'Please select a valid breed from the list.');
      return;
    }

    if (variety.isEmpty) {
      setState(() => _msg = 'Variety is required.');
      return;
    }

    if (!_hasValidVarietySelection) {
      setState(() => _msg = 'Please select a valid variety from the list.');
      return;
    }

    if (t1.isEmpty || t2.isEmpty || t3.isEmpty) {
      setState(() => _msg = 'All 3 tattoos are required.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 10));

    if (!mounted) return;

    Navigator.pop(
      context,
      _MeatPenInput(
        breed: breed,
        variety: variety,
        tattoos: [t1, t2, t3],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Meat Pen'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All 3 rabbits must be the same breed and variety. Weight verified at show.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_loadingBreeds) const LinearProgressIndicator(),
              _FocusOpenAutocomplete(
                textController: _breedText,
                focusNode: _breedFocus,
                labelText: 'Breed (required)',
                hintText: 'Type to search and select a breed…',
                options: _breedOptions,
                displayStringForOption: (opt) => (opt['name'] ?? '').toString(),
                onSelectedAsync: (opt) async {
                  setState(() {
                    _breedId = (opt['id'] ?? '').toString();
                    _breedText.text = (opt['name'] ?? '').toString();
                    _msg = null;
                  });
                  await _loadVarietiesForBreed(_breedId!);
                  if (mounted) {
                    FocusScope.of(context).requestFocus(_varietyFocus);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_breedId != null && _loadingVarieties)
                const LinearProgressIndicator(),
              _FocusOpenAutocomplete(
                textController: _varietyText,
                focusNode: _varietyFocus,
                labelText: 'Variety (required)',
                hintText: _breedId == null
                    ? 'Select a breed first'
                    : 'Type to search and select a variety…',
                options: _breedId == null ? const [] : _varietyOptions,
                displayStringForOption: (opt) => (opt['name'] ?? '').toString(),
                enabled: _breedId != null,
                readOnly: _breedId == null,
                onSelected: (_) {
                  setState(() {
                    _msg = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tattoo1,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(labelText: 'Tattoo 1'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tattoo2,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(labelText: 'Tattoo 2'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tattoo3,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(labelText: 'Tattoo 3'),
              ),
              if (_msg != null) ...[
                const SizedBox(height: 10),
                Text(
                  _msg!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            await Future.delayed(const Duration(milliseconds: 10));
            if (!mounted) return;
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FocusOpenAutocomplete extends StatefulWidget {
  final TextEditingController textController;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final List<Map<String, dynamic>> options;
  final String Function(Map<String, dynamic>) displayStringForOption;
  final Future<void> Function(Map<String, dynamic>)? onSelectedAsync;
  final void Function(Map<String, dynamic>)? onSelected;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onFieldTap;
  final Widget? suffixIcon;

  const _FocusOpenAutocomplete({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.options,
    required this.displayStringForOption,
    this.onSelectedAsync,
    this.onSelected,
    this.enabled = true,
    this.readOnly = false,
    this.onFieldTap,
    this.suffixIcon,
  });

  @override
  State<_FocusOpenAutocomplete> createState() => _FocusOpenAutocompleteState();
}

class _FocusOpenAutocompleteState extends State<_FocusOpenAutocomplete> {
  List<Map<String, dynamic>> _lastOptions = const [];
  int _highlightedIndex = 0;
  void Function(Map<String, dynamic>)? _rawOnSelected;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _FocusOpenAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocus);
      widget.focusNode.addListener(_handleFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  void _handleFocus() {
    if (widget.focusNode.hasFocus) {
      _openOptions();
    }
  }

  void _openOptions() {
    if (!widget.enabled || widget.readOnly) return;

    final currentText = widget.textController.text;
    final currentSelection = widget.textController.selection;

    widget.textController.value = TextEditingValue(
      text: '$currentText ',
      selection: TextSelection.collapsed(offset: currentText.length + 1),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      widget.textController.value = TextEditingValue(
        text: currentText,
        selection: currentSelection.isValid
            ? currentSelection
            : TextSelection.collapsed(offset: currentText.length),
      );
    });
  }

  void _commitHighlightedOption() {
    if (_lastOptions.isEmpty || _rawOnSelected == null) return;
    final index = _highlightedIndex.clamp(0, _lastOptions.length - 1);
    _rawOnSelected!(_lastOptions[index]);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: widget.textController,
      focusNode: widget.focusNode,
      displayStringForOption: widget.displayStringForOption,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!widget.enabled || widget.readOnly) {
          _lastOptions = const [];
          _highlightedIndex = 0;
          return const Iterable<Map<String, dynamic>>.empty();
        }

        final q = textEditingValue.text.trim().toLowerCase();

        final results = widget.options.where((opt) {
          final label = widget.displayStringForOption(opt).trim().toLowerCase();
          return q.isEmpty || label.contains(q);
        }).toList()
          ..sort((a, b) {
            final aSort = a['sort_order'];
            final bSort = b['sort_order'];

            if (aSort != null || bSort != null) {
              final ai = aSort is int
                  ? aSort
                  : int.tryParse(aSort?.toString() ?? '') ?? 9999;
              final bi = bSort is int
                  ? bSort
                  : int.tryParse(bSort?.toString() ?? '') ?? 9999;

              final cmp = ai.compareTo(bi);
              if (cmp != 0) return cmp;
            }

            final aLabel = widget.displayStringForOption(a).toLowerCase();
            final bLabel = widget.displayStringForOption(b).toLowerCase();
            return aLabel.compareTo(bLabel);
          });

        _lastOptions = List<Map<String, dynamic>>.from(results);
        if (_highlightedIndex >= _lastOptions.length) {
          _highlightedIndex = 0;
        }

        return results;
      },
      onSelected: (opt) async {
        final label = widget.displayStringForOption(opt);

        widget.textController.value = TextEditingValue(
          text: label,
          selection: TextSelection.collapsed(offset: label.length),
        );

        widget.onSelected?.call(opt);

        if (widget.onSelectedAsync != null) {
          await widget.onSelectedAsync!(opt);
        }
      },
      fieldViewBuilder: (
        context,
        textEditingController,
        focusNode,
        onFieldSubmitted,
      ) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;

            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                _lastOptions.isNotEmpty) {
              setState(() {
                _highlightedIndex =
                    (_highlightedIndex + 1) % _lastOptions.length;
              });
              return KeyEventResult.handled;
            }

            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                _lastOptions.isNotEmpty) {
              setState(() {
                _highlightedIndex =
                    (_highlightedIndex - 1 + _lastOptions.length) %
                        _lastOptions.length;
              });
              return KeyEventResult.handled;
            }

            if ((event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.tab) &&
                _lastOptions.isNotEmpty) {
              _commitHighlightedOption();
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: textEditingController,
            focusNode: focusNode,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            textInputAction: TextInputAction.next,
            onTap: () {
              widget.onFieldTap?.call();
              _openOptions();
            },
            onSubmitted: (_) => onFieldSubmitted(),
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              suffixIcon: widget.suffixIcon,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();
        _rawOnSelected = onSelected;

        if (opts.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
                maxHeight: 240,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, index) {
                  final opt = opts[index];
                  final label = widget.displayStringForOption(opt);
                  final isHighlighted = index == _highlightedIndex;

                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Container(
                      color:
                          isHighlighted ? Theme.of(context).highlightColor : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight:
                              isHighlighted ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}