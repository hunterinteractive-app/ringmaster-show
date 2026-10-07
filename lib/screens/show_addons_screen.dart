import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/contest_settings.dart';
import '../widgets/contests/contest_registration_fields.dart';
import '../widgets/contests/contest_answer_field.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/show_addon.dart';
import '../utils/date_time_utils.dart';
import '../services/app_session.dart';
import '../services/show_addon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'cart_screen.dart';

class ShowAddonsScreen extends StatefulWidget {
  const ShowAddonsScreen({
    super.key,
    required this.cartId,
    required this.showId,
    required this.showName,
    this.exhibitorId,
    this.openCart = true,
  });
  final String cartId, showId, showName;
  final String? exhibitorId;
  final bool openCart;
  @override
  State<ShowAddonsScreen> createState() => _ShowAddonsScreenState();
}

class _ShowAddonsScreenState extends State<ShowAddonsScreen> {
  final _service = ShowAddonService();
  bool _loading = true, _busy = false;
  String? _error, _exhibitorId;
  String _currency = 'usd';
  List<ShowAddon> _items = [];
  List<Map<String, dynamic>> _cart = [], _exhibitors = [], _drafts = [];
  @override
  void initState() {
    super.initState();
    _exhibitorId = widget.exhibitorId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ownerId = AppSession.householdOwnerUserId;
      if (ownerId == null) {
        throw StateError(
          'Sign in to register for contests or purchase add-ons.',
        );
      }
      final data = await _service.catalog(widget.showId);
      final cart = await _service.cart(widget.cartId);
      final drafts = await _service.drafts(widget.cartId);
      final exhibitors = await Supabase.instance.client
          .from('exhibitors')
          .select('id,showing_name,display_name,exhibitor_number')
          .eq('owner_user_id', ownerId)
          .eq('is_active', true)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List)
            .map((r) => ShowAddon.fromJson(Map<String, dynamic>.from(r)))
            .toList();
        _cart = cart;
        _drafts = drafts;
        _currency = data['currency'].toString();
        _exhibitors = (exhibitors as List).cast<Map<String, dynamic>>();
        if (!_exhibitors.any((e) => e['id'] == _exhibitorId)) {
          _exhibitorId = _exhibitors.firstOrNull?['id']?.toString();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _selection(ShowAddon item) => _cart
      .where(
        (r) => r['offering_id'] == item.id && r['exhibitor_id'] == _exhibitorId,
      )
      .firstOrNull;
  Future<void> _choose(ShowAddon item, {Map<String, dynamic>? existing}) async {
    final exhibitorId = _exhibitorId!;
    List<Map<String, dynamic>> animals = [];
    if (item.isContest &&
        (item.animalSelection != 'none' || item.contest.expandedAnimals)) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        animals = await _service.animals(widget.cartId, exhibitorId);
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
    }
    final result = await showDialog<AddonEntryValues>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddonEntryDialog(
        item: item,
        currency: _currency,
        existing: existing ?? (item.isContest ? null : _selection(item)),
        upload: () => _service.upload(item.id),
        openFile: _service.openAttachment,
        animals: animals,
        exhibitorName: _name(
          _exhibitors.firstWhere((e) => e['id'] == exhibitorId),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (result.isDraft) {
        await _service.saveDraft(
          widget.cartId,
          item.id,
          exhibitorId,
          result.selectionId!,
          {
            'answers': result.answers,
            'division': result.division,
            'animal_key': result.animalKey,
            'registration_data': result.registrationData,
          },
        );
      } else {
        await _service.add(
          cartId: widget.cartId,
          offeringId: item.id,
          exhibitorId: exhibitorId,
          quantity: result.quantity,
          answers: result.answers,
          division: result.division,
          animalKey: result.animalKey,
          selectionId: item.isContest ? result.selectionId : null,
          registrationData: item.isContest ? result.registrationData : null,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isDraft
                  ? 'Draft saved. Resume here when you are ready; no fee has been added.'
                  : '${item.name} added to your cart.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.remove(row['id'].toString());
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue() {
    if (!widget.openCart) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CartScreen(
          cartId: widget.cartId,
          showId: widget.showId,
          showName: widget.showName,
        ),
      ),
    );
  }

  String _name(Map<String, dynamic> e) =>
      '${(e['showing_name'] ?? '').toString().trim().isNotEmpty ? e['showing_name'] : e['display_name']} • #${e['exhibitor_number'] ?? '—'}';
  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    useScrollView: true,
    title: 'Contests & Add-Ons',
    subtitle: widget.showName,
    showBackButton: true,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : AppTheme.surfaceTextScope(
            context,
            child: Card(
              color: Colors.white,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add something to your visit',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose optional contests and add-ons, then continue to your cart. Animal entries you have added stay in your cart.',
                    ),
                    const SizedBox(height: 16),
                    if (_exhibitors.isEmpty)
                      const Text(
                        'Add an exhibitor in your account before registering for a contest or purchasing add-ons.',
                      )
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey(_exhibitorId),
                        initialValue: _exhibitorId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'For exhibitor',
                        ),
                        items: [
                          for (final e in _exhibitors)
                            DropdownMenuItem(
                              value: e['id'].toString(),
                              child: Text(
                                _name(e),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _exhibitorId = v),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ),
                    for (final kind in ['contest', 'extra'])
                      if (_items.any((i) => i.kind == kind)) ...[
                        const SizedBox(height: 24),
                        Text(
                          kind == 'contest' ? 'Contests' : 'Show Add-Ons',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        for (final item in _items.where((i) => i.kind == kind))
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  if (item.description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(item.description),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.priceCents == 0
                                        ? 'Free'
                                        : '${addonMoney(item.priceCents, _currency)}${item.isContest ? ' per registration' : ' each'}',
                                  ),
                                  if (item.requiresAnimalEntry)
                                    const Text(
                                      'Requires an animal entry for this exhibitor.',
                                    ),
                                  if (item.isContest) ...[
                                    if (item.effectiveOpenAt != null)
                                      Text(
                                        'Registration opens: ${formatLocalDateTime(item.effectiveOpenAt!.toIso8601String())}',
                                      ),
                                    if (item.effectiveCloseAt != null)
                                      Text(
                                        'Registration closes: ${formatLocalDateTime(item.effectiveCloseAt!.toIso8601String())}',
                                      ),
                                    const Text(
                                      'Dates and times are in your current time zone.',
                                    ),
                                  ],
                                  if (!item.registrationIsOpen)
                                    Text(switch (item.registrationStatus) {
                                      'upcoming' =>
                                        'Registration has not opened yet.',
                                      'closed' => 'Registration has closed.',
                                      _ => 'This show is locked or finalized.',
                                    }),
                                  if (!item.isContest)
                                    Text(
                                      'Limit ${item.maxPerExhibitor} per exhibitor for this show.',
                                    ),
                                  const SizedBox(height: 12),
                                  if (item.isContest) ...[
                                    for (final row in _cart.where(
                                      (r) =>
                                          r['offering_id'] == item.id &&
                                          r['exhibitor_id'] == _exhibitorId,
                                    ))
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          contestEntryLabel(row).isEmpty
                                              ? 'Registration in cart'
                                              : contestEntryLabel(row),
                                        ),
                                        subtitle: Text(
                                          [
                                                row['division'],
                                                row['registration_data']?['category'],
                                              ]
                                              .where(
                                                (v) => v != null && v != '',
                                              )
                                              .join(' • '),
                                        ),
                                        trailing: Wrap(
                                          children: [
                                            TextButton(
                                              onPressed:
                                                  _busy ||
                                                      !item
                                                          .registrationIsOpen ||
                                                      AppSession.isSupportMode
                                                  ? null
                                                  : () => _choose(
                                                      item,
                                                      existing: row,
                                                    ),
                                              child: const Text('Edit'),
                                            ),
                                            IconButton(
                                              tooltip: 'Remove',
                                              onPressed:
                                                  _busy ||
                                                      AppSession.isSupportMode
                                                  ? null
                                                  : () => _remove(row),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    for (final draft in _drafts.where(
                                      (r) =>
                                          r['offering_id'] == item.id &&
                                          r['exhibitor_id'] == _exhibitorId,
                                    ))
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Saved draft'),
                                        subtitle: const Text(
                                          'Not registered until added to cart and checked out',
                                        ),
                                        trailing: TextButton(
                                          onPressed:
                                              _busy ||
                                                  !item.registrationIsOpen ||
                                                  AppSession.isSupportMode
                                              ? null
                                              : () => _choose(
                                                  item,
                                                  existing: {
                                                    ...Map<
                                                      String,
                                                      dynamic
                                                    >.from(draft['data']),
                                                    'id': draft['id'],
                                                    'is_draft': true,
                                                  },
                                                ),
                                          child: const Text('Resume'),
                                        ),
                                      ),
                                  ],
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton(
                                        onPressed:
                                            _busy ||
                                                _exhibitorId == null ||
                                                !item.registrationIsOpen ||
                                                AppSession.isSupportMode
                                            ? null
                                            : () => _choose(item),
                                        child: Text(
                                          item.isContest
                                              ? (_selection(item) == null
                                                    ? 'Register'
                                                    : 'Add Another Registration')
                                              : (_selection(item) == null
                                                    ? 'Add to Cart'
                                                    : 'Edit in Cart'),
                                        ),
                                      ),
                                      if (!item.isContest &&
                                          _selection(item) != null)
                                        TextButton(
                                          onPressed:
                                              _busy || AppSession.isSupportMode
                                              ? null
                                              : () =>
                                                    _remove(_selection(item)!),
                                          child: const Text('Remove'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    if (_items.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'This show has no contests or add-ons available right now.',
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _continue,
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: const Text('Continue to Cart'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}

class AddonEntryValues {
  const AddonEntryValues(
    this.quantity,
    this.answers, {
    this.division,
    this.animalKey,
    this.selectionId,
    this.registrationData = const {},
    this.isDraft = false,
  });
  final int quantity;
  final Map<String, dynamic> answers;
  final String? division, animalKey, selectionId;
  final Map<String, dynamic> registrationData;
  final bool isDraft;
}

class AddonEntryDialog extends StatefulWidget {
  const AddonEntryDialog({
    super.key,
    required this.item,
    required this.currency,
    this.existing,
    this.animals = const [],
    this.exhibitorName,
    this.upload,
    this.openFile,
    this.allowDraft = true,
    this.submitLabel = 'Add to Cart',
  });
  final ShowAddon item;
  final String currency;
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> animals;
  final String? exhibitorName;
  final bool allowDraft;
  final String submitLabel;
  final Future<Map<String, dynamic>?> Function()? upload;
  final Future<void> Function(Map<String, dynamic>)? openFile;
  @override
  State<AddonEntryDialog> createState() => _AddonEntryDialogState();
}

class _AddonEntryDialogState extends State<AddonEntryDialog> {
  final _form = GlobalKey<FormState>();
  late final String _id =
      widget.existing?['id']?.toString() ?? const Uuid().v4();
  late final Map<String, dynamic> _data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(widget.existing?['registration_data'] ?? {})),
  );
  void _finish({bool draft = false}) {
    if (!draft && !_form.currentState!.validate()) return;
    final answers = {
      for (final f in widget.item.fields.where(
        (f) =>
            f.visibleFor(_data['category']?.toString() ?? '', _division ?? ''),
      ))
        if (_answers.containsKey(f.id)) f.id: _answers[f.id],
    };
    final data = Map<String, dynamic>.from(jsonDecode(jsonEncode(_data)));
    if (data['animals'] is List) {
      data['animals'] = (data['animals'] as List)
          .where((a) => '${a['source'] ?? ''}'.isNotEmpty)
          .toList();
    }
    if (!widget.item.contest.isTeam) data.remove('team');
    Navigator.pop(
      context,
      AddonEntryValues(
        widget.item.isContest ? 1 : int.parse(_quantity.text),
        answers,
        division: _division,
        animalKey: _animalKey,
        selectionId: _id,
        registrationData: data,
        isDraft: draft,
      ),
    );
  }

  late String? _division =
      widget.item.divisions.contains(widget.existing?['division'])
      ? (widget.existing?['division'] as String?)
      : null;
  late String? _animalKey =
      widget.animals.any((a) => a['key'] == widget.existing?['animal_key'])
      ? (widget.existing?['animal_key'] as String?)
      : null;
  late final _quantity = TextEditingController(
    text: (widget.existing?['quantity'] ?? 1).toString(),
  );
  late final Map<String, dynamic> _answers = {
    for (final f in widget.item.fields)
      if ((widget.existing?['answers'] as Map?)?.containsKey(f.id) == true)
        f.id: widget.existing!['answers'][f.id],
  };
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.surfaceTheme(Theme.of(context)),
    child: AlertDialog(
      backgroundColor: Colors.white,
      titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.text),
      title: Text(widget.item.name),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.exhibitorName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Exhibitor: ${widget.exhibitorName}'),
                  ),
                Text(
                  widget.item.priceCents == 0
                      ? 'Free'
                      : addonMoney(widget.item.priceCents, widget.currency),
                ),
                if (widget.item.isContest && widget.item.divisions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: DropdownButtonFormField<String>(
                      initialValue: _division,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Division *',
                      ),
                      items: [
                        for (final division in widget.item.divisions)
                          DropdownMenuItem(
                            value: division,
                            child: Text(
                              division,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _division = v),
                      validator: (v) => v == null ? 'Choose a division.' : null,
                    ),
                  ),
                if (widget.item.isContest &&
                    !widget.item.contest.expandedAnimals &&
                    widget.item.animalSelection != 'none') ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: DropdownButtonFormField<String>(
                      initialValue: _animalKey,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            'Entered animal${widget.item.animalSelection == 'required' ? ' *' : ' (optional)'}',
                      ),
                      items: [
                        if (widget.item.animalSelection == 'optional')
                          const DropdownMenuItem(
                            value: '',
                            child: Text('No animal selected'),
                          ),
                        for (final animal in widget.animals)
                          DropdownMenuItem(
                            value: animal['key'].toString(),
                            child: Text(
                              animal['label'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => _animalKey = v == '' ? null : v,
                      validator: (v) =>
                          widget.item.animalSelection == 'required' &&
                              (v == null || v.isEmpty)
                          ? 'Choose an entered animal.'
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.animals.isEmpty
                          ? 'No eligible animals for this exhibitor. Add their animal entries to this show first.'
                          : 'Animals entered in this show, including this cart. Animals entered in multiple sections appear once.',
                    ),
                  ),
                ],
                if (!widget.item.isContest)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextFormField(
                      controller: _quantity,
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        helperText:
                            'Maximum ${widget.item.maxPerExhibitor} per exhibitor',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null ||
                                n < 1 ||
                                n > widget.item.maxPerExhibitor
                            ? 'Enter a valid quantity.'
                            : null;
                      },
                    ),
                  ),
                if (widget.item.isContest)
                  ContestRegistrationFields(
                    item: widget.item,
                    data: _data,
                    animals: widget.animals,
                    onChanged: () => setState(() {}),
                  ),
                for (final field in widget.item.fields.where(
                  (f) => f.visibleFor(
                    _data['category']?.toString() ?? '',
                    _division ?? '',
                  ),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: ContestAnswerField(
                      key: ValueKey(field.id),
                      field: field,
                      value: _answers[field.id],
                      onChanged: (v) => _answers[field.id] = v,
                      upload: widget.upload,
                      openFile: widget.openFile,
                    ),
                  ),
                if (widget.item.isContest && widget.item.fields.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Your exhibitor name and number will be included with this registration.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.allowDraft &&
            widget.item.isContest &&
            (widget.existing == null || widget.existing?['is_draft'] == true))
          TextButton(
            onPressed: () => _finish(draft: true),
            child: const Text('Save Draft'),
          ),
        FilledButton(onPressed: _finish, child: Text(widget.submitLabel)),
      ],
    ),
  );
}
