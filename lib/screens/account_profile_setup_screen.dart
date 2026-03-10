import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'show_list_screen.dart';

final supabase = Supabase.instance.client;

/// Exhibitor Add/Edit screen
/// Uses "Showing name" in the UI, but writes to DB column `display_name`.
/// Adds basic email + phone format validation.
///
/// Assumes `exhibitors` has at least:
/// id, owner_user_id, type, display_name, arba_number, email, phone,
/// birth_date, is_active,
/// address_line1, address_line2, city, state, zip
///
/// Optional columns supported if they exist:
/// first_name, last_name
class AccountProfileSetupScreen extends StatefulWidget {
  /// If null -> create new exhibitor
  final String? exhibitorId;

  const AccountProfileSetupScreen({super.key, this.exhibitorId});

  @override
  State<AccountProfileSetupScreen> createState() => _AccountProfileSetupScreenState();
}

class _AccountProfileSetupScreenState extends State<AccountProfileSetupScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  // form
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

  // Track whether user has manually edited showing name
  bool _showingNameTouched = false;

  @override
  void initState() {
    super.initState();
    _wireAutofillShowingName();
    _loadIfEditing();
  }

  void _wireAutofillShowingName() {
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

  Future<void> _loadIfEditing() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _msg = 'Not signed in.';
      });
      return;
    }

    if (widget.exhibitorId == null) {
      setState(() => _loading = false);
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
            'id,owner_user_id,type,display_name,arba_number,email,phone,'
            'birth_date,is_active,'
            'first_name,last_name,'
            'address_line1,address_line2,city,state,zip',
          )
          .eq('id', widget.exhibitorId!)
          .single();

      if (!mounted) return;

      final first = (row['first_name'] ?? '').toString();
      final last = (row['last_name'] ?? '').toString();
      final showing = (row['display_name'] ?? '').toString();

      setState(() {
        _type = (row['type'] ?? 'adult').toString();
        _active = row['is_active'] == true;

        _firstName.text = first;
        _lastName.text = last;

        _showingName.text = showing;
        _showingNameTouched = showing.trim() != ('$first $last').trim();

        _arba.text = (row['arba_number'] ?? '').toString();
        _email.text = (row['email'] ?? '').toString();
        _phone.text = (row['phone'] ?? '').toString();

        _address1.text = (row['address_line1'] ?? '').toString();
        _address2.text = (row['address_line2'] ?? '').toString();
        _city.text = (row['city'] ?? '').toString();
        _state.text = (row['state'] ?? '').toString();
        _zip.text = (row['zip'] ?? '').toString();

        final bd = row['birth_date']?.toString();
        _birthDate = bd == null ? null : DateTime.tryParse(bd);

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
  // Validation
  // ------------------------------

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
    final email = _email.text.trim();
    final phone = _phone.text.trim();

    if (first.isEmpty) return _fail('First name is required.');
    if (last.isEmpty) return _fail('Last name is required.');

    final showingName = (showing.isNotEmpty ? showing : '$first $last').trim();
    if (showingName.isEmpty) return _fail('Showing name is required.');

    if (email.isEmpty) return _fail('Email is required.');
    if (!_isValidEmail(email)) return _fail('Please enter a valid email (example: name@example.com).');

    if (phone.isEmpty) return _fail('Phone is required.');
    if (!_isValidPhone(phone)) return _fail('Please enter a valid phone number (at least 10 digits).');

    if (_address1.text.trim().isEmpty) return _fail('Address line 1 is required.');
    if (_city.text.trim().isEmpty) return _fail('City is required.');
    if (_state.text.trim().isEmpty) return _fail('State is required.');
    if (_zip.text.trim().isEmpty) return _fail('ZIP is required.');

    if (_type == 'youth' && _birthDate == null) return _fail('Birth date is required for Youth.');
    return true;
  }

  // ------------------------------
  // Actions
  // ------------------------------

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

        // required in your DB
        'display_name': showingName,

        // optional columns (remove if not in DB)
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

        'birth_date': _birthDate == null ? null : _birthDate!.toIso8601String().substring(0, 10),
      };

      if (widget.exhibitorId == null) {
        await supabase.from('exhibitors').insert(payload);
      } else {
        await supabase.from('exhibitors').update(payload).eq('id', widget.exhibitorId!);
      }

      if (!mounted) return;

      // If opened from Account Settings → go back
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
        return;
      }

      // First-time setup (Root) → replace stack with app
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ShowListScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  } // ✅ IMPORTANT: this closes _save()

  // ------------------------------
  // UI
  // ------------------------------

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.exhibitorId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Exhibitor' : 'Add Exhibitor'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_msg!, style: const TextStyle(color: Colors.red)),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _type,
                            items: const [
                              DropdownMenuItem(value: 'adult', child: Text('Adult')),
                              DropdownMenuItem(value: 'youth', child: Text('Youth (under 19)')),
                              DropdownMenuItem(value: 'group', child: Text('Group / Family')),
                            ],
                            onChanged: _saving ? null : (v) => setState(() => _type = v ?? 'adult'),
                            decoration: const InputDecoration(labelText: 'Type'),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: _firstName,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'First name *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _lastName,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Last name *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _showingName,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Showing name',
                              helperText: 'Defaults to First + Last unless changed.',
                            ),
                          ),

                          const SizedBox(height: 8),
                          TextField(
                            controller: _arba,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'ARBA number'),
                          ),

                          const SizedBox(height: 12),

                          TextField(
                            controller: _email,
                            enabled: !_saving,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Email *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _phone,
                            enabled: !_saving,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Phone *',
                              helperText: 'Example: (260) 555-1234',
                            ),
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller: _address1,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Address line 1 *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _address2,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Address line 2'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _city,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'City *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _state,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'State *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _zip,
                            enabled: !_saving,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(labelText: 'ZIP *'),
                          ),

                          const SizedBox(height: 16),

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
                                  onPressed: _saving ? null : () => setState(() => _birthDate = null),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _type == 'youth'
                                  ? 'Birth date is required for Youth.'
                                  : 'Birth date is only required for Youth exhibitors.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),

                          const SizedBox(height: 16),

                          SwitchListTile(
                            title: const Text('Active'),
                            subtitle: const Text('Inactive exhibitors won’t show up in pickers.'),
                            value: _active,
                            onChanged: _saving ? null : (v) => setState(() => _active = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving…' : 'Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}