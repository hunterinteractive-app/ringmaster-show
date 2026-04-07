// lib/widgets/exhibitor_builder_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ExhibitorBuilderDialog extends StatefulWidget {
  final String? exhibitorId;

  const ExhibitorBuilderDialog({
    super.key,
    this.exhibitorId,
  });

  @override
  State<ExhibitorBuilderDialog> createState() =>
      _ExhibitorBuilderDialogState();
}

class _ExhibitorBuilderDialogState extends State<ExhibitorBuilderDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  String _type = 'adult'; // adult | youth | group
  bool _active = true;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _showingName = TextEditingController();
  final _arba = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();

  DateTime? _birthDate;
  bool _groupShowsAsYouth = false;

  bool _showingNameTouched = false;
  bool _isWiringShowingName = false;

  final List<_GroupMemberInput> _groupMembers = [];

  bool get _isEdit => widget.exhibitorId != null;
  bool get _isGroup => _type == 'group';
  bool get _isYouth => _type == 'youth';

  @override
  void initState() {
    super.initState();
    _wireAutofillShowingName();
    _loadIfEditing();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _showingName.dispose();
    _arba.dispose();
    _email.dispose();
    _phone.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();

    for (final m in _groupMembers) {
      m.dispose();
    }

    super.dispose();
  }

  void _wireAutofillShowingName() {
    void recompute() {
      if (_showingNameTouched) return;
      _recomputeShowingName();
    }

    _firstName.addListener(recompute);
    _lastName.addListener(recompute);

    _showingName.addListener(() {
      if (_isWiringShowingName) return;
      final expected = _buildAutoShowingName();
      if (_showingName.text.trim() != expected.trim()) {
        _showingNameTouched = true;
      }
    });
  }

  void _recomputeShowingName() {
    if (_showingNameTouched) return;

    final value = _buildAutoShowingName();

    _isWiringShowingName = true;
    _showingName.text = value;
    _showingName.selection = TextSelection.fromPosition(
      TextPosition(offset: _showingName.text.length),
    );
    _isWiringShowingName = false;
  }

  String _buildAutoShowingName() {
    if (_isGroup) {
      return _buildGroupShowingName();
    }

    final fn = _firstName.text.trim();
    final ln = _lastName.text.trim();
    return ('$fn $ln').trim();
  }

  String _buildGroupShowingName() {
    final filled = _groupMembers.where((m) => m.hasName).toList();
    if (filled.isEmpty) return '';

    String fullName(_GroupMemberInput m) {
      final fn = m.firstName.text.trim();
      final ln = m.lastName.text.trim();
      return ('$fn $ln').trim();
    }

    String firstThenLast(_GroupMemberInput m, {required bool includeLast}) {
      final fn = m.firstName.text.trim();
      final ln = m.lastName.text.trim();
      if (includeLast && ln.isNotEmpty) {
        return ('$fn $ln').trim();
      }
      return fn.isNotEmpty ? fn : ln;
    }

    if (filled.length == 1) {
      return fullName(filled.first);
    }

    final nonBlankLastNames = filled
        .map((m) => m.lastName.text.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    final sameLastName = nonBlankLastNames.length == 1;

    if (sameLastName) {
      final sharedLastName = nonBlankLastNames.first;
      final firstParts = filled
          .map((m) => m.firstName.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (firstParts.isEmpty) {
        return sharedLastName;
      }

      return '${firstParts.join(', ')} $sharedLastName';
    }

    return filled.map((m) => firstThenLast(m, includeLast: true)).join(', ');
  }

  void _setType(String newType) {
    if (_type == newType) return;

    setState(() {
      _type = newType;
      _msg = null;

      if (_isGroup) {
        _firstName.clear();
        _lastName.clear();
        _arba.clear();

        if (_groupMembers.isEmpty) {
          _addBlankGroupMember();
        }
        _ensureTrailingBlankGroupMember();
      } else {
        _clearGroupMembers();
        _groupShowsAsYouth = false;
      }

      if (!_showingNameTouched) {
        _recomputeShowingName();
      }
    });
  }

  void _clearGroupMembers() {
    for (final m in _groupMembers) {
      m.dispose();
    }
    _groupMembers.clear();
  }

  void _addBlankGroupMember() {
    final member = _GroupMemberInput();
    member.firstName.addListener(_onGroupMembersChanged);
    member.lastName.addListener(_onGroupMembersChanged);
    member.arbaNumber.addListener(_onGroupMembersChanged);
    _groupMembers.add(member);
  }

  void _ensureTrailingBlankGroupMember() {
    if (_groupMembers.isEmpty || _groupMembers.last.hasAnyValue) {
      _addBlankGroupMember();
    }
  }

  void _trimExtraTrailingBlanks() {
    while (_groupMembers.length > 1 &&
        _groupMembers.last.isBlank &&
        _groupMembers[_groupMembers.length - 2].isBlank) {
      final removed = _groupMembers.removeLast();
      removed.dispose();
    }
  }

  void _onGroupMembersChanged() {
    if (!mounted) return;

    setState(() {
      _trimExtraTrailingBlanks();
      _ensureTrailingBlankGroupMember();

      if (!_showingNameTouched) {
        _recomputeShowingName();
      }
    });
  }

  List<_GroupMemberInput> get _filledGroupMembers =>
      _groupMembers.where((m) => m.hasAnyValue).toList();

  Future<void> _pickGroupMemberBirthDate(_GroupMemberInput member) async {
    final initial = member.birthDate ?? DateTime(DateTime.now().year - 10, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked == null) return;

    setState(() {
      member.birthDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _prefillFromPrimaryExhibitor(String ownerUserId) async {
    final rows = await supabase
        .from('exhibitors')
        .select(
          'id, email, phone, address_line1, address_line2, city, state, zip',
        )
        .eq('owner_user_id', ownerUserId)
        .eq('is_active', true)
        .order('created_at', ascending: true)
        .limit(1);

    if (rows is! List || rows.isEmpty) return;

    final primary = Map<String, dynamic>.from(rows.first as Map);

    if (_email.text.trim().isEmpty) {
      _email.text = (primary['email'] ?? '').toString();
    }
    if (_phone.text.trim().isEmpty) {
      _phone.text = (primary['phone'] ?? '').toString();
    }
    if (_address1.text.trim().isEmpty) {
      _address1.text = (primary['address_line1'] ?? '').toString();
    }
    if (_address2.text.trim().isEmpty) {
      _address2.text = (primary['address_line2'] ?? '').toString();
    }
    if (_city.text.trim().isEmpty) {
      _city.text = (primary['city'] ?? '').toString();
    }
    if (_state.text.trim().isEmpty) {
      _state.text = (primary['state'] ?? '').toString();
    }
    if (_zip.text.trim().isEmpty) {
      _zip.text = (primary['zip'] ?? '').toString();
    }
  }

  Future<void> _loadIfEditing() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _msg = 'Not signed in.';
      });
      return;
    }

    if (!_isEdit) {
      try {
        await _prefillFromPrimaryExhibitor(user.id);
      } catch (_) {
        // Non-blocking on purpose.
      }

      setState(() {
        _loading = false;
        if (_isGroup) {
          _ensureTrailingBlankGroupMember();
        }
      });
      return;
    }

    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final row = await supabase
          .from('exhibitors')
          .select(
            'id, owner_user_id, type, display_name, showing_name, '
            'arba_number, email, phone, birth_date, is_active, '
            'first_name, last_name, '
            'address_line1, address_line2, city, state, zip, '
            'group_members, group_shows_as_youth',
          )
          .eq('id', widget.exhibitorId!)
          .single();

      if (!mounted) return;

      final first = (row['first_name'] ?? '').toString();
      final last = (row['last_name'] ?? '').toString();
      final showing =
          (row['showing_name'] ?? row['display_name'] ?? '').toString();

      _type = (row['type'] ?? 'adult').toString();
      _active = row['is_active'] == true;

      _firstName.text = first;
      _lastName.text = last;
      _showingName.text = showing;
      _arba.text = (row['arba_number'] ?? '').toString();
      _email.text = (row['email'] ?? '').toString();
      _phone.text = (row['phone'] ?? '').toString();

      _address1.text = (row['address_line1'] ?? '').toString();
      _address2.text = (row['address_line2'] ?? '').toString();
      _city.text = (row['city'] ?? '').toString();
      _state.text = (row['state'] ?? '').toString();
      _zip.text = (row['zip'] ?? '').toString();

      final bd = row['birth_date']?.toString();
      _birthDate = bd == null || bd.isEmpty ? null : DateTime.tryParse(bd);
      _groupShowsAsYouth = row['group_shows_as_youth'] == true;

      _clearGroupMembers();

      if (_type == 'group') {
        final rawMembers = row['group_members'];
        if (rawMembers is List) {
          for (final item in rawMembers) {
            if (item is Map) {
              final member = _GroupMemberInput();
              member.firstName.text = (item['first_name'] ?? '').toString();
              member.lastName.text = (item['last_name'] ?? '').toString();
              member.arbaNumber.text = (item['arba_number'] ?? '').toString();

              final memberBirthDate = item['birth_date']?.toString();
              member.birthDate = memberBirthDate == null || memberBirthDate.isEmpty
                  ? null
                  : DateTime.tryParse(memberBirthDate);

              member.firstName.addListener(_onGroupMembersChanged);
              member.lastName.addListener(_onGroupMembersChanged);
              member.arbaNumber.addListener(_onGroupMembersChanged);

              _groupMembers.add(member);
            }
          }
        }

        _ensureTrailingBlankGroupMember();
      }

      _showingNameTouched = showing.trim() != _buildAutoShowingName().trim();

      setState(() {
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

  bool _isValidEmail(String v) {
    final s = v.trim();
    if (s.isEmpty) return true;
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(s);
  }

  bool _isValidPhone(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty || (digits.length >= 10 && digits.length <= 15);
  }

  String _digitsOnlyPhone(String v) => v.replaceAll(RegExp(r'\D'), '');

  bool _fail(String m) {
    setState(() => _msg = m);
    return false;
  }

  bool _isYouthEligible(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;

    final hadBirthdayThisYear =
        (today.month > birthDate.month) ||
        (today.month == birthDate.month && today.day >= birthDate.day);

    if (!hadBirthdayThisYear) {
      age--;
    }

    return age < 19;
  }

  bool _validateGroupMembers() {
    final filled = _filledGroupMembers;
    if (filled.isEmpty) return _fail('Add at least one group member.');

    for (final m in filled) {
      if (!m.hasName) {
        return _fail(
          'Each group member must include at least a first or last name.',
        );
      }

      if (_groupShowsAsYouth) {
        if (m.birthDate == null) {
          return _fail(
            'Birth date is required for each youth group/family member.',
          );
        }

        if (!_isYouthEligible(m.birthDate!)) {
          final name =
              ('${m.firstName.text.trim()} ${m.lastName.text.trim()}').trim();
          return _fail(
            name.isEmpty
                ? 'One group member is not youth-eligible based on birth date.'
                : '$name is not youth-eligible based on birth date.',
          );
        }
      }
    }

    return true;
  }

  bool _validate() {
    final showing = _showingName.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();

    if (_isGroup) {
      if (!_validateGroupMembers()) return false;
    } else {
      if (_firstName.text.trim().isEmpty) {
        return _fail('First name is required.');
      }
      if (_lastName.text.trim().isEmpty) {
        return _fail('Last name is required.');
      }
    }

    if (showing.isEmpty) return _fail('Showing name is required.');

    if (email.isNotEmpty && !_isValidEmail(email)) {
      return _fail('Please enter a valid email.');
    }

    if (phone.isNotEmpty && !_isValidPhone(phone)) {
      return _fail('Please enter a valid phone number.');
    }

    if (_isYouth && _birthDate == null) {
      return _fail('Birth date is required for Youth.');
    }

    if (_isYouth && _birthDate != null && !_isYouthEligible(_birthDate!)) {
      return _fail('This exhibitor is not youth-eligible based on birth date.');
    }

    return true;
  }

  Future<void> _pickBirthDate() async {
    final initial = _birthDate ?? DateTime(DateTime.now().year - 10, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _birthDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    if (!_validate()) return;

    final showingName = _showingName.text.trim();

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final groupMembersPayload = _isGroup
          ? _filledGroupMembers
                .map(
                  (m) => {
                    'first_name': m.firstName.text.trim(),
                    'last_name': m.lastName.text.trim(),
                    'arba_number': m.arbaNumber.text.trim().isEmpty
                        ? null
                        : m.arbaNumber.text.trim(),
                    'birth_date': m.birthDate == null
                        ? null
                        : m.birthDate!.toIso8601String().substring(0, 10),
                  },
                )
                .toList()
          : null;

      final payload = <String, dynamic>{
        'owner_user_id': user.id,
        'type': _type,
        'is_active': _active,
        'group_shows_as_youth': _isGroup ? _groupShowsAsYouth : false,

        'display_name': showingName,
        'showing_name': showingName,

        'first_name': _isGroup ? null : _firstName.text.trim(),
        'last_name': _isGroup ? null : _lastName.text.trim(),
        'arba_number': _isGroup
            ? null
            : (_arba.text.trim().isEmpty ? null : _arba.text.trim()),

        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty
            ? null
            : _digitsOnlyPhone(_phone.text),

        'address_line1':
            _address1.text.trim().isEmpty ? null : _address1.text.trim(),
        'address_line2':
            _address2.text.trim().isEmpty ? null : _address2.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'state': _state.text.trim().isEmpty ? null : _state.text.trim(),
        'zip': _zip.text.trim().isEmpty ? null : _zip.text.trim(),

        'birth_date': _birthDate == null
            ? null
            : _birthDate!.toIso8601String().substring(0, 10),

        'group_members': groupMembersPayload,
      };

      Map<String, dynamic> savedRow;

      if (_isEdit) {
        savedRow = await supabase
            .from('exhibitors')
            .update(payload)
            .eq('id', widget.exhibitorId!)
            .select()
            .single();
      } else {
        savedRow = await supabase
            .from('exhibitors')
            .insert(payload)
            .select()
            .single();
      }

      if (!mounted) return;
      Navigator.pop(context, savedRow);
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
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
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildGroupMemberBlock(int index, _GroupMemberInput member) {
    final filledMembers = _filledGroupMembers;
    final isTrailingBlank = member.isBlank && index == _groupMembers.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              isTrailingBlank ? 'Add another member' : 'Member ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: member.firstName,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'First Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: member.lastName,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Last Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: member.arbaNumber,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'ARBA Number',
              border: OutlineInputBorder(),
            ),
          ),
        if (_groupShowsAsYouth) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  member.birthDate == null
                      ? 'Birth date: (not set)'
                      : 'Birth date: ${member.birthDate!.toIso8601String().substring(0, 10)}',
                ),
              ),
              TextButton(
                onPressed: _saving ? null : () => _pickGroupMemberBirthDate(member),
                child: const Text('Pick'),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => member.birthDate = null),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
          if (!isTrailingBlank && filledMembers.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          final removed = _groupMembers.removeAt(index);
                          removed.dispose();
                          _trimExtraTrailingBlanks();
                          _ensureTrailingBlankGroupMember();
                          if (!_showingNameTouched) {
                            _recomputeShowingName();
                          }
                        });
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Exhibitor' : 'Add Exhibitor'),
      content: SizedBox(
        width: 700,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_msg != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.withOpacity(.25)),
                        ),
                        child: Text(
                          _msg!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _buildSectionCard(
                      title: 'Exhibitor Type',
                      children: [
                        DropdownButtonFormField<String>(
                          value: _type,
                          items: const [
                            DropdownMenuItem(
                              value: 'adult',
                              child: Text('Adult'),
                            ),
                            DropdownMenuItem(
                              value: 'youth',
                              child: Text('Youth (under 19)'),
                            ),
                            DropdownMenuItem(
                              value: 'group',
                              child: Text('Group / Family'),
                            ),
                          ],
                          onChanged:
                              _saving ? null : (v) => _setType(v ?? 'adult'),
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    _buildSectionCard(
                      title: 'Birth Date & Status',
                      children: [
                        if (_isGroup)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Youth Showing Group'),
                            subtitle: const Text(
                              'Turn this on when all members of this group/family are youth exhibitors.',
                            ),
                            value: _groupShowsAsYouth,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() {
                                      _groupShowsAsYouth = v;
                                    }),
                          ),
                        if (!_isGroup) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _birthDate == null
                                      ? 'Birth date: (not set)'
                                      : 'Birth date: ${_birthDate!.toIso8601String().substring(0, 10)}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving ? null : _pickBirthDate,
                                child: const Text('Pick'),
                              ),
                              if (_isYouth)
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _birthDate = null),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _isGroup && _groupShowsAsYouth
                                ? 'Each youth group/family member must have their own birth date.'
                                : _isYouth
                                    ? 'Birth date is required for Youth.'
                                    : 'Birth date is only required for youth exhibitors. Youth groups require a birth date for each member.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Active'),
                          subtitle: const Text(
                            'Inactive exhibitors won’t show in entry pickers.',
                          ),
                          value: _active,
                          onChanged:
                              _saving ? null : (v) => setState(() => _active = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    if (_isGroup)
                      _buildSectionCard(
                        title: 'Group Members',
                        children: [
                          ...List.generate(
                            _groupMembers.length,
                            (index) => _buildGroupMemberBlock(
                              index,
                              _groupMembers[index],
                            ),
                          ),
                        ],
                      )
                    else
                      _buildSectionCard(
                        title: 'Names',
                        children: [
                          TextField(
                            controller: _firstName,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'First name *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _lastName,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Last name *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _arba,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'ARBA number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    _buildSectionCard(
                      title: 'Showing Name',
                      children: [
                        TextField(
                          controller: _showingName,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Showing name',
                            helperText: 'Auto-generated unless you change it.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    _buildSectionCard(
                      title: 'Contact Information',
                      children: [
                        if (!_isEdit)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'For additional exhibitors, contact and address fields may be prefilled from the primary profile. You can still change them.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        TextField(
                          controller: _email,
                          enabled: !_saving,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phone,
                          enabled: !_saving,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    _buildSectionCard(
                      title: 'Address',
                      children: [
                        TextField(
                          controller: _address1,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Address line 1',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _address2,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Address line 2',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _city,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _state,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'State',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _zip,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'ZIP',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Exhibitor'),
        ),
      ],
    );
  }
}

class _GroupMemberInput {
  final TextEditingController firstName = TextEditingController();
  final TextEditingController lastName = TextEditingController();
  final TextEditingController arbaNumber = TextEditingController();

  DateTime? birthDate;

  bool get isBlank =>
      firstName.text.trim().isEmpty &&
      lastName.text.trim().isEmpty &&
      arbaNumber.text.trim().isEmpty &&
      birthDate == null;

  bool get hasAnyValue =>
      firstName.text.trim().isNotEmpty ||
      lastName.text.trim().isNotEmpty ||
      arbaNumber.text.trim().isNotEmpty ||
      birthDate != null;

  bool get hasName =>
      firstName.text.trim().isNotEmpty || lastName.text.trim().isNotEmpty;

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    arbaNumber.dispose();
  }
}