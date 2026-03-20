// lib/screens/enter_show_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  DateTime? _showDate;

  /// lower(breedName) -> 'four' or 'six'
  final Map<String, String> _rabbitBreedClassSystem = {};

  // --- Show settings caches ---
  bool _showHasBreedRows = false;
  final Set<String> _enabledRabbitBreeds = {};
  final Set<String> _enabledCavyBreeds = {};

  // For each breed name (lower): if show has any variety overrides for that breed
  final Set<String> _breedHasVarietyOverrides = {};

  // Allowed varieties by breed name (lower) from show overrides:
  final Map<String, Set<String>> _allowedVarietiesByBreedLower = {};

  // ------------------------------
  // Section multi-select state
  // ------------------------------
  final Set<String> _selectedSectionIds = {};
  String? _lockedSectionKind; // 'open' | 'youth'

  // ------------------------------
  // Exhibitor selection state
  // ------------------------------
  List<Map<String, dynamic>> _exhibitors = [];
  String? _selectedExhibitorId;

  // ------------------------------
  // Cart / existing entry state
  // ------------------------------
  String? _activeCartId;
  final Set<String> _animalIdsInCart = {};
  final Set<String> _animalIdsAlreadyEnteredForShow = {};

  // ------------------------------
  // Collapse / expand state
  // ------------------------------
  final Set<String> _collapsedBreeds = {};
  final Set<String> _collapsedVarieties = {};

  late final Future<_EnterShowLoadBundle> _loadFuture;

  TextEditingController _classControllerFor(String animalId) {
    return _classControllers.putIfAbsent(animalId, () => TextEditingController());
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

  Future<_EnterShowLoadBundle> _loadAll() async {
    await _loadShowContext();
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

  // ------------------------------
  // Exhibitors
  // ------------------------------
  Future<List<Map<String, dynamic>>> _loadActiveExhibitors() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final rows = await supabase
        .from('exhibitors')
        .select('id,showing_name,display_name,type,is_active,created_at')
        .eq('owner_user_id', user.id)
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

  bool _isExhibitorAllowedForKind(
    Map<String, dynamic> exhibitor,
    String? sectionKind,
  ) {
    if (sectionKind == 'youth') {
      return _isYouthExhibitor(exhibitor);
    }

    return true;
  }

  List<Map<String, dynamic>> _allowedExhibitorsForCurrentSectionKind(
    List<Map<String, dynamic>> exhibitors,
  ) {
    return exhibitors
        .where((e) => _isExhibitorAllowedForKind(e, _lockedSectionKind))
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

    if (!_isExhibitorAllowedForKind(exhibitor, _lockedSectionKind)) {
      _selectedExhibitorId = null;
    }
  }

  // ------------------------------
  // Cart loaders
  // ------------------------------
  Future<void> _loadActiveCartIdIfExists() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _activeCartId = null;
      return;
    }

    final existing = await supabase
        .from('entry_carts')
        .select('id')
        .eq('show_id', widget.showId)
        .eq('user_id', user.id)
        .eq('status', 'active')
        .maybeSingle();

    _activeCartId = existing == null ? null : existing['id'].toString();
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

  Future<void> _refreshAnimalsAlreadyEnteredForShow(List<Map<String, dynamic>> animals) async {
    _animalIdsAlreadyEnteredForShow.clear();

    final animalIds = animals
        .map((a) => (a['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (animalIds.isEmpty) return;

    final rows = await supabase
        .from('entries')
        .select('animal_id')
        .eq('show_id', widget.showId)
        .inFilter('animal_id', animalIds);

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final aid = r['animal_id']?.toString();
      if (aid != null && aid.isNotEmpty) {
        _animalIdsAlreadyEnteredForShow.add(aid);
      }
    }
  }

  bool _isAnimalInCart(String animalId) => _animalIdsInCart.contains(animalId);

  bool _isAnimalAlreadyEntered(String animalId) {
    return _animalIdsAlreadyEnteredForShow.contains(animalId);
  }

  // ------------------------------
  // Loading show rules + settings
  // ------------------------------
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
        .select('id,name,species,class_system,is_active')
        .eq('is_active', true)
        .order('name');

    final breedRows = (breeds as List).cast<Map<String, dynamic>>();
    final Map<String, Map<String, dynamic>> breedById = {
      for (final b in breedRows) (b['id'] as String): b,
    };

    _rabbitBreedClassSystem.clear();
    for (final b in breedRows) {
      final species = (b['species'] ?? '').toString();
      if (species != 'rabbit') continue;
      final name = (b['name'] ?? '').toString().trim();
      final cs = (b['class_system'] ?? 'four').toString();
      if (name.isNotEmpty) _rabbitBreedClassSystem[name.toLowerCase()] = cs;
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
        _allowedVarietiesByBreedLower.putIfAbsent(breedLower, () => <String>{});

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
        .select('id,kind,letter,display_name,sort_order')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true)
        .order('sort_order');
    return rows.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _loadAnimals() async {
    final res = await supabase
        .from('animals')
        .select('id,species,name,tattoo,breed,variety,sex,birth_date')
        .order('created_at', ascending: false);

    return (res as List).cast<Map<String, dynamic>>();
  }

  bool _breedAllowed(String species, String breedName) {
    final b = breedName.trim().toLowerCase();
    if (b.isEmpty) return false;
    if (species == 'rabbit') return _enabledRabbitBreeds.contains(b);
    if (species == 'cavy') return _enabledCavyBreeds.contains(b);
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

  // ------------------------------
  // Class suggestion logic
  // ------------------------------
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
    required DateTime birthDate,
    required DateTime showDate,
  }) {
    final months = _ageInMonthsApprox(birthDate, showDate);
    final classSystem = _rabbitBreedClassSystem[breedName.trim().toLowerCase()] ?? 'four';

    if (months < 6.0) return 'Jr';
    if (classSystem == 'six') {
      if (months <= 8.0) return 'Int';
      return 'Sr';
    }
    return 'Sr';
  }

  String? _suggestClassForAnimal(Map<String, dynamic> a) {
    final species = (a['species'] ?? '').toString();
    if (_showDate == null) return null;

    final bdRaw = a['birth_date']?.toString();
    final birthDate = bdRaw == null ? null : DateTime.tryParse(bdRaw);
    if (birthDate == null) return null;

    final sex = _sexLabel(species, a['sex']?.toString());

    if (species == 'rabbit') {
      final breed = (a['breed'] ?? '').toString();
      if (breed.trim().isEmpty) return null;
      final div = _suggestRabbitDivision(
        breedName: breed,
        birthDate: birthDate,
        showDate: _showDate!,
      );
      return div == 'Jr'
          ? 'Junior'
          : div == 'Int'
              ? 'Intermediate'
              : 'Senior';
    }

    return 'Open $sex';
  }

  void _toggleSelected(Map<String, dynamic> animal, bool isSelected) {
    final id = animal['id'] as String;

    if (_isAnimalInCart(id) || _isAnimalAlreadyEntered(id)) return;

    setState(() {
      _selected[id] = isSelected;
      _msg = null;
    });

    if (isSelected) {
      final ctrl = _classControllerFor(id);
      if (ctrl.text.trim().isEmpty) {
        final suggestion = _suggestClassForAnimal(animal);
        if (suggestion != null) ctrl.text = suggestion;
      }
    }
  }

  void _toggleManySelected(List<Map<String, dynamic>> animals, bool isSelected) {
    setState(() {
      _msg = null;
      for (final animal in animals) {
        final id = animal['id'] as String;
        if (_isAnimalInCart(id) || _isAnimalAlreadyEntered(id)) continue;

        _selected[id] = isSelected;

        if (isSelected) {
          final ctrl = _classControllerFor(id);
          if (ctrl.text.trim().isEmpty) {
            final suggestion = _suggestClassForAnimal(animal);
            if (suggestion != null) ctrl.text = suggestion;
          }
        }
      }
    });
  }

  // ------------------------------
  // Section picker behavior
  // ------------------------------
  void _clearSectionSelection() {
    setState(() {
      _selectedSectionIds.clear();
      _lockedSectionKind = null;
      _msg = null;
    });
  }

  void _toggleSection({
    required String sectionId,
    required String kind,
  }) {
    setState(() {
      _msg = null;

      if (_lockedSectionKind == null) {
        _lockedSectionKind = kind;
      }

      if (_lockedSectionKind != kind) {
        _msg = 'You can’t mix Open and Youth. Clear selection to switch.';
        return;
      }

      if (_selectedSectionIds.contains(sectionId)) {
        _selectedSectionIds.remove(sectionId);
        if (_selectedSectionIds.isEmpty) _lockedSectionKind = null;
      } else {
        _selectedSectionIds.add(sectionId);
      }
    });
  }

  // ------------------------------
  // Add to cart
  // ------------------------------
  Future<void> _addSelectedToCart(List<Map<String, dynamic>> eligibleAnimals) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    if (_exhibitors.isEmpty) {
      setState(() => _msg = 'No active exhibitors found. Add one in Account Settings first.');
      return;
    }
    if (_selectedExhibitorId == null) {
      setState(() => _msg = 'Select an exhibitor.');
      return;
    }
    if (_selectedSectionIds.isEmpty || _lockedSectionKind == null) {
      setState(() => _msg = 'Select one or more sections (Open A/B… or Youth A/B…).');
      return;
    }

    final chosen = eligibleAnimals.where((a) => _selected[a['id']] == true).toList();
    if (chosen.isEmpty) {
      setState(() => _msg = 'Select at least one animal.');
      return;
    }

    for (final a in chosen) {
      final id = a['id'] as String;
      if (_isAnimalInCart(id)) {
        setState(() => _msg = 'One or more selected animals are already in the cart.');
        return;
      }
      if (_isAnimalAlreadyEntered(id)) {
        setState(() => _msg = 'One or more selected animals are already entered in this show.');
        return;
      }
    }

    for (final a in chosen) {
      final cls = _classControllerFor(a['id'] as String).text.trim();
      if (cls.isEmpty) {
        setState(() => _msg = 'Class is required for all selected entries.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _msg = null;
    });

    try {
      final cartId = await _getOrCreateActiveCartId(showId: widget.showId, userId: user.id);
      _activeCartId = cartId;

      final List<Map<String, dynamic>> itemsToAdd = [];
      for (final a in chosen) {
        final String animalId = a['id'] as String;
        final String className = _classControllerFor(animalId).text.trim();

        for (final sectionId in _selectedSectionIds) {
          itemsToAdd.add({
            'cart_id': cartId,
            'section_id': sectionId,
            'animal_id': animalId,
            'exhibitor_id': _selectedExhibitorId,
            'species': a['species'],
            'tattoo': a['tattoo'],
            'breed': a['breed'],
            'variety': a['variety'],
            'sex': a['sex'],
            'class_name': className,
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
          _selected[a['id'] as String] = false;
        }
        _selectedSectionIds.clear();
        _lockedSectionKind = null;
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
      await _refreshAnimalsAlreadyEnteredForShow(bundleAnimalsFallback(chosen, eligibleAnimals));
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Add to cart failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<Map<String, dynamic>> bundleAnimalsFallback(
    List<Map<String, dynamic>> chosen,
    List<Map<String, dynamic>> eligibleAnimals,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final a in eligibleAnimals) {
      map[(a['id'] ?? '').toString()] = a;
    }
    for (final a in chosen) {
      map[(a['id'] ?? '').toString()] = a;
    }
    return map.values.toList();
  }

  Future<void> _viewCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    final cartId = await _getOrCreateActiveCartId(showId: widget.showId, userId: user.id);
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
    if (mounted) setState(() {});
  }

  // ------------------------------
  // Sorting / grouping helpers
  // ------------------------------
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
      final speciesCmp = _speciesRank(_safeString(a, 'species'))
          .compareTo(_speciesRank(_safeString(b, 'species')));
      if (speciesCmp != 0) return speciesCmp;

      final breedCmp = _safeString(a, 'breed').toLowerCase().compareTo(
            _safeString(b, 'breed').toLowerCase(),
          );
      if (breedCmp != 0) return breedCmp;

      final varietyCmp = _safeString(a, 'variety').toLowerCase().compareTo(
            _safeString(b, 'variety').toLowerCase(),
          );
      if (varietyCmp != 0) return varietyCmp;

      final titleCmp = _displayAnimalTitle(a).toLowerCase().compareTo(
            _displayAnimalTitle(b).toLowerCase(),
          );
      if (titleCmp != 0) return titleCmp;

      return _safeString(a, 'tattoo').toLowerCase().compareTo(
            _safeString(b, 'tattoo').toLowerCase(),
          );
    });

    return list;
  }

  bool _allSelectableChecked(List<Map<String, dynamic>> animals) {
    final selectable = animals
        .where((a) =>
            !_isAnimalInCart((a['id'] ?? '').toString()) &&
            !_isAnimalAlreadyEntered((a['id'] ?? '').toString()))
        .toList();
    if (selectable.isEmpty) return false;
    return selectable.every((a) => _selected[a['id']] == true);
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _groupEligibleAnimals(
    List<Map<String, dynamic>> animals,
  ) {
    final sorted = _sortAnimals(animals);

    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

    for (final animal in sorted) {
      final breed = _safeString(animal, 'breed').isEmpty ? '(No Breed)' : _safeString(animal, 'breed');
      final variety = _safeString(animal, 'variety').isEmpty ? '(No Variety)' : _safeString(animal, 'variety');

      grouped.putIfAbsent(breed, () => <String, List<Map<String, dynamic>>>{});
      grouped[breed]!.putIfAbsent(variety, () => <Map<String, dynamic>>[]);
      grouped[breed]![variety]!.add(animal);
    }

    return grouped;
  }

  String _breedCollapseKey(String breedName) => breedName.trim().toLowerCase();

  String _varietyCollapseKey(String breedName, String varietyName) =>
      '${breedName.trim().toLowerCase()}__${varietyName.trim().toLowerCase()}';

  bool _isBreedCollapsed(String breedName) {
    return _collapsedBreeds.contains(_breedCollapseKey(breedName));
  }

  bool _isVarietyCollapsed(String breedName, String varietyName) {
    return _collapsedVarieties.contains(_varietyCollapseKey(breedName, varietyName));
  }

  void _toggleBreedCollapsed(String breedName) {
    final key = _breedCollapseKey(breedName);
    setState(() {
      if (_collapsedBreeds.contains(key)) {
        _collapsedBreeds.remove(key);
      } else {
        _collapsedBreeds.add(key);
      }
    });
  }

  void _toggleVarietyCollapsed(String breedName, String varietyName) {
    final key = _varietyCollapseKey(breedName, varietyName);
    setState(() {
      if (_collapsedVarieties.contains(key)) {
        _collapsedVarieties.remove(key);
      } else {
        _collapsedVarieties.add(key);
      }
    });
  }

  Widget _buildAnimalTile(Map<String, dynamic> a) {
    final id = a['id'] as String;
    final checked = _selected[id] ?? false;
    final inCart = _isAnimalInCart(id);
    final alreadyEntered = _isAnimalAlreadyEntered(id);
    final disabled = inCart || alreadyEntered;

    final tile = ListTile(
      leading: Checkbox(
        value: checked,
        onChanged: (_submitting || disabled) ? null : (v) => _toggleSelected(a, v ?? false),
      ),
      title: Text(_displayAnimalTitle(a)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_safeString(a, 'species').toUpperCase()} • ${_safeString(a, 'breed')} • ${_safeString(a, 'variety')} • ${_safeString(a, 'sex')}',
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _classControllerFor(id),
            enabled: !_submitting && !disabled,
            decoration: InputDecoration(
              labelText: 'Class (required if selected)',
              hintText: 'Example: Jr Buck, Sr Doe, Int Buck, Open Boar',
              helperText: alreadyEntered
                  ? 'Already entered in this show'
                  : (inCart ? 'Already in cart' : null),
            ),
          ),
        ],
      ),
      isThreeLine: true,
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

  @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 70,
          titleSpacing: 0,
          title: Row(
            children: [
              const SizedBox(width: 12),
              Image.asset(
                'assets/images/ringmaster_show_logo.png',
                height: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.showName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        body: Container(
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

          child: FutureBuilder<_EnterShowLoadBundle>(
            future: _loadFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snap.error}',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }

              final bundle = snap.data!;
              final allAnimals = bundle.animals;
              final sections = bundle.sections;

              _exhibitors = bundle.exhibitors;

              final allowedExhibitors = _allowedExhibitorsForCurrentSectionKind(_exhibitors);

              if (_selectedExhibitorId == null && allowedExhibitors.isNotEmpty) {
                _selectedExhibitorId = allowedExhibitors.first['id'].toString();
              }

              final showDateText = _showDate == null
                  ? '(show date missing)'
                  : _showDate!.toIso8601String().substring(0, 10);

              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F6FB),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [

                    /// HEADER CARD
                    Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.05),
                            blurRadius: 10,
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Show Date: $showDateText',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),

                          DropdownButtonFormField<String>(
                            value: _selectedExhibitorId,
                            decoration: const InputDecoration(
                              labelText: 'Exhibitor',
                              border: OutlineInputBorder(),
                            ),
                            items: allowedExhibitors.map((e) {
                              return DropdownMenuItem(
                                value: e['id'].toString(),
                                child: Text(_exhibitorLabel(e)),
                              );
                            }).toList(),
                            onChanged: _submitting
                                ? null
                                : (v) => setState(() => _selectedExhibitorId = v),
                          ),

                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _viewCart,
                                  icon: const Icon(Icons.shopping_cart_outlined),
                                  label: const Text('View Cart'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    /// SECTIONS
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: sections.map((s) {
                          final id = s['id'].toString();
                          final selected = _selectedSectionIds.contains(id);

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(s['display_name']),
                              selected: selected,
                              selectedColor: const Color(0xFFD4A623),
                              onSelected: (_) => _toggleSection(
                                sectionId: id,
                                kind: s['kind'],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _msg!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    /// ANIMALS LIST
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: _sortAnimals(allAnimals).map((a) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.04),
                                  blurRadius: 8,
                                )
                              ],
                            ),
                            child: _buildAnimalTile(a),
                          );
                        }).toList(),
                      ),
                    ),

                    /// ADD TO CART
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A623),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _addSelectedToCart(_sortAnimals(allAnimals)),
                          child: Text(_submitting ? 'Saving…' : 'Add Selected to Cart'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
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