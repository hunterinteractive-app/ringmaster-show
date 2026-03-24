//lib/screens/enter_show_screen.dart

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/widgets/exhibitor_builder_dialog.dart';

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

  final Map<String, String> _rabbitBreedClassSystem = {};

  bool _showHasBreedRows = false;
  final Set<String> _enabledRabbitBreeds = {};
  final Set<String> _enabledCavyBreeds = {};

  final Set<String> _breedHasVarietyOverrides = {};
  final Map<String, Set<String>> _allowedVarietiesByBreedLower = {};

  final Set<String> _selectedSectionIds = {};
  final Map<String, Map<String, dynamic>> _sectionById = {};

  List<Map<String, dynamic>> _exhibitors = [];
  String? _selectedExhibitorId;

  String? _activeCartId;
  final Set<String> _animalIdsInCart = {};
  final Set<String> _animalIdsAlreadyEnteredForShow = {};

  Future<_EnterShowLoadBundle>? _loadFuture;

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
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _InlineAnimalEditorDialog(),
    );

    if (saved == true) {
      await _reloadAll();
    }
  }

  Future<void> _openAddExhibitorDialog() async {
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

  bool _isSixClassBreed(String breedName) {
    final classSystem =
        _rabbitBreedClassSystem[breedName.trim().toLowerCase()] ?? 'four';
    return classSystem == 'six';
  }

  List<String> _allowedClassOptionsForAnimal(Map<String, dynamic> animal) {
    final species = (animal['species'] ?? '').toString().trim().toLowerCase();
    final breed = (animal['breed'] ?? '').toString().trim();

    if (species == 'rabbit') {
      if (_isSixClassBreed(breed)) {
        return const ['Junior', 'Intermediate', 'Senior'];
      }
      return const ['Junior', 'Senior'];
    }

    return const ['Open Boar', 'Open Sow'];
  }

  Future<void> _editProjectedClass(Map<String, dynamic> animal) async {
    final animalId = (animal['id'] ?? '').toString();
    final options = _allowedClassOptionsForAnimal(animal);

    if (options.isEmpty) return;

    final current = _classControllerFor(animalId).text.trim();
    String selectedValue = options.contains(current) ? current : options.first;

    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Class'),
        content: StatefulBuilder(
          builder: (context, setLocalState) {
            return DropdownButtonFormField<String>(
              value: selectedValue,
              items: options
                  .map(
                    (opt) => DropdownMenuItem<String>(
                      value: opt,
                      child: Text(opt),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setLocalState(() {
                  selectedValue = v;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selectedValue),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != null) {
      setState(() {
        _classControllerFor(animalId).text = saved;
      });
    }
  }

  Future<void> _viewCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    final cartId = await _getOrCreateActiveCartId(
      showId: widget.showId,
      userId: user.id,
    );

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

  Future<void> _refreshAnimalsAlreadyEnteredForShow(
    List<Map<String, dynamic>> animals,
  ) async {
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
        .select('id,kind,letter,display_name,sort_order')
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
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final res = await supabase
        .from('animals')
        .select(
          'id,species,name,tattoo,breed,variety,sex,birth_date,is_dob_unknown',
        )
        .eq('owner_user_id', user.id)
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
    required DateTime birthDate,
    required DateTime showDate,
  }) {
    final months = _ageInMonthsApprox(birthDate, showDate);
    final classSystem =
        _rabbitBreedClassSystem[breedName.trim().toLowerCase()] ?? 'four';

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

    final isDobUnknown = a['is_dob_unknown'] == true;
    if (isDobUnknown) return null;

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

  String _classDisplayForAnimal(Map<String, dynamic> animal) {
    final animalId = (animal['id'] ?? '').toString();
    final controller = _classControllerFor(animalId);
    final manualValue = controller.text.trim();

    if (manualValue.isNotEmpty) {
      final suggested = _suggestClassForAnimal(animal);
      if (suggested != null && suggested == manualValue) {
        return 'Projected Class: $manualValue';
      }
      return 'Class: $manualValue';
    }

    final suggested = _suggestClassForAnimal(animal);
    if (suggested != null && suggested.isNotEmpty) {
      controller.text = suggested;
      return 'Projected Class: $suggested';
    }

    return 'Class: Needs Validation';
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
        if (suggestion != null && suggestion.isNotEmpty) {
          ctrl.text = suggestion;
        }
      }
    }
  }

  void _clearSectionSelection() {
    setState(() {
      _selectedSectionIds.clear();
      _msg = null;
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
      } else {
        _selectedSectionIds.add(sectionId);
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

    if (_selectedSectionIds.isEmpty) {
      errors.add('Select at least one section.');
      return errors;
    }

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
        errors.add('$title is not eligible because "$breed" is not enabled for this show.');
      }

      if (variety.isEmpty) {
        errors.add('$title is missing a variety.');
      } else if (!_varietyAllowed(breed, variety)) {
        errors.add(
          '$title is not eligible because "$variety" is not an allowed variety for $breed at this show.',
        );
      }

      if (_isAnimalInCart(animalId)) {
        errors.add('$title is already in the cart.');
      }

      if (_isAnimalAlreadyEntered(animalId)) {
        errors.add('$title is already entered in this show.');
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
                  (a) => Text(
                    '• ${_displayAnimalTitle(a)} — ${_classControllerFor((a['id'] ?? '').toString()).text.trim()}',
                  ),
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
    final user = supabase.auth.currentUser;
    if (user == null) {
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
        userId: user.id,
      );
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
            'class_name': className.isNotEmpty ? className : null,
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
      final speciesCmp = _speciesRank(_safeString(a, 'species'))
          .compareTo(_speciesRank(_safeString(b, 'species')));
      if (speciesCmp != 0) return speciesCmp;

      final breedCmp = _safeString(a, 'breed')
          .toLowerCase()
          .compareTo(_safeString(b, 'breed').toLowerCase());
      if (breedCmp != 0) return breedCmp;

      final varietyCmp = _safeString(a, 'variety')
          .toLowerCase()
          .compareTo(_safeString(b, 'variety').toLowerCase());
      if (varietyCmp != 0) return varietyCmp;

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
    final alreadyEntered = _isAnimalAlreadyEntered(id);
    final disabled = inCart || alreadyEntered;

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
          const SizedBox(height: 6),
          Row(
            children: [
              Builder(
                builder: (context) {
                  final classLabel = _classDisplayForAnimal(a);
                  final needsValidation =
                      classLabel == 'Class: Needs Validation';

                  return Expanded(
                    child: Text(
                      classLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: needsValidation ? Colors.red : null,
                            fontWeight:
                                needsValidation ? FontWeight.w600 : null,
                          ),
                    ),
                  );
                },
              ),
              TextButton(
                onPressed: (_submitting || disabled)
                    ? null
                    : () => _editProjectedClass(a),
                child: const Text('Change'),
              ),
            ],
          ),
          if (alreadyEntered || inCart)
            Text(
              alreadyEntered
                  ? 'Already entered in this show'
                  : 'Already in cart',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
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
    return FutureBuilder<_EnterShowLoadBundle>(
      future: _loadFuture,
      builder: (context, snap) {
        return RingMasterPageShell(
          title: widget.showName,
          subtitle: 'Enter Show',
          showBackButton: true,
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
                                  onPressed:
                                      _submitting ? null : _openAddExhibitorDialog,
                                  icon: const Icon(Icons.person_add_alt_1),
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
                                OutlinedButton.icon(
                                  onPressed: _openAddAnimalDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Animal'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _viewCart,
                                  icon: const Icon(Icons.shopping_cart_outlined),
                                  label: const Text('View Cart'),
                                ),
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
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: sections.map((s) {
                            final id = s['id'].toString();
                            final selected = _selectedSectionIds.contains(id);

                            return FilterChip(
                              label: Text(_sectionChipLabel(s)),
                              selected: selected,
                              onSelected: _submitting
                                  ? null
                                  : (_) => _toggleSection(
                                        sectionId: id,
                                        kind: (s['kind'] ?? '').toString(),
                                      ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                    Expanded(
                      child: animals.isEmpty
                          ? const Center(child: Text('No animals found.'))
                          : ListView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
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

class _InlineAnimalEditorDialog extends StatefulWidget {
  const _InlineAnimalEditorDialog();

  @override
  State<_InlineAnimalEditorDialog> createState() =>
      _InlineAnimalEditorDialogState();
}

class _InlineAnimalEditorDialogState extends State<_InlineAnimalEditorDialog> {
  final _name = TextEditingController();
  final _tattoo = TextEditingController();
  final _breedText = TextEditingController();
  final _varietyText = TextEditingController();
  final _sexText = TextEditingController();

  final _nameFocus = FocusNode();
  final _tattooFocus = FocusNode();
  final _breedFocus = FocusNode();
  final _varietyFocus = FocusNode();
  final _sexFocus = FocusNode();

  String _species = 'rabbit';
  String? _sexValue;
  DateTime? _birthDate;
  bool _isDobUnknown = false;
  String? _breedId;

  List<Map<String, dynamic>> _breedOptions = [];
  List<Map<String, dynamic>> _varietyOptions = [];

  bool _loadingBreeds = false;
  bool _loadingVarieties = false;
  bool _saving = false;
  String? _msg;

  bool _isLopBreedName(String breedName) {
    return breedName.trim().toLowerCase().endsWith('lop');
  }

  List<String> get _sexOptions =>
      _species == 'rabbit' ? const ['Buck', 'Doe'] : const ['Boar', 'Sow'];

  bool get _hasValidBreedSelection {
    if (_breedId == null) return false;
    final breedName = _breedText.text.trim().toLowerCase();
    return _breedOptions.any((b) {
      return (b['id']?.toString() == _breedId) &&
          ((b['name'] ?? '').toString().trim().toLowerCase() == breedName);
    });
  }

  bool get _hasValidVarietySelection {
    if (!_hasValidBreedSelection) return false;
    final varietyName = _varietyText.text.trim().toLowerCase();
    if (varietyName.isEmpty) return false;
    return _varietyOptions.any((v) {
      return ((v['name'] ?? '').toString().trim().toLowerCase() == varietyName);
    });
  }

  bool get _hasValidSexSelection {
    final sexName = _sexText.text.trim().toLowerCase();
    if (sexName.isEmpty) return false;
    return _sexOptions.any((s) => s.toLowerCase() == sexName);
  }

  @override
  void initState() {
    super.initState();
    _sexValue = _sexOptions.first;
    _sexText.text = _sexValue ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBreedsForSpecies();
    });

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
          });
        }
        return;
      }

      final match = _breedOptions.where((b) {
        final name = (b['name'] as String).trim().toLowerCase();
        return name == typed;
      }).toList();

      if (match.isNotEmpty) {
        final newId = match.first['id'] as String;
        if (newId != _breedId) {
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
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _tattoo.dispose();
    _breedText.dispose();
    _varietyText.dispose();
    _sexText.dispose();

    _nameFocus.dispose();
    _tattooFocus.dispose();
    _breedFocus.dispose();
    _varietyFocus.dispose();
    _sexFocus.dispose();
    super.dispose();
  }

  Future<void> _loadBreedsForSpecies() async {
    setState(() => _loadingBreeds = true);

    final res = await supabase
        .from('breeds')
        .select('id,name')
        .eq('species', _species)
        .order('name');

    if (!mounted) return;
    setState(() {
      _breedOptions = (res as List)
          .cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
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
      _varietyOptions = (res as List)
          .cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      _loadingVarieties = false;
    });
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _isDobUnknown = false;
      });
    }
  }

  Future<void> _toggleUnknownDob(bool value) async {
    if (!value) {
      setState(() => _isDobUnknown = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unknown Date of Birth'),
        content: const Text(
          'You can continue without a date of birth. This rabbit’s class may need to be validated during show entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isDobUnknown = true;
        _birthDate = null;
      });
    }
  }

  bool _validate() {
    if (_species.trim().isEmpty) return false;
    if (_tattoo.text.trim().isEmpty) return false;
    if (_sexValue == null) return false;
    if (_birthDate == null && !_isDobUnknown) return false;
    if (_breedText.text.trim().isEmpty) return false;
    if (_varietyText.text.trim().isEmpty) return false;
    if (!_hasValidBreedSelection) return false;
    if (!_hasValidVarietySelection) return false;
    if (!_hasValidSexSelection) return false;
    return true;
  }

  Future<void> _save() async {
    if (_sexText.text.trim().isNotEmpty) {
      _sexValue = _sexText.text.trim();
    }

    if (_breedText.text.trim().isEmpty) {
      setState(() => _msg = 'Breed is required.');
      return;
    }

    if (!_hasValidBreedSelection) {
      setState(() => _msg = 'Please select a breed from the list.');
      return;
    }

    if (_varietyText.text.trim().isEmpty) {
      setState(() => _msg = 'Variety is required.');
      return;
    }

    if (!_hasValidVarietySelection) {
      setState(() => _msg = 'Please select a valid variety from the list.');
      return;
    }

    if (_sexText.text.trim().isEmpty) {
      setState(() => _msg = 'Sex is required.');
      return;
    }

    if (!_hasValidSexSelection) {
      setState(() => _msg = 'Please select a valid sex from the list.');
      return;
    }

    if (!_validate()) {
      setState(() => _msg =
          'Required: species, tattoo, sex, breed, and variety. Date of birth can be exact or marked unknown. (Name is optional)');
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    final payload = {
      'owner_user_id': user.id,
      'species': _species,
      'name': _name.text.trim().isEmpty ? null : _name.text.trim(),
      'tattoo': _tattoo.text.trim(),
      'breed': _breedText.text.trim(),
      'variety': _varietyText.text.trim(),
      'sex': _sexValue,
      'birth_date': _isDobUnknown
          ? null
          : _birthDate?.toIso8601String().substring(0, 10),
      'is_dob_unknown': _isDobUnknown,
    };

    try {
      await supabase.from('animals').insert(payload);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _msg = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalidBreedWarning =
        (!_hasValidBreedSelection && _breedText.text.trim().isNotEmpty)
            ? 'Choose a breed from the list.'
            : null;

    final invalidVarietyWarning =
        (_breedId != null &&
                _varietyText.text.trim().isNotEmpty &&
                !_hasValidVarietySelection)
            ? 'Choose a variety from the list.'
            : null;

    final invalidSexWarning =
        (_sexText.text.trim().isNotEmpty && !_hasValidSexSelection)
            ? 'Choose a sex from the list.'
            : null;

    return AlertDialog(
      title: const Text('Add Animal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _species,
              items: const [
                DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
              ],
              onChanged: (v) async {
                final newSpecies = v ?? 'rabbit';
                setState(() {
                  _species = newSpecies;
                  _sexValue = _sexOptions.first;
                  _sexText.text = _sexOptions.first;
                  _breedId = null;
                  _breedOptions = [];
                  _varietyOptions = [];
                  _breedText.clear();
                  _varietyText.clear();
                  _msg = null;
                });
                await _loadBreedsForSpecies();
              },
              decoration: const InputDecoration(labelText: 'Species (required)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_tattooFocus),
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            TextField(
              controller: _tattoo,
              focusNode: _tattooFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_breedFocus),
              decoration:
                  const InputDecoration(labelText: 'Tattoo / ID (required)'),
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
                  _breedId = opt['id'] as String;
                  _breedText.text = (opt['name'] as String);
                  _varietyText.clear();
                  _msg = null;
                });
                await _loadVarietiesForBreed(_breedId!);
                if (mounted) {
                  FocusScope.of(context).requestFocus(_varietyFocus);
                }
              },
            ),
            if (invalidBreedWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  invalidBreedWarning,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
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
              suffixIcon: _varietyText.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear variety',
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() {
                                _varietyText.clear();
                                _msg = null;
                              });
                            },
                      icon: const Icon(Icons.clear),
                    ),
              onSelected: (opt) {
                setState(() {
                  _varietyText.text = (opt['name'] as String);
                  _msg = null;
                });
                FocusScope.of(context).requestFocus(_sexFocus);
              },
            ),
            if (invalidVarietyWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  invalidVarietyWarning,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _FocusOpenAutocomplete(
              textController: _sexText,
              focusNode: _sexFocus,
              labelText: 'Sex (required)',
              hintText: _species == 'rabbit' ? 'Buck or Doe' : 'Boar or Sow',
              options: _sexOptions.map((s) => {'name': s}).toList(),
              displayStringForOption: (opt) => (opt['name'] ?? '').toString(),
              onSelected: (opt) {
                setState(() {
                  _sexValue = (opt['name'] ?? '').toString();
                  _sexText.text = _sexValue ?? '';
                  _msg = null;
                });
              },
            ),
            if (invalidSexWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  invalidSexWarning,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Exact date not required. This is only used to help project the correct class when entering shows.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isDobUnknown
                        ? 'Birth date: Unknown'
                        : 'Birth date: ${_birthDate == null ? "(optional)" : _birthDate!.toString().substring(0, 10)}',
                  ),
                ),
                TextButton(
                  onPressed:
                      (_saving || _isDobUnknown) ? null : _pickBirthDate,
                  child: const Text('Pick'),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unknown DOB'),
              value: _isDobUnknown,
              onChanged: _saving ? null : (v) => _toggleUnknownDob(v ?? false),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 8),
              Text(_msg!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Save & Add to Entry' : 'Save & Add to Entry'),
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
  late final TextEditingController _fieldController;

  bool _syncingFromExternal = false;
  bool _syncingToExternal = false;

  List<Map<String, dynamic>> _lastOptions = const [];
  int _highlightedIndex = 0;
  void Function(Map<String, dynamic>)? _rawOnSelected;

  @override
  void initState() {
    super.initState();
    _fieldController = TextEditingController(text: widget.textController.text);

    widget.textController.addListener(_handleExternalTextChanged);
    _fieldController.addListener(_handleFieldTextChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _FocusOpenAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_handleExternalTextChanged);
      widget.textController.addListener(_handleExternalTextChanged);

      _syncingFromExternal = true;
      _fieldController.value = widget.textController.value;
      _syncingFromExternal = false;
    }

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_handleExternalTextChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _fieldController.removeListener(_handleFieldTextChanged);
    _fieldController.dispose();
    super.dispose();
  }

  void _handleExternalTextChanged() {
    if (_syncingToExternal) return;
    if (_fieldController.text == widget.textController.text) return;

    _syncingFromExternal = true;
    _fieldController.value = widget.textController.value;
    _syncingFromExternal = false;
  }

  void _handleFieldTextChanged() {
    if (_syncingFromExternal) return;
    if (widget.textController.text == _fieldController.text) return;

    _syncingToExternal = true;
    widget.textController.value = _fieldController.value;
    _syncingToExternal = false;
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) return;
    if (!widget.enabled || widget.readOnly) return;
    _openOptions();
  }

  void _openOptions() {
    final currentText = _fieldController.text;
    final currentSelection = _fieldController.selection;

    _syncingToExternal = true;
    _fieldController.value = TextEditingValue(
      text: '$currentText ',
      selection: TextSelection.collapsed(offset: currentText.length + 1),
    );
    _syncingToExternal = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _syncingToExternal = true;
      _fieldController.value = TextEditingValue(
        text: currentText,
        selection: currentSelection.isValid
            ? currentSelection
            : TextSelection.collapsed(offset: currentText.length),
      );
      _syncingToExternal = false;

      widget.textController.value = _fieldController.value;
    });
  }

  void _commitHighlightedOption() {
    if (_lastOptions.isEmpty || _rawOnSelected == null) return;

    final index = _highlightedIndex.clamp(0, _lastOptions.length - 1);
    final selected = _lastOptions[index];
    _rawOnSelected!(selected);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: _fieldController,
      focusNode: widget.focusNode,
      displayStringForOption: widget.displayStringForOption,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!widget.enabled) {
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

        _syncingToExternal = true;
        _fieldController.value = TextEditingValue(
          text: label,
          selection: TextSelection.collapsed(offset: label.length),
        );
        _syncingToExternal = false;

        widget.textController.value = _fieldController.value;

        if (widget.onSelected != null) {
          widget.onSelected!(opt);
        }
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
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;

            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (_lastOptions.isNotEmpty) {
                setState(() {
                  _highlightedIndex =
                      (_highlightedIndex + 1) % _lastOptions.length;
                });
                return KeyEventResult.handled;
              }
            }

            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (_lastOptions.isNotEmpty) {
                setState(() {
                  _highlightedIndex =
                      (_highlightedIndex - 1 + _lastOptions.length) %
                          _lastOptions.length;
                });
                return KeyEventResult.handled;
              }
            }

            if (event.logicalKey == LogicalKeyboardKey.tab) {
              if (_lastOptions.isNotEmpty) {
                _commitHighlightedOption();
                return KeyEventResult.handled;
              }
            }

            if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (_lastOptions.isNotEmpty) {
                _commitHighlightedOption();
                return KeyEventResult.handled;
              }
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
              if (widget.enabled && !widget.readOnly) {
                _openOptions();
              }
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

        if (opts.isEmpty) {
          return const SizedBox.shrink();
        }

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
                      color: isHighlighted
                          ? Theme.of(context).highlightColor
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isHighlighted
                              ? FontWeight.w600
                              : FontWeight.normal,
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