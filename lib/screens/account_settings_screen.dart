// lib/screens/account_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_profile_setup_screen.dart';

final supabase = Supabase.instance.client;

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _loading = true;
  String? _msg;
  List<Map<String, dynamic>> _exhibitors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _msg = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rows = await supabase
          .from('exhibitors')
          .select(
            'id,type,display_name,arba_number,email,phone,'
            'birth_date,is_active,created_at,'
            'first_name,last_name,'
            'address_line1,address_line2,city,state,zip',
          )
          .eq('owner_user_id', user.id)
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _exhibitors = (rows as List).cast<Map<String, dynamic>>();
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

  // ------------------------------
  // Profile (Option A: profiles table)
  // ------------------------------
  Future<void> _openProfileSetup() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AccountProfileSetupScreen()),
    );

    if (saved == true) {
      // Optional: refresh in case profile info is used elsewhere
      if (mounted) setState(() => _msg = 'Profile saved.');
    }
  }

  // ------------------------------
  // Exhibitors (separate from profile)
  // ------------------------------
  Future<void> _openExhibitorEditor({Map<String, dynamic>? existing}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExhibitorEditorScreen(existing: existing),
        fullscreenDialog: true,
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _toggleActive(String id, bool newActive) async {
    try {
      await supabase.from('exhibitors').update({'is_active': newActive}).eq('id', id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
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
            const Expanded(
              child: Text(
                'Account Settings',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add Exhibitor',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _loading ? null : () => _openExhibitorEditor(),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
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
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : SafeArea(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      if (_msg != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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

                      Expanded(
                        child: _exhibitors.isEmpty
                            ? const Center(
                                child: Text(
                                  'No exhibitors yet.\nTap + to add one.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _exhibitors.length,
                                itemBuilder: (context, i) {
                                  final e = _exhibitors[i];
                                  final id = e['id'].toString();
                                  final type = (e['type'] ?? '').toString();
                                  final name = (e['display_name'] ?? '').toString();
                                  final active = e['is_active'] == true;
                                  final bd = e['birth_date']?.toString();

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
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
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Type: ${type.toUpperCase()}'
                                        '${bd == null ? '' : ' • DOB: $bd'}'
                                        '${active ? '' : ' • INACTIVE'}',
                                      ),
                                      onTap: () =>
                                          _openExhibitorEditor(existing: e),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'edit') {
                                            _openExhibitorEditor(existing: e);
                                          }
                                          if (v == 'deactivate') {
                                            _toggleActive(id, false);
                                          }
                                          if (v == 'activate') {
                                            _toggleActive(id, true);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          if (active)
                                            const PopupMenuItem(
                                              value: 'deactivate',
                                              child: Text('Deactivate'),
                                            )
                                          else
                                            const PopupMenuItem(
                                              value: 'activate',
                                              child: Text('Activate'),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          
      ),
    );
  }
}
class ExhibitorEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const ExhibitorEditorScreen({super.key, this.existing});

  @override
  State<ExhibitorEditorScreen> createState() => _ExhibitorEditorScreenState();
}

class _ExhibitorEditorScreenState extends State<ExhibitorEditorScreen> {
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
  bool _showingNameTouched = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final e = widget.existing;

    _type = (e?['type'] ?? 'adult').toString();
    _active = e == null ? true : (e['is_active'] == true);

    _firstName.text = (e?['first_name'] ?? '').toString();
    _lastName.text = (e?['last_name'] ?? '').toString();

    final existingShowing = (e?['display_name'] ?? '').toString();
    _showingName.text = existingShowing;

    _arba.text = (e?['arba_number'] ?? '').toString();
    _email.text = (e?['email'] ?? '').toString();
    _phone.text = (e?['phone'] ?? '').toString();

    _address1.text = (e?['address_line1'] ?? '').toString();
    _address2.text = (e?['address_line2'] ?? '').toString();
    _city.text = (e?['city'] ?? '').toString();
    _state.text = (e?['state'] ?? '').toString();
    _zip.text = (e?['zip'] ?? '').toString();

    final bd = e?['birth_date']?.toString();
    _birthDate = bd == null ? null : DateTime.tryParse(bd);

    void recompute() {
      if (_showingNameTouched) return;
      final fn = _firstName.text.trim();
      final ln = _lastName.text.trim();
      final combined = ('$fn $ln').trim();
      _showingName.text = combined;
      _showingName.selection = TextSelection.fromPosition(
        TextPosition(offset: _showingName.text.length),
      );
    }

    _firstName.addListener(recompute);
    _lastName.addListener(recompute);

    _showingName.addListener(() {
      final fn = _firstName.text.trim();
      final ln = _lastName.text.trim();
      final combined = ('$fn $ln').trim();
      if (_showingName.text.trim() != combined) {
        _showingNameTouched = true;
      }
    });

    final fn0 = _firstName.text.trim();
    final ln0 = _lastName.text.trim();
    final combined0 = ('$fn0 $ln0').trim();
    if (existingShowing.trim().isNotEmpty && existingShowing.trim() != combined0) {
      _showingNameTouched = true;
    }
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
    super.dispose();
  }

  bool _isValidEmail(String v) {
    final s = v.trim();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(s);
  }

  bool _isValidPhone(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 && digits.length <= 15;
  }

  String _digitsOnlyPhone(String v) => v.replaceAll(RegExp(r'\D'), '');

  bool _fail(String m) {
    setState(() => _msg = m);
    return false;
  }

  bool _validate() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final showing = _showingName.text.trim();

    if (first.isEmpty) return _fail('First name is required.');
    if (last.isEmpty) return _fail('Last name is required.');

    final showingName = (showing.isNotEmpty ? showing : '$first $last').trim();
    if (showingName.isEmpty) return _fail('Showing name is required.');

    final email = _email.text.trim();
    if (email.isEmpty) return _fail('Email is required.');
    if (!_isValidEmail(email)) return _fail('Please enter a valid email.');

    final phone = _phone.text.trim();
    if (phone.isEmpty) return _fail('Phone is required.');
    if (!_isValidPhone(phone)) return _fail('Please enter a valid phone (10+ digits).');

    if (_address1.text.trim().isEmpty) return _fail('Address line 1 is required.');
    if (_city.text.trim().isEmpty) return _fail('City is required.');
    if (_state.text.trim().isEmpty) return _fail('State is required.');
    if (_zip.text.trim().isEmpty) return _fail('ZIP is required.');

    if (_type == 'youth' && _birthDate == null) {
      return _fail('Birth date is required for Youth.');
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
    setState(() => _birthDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (!_validate()) return;

    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final showing = _showingName.text.trim();
    final showingName = (showing.isNotEmpty ? showing : '$first $last').trim();

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final payload = <String, dynamic>{
        'owner_user_id': user.id,
        'type': _type,
        'is_active': _active,
        'display_name': showingName,
        'first_name': first,
        'last_name': last,
        'arba_number': _arba.text.trim().isEmpty ? null : _arba.text.trim(),
        'email': _email.text.trim(),
        'phone': _digitsOnlyPhone(_phone.text),
        'address_line1': _address1.text.trim(),
        'address_line2': _address2.text.trim().isEmpty ? null : _address2.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'zip': _zip.text.trim(),
        'birth_date': _birthDate == null
            ? null
            : _birthDate!.toIso8601String().substring(0, 10),
      };

      if (_isEdit) {
        await supabase
            .from('exhibitors')
            .update(payload)
            .eq('id', widget.existing!['id']);
      } else {
        await supabase.from('exhibitors').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildCard({
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
                _isEdit ? 'Edit Exhibitor' : 'Add Exhibitor',
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
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F6FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_msg != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
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

                          _buildCard(
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
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() => _type = v ?? 'adult'),
                                decoration: const InputDecoration(
                                  labelText: 'Type',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),

                          _buildCard(
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
                                controller: _showingName,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: 'Showing name',
                                  helperText: 'Defaults to First + Last unless changed.',
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

                          _buildCard(
                            title: 'Contact Information',
                            children: [
                              TextField(
                                controller: _email,
                                enabled: !_saving,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email *',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _phone,
                                enabled: !_saving,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone *',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),

                          _buildCard(
                            title: 'Address',
                            children: [
                              TextField(
                                controller: _address1,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: 'Address line 1 *',
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
                                  labelText: 'City *',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _state,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: 'State *',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _zip,
                                enabled: !_saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'ZIP *',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),

                          _buildCard(
                            title: 'Birth Date & Status',
                            children: [
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
                                  if (_type == 'youth')
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => setState(() => _birthDate = null),
                                      child: const Text('Clear'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _type == 'youth'
                                      ? 'Birth date is required for Youth.'
                                      : 'Birth date only required for Youth.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('Active'),
                                subtitle: const Text(
                                  'Inactive exhibitors won’t show in pickers.',
                                ),
                                value: _active,
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() => _active = v),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A623),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

