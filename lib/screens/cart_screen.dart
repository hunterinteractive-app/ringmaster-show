import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class CartScreen extends StatefulWidget {
  final String cartId;
  final String showId;
  final String showName;

  const CartScreen({
    super.key,
    required this.cartId,
    required this.showId,
    required this.showName,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _loading = true;
  bool _confirming = false;
  String? _msg;

  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _show;
  Map<String, Map<String, dynamic>> _sectionById = {};

  // Fee settings
  Map<String, dynamic>? _feeSettings;

  // NEW: exhibitor label lookup
  final Map<String, String> _exhibitorLabelById = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ------------------------------
  // Load
  // ------------------------------
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      // Show basic
      final show = await supabase
          .from('shows')
          .select('id,name,entry_close_at,entry_open_at,start_date')
          .eq('id', widget.showId)
          .single();

      // Fee settings (may not exist)
      final fee = await supabase
          .from('show_fee_settings')
          .select(
              'show_id,currency,fee_per_entry,fee_per_show,multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value')
          .eq('show_id', widget.showId)
          .maybeSingle();

      // Sections
      final sections = await supabase
          .from('show_sections')
          .select('id,display_name,kind,letter,sort_order')
          .eq('show_id', widget.showId)
          .order('sort_order');

      _sectionById = {
        for (final s in (sections as List).cast<Map<String, dynamic>>())
          s['id'].toString(): s,
      };

      // Cart items (NOW includes exhibitor_id)
      final items = await supabase
          .from('entry_cart_items')
          .select(
              'id,exhibitor_id,section_id,animal_id,species,breed,variety,sex,tattoo,class_name,created_at')
          .eq('cart_id', widget.cartId)
          .order('created_at');

      final parsedItems = (items as List).cast<Map<String, dynamic>>();

      // Fetch exhibitor labels used in this cart
      await _loadExhibitorLabelsForCart(parsedItems);

      if (!mounted) return;
      setState(() {
        _show = show;
        _feeSettings = fee;
        _items = parsedItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  Future<void> _loadExhibitorLabelsForCart(List<Map<String, dynamic>> items) async {
    _exhibitorLabelById.clear();

    final ids = <String>{};
    for (final it in items) {
      final id = it['exhibitor_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }

    if (ids.isEmpty) return;

    final rows = await supabase
        .from('exhibitors')
        .select('id,showing_name,first_name,last_name')
        .inFilter('id', ids.toList());

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final id = r['id'].toString();
      final showingName = (r['showing_name'] ?? '').toString().trim();
      final fn = (r['first_name'] ?? '').toString().trim();
      final ln = (r['last_name'] ?? '').toString().trim();

      final label = showingName.isNotEmpty
          ? showingName
          : [fn, ln].where((x) => x.isNotEmpty).join(' ').trim();

      _exhibitorLabelById[id] = label.isEmpty ? 'Exhibitor' : label;
    }
  }

  // ------------------------------
  // Helpers
  // ------------------------------
  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  bool _deadlinePassed() {
    final closeAt = _parseTs(_show?['entry_close_at']);
    if (closeAt == null) return false;
    return DateTime.now().isAfter(closeAt.toLocal());
  }

  double _asDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return fallback;
    return double.tryParse(s) ?? fallback;
  }

  String _currencySymbol(String? currency) {
    final c = (currency ?? 'USD').toUpperCase();
    if (c == 'USD') return r'$';
    if (c == 'CAD') return r'$';
    if (c == 'EUR') return '€';
    if (c == 'GBP') return '£';
    return r'$';
  }

  String _money(double v, {String? currency}) {
    final sym = _currencySymbol(currency);
    return '$sym${v.toStringAsFixed(2)}';
  }

  // ------------------------------
  // Fee calculation (overall)
  // ------------------------------
  Map<String, dynamic> _calculateFeesForItems(List<Map<String, dynamic>> items) {
    final currency = (_feeSettings?['currency'] ?? 'USD').toString();
    final feePerEntry = _asDouble(_feeSettings?['fee_per_entry']);
    final feePerShow = _asDouble(_feeSettings?['fee_per_show']);

    final discountEnabled = _feeSettings?['multi_show_discount_enabled'] == true;
    final discountType =
        (_feeSettings?['multi_show_discount_type'] ?? '').toString().toLowerCase(); // 'percent'|'amount'
    final discountValue = _asDouble(_feeSettings?['multi_show_discount_value']);

    final entryCount = items.length;
    final entriesSubtotal = feePerEntry * entryCount;

    // Group by animal for multi-show discount
    final Map<String, int> perAnimalCounts = {};
    for (final it in items) {
      final animalId = it['animal_id']?.toString();
      if (animalId == null || animalId.isEmpty) continue;
      perAnimalCounts[animalId] = (perAnimalCounts[animalId] ?? 0) + 1;
    }

    int additionalEntries = 0;
    perAnimalCounts.forEach((_, count) {
      if (count > 1) additionalEntries += (count - 1);
    });

    double discountAmount = 0.0;
    if (discountEnabled && additionalEntries > 0 && feePerEntry > 0) {
      if (discountType == 'percent') {
        final pct = (discountValue <= 1.0) ? discountValue : (discountValue / 100.0);
        discountAmount = (feePerEntry * additionalEntries) * pct;
      } else if (discountType == 'amount') {
        discountAmount = additionalEntries * discountValue;
      }

      final maxDiscount = feePerEntry * additionalEntries;
      if (discountAmount > maxDiscount) discountAmount = maxDiscount;
      if (discountAmount < 0) discountAmount = 0;
    }

    final total = (entriesSubtotal + feePerShow) - discountAmount;

    return {
      'currency': currency,
      'fee_per_entry': feePerEntry,
      'fee_per_show': feePerShow,
      'entry_count': entryCount,
      'entries_subtotal': entriesSubtotal,
      'additional_entries': additionalEntries,
      'discount_enabled': discountEnabled,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_amount': discountAmount,
      'show_fee': feePerShow,
      'total': total < 0 ? 0.0 : total,
    };
  }

  // ------------------------------
  // Grouping by exhibitor
  // ------------------------------
  Map<String, List<Map<String, dynamic>>> _groupItemsByExhibitor() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final it in _items) {
      final exhibitorId = it['exhibitor_id']?.toString().trim();
      final key = (exhibitorId == null || exhibitorId.isEmpty) ? '__unassigned__' : exhibitorId;
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(it);
    }

    // Stable ordering: exhibitor label, unassigned last
    final keys = grouped.keys.toList();
    keys.sort((a, b) {
      if (a == '__unassigned__') return 1;
      if (b == '__unassigned__') return -1;
      final la = (_exhibitorLabelById[a] ?? a).toLowerCase();
      final lb = (_exhibitorLabelById[b] ?? b).toLowerCase();
      return la.compareTo(lb);
    });

    final ordered = <String, List<Map<String, dynamic>>>{};
    for (final k in keys) {
      ordered[k] = grouped[k]!;
    }
    return ordered;
  }

  // ------------------------------
  // Actions
  // ------------------------------
  Future<void> _removeItem(String itemId) async {
    try {
      await supabase.from('entry_cart_items').delete().eq('id', itemId);
      await _load();
    } catch (e) {
      setState(() => _msg = 'Remove failed: $e');
    }
  }

  Future<void> _confirmDayOf() async {
    if (_items.isEmpty) {
      setState(() => _msg = 'Your cart is empty.');
      return;
    }
    if (_deadlinePassed()) {
      setState(() => _msg = 'Entry deadline has passed. You can’t submit this cart.');
      return;
    }

    // If any items are unassigned, block (optional but recommended)
    final hasUnassigned = _items.any((it) {
      final ex = it['exhibitor_id']?.toString().trim();
      return ex == null || ex.isEmpty;
    });
    if (hasUnassigned) {
      setState(() => _msg = 'One or more cart items are missing an exhibitor. Please fix before confirming.');
      return;
    }

    setState(() {
      _confirming = true;
      _msg = null;
    });

    try {
      final res = await supabase.rpc(
        'commit_entry_cart_day_of',
        params: {'p_cart_id': widget.cartId},
      );

      final insertedCount = (res as num).toInt();

      if (!mounted) return;
      Navigator.pop(context, insertedCount > 0);
    } catch (e) {
      setState(() => _msg = 'Confirm failed: $e');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  // ------------------------------
  // UI
  // ------------------------------
  @override
  Widget build(BuildContext context) {
    final title = 'Cart — ${widget.showName}';

    final overallFee = _calculateFeesForItems(_items);
    final currency = overallFee['currency'] as String;

    final grouped = _groupItemsByExhibitor();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _confirming ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_msg!, style: const TextStyle(color: Colors.red)),
                  ),

                // Deadline + Overall Fee Summary
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _deadlinePassed()
                            ? 'Entry deadline: PASSED'
                            : 'Entry deadline: ${_parseTs(_show?['entry_close_at'])?.toLocal().toString() ?? '(not set)'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      Text('Overall Fees', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      _feeSettings == null
                          ? Text(
                              'No show fee settings found yet. (show_fee_settings row missing)',
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${overallFee['entry_count']} entries × ${_money(overallFee['fee_per_entry'] as double, currency: currency)} = '
                                  '${_money(overallFee['entries_subtotal'] as double, currency: currency)}',
                                ),
                                if ((overallFee['show_fee'] as double) > 0)
                                  Text('Per-show fee: ${_money(overallFee['show_fee'] as double, currency: currency)}'),
                                if ((overallFee['discount_amount'] as double) > 0)
                                  Text(
                                    'Multi-show discount (${overallFee['additional_entries']} additional entries): '
                                    '-${_money(overallFee['discount_amount'] as double, currency: currency)}',
                                  ),
                                const SizedBox(height: 6),
                                Text(
                                  'Total: ${_money(overallFee['total'] as double, currency: currency)}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ],
                            ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Grouped cart list
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('Your cart is empty.'))
                      : ListView(
                          children: [
                            for (final entry in grouped.entries) ...[
                              _ExhibitorGroupHeader(
                                exhibitorName: entry.key == '__unassigned__'
                                    ? 'Unassigned Exhibitor'
                                    : (_exhibitorLabelById[entry.key] ?? 'Exhibitor'),
                                feeSettingsExists: _feeSettings != null,
                                feeLine: _feeSettings == null
                                    ? null
                                    : _buildExhibitorFeeLine(
                                        exhibitorItems: entry.value,
                                        currency: currency,
                                      ),
                              ),
                              ...entry.value.map((it) {
                                final sectionId = it['section_id']?.toString() ?? '';
                                final sec = _sectionById[sectionId];
                                final secName = (sec?['display_name'] ?? 'Section').toString();

                                final animalLabel =
                                    '${(it['breed'] ?? '').toString()} • ${(it['variety'] ?? '').toString()} • ${(it['sex'] ?? '').toString()}';

                                final top =
                                    '${(it['tattoo'] ?? '').toString().trim().isEmpty ? it['animal_id'] : it['tattoo']}';

                                return ListTile(
                                  title: Text('$secName — $top'),
                                  subtitle: Text('$animalLabel\nClass: ${(it['class_name'] ?? '').toString()}'),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    tooltip: 'Remove',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: _confirming ? null : () => _removeItem(it['id'].toString()),
                                  ),
                                );
                              }).toList(),
                              const Divider(height: 1),
                            ],
                          ],
                        ),
                ),

                // Confirm button
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_confirming || _deadlinePassed() || _items.isEmpty) ? null : _confirmDayOf,
                      child: Text(_confirming ? 'Confirming…' : 'Confirm Entries (Pay Day-of-Show)'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _buildExhibitorFeeLine({
    required List<Map<String, dynamic>> exhibitorItems,
    required String currency,
  }) {
    final f = _calculateFeesForItems(exhibitorItems);

    // NOTE: we intentionally DO NOT include fee_per_show in exhibitor subtotal
    // because that’s a cart-level fee. So we show: entries subtotal - discount.
    final entriesSubtotal = f['entries_subtotal'] as double;
    final discountAmount = f['discount_amount'] as double;
    final total = (entriesSubtotal - discountAmount);
    final count = f['entry_count'] as int;

    if (discountAmount > 0) {
      return '$count entries: ${_money(entriesSubtotal, currency: currency)} '
          '- ${_money(discountAmount, currency: currency)} = ${_money(total, currency: currency)}';
    }
    return '$count entries: ${_money(entriesSubtotal, currency: currency)}';
  }
}

// ------------------------------
// Simple header widget per exhibitor
// ------------------------------
class _ExhibitorGroupHeader extends StatelessWidget {
  final String exhibitorName;
  final bool feeSettingsExists;
  final String? feeLine;

  const _ExhibitorGroupHeader({
    required this.exhibitorName,
    required this.feeSettingsExists,
    required this.feeLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exhibitorName, style: Theme.of(context).textTheme.titleMedium),
          if (feeSettingsExists && feeLine != null) ...[
            const SizedBox(height: 4),
            Text(
              feeLine!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}