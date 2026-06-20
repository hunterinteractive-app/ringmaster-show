// lib/screens/admin/admin_audit_log_screen.dart

import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/app_session.dart';

class AdminAuditLogScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminAuditLogScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  final supabase = Supabase.instance.client;

  bool _loadingCorrections = true;
  bool _loadingWriters = true;
  String? _correctionsError;
  String? _writersError;

  List<Map<String, dynamic>> _corrections = [];
  List<Map<String, dynamic>> _writerRows = [];

  final _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _fieldFilter = 'all';
  String _roleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadCorrections(),
      _loadWriters(),
    ]);
  }

  Future<void> _loadCorrections() async {
    setState(() {
      _loadingCorrections = true;
      _correctionsError = null;
    });

    try {
      final rows = await supabase.rpc(
        'get_show_qr_correction_audit_log',
        params: {
          'p_show_id': widget.showId,
        },
      );

      if (!mounted) return;
      setState(() {
        _corrections = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loadingCorrections = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _correctionsError = e.toString();
        _loadingCorrections = false;
      });
    }
  }

  Future<void> _loadWriters() async {
    setState(() {
      _loadingWriters = true;
      _writersError = null;
    });

    try {
      final rows = await supabase.rpc(
        'get_show_qr_writer_activity',
        params: {
          'p_show_id': widget.showId,
        },
      );

      if (!mounted) return;
      setState(() {
        _writerRows = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loadingWriters = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _writersError = e.toString();
        _loadingWriters = false;
      });
    }
  }

  String _text(Map<String, dynamic> row, String key) {
    return (row[key] ?? '').toString().trim();
  }

  DateTime? _date(dynamic raw) {
    return DateTime.tryParse((raw ?? '').toString())?.toLocal();
  }

  String _fmtDateTime(dynamic raw) {
    final parsed = raw is DateTime ? raw : _date(raw);
    if (parsed == null) return '';
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final year = parsed.year.toString();
    final hourRaw = parsed.hour;
    final hour = hourRaw == 0 ? 12 : hourRaw > 12 ? hourRaw - 12 : hourRaw;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final ampm = hourRaw >= 12 ? 'PM' : 'AM';
    return '$month/$day/$year $hour:$minute $ampm';
  }

  bool _matchesDateRange(dynamic raw) {
    final parsed = _date(raw);
    if (parsed == null) return true;

    if (_startDate != null) {
      final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      if (parsed.isBefore(start)) return false;
    }

    if (_endDate != null) {
      final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      if (parsed.isAfter(end)) return false;
    }

    return true;
  }

  String _searchText() => _searchController.text.trim().toLowerCase();

  bool _rowContainsSearch(Map<String, dynamic> row, Iterable<String> keys) {
    final search = _searchText();
    if (search.isEmpty) return true;

    return keys.any((key) => _text(row, key).toLowerCase().contains(search));
  }

  List<Map<String, dynamic>> get _filteredCorrections {
    return _corrections.where((row) {
      if (!_matchesDateRange(row['created_at'])) return false;

      if (_fieldFilter != 'all' && _text(row, 'field_name') != _fieldFilter) {
        return false;
      }

      if (_roleFilter != 'all' && _text(row, 'approved_by_role') != _roleFilter) {
        return false;
      }

      return _rowContainsSearch(row, const [
        'entry_id',
        'animal_name',
        'exhibitor_label',
        'breed',
        'variety',
        'class_name',
        'sex',
        'tattoo',
        'field_name',
        'old_value',
        'new_value',
        'reason',
        'writer_name',
        'writer_phone',
        'approved_by_role',
        'approved_by_pin',
      ]);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredWriterRows {
    return _writerRows.where((row) {
      if (!_matchesDateRange(row['result_entered_at'])) return false;

      return _rowContainsSearch(row, const [
        'result_entered_by_name',
        'result_entered_by_user_id',
        'result_entered_by_phone',
        'breed',
        'variety',
        'class_name',
        'sex',
        'tattoo',
      ]);
    }).toList();
  }

  List<Map<String, dynamic>> get _groupedWriters {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in _filteredWriterRows) {
      final name = _text(row, 'result_entered_by_name');
      final phone = _text(row, 'result_entered_by_phone');
      final userId = _text(row, 'result_entered_by_user_id');

      final key = [
        if (userId.isNotEmpty) userId,
        if (name.isNotEmpty) name,
        if (phone.isNotEmpty) phone,
      ].join('|');

      if (key.isEmpty) continue;

      final item = grouped.putIfAbsent(key, () {
        return {
          'name': name.isEmpty ? 'Unknown Writer' : name,
          'phone': phone,
          'count': 0,
          'last_at': row['result_entered_at'],
          'classes': <String>{},
          'tattoos': <String>{},
        };
      });

      item['count'] = (item['count'] as int) + 1;

      final breed = _text(row, 'breed');
      final variety = _text(row, 'variety');
      final className = _text(row, 'class_name');
      final sex = _text(row, 'sex');
      final tattoo = _text(row, 'tattoo');

      final label = [
        if (breed.isNotEmpty) breed,
        if (variety.isNotEmpty) variety,
        if (className.isNotEmpty || sex.isNotEmpty)
          [className, sex].where((x) => x.isNotEmpty).join(' '),
      ].where((x) => x.trim().isNotEmpty).join(' • ');

      if (label.isNotEmpty) {
        (item['classes'] as Set<String>).add(label);
      }

      if (tattoo.isNotEmpty) {
        (item['tattoos'] as Set<String>).add(tattoo);
      }

      final existingLast = _date(item['last_at']);
      final rowLast = _date(row['result_entered_at']);
      if (existingLast == null || (rowLast != null && rowLast.isAfter(existingLast))) {
        item['last_at'] = row['result_entered_at'];
      }
    }

    return grouped.values.toList()
      ..sort((a, b) {
        final ad = _date(a['last_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = _date(b['last_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
  }

  Set<String> get _fieldOptions {
    return _corrections
        .map((e) => _text(e, 'field_name'))
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Set<String> get _roleOptions {
    return _corrections
        .map((e) => _text(e, 'approved_by_role'))
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'tattoo':
        return 'Ear #';
      case 'class_name':
        return 'Class';
      case 'sex':
        return 'Sex';
      case 'variety':
        return 'Variety';
      default:
        return field.replaceAll('_', ' ');
    }
  }

  IconData _severityIcon(String field) {
    switch (field) {
      case 'class_name':
      case 'sex':
        return Icons.warning_amber_rounded;
      case 'tattoo':
        return Icons.priority_high_rounded;
      default:
        return Icons.info_outline;
    }
  }

  Color _severityColor(String field) {
    switch (field) {
      case 'class_name':
      case 'sex':
        return Colors.orange.withValues(alpha: .14);
      case 'tattoo':
        return Colors.red.withValues(alpha: .12);
      default:
        return Colors.blueGrey.withValues(alpha: .10);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _startDate = null;
      _endDate = null;
      _fieldFilter = 'all';
      _roleFilter = 'all';
    });
  }

  void _downloadCsv({required bool corrections}) {
    final filename = corrections
        ? 'qr_overrides_${widget.showId}.csv'
        : 'qr_writers_${widget.showId}.csv';

    final rows = corrections ? _filteredCorrections : _groupedWriters;

    final headers = corrections
        ? <String>[
            'When',
            'Animal',
            'Ear Number',
            'Exhibitor',
            'Breed',
            'Variety',
            'Class',
            'Sex',
            'Entry ID',
            'Field',
            'Old Value',
            'New Value',
            'Reason',
            'Writer Name',
            'Writer Phone',
            'Approved By User ID',
            'Approved Role',
            'PIN',
          ]
        : <String>[
            'Writer Name',
            'Writer Phone',
            'Entries Written',
            'Last Activity',
            'Wrote For',
            'Ear Numbers',
          ];

    List<String> rowValues(Map<String, dynamic> row) {
      if (corrections) {
        return [
          _fmtDateTime(row['created_at']),
          _text(row, 'animal_name'),
          _text(row, 'tattoo'),
          _text(row, 'exhibitor_label'),
          _text(row, 'breed'),
          _text(row, 'variety'),
          _text(row, 'class_name'),
          _text(row, 'sex'),
          _text(row, 'entry_id'),
          _fieldLabel(_text(row, 'field_name')),
          _text(row, 'old_value'),
          _text(row, 'new_value'),
          _text(row, 'reason'),
          _text(row, 'writer_name'),
          _text(row, 'writer_phone'),
          _text(row, 'approved_by_user_id'),
          _text(row, 'approved_by_role'),
          _text(row, 'approved_by_pin'),
        ];
      }

      final classes = ((row['classes'] as Set<String>).toList()..sort()).join('; ');
      final tattoos = ((row['tattoos'] as Set<String>).toList()..sort()).join('; ');
      return [
        (row['name'] ?? '').toString(),
        (row['phone'] ?? '').toString(),
        (row['count'] ?? 0).toString(),
        _fmtDateTime(row['last_at']),
        classes,
        tattoos,
      ];
    }

    String escape(String value) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }

    final csv = [
      headers.map(escape).join(','),
      ...rows.map((row) => rowValues(row).map(escape).join(',')),
    ].join('\n');

    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Widget _filters({required bool showCorrectionFilters}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search',
                hintText: showCorrectionFilters
                    ? 'Search ear #, reason, writer, PIN, role...'
                    : 'Search writer, phone, breed, variety, class, ear #...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          setState(() => _searchController.clear());
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_startDate == null ? 'Start date' : 'From ${_fmtDateTime(_startDate).split(' ').first}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_endDate == null ? 'End date' : 'To ${_fmtDateTime(_endDate).split(' ').first}'),
                ),
                if (showCorrectionFilters) ...[
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      initialValue: _fieldFilter,
                      decoration: const InputDecoration(
                        labelText: 'Field',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All fields')),
                        ...(_fieldOptions.toList()..sort()).map(
                          (field) => DropdownMenuItem(
                            value: field,
                            child: Text(_fieldLabel(field)),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _fieldFilter = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _roleFilter,
                      decoration: const InputDecoration(
                        labelText: 'Approved role',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All roles')),
                        ...(_roleOptions.toList()..sort()).map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(role.replaceAll('_', ' ')),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _roleFilter = value);
                      },
                    ),
                  ),
                ],
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Clear filters'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: .08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF11285A)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF11285A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String text, {bool loading = false, String? error, VoidCallback? onRetry}) {
    return Center(
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) const CircularProgressIndicator(),
              if (loading) const SizedBox(height: 16),
              Text(error ?? text, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportModeNotice(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.support_agent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _correctionsTab() {
    if (_loadingCorrections) {
      return _statusCard('Loading QR overrides...', loading: true);
    }

    if (_correctionsError != null) {
      return _statusCard(
        'Failed to load QR overrides.',
        error: _correctionsError,
        onRetry: _loadCorrections,
      );
    }

    final rows = _filteredCorrections;

    return Column(
      children: [
        if (AppSession.isSupportMode) ...[
          _supportModeNotice(
            'Support Mode — Viewing QR correction overrides as an admin while viewing another user.',
          ),
        ],
        _filters(showCorrectionFilters: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text('${rows.length} override${rows.length == 1 ? '' : 's'}'),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: rows.isEmpty ? null : () => _downloadCsv(corrections: true),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download CSV'),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? _statusCard('No QR correction overrides match the current filters.')
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('')),
                        DataColumn(label: Text('When')),
                        DataColumn(label: Text('Animal')),
                        DataColumn(label: Text('Ear #')),
                        DataColumn(label: Text('Exhibitor')),
                        DataColumn(label: Text('Breed / Variety / Class')),
                        DataColumn(label: Text('Field')),
                        DataColumn(label: Text('Old')),
                        DataColumn(label: Text('New')),
                        DataColumn(label: Text('Reason')),
                        DataColumn(label: Text('Writer')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Approved Role')),
                        DataColumn(label: Text('PIN')),
                      ],
                      rows: rows.map((row) {
                        final field = _text(row, 'field_name');
                        return DataRow(
                          color: WidgetStatePropertyAll(_severityColor(field)),
                          cells: [
                            DataCell(Icon(_severityIcon(field), size: 18)),
                            DataCell(Text(_fmtDateTime(row['created_at']))),
                            DataCell(Text(_text(row, 'animal_name').isEmpty ? '(Unnamed)' : _text(row, 'animal_name'))),
                            DataCell(Text(_text(row, 'tattoo'))),
                            DataCell(SizedBox(width: 180, child: Text(_text(row, 'exhibitor_label')))),
                            DataCell(SizedBox(
                              width: 260,
                              child: Text([
                                _text(row, 'breed'),
                                _text(row, 'variety'),
                                [_text(row, 'class_name'), _text(row, 'sex')]
                                    .where((x) => x.isNotEmpty)
                                    .join(' '),
                              ].where((x) => x.isNotEmpty).join(' • ')),
                            )),
                            DataCell(Text(_fieldLabel(field))),
                            DataCell(Text(_text(row, 'old_value'))),
                            DataCell(Text(_text(row, 'new_value'))),
                            DataCell(SizedBox(width: 260, child: Text(_text(row, 'reason')))),
                            DataCell(Text(_text(row, 'writer_name'))),
                            DataCell(Text(_text(row, 'writer_phone'))),
                            DataCell(Text(_text(row, 'approved_by_role').replaceAll('_', ' '))),
                            DataCell(Text(_text(row, 'approved_by_pin'))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _writersTab() {
    if (_loadingWriters) {
      return _statusCard('Loading QR writers...', loading: true);
    }

    if (_writersError != null) {
      return _statusCard(
        'Failed to load QR writers.',
        error: _writersError,
        onRetry: _loadWriters,
      );
    }

    final rows = _groupedWriters;
    final totalEntriesWritten = rows.fold<int>(
      0,
      (sum, row) => sum + ((row['count'] as int?) ?? 0),
    );

    return Column(
      children: [
        if (AppSession.isSupportMode) ...[
          _supportModeNotice(
            'Support Mode — Viewing QR writer activity as an admin while viewing another user.',
          ),
        ],
        _filters(showCorrectionFilters: false),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _summaryPill(
                icon: Icons.edit_note_outlined,
                label: '${rows.length} writer${rows.length == 1 ? '' : 's'}',
              ),
              const SizedBox(width: 8),
              _summaryPill(
                icon: Icons.check_circle_outline,
                label: '$totalEntriesWritten entries written',
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: rows.isEmpty ? null : () => _downloadCsv(corrections: false),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download CSV'),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? _statusCard('No QR writer activity matches the current filters.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final name = (row['name'] ?? 'Unknown Writer').toString().trim();
                    final phone = (row['phone'] ?? '').toString().trim();
                    final count = ((row['count'] as int?) ?? 0);
                    final classes = ((row['classes'] as Set<String>).toList()..sort());
                    final tattoos = ((row['tattoos'] as Set<String>).toList()..sort());
                    final previewClasses = classes.take(6).toList();
                    final extraClassCount = classes.length - previewClasses.length;
                    final previewTattoos = tattoos.take(20).join(', ');
                    final extraTattooCount = tattoos.length - tattoos.take(20).length;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: Colors.black.withValues(alpha: .06)),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          leading: CircleAvatar(
                            child: Text(
                              name.isNotEmpty
                                  ? name.characters.first.toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(
                            name.isEmpty ? 'Unknown Writer' : name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (phone.isNotEmpty)
                                  _smallInfoChip(Icons.phone_outlined, phone),
                                _smallInfoChip(Icons.check_circle_outline, '$count entries'),
                                _smallInfoChip(Icons.schedule_outlined, _fmtDateTime(row['last_at'])),
                              ],
                            ),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Wrote for',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (classes.isEmpty)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('No class details recorded.'),
                              )
                            else
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ...previewClasses.map(
                                      (label) => Chip(
                                        label: Text(label),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    if (extraClassCount > 0)
                                      Chip(
                                        label: Text('+$extraClassCount more'),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Ear numbers',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                tattoos.isEmpty
                                    ? 'No ear numbers recorded.'
                                    : '$previewTattoos${extraTattooCount > 0 ? ', +$extraTattooCount more' : ''}',
                                style: const TextStyle(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: AppBar(
          title: Text('Audit Log — ${widget.showName}'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            tabs: [
              Tab(text: 'QR Code Overrides'),
              Tab(text: 'Writers'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _correctionsTab(),
            _writersTab(),
          ],
        ),
      ),
    );
  }
}