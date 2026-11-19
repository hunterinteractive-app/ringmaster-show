import '../../services/show_assistant_service.dart';
// lib/screens/admin/edit_show_settings_screen.dart
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, use_build_context_synchronously

import 'package:ringmaster_show/services/final_award_format.dart';
import 'package:ringmaster_show/services/final_award_access_service.dart';
import 'package:flutter/material.dart';
import 'show_addon_settings_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:ringmaster_show/widgets/help_report_dialog.dart';
import '../../services/locked_show_data_export.dart';

import '../show_list_screen.dart';
import '../../services/club_service.dart';
import '../../services/app_session.dart';
import 'show_breed_settings_screen.dart';
import 'show_sanctions_dialog.dart';
import 'show_fees_dialog.dart';
import 'payback_settings_dialog.dart';
import 'show_role_assignments_dialog.dart';
import 'show_sections_dialog.dart';
import 'show_judges_dialog.dart';
import 'show_checkin_settings_dialog.dart';
import 'show_wave_schedule_dialog.dart';
import 'show_checkin_dashboard_screen.dart';
import 'checkin_change_requests_screen.dart';
import 'show_finances_screen.dart';
import '../../widgets/rm_timezone_notice_banner.dart';
import '../../widgets/rm_widgets.dart';
import '../../widgets/show_layout_scope.dart';
import '../../services/show_permissions_service.dart';
import '../../services/stripe_connect_service.dart';

// ✅ Admin Operations (Pre-show) screens
import 'admin_entry_management_screen.dart';
import 'admin_show_reports_screen.dart';
import 'coop_numbers_screen.dart';
import 'admin_print_packs_screen.dart';

// ✅ Admin Operations (Post-show) screens
import 'results/admin_results_entry_screen.dart';
import 'package:ringmaster_show/screens/admin/show_closeout.dart';
import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';
import 'admin_audit_log_screen.dart';
import '../../superintendent/superintendent_lineup_screen.dart';

SupabaseClient get supabase => ringMasterClient;

enum _ShowWorkspaceArea {
  overview('Overview'),
  setup('Setup'),
  entries('Entries & Check-In'),
  judging('Judging'),
  finances('Finances'),
  reports('Reports & Closeout');

  const _ShowWorkspaceArea(this.label);

  final String label;
}

enum _ShowTool {
  judges,
  balances,
  entries,
  breedCounts,
  coopNumbers,
  printPacks,
  checkIn,
  results,
  legacyCloseout,
  closeout,
  lock,
  export,
  breeds,
  sections,
  sanctions,
  fees,
  waves,
  contests,
  addOns,
  checkInSettings,
  paybacks,
  lineup,
  roles,
  audit,
  controlSheets,
  changeRequests,
}

class EditShowSettingsScreen extends StatefulWidget {
  final String showId;
  final bool demoMode;

  const EditShowSettingsScreen({
    super.key,
    required this.showId,
    this.demoMode = false,
  });

  @override
  State<EditShowSettingsScreen> createState() => _EditShowSettingsScreenState();
}

class _EditShowSettingsScreenState extends State<EditShowSettingsScreen> {
  // Keep the previous entry points available in code while Close Show/Reports
  // V2 is rolled out.  They can be restored by changing this flag.
  static const bool _showLegacyCloseoutActions = false;

  bool _loading = true;
  bool _loadingPermissions = true;
  ShowPermissions _permissions = ShowPermissions.none;
  bool _canManageCheckinSettings = false;
  bool _saving = false;
  String? _msg;
  bool _loadingStripeStatus = false;
  Map<String, dynamic>? _stripeStatus;
  Map<String, dynamic>? _myStaffPin;
  bool _loadingPins = false;
  bool _regeneratingPins = false;
  _ShowWorkspaceArea _workspaceArea = _ShowWorkspaceArea.overview;
  Future<Map<String, dynamic>>? _checkinSummary;
  Future<void> _loadStaffPins() async {
    setState(() => _loadingPins = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        throw Exception('No signed-in user found.');
      }

      final rows = await supabase
          .rpc(
            'get_my_show_staff_approval_pin',
            params: {'p_show_id': widget.showId},
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('PIN lookup timed out.'),
          );
      if (!mounted) return;
      setState(() {
        final list = rows as List;
        _myStaffPin = list.isEmpty
            ? null
            : Map<String, dynamic>.from(list.first as Map);
        _loadingPins = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPins = false;
        _msg = 'Failed to load your staff PIN: $e';
      });
    }
  }

  Future<void> _regenerateStaffPins() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Regenerate Staff PINs?'),
            content: const Text(
              'This will replace your approval PIN for this show. You will need the new code before approving corrections.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Regenerate'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _regeneratingPins = true;
      _msg = null;
    });

    try {
      await supabase
          .rpc(
            'regenerate_my_show_staff_approval_pin',
            params: {'p_show_id': widget.showId},
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('PIN generation timed out.'),
          );

      await _loadStaffPins();

      if (!mounted) return;
      setState(() {
        _regeneratingPins = false;
        _msg = 'Your staff PIN was regenerated.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _regeneratingPins = false;
        _msg = 'Failed to regenerate your staff PIN: $e';
      });
    }
  }

  final _name = TextEditingController();
  final _location = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? _entryOpenAt;
  DateTime? _entryCloseAt;

  bool _published = false;
  bool _isNationalShow = false;
  String? _nationalShowSectionId;
  List<Map<String, dynamic>> _showSections = [];
  bool _isLocked = false;
  bool _isFinalized = false;
  bool _isCheckinPortalEnabled = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  String _timezone = 'America/Indiana/Indianapolis';
  String _showNameForTitle = 'Show';
  String _finalAwardMode = 'four_six_bis';
  bool _canConfigureBestOpposite = false;

  List<Map<String, dynamic>> _clubs = [];
  String? _selectedClubId;
  String? _selectedClubName;
  bool _loadingClubs = false;
  bool _canSwitchHostingClub = false;
  bool _canManageHostingClubs = false;
  static const String _addClubActionValue = '__add_new_club__';
  static const String _manageClubsActionValue = '__manage_clubs__';

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  DateTime _asLocal(DateTime dt) => dt.toLocal();

  String _effectiveShowName() {
    final n = _name.text.trim();
    return n.isEmpty ? _showNameForTitle : n;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '(not set)';
    final x = _asLocal(d);
    return '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '(not set)';
    final x = _asLocal(d);
    final hh = x.hour.toString().padLeft(2, '0');
    final mm = x.minute.toString().padLeft(2, '0');
    return '${_fmtDate(x)} $hh:$mm';
  }

  DateTime? _parseDateOnly(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  DateTime? _parseTs(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _finalAwardModeLabel(String mode) => finalAwardFormatLabel(mode);

  Future<void> _toggleShowLock() async {
    if (_isFinalized) return;

    final nextLocked = !_isLocked;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(nextLocked ? 'Lock Show?' : 'Unlock Show?'),
            content: Text(
              nextLocked
                  ? 'This will prevent setup changes like sections, fees, judges, sanctions, rules, and show details.\n\n Show data and report files may be retained on the server for up to 1 year.\n\nYou can unlock it at any time.'
                  : 'This will allow setup changes again. Only unlock if corrections are needed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(nextLocked ? 'Lock Show' : 'Unlock Show'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase
          .from('shows')
          .update({
            'is_locked': nextLocked,
            'locked_at': nextLocked
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('id', widget.showId);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _isLocked = nextLocked;
        _msg = nextLocked ? 'Show locked.' : 'Show unlocked.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Failed to update lock status: $e';
      });
    }
  }

  Future<void> _loadClubs() async {
    setState(() => _loadingClubs = true);

    try {
      final clubs = await ClubService.loadMyClubs();
      final canSwitch = await ClubService.canSwitchHostingClub();
      final canManage =
          clubs.isEmpty || clubs.any(ClubService.canManageClubRecord);

      if (!mounted) return;
      setState(() {
        _clubs = clubs;
        _canSwitchHostingClub = canSwitch && canManage;
        _canManageHostingClubs = canManage;

        if ((_selectedClubId == null || _selectedClubId!.isEmpty) &&
            _clubs.isNotEmpty) {
          _selectedClubId = _clubs.first['id']?.toString();
          _selectedClubName = _clubs.first['name']?.toString();
        }

        // Keep the show's saved hosting club even if it is not in the user's club list.
        // This prevents existing shows from "falling back" to the first club on your account.
        if (_selectedClubId != null &&
            _selectedClubId!.isNotEmpty &&
            !_clubs.any((club) => club['id']?.toString() == _selectedClubId)) {
          _clubs.insert(0, {
            'id': _selectedClubId,
            'name':
                (_selectedClubName == null || _selectedClubName!.trim().isEmpty)
                ? 'Current Hosting Club'
                : _selectedClubName,
          });
        }

        if (_selectedClubId != null && _selectedClubId!.isNotEmpty) {
          final selected = _clubs.cast<Map<String, dynamic>?>().firstWhere(
            (club) => club?['id']?.toString() == _selectedClubId,
            orElse: () => null,
          );

          if (selected != null) {
            _selectedClubName = selected['name']?.toString();
          }
        }

        _loadingClubs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingClubs = false;
        _msg = 'Failed to load clubs: $e';
      });
    }
  }

  Future<void> _showAddClubDialog() async {
    final controller = TextEditingController();
    bool submitting = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final name = controller.text.trim();

              if (name.isEmpty) {
                setDialogState(() => errorText = 'Club name is required.');
                return;
              }

              setDialogState(() {
                submitting = true;
                errorText = null;
              });

              try {
                final created = await ClubService.createClub(name: name);

                if (!mounted) return;

                await _loadClubs();

                if (!mounted) return;
                setState(() {
                  _selectedClubId = created['id']?.toString();
                  _selectedClubName = created['name']?.toString();
                  _msg = 'Club added.';
                });

                Navigator.of(dialogContext).pop();
              } catch (e) {
                setDialogState(() {
                  submitting = false;
                  errorText = 'Failed to add club: $e';
                });
              }
            }

            return AlertDialog(
              title: const Text('Add New Club'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    enabled: !submitting,
                    decoration: InputDecoration(
                      labelText: 'Club name',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? 'Adding…' : 'Add Club'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _loadPermissions() async {
    try {
      var canManageCheckinSettings = false;
      try {
        canManageCheckinSettings =
            await supabase.rpc(
              'user_can_manage_show_checkin_settings',
              params: {'p_show_id': widget.showId},
            ) ==
            true;
      } catch (_) {
        // Keep this fail-closed until the database confirms access.
      }
      final permissions = await ShowPermissionsService.load(widget.showId);

      if (!mounted) return;
      setState(() {
        _permissions = permissions;
        _canManageCheckinSettings = canManageCheckinSettings;
        _loadingPermissions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissions = ShowPermissions.none;
        _canManageCheckinSettings = false;
        _loadingPermissions = false;
        _msg = 'Failed to load permissions: $e';
      });
    }
  }

  Future<void> _showManageClubsDialog() async {
    final renamedValues = <String, TextEditingController>{};

    for (final club in _clubs.where(ClubService.canManageClubRecord)) {
      final id = club['id']?.toString() ?? '';
      final name = (club['name'] ?? '').toString();
      renamedValues[id] = TextEditingController(text: name);
    }

    bool saving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> saveChanges() async {
              setDialogState(() {
                saving = true;
                errorText = null;
              });

              try {
                for (final club in _clubs.where(
                  ClubService.canManageClubRecord,
                )) {
                  final id = club['id']?.toString() ?? '';
                  final originalName = (club['name'] ?? '').toString();
                  final updatedName = renamedValues[id]!.text.trim();

                  if (updatedName.isEmpty) {
                    throw Exception('Club names cannot be blank.');
                  }

                  if (updatedName != originalName) {
                    await ClubService.updateClub(clubId: id, name: updatedName);
                  }
                }

                if (!mounted) return;

                await _loadClubs();

                if (!mounted) return;
                setState(() {
                  _msg = 'Clubs updated.';
                });

                Navigator.of(dialogContext).pop();
              } catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = 'Failed to update clubs: $e';
                });
              }
            }

            return AlertDialog(
              title: const Text('Manage Clubs'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (errorText != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: .25),
                            ),
                          ),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      for (final club in _clubs) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller:
                                renamedValues[club['id']?.toString() ?? ''],
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Club name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: saving ? null : saveChanges,
                  child: Text(saving ? 'Saving…' : 'Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in renamedValues.values) {
      controller.dispose();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
      _checkinSummary = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select(
            'id,name,location_name,start_date,end_date,timezone,is_published,is_national_show,national_show_section_id,entry_open_at,entry_close_at,final_award_mode,club_id,club_name,is_locked,locked_at,finalized_at',
          )
          .eq('id', widget.showId)
          .single();

      _showNameForTitle = (show['name'] ?? 'Show').toString();

      _name.text = (show['name'] ?? '').toString();
      _location.text = (show['location_name'] ?? '').toString();

      _startDate = _parseDateOnly(show['start_date']?.toString());
      _endDate = _parseDateOnly(show['end_date']?.toString());

      _timezone = (show['timezone'] ?? _timezone).toString();
      _published = show['is_published'] == true;
      _isNationalShow = show['is_national_show'] == true;
      _nationalShowSectionId = show['national_show_section_id']?.toString();
      _isLocked = show['is_locked'] == true;

      _showSections = List<Map<String, dynamic>>.from(
        await supabase
            .from('show_sections')
            .select('id,kind,letter,display_name')
            .eq('show_id', widget.showId)
            .eq('is_enabled', true)
            .order('sort_order'),
      );

      final checkinSettings = await supabase
          .from('show_checkin_settings')
          .select('is_enabled')
          .eq('show_id', widget.showId)
          .maybeSingle();
      _isCheckinPortalEnabled = checkinSettings?['is_enabled'] == true;

      final finalizedAt = (show['finalized_at'] ?? '').toString().trim();
      _isFinalized = finalizedAt.isNotEmpty;

      _entryOpenAt = _parseTs(show['entry_open_at']?.toString());
      _entryCloseAt = _parseTs(show['entry_close_at']?.toString());

      _canConfigureBestOpposite =
          await FinalAwardAccessService.canConfigureBestOpposite(widget.showId);
      _finalAwardMode = (show['final_award_mode'] ?? 'four_six_bis').toString();

      _selectedClubId = show['club_id']?.toString();
      _selectedClubName = show['club_name']?.toString();

      await _loadClubs();
      await _loadStripeStatus(showErrorInBanner: false);
      await _loadStaffPins();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  Future<void> _loadStripeStatus({bool showErrorInBanner = true}) async {
    if (mounted) {
      setState(() => _loadingStripeStatus = true);
    }

    try {
      final status = await StripeConnectService.getAccountStatus(widget.showId);

      if (!mounted) return;
      setState(() {
        _stripeStatus = status;
        _loadingStripeStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStripeStatus = false;
        if (showErrorInBanner) {
          _msg = 'Stripe status check failed: $e';
        }
      });
    }
  }

  Future<void> _refreshStripeStatusFromBanner() async {
    if (mounted) {
      setState(() {
        _loadingStripeStatus = true;
        _msg = null;
      });
    }

    try {
      await StripeConnectService.refreshAccountStatus(widget.showId);
      await _loadStripeStatus(showErrorInBanner: true);

      if (!mounted) return;
      setState(() {
        _msg = 'Stripe status refreshed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStripeStatus = false;
        _msg = 'Stripe status refresh failed: $e';
      });
    }
  }

  Future<void> _pickStartDate() async {
    final initial = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(
      () => _startDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _pickEndDate() async {
    final initial = _endDate ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final base = current?.toLocal() ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (t == null) return null;

    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pickEntryOpenAt() async {
    final picked = await _pickDateTime(_entryOpenAt);
    if (picked == null) return;
    setState(() => _entryOpenAt = picked);
  }

  Future<void> _pickEntryCloseAt() async {
    final picked = await _pickDateTime(_entryCloseAt);
    if (picked == null) return;
    setState(() => _entryCloseAt = picked);
  }

  bool _validate() {
    if (_name.text.trim().isEmpty) {
      setState(() => _msg = 'Show name is required.');
      return false;
    }

    if (_location.text.trim().isEmpty) {
      setState(() => _msg = 'Location is required.');
      return false;
    }

    if (_selectedClubId == null || _selectedClubId!.isEmpty) {
      setState(() => _msg = 'Hosting club is required.');
      return false;
    }

    if (_startDate == null || _endDate == null) {
      setState(() => _msg = 'Start and end dates are required.');
      return false;
    }

    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _msg = 'End date can’t be before start date.');
      return false;
    }

    if (_entryOpenAt != null && _entryCloseAt != null) {
      if (_entryCloseAt!.isBefore(_entryOpenAt!)) {
        setState(() => _msg = 'Entry close can’t be before entry open.');
        return false;
      }
    }

    if (!isValidFinalAwardMode(_finalAwardMode)) {
      setState(() => _msg = 'Final award mode is invalid.');
      return false;
    }

    if (_isNationalShow &&
        (_nationalShowSectionId == null ||
            !_showSections.any(
              (section) => section['id']?.toString() == _nationalShowSectionId,
            ))) {
      setState(() => _msg = 'Select which show is the national show.');
      return false;
    }

    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase
          .from('shows')
          .update({
            'name': _name.text.trim(),
            'location_name': _location.text.trim(),
            'start_date': _startDate!.toIso8601String().substring(0, 10),
            'end_date': _endDate!.toIso8601String().substring(0, 10),
            'timezone': _timezone,
            'is_published': _published,
            'is_national_show': _isNationalShow,
            'national_show_section_id': _isNationalShow
                ? _nationalShowSectionId
                : null,
            'entry_open_at': _entryOpenAt?.toUtc().toIso8601String(),
            'entry_close_at': _entryCloseAt?.toUtc().toIso8601String(),
            'final_award_mode': _finalAwardMode,
            'club_id': _selectedClubId,
            'club_name': _selectedClubName,
          })
          .eq('id', widget.showId);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _showNameForTitle = _name.text.trim();
        _msg = 'Saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  Future<void> _openBreedSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShowBreedSettingsScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openSanctions() {
    ShowSanctionsDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );
  }

  void _openFees() {
    ShowFeesDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );
  }

  void _openPaybacks() {
    showDialog<void>(
      context: context,
      builder: (_) => PaybackSettingsDialog(showId: widget.showId),
    );
  }

  Future<void> _openCheckinSettings() async {
    await ShowCheckinSettingsDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );

    if (mounted) await _load();
  }

  void _openRoleAssignments() {
    ShowRoleAssignmentsDialog.open(
      context,
      showId: widget.showId,
      showName: _effectiveShowName(),
    );
  }

  void _openAuditLogTable() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAuditLogScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openSuperintendentLayout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SuperintendentLineupScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
          readOnly: true,
        ),
      ),
    );
  }

  void _openEntryManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEntryManagementScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openShowReports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShowReportsScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openCoopNumbers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminCoopNumbersScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  void _openPrintPacks({bool controlSheetsOnly = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPrintPacksScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
          controlSheetsOnly: controlSheetsOnly,
        ),
      ),
    );
  }

  void _openResultsEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminResultsEntryScreen(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  //  void _openResultsValidation() {
  //    _showPostShowPlaceholder(
  //      title: 'Results Validation',
  //      body:
  //          'This is the next post-show screen to build.\n\nUse it to review missing placements, inconsistent specials, and incomplete class results before publishing.',
  //    );
  //  }

  Future<void> _downloadLockedShowData() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await downloadLockedShowDataExport(
        showId: widget.showId,
        showName: _effectiveShowName(),
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Locked show ZIP downloaded.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Download failed: $e';
      });
    }
  }

  void _openShowCloseout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShowCloseoutPage(
          showId: widget.showId,
          showName: _effectiveShowName(),
        ),
      ),
    );
  }

  Future<void> _openReportsAndCloseout() async {
    if (!_permissions.canFinalizeShow) return;
    final updated = ShowLayoutScope.isUpdated(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShowCloseoutV2PreviewPage(
          showId: widget.showId,
          showName: _effectiveShowName(),
          canFinalizeShow: _permissions.canFinalizeShow,
        ),
      ),
    );
    if (mounted && updated) await _load();
  }

  bool get _canOpenCheckin =>
      _isCheckinPortalEnabled &&
      (_permissions.canManageEntries || _permissions.canManageShowSettings);

  Future<void> _openCheckinDashboard() async {
    if (!_canOpenCheckin) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShowCheckinDashboardScreen(showId: widget.showId),
      ),
    );
    if (mounted) setState(() => _checkinSummary = null);
  }

  Future<void> _openChangeRequests() async {
    if (!_canOpenCheckin) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CheckinChangeRequestsScreen(showId: widget.showId),
      ),
    );
    if (mounted) setState(() => _checkinSummary = null);
  }

  Map<_ShowWorkspaceArea, List<_ShowTool>> _workspaceTools() {
    final permissions = _permissions;
    return {
      _ShowWorkspaceArea.overview: const [],
      _ShowWorkspaceArea.setup: [
        if (permissions.canManageShowSettings) ...[
          _ShowTool.sections,
          _ShowTool.breeds,
          _ShowTool.sanctions,
          _ShowTool.roles,
          _ShowTool.contests,
          _ShowTool.addOns,
          if (_canConfigureBestOpposite) _ShowTool.waves,
          if (_canManageCheckinSettings) _ShowTool.checkInSettings,
        ],
      ],
      if (permissions.canManageShow)
        _ShowWorkspaceArea.entries: [
          if (_canOpenCheckin) ...[_ShowTool.checkIn, _ShowTool.changeRequests],
          if (permissions.canManageEntries) _ShowTool.entries,
          _ShowTool.breedCounts,
          if (permissions.canManageEntries) _ShowTool.coopNumbers,
          _ShowTool.printPacks,
        ],
      if (permissions.canManageShow ||
          permissions.canEnterResults ||
          permissions.canManageJudges)
        _ShowWorkspaceArea.judging: [
          if (permissions.canManageJudges) _ShowTool.judges,
          if (permissions.canManageShowSettings) _ShowTool.lineup,
          if (permissions.canManageShow) _ShowTool.controlSheets,
          if (permissions.canEnterResults) _ShowTool.results,
          if (permissions.canManageShowSettings) _ShowTool.audit,
        ],
      if (permissions.canManageEntries || permissions.canManageShowSettings)
        _ShowWorkspaceArea.finances: [
          _ShowTool.balances,
          if (permissions.canManageShowSettings) ...[
            _ShowTool.fees,
            _ShowTool.paybacks,
          ],
        ],
      if (permissions.canFinalizeShow)
        _ShowWorkspaceArea.reports: [_ShowTool.closeout],
    };
  }

  Widget _buildWorkspaceBody({
    required _ShowWorkspaceArea? selected,
    required Iterable<_ShowWorkspaceArea> areas,
    required Widget child,
  }) {
    final scroll = SingleChildScrollView(
      key: selected == null ? null : ValueKey(selected),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: selected == null
          ? child
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: child,
              ),
            ),
    );
    if (selected == null) return scroll;
    return Column(
      children: [
        _buildWorkspaceNavigation(areas, selected),
        Expanded(child: scroll),
      ],
    );
  }

  Widget _buildWorkspaceNavigation(
    Iterable<_ShowWorkspaceArea> areas,
    _ShowWorkspaceArea selected,
  ) => Material(
    color: AppColors.surface,
    child: AppTheme.surfaceTextScope(
      context,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final area in areas)
                ChoiceChip(
                  label: Text(area.label),
                  selected: selected == area,
                  selectedColor: AppColors.primaryButton,
                  labelStyle: const TextStyle(color: AppColors.text),
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _workspaceArea = area),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildWorkspaceOverview(
    Map<_ShowWorkspaceArea, List<_ShowTool>> available,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final finalDate = _endDate ?? _startDate;
    final showEnded = finalDate != null && today.isAfter(finalDate);
    final showStarted = _startDate != null && !today.isBefore(_startDate!);
    final showDate = _startDate == null
        ? 'Show date to be set'
        : MaterialLocalizations.of(context).formatFullDate(_startDate!);
    return FutureBuilder<Map<String, dynamic>>(
      future: _canOpenCheckin
          ? (_checkinSummary ??= loadShowCheckinDashboard(widget.showId))
          : null,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final pending = (data?['pending_change_requests'] as num?)?.toInt();
        final records = data?['records'] as Map?;
        final waveName = data?['wave_name'] as String?;

        final (actionTitle, actionIcon, VoidCallback onAction) = switch ((
          _isReadOnly,
          _published,
          pending ?? 0,
          showEnded,
          showStarted,
        )) {
          (true, _, _, _, _)
              when available.containsKey(_ShowWorkspaceArea.reports) =>
            (
              'Open Reports & Closeout',
              Icons.archive_outlined,
              _openReportsAndCloseout,
            ),
          (false, false, _, _, _) when _permissions.canManageShowSettings => (
            'Continue show setup',
            Icons.tune,
            () => _selectWorkspaceArea(_ShowWorkspaceArea.setup),
          ),
          (false, _, > 0, _, _) => (
            'Review change requests',
            Icons.playlist_add_check,
            _openChangeRequests,
          ),
          (_, _, _, true, _) when _permissions.canEnterResults => (
            'Open Results Entry',
            Icons.fact_check_outlined,
            _openResultsEntry,
          ),
          (_, _, _, true, _)
              when available.containsKey(_ShowWorkspaceArea.reports) =>
            (
              'Open Reports & Closeout',
              Icons.archive_outlined,
              _openReportsAndCloseout,
            ),
          (_, _, _, _, true) when _canOpenCheckin => (
            'Open Check-In Dashboard',
            Icons.how_to_reg,
            _openCheckinDashboard,
          ),
          (_, _, _, _, true)
              when available.containsKey(_ShowWorkspaceArea.judging) =>
            (
              'Open judging tools',
              Icons.gavel,
              () => _selectWorkspaceArea(_ShowWorkspaceArea.judging),
            ),
          _ => (
            'Open entry tools',
            Icons.list_alt,
            () => _selectWorkspaceArea(_ShowWorkspaceArea.entries),
          ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionCard(
              title: _effectiveShowName(),
              subtitle: _location.text.trim().isEmpty
                  ? showDate
                  : '$showDate · ${_location.text.trim()}',
              children: [
                if (_entryCloseAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      '${DateTime.now().isAfter(_entryCloseAt!) ? 'Entries closed' : 'Entries close'} ${_fmtDateTime(_entryCloseAt)}',
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : onAction,
                    icon: Icon(actionIcon),
                    label: Text(actionTitle),
                  ),
                ),
              ],
            ),
            if (_canOpenCheckin)
              _buildSectionCard(
                title: waveName == null
                    ? 'Check-In Status'
                    : '$waveName Check-In',
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator()
                  else if (snapshot.hasError)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Check-in status is unavailable.'),
                        TextButton(
                          onPressed: () =>
                              setState(() => _checkinSummary = null),
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        RMBadge(
                          icon: Icons.playlist_add_check,
                          text: '${pending ?? 0} pending change requests',
                        ),
                        RMBadge(
                          icon: Icons.how_to_reg,
                          text:
                              '${(records?['completed'] as num? ?? 0) + (records?['reviewed'] as num? ?? 0) + (records?['locked'] as num? ?? 0)} checked in',
                        ),
                        RMBadge(
                          icon: Icons.payments_outlined,
                          text:
                              '${data?['unpaid_exhibitors'] ?? 0} exhibitors with balances due',
                        ),
                      ],
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  void _selectWorkspaceArea(_ShowWorkspaceArea area) =>
      setState(() => _workspaceArea = area);

  Map<_ShowTool, Widget> _buildTools({required bool updated}) => {
    _ShowTool.judges: _buildSettingsActionTile(
      icon: Icons.gavel,
      title: 'Judges',
      subtitle: 'Select judges available for staff assignment',
      onTap: (_saving || !_permissions.canManageJudges)
          ? null
          : () async {
              final changed = await ShowJudgesDialog.open(
                context,
                showId: widget.showId,
                showName: _showNameForTitle,
              );
              if (changed == true && mounted) {
                setState(() => _msg = 'Judges updated.');
              }
            },
    ),
    _ShowTool.balances: _buildSettingsActionTile(
      icon: Icons.account_balance_wallet_outlined,
      title: updated ? 'Balances & Payment History' : 'Show Finances',
      subtitle: 'Balances, payment history, external payments and credits',
      onTap: _saving
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShowFinancesScreen(showId: widget.showId),
              ),
            ),
    ),
    _ShowTool.entries: _buildSettingsActionTile(
      icon: Icons.edit_note,
      title: 'Entry Management',
      subtitle: 'Search, edit, scratch, move class, add notes',
      onTap: _saving ? null : _openEntryManagement,
    ),
    _ShowTool.breedCounts: _buildSettingsActionTile(
      icon: Icons.bar_chart,
      title: 'Breed Counts',
      subtitle: 'Totals by breed/show',
      onTap: _saving ? null : _openShowReports,
    ),
    _ShowTool.coopNumbers: _buildSettingsActionTile(
      icon: Icons.grid_on,
      title: 'Coop Numbers',
      subtitle: 'Generate, review, and manually edit coop assignments',
      onTap: _saving ? null : _openCoopNumbers,
    ),
    _ShowTool.printPacks: _buildSettingsActionTile(
      icon: Icons.print,
      title: 'Print Packs',
      subtitle: 'Check-In Sheets, Control Sheets, Coop Tags, Comment Cards',
      onTap: _saving ? null : _openPrintPacks,
    ),
    _ShowTool.checkIn: _buildSettingsActionTile(
      icon: Icons.fact_check_outlined,
      title: 'Check-In Dashboard',
      subtitle: 'Live check-in progress, balances, and exhibitor activity',
      onTap: _saving ? null : _openCheckinDashboard,
    ),
    _ShowTool.results: _buildSettingsActionTile(
      icon: Icons.fact_check,
      title: 'Results Entry',
      subtitle: 'Enter placements, DQs, and specials by class',
      onTap: _saving ? null : _openResultsEntry,
    ),
    _ShowTool.legacyCloseout: _buildSettingsActionTile(
      icon: Icons.archive,
      title: 'Close Show/Reports',
      subtitle: 'Finalize, send reports, and lock/download copy',
      onTap: _saving ? null : _openShowCloseout,
    ),
    _ShowTool.closeout: _buildSettingsActionTile(
      icon: Icons.archive_outlined,
      title: updated ? 'Open Reports & Closeout' : 'Close Show/Reports V2',
      subtitle: 'Finalize, send reports, and lock/download a copy',
      onTap: _saving ? null : _openReportsAndCloseout,
    ),
    _ShowTool.lock: _buildSettingsActionTile(
      icon: _isLocked ? Icons.lock_open : Icons.lock,
      title: _isLocked ? 'Unlock Show' : 'Lock Show',
      subtitle: _isFinalized
          ? 'Finalized shows cannot be unlocked.'
          : _isLocked
          ? 'Allow setup changes again if corrections are needed'
          : 'Prevent further setup changes before closeout',
      onTap: (_saving || _isFinalized) ? null : _toggleShowLock,
    ),
    _ShowTool.export: _buildSettingsActionTile(
      icon: Icons.download_for_offline,
      title: 'Download Locked Show Data',
      subtitle:
          'Download a ZIP backup of this show’s entries, results, settings, and reports',
      onTap: _saving ? null : _downloadLockedShowData,
    ),
    _ShowTool.breeds: _buildSettingsActionTile(
      icon: Icons.pets,
      title: 'Breed Settings',
      subtitle: 'Manage allowed breeds and varieties for this show',
      onTap: _saving ? null : _openBreedSettings,
    ),
    _ShowTool.sections: _buildSettingsActionTile(
      icon: Icons.view_module,
      title: updated ? 'Show Sections' : 'Modify Number of Shows',
      subtitle: 'Open A/B, Youth A/B, and setup',
      onTap: _saving
          ? null
          : () async {
              await ShowSectionsDialog.open(
                context,
                showId: widget.showId,
                showName: _effectiveShowName(),
              );

              if (!mounted) return;
              await _load();
            },
    ),
    _ShowTool.sanctions: _buildSettingsActionTile(
      icon: Icons.confirmation_number,
      title: 'Sanction Numbers',
      subtitle: 'Add or edit ARBA and breed/club sanction numbers',
      onTap: _saving ? null : _openSanctions,
    ),
    _ShowTool.fees: _buildSettingsActionTile(
      icon: Icons.attach_money,
      title: updated ? 'Fees & Payment Setup' : 'Show Fees & Payments',
      subtitle:
          'Per-animal fees, discounts, day-of-show, and online payment setup',
      onTap: _saving ? null : _openFees,
    ),
    _ShowTool.waves: _buildSettingsActionTile(
      icon: Icons.schedule,
      title: 'Wave Schedule',
      subtitle:
          'Assign breeds to waves and schedule check-in, showing, check-out, and emails',
      onTap: (_saving || _isReadOnly)
          ? null
          : () async {
              await ShowWaveScheduleDialog.open(
                context,
                showId: widget.showId,
                showName: _effectiveShowName(),
              );
              if (mounted) await _load();
            },
    ),
    _ShowTool.contests: _buildSettingsActionTile(
      icon: Icons.emoji_events_outlined,
      title: 'Contest Settings',
      subtitle:
          'Enable contests, set entry fees, and choose registration fields',
      onTap: (_saving || _isReadOnly)
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShowAddonSettingsScreen(
                  showId: widget.showId,
                  showName: _effectiveShowName(),
                  kind: 'contest',
                ),
              ),
            ),
    ),
    _ShowTool.addOns: _buildSettingsActionTile(
      icon: Icons.confirmation_number_outlined,
      title: 'Show Add-Ons',
      subtitle:
          'Offer extra coops, parking passes, banquet tickets, tours, and custom items',
      onTap: (_saving || _isReadOnly)
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShowAddonSettingsScreen(
                  showId: widget.showId,
                  showName: _effectiveShowName(),
                  kind: 'extra',
                ),
              ),
            ),
    ),
    _ShowTool.checkInSettings: _buildSettingsActionTile(
      icon: Icons.qr_code_2,
      title: 'Check-In Settings',
      subtitle:
          'Portal availability, QR code, confirmations, and entry-change permissions',
      onTap: (_saving || _isReadOnly) ? null : _openCheckinSettings,
    ),
    _ShowTool.paybacks: _buildSettingsActionTile(
      icon: Icons.payments_outlined,
      title: 'Payback Settings',
      subtitle:
          'Enter class payback schedules and special money by show letter',
      onTap: (_saving || _isReadOnly) ? null : _openPaybacks,
    ),
    _ShowTool.lineup: _buildSettingsActionTile(
      icon: Icons.visibility_outlined,
      title: updated ? 'Superintendent Lineup' : 'View Superintendent Layout',
      subtitle:
          'View the judging line-up for this show; superintendent changes are disabled',
      onTap: _openSuperintendentLayout,
    ),
    _ShowTool.roles: _buildSettingsActionTile(
      icon: Icons.manage_accounts,
      title: 'Role Assignments',
      subtitle: 'Assign Show Superintendent, and Other Staff Roles',
      onTap: _saving ? null : _openRoleAssignments,
    ),
    _ShowTool.audit: _buildSettingsActionTile(
      icon: Icons.history,
      title: updated ? 'Judging Activity' : 'Audit Log Table',
      subtitle: 'Review QR overrides and writer activity for this show',
      onTap: _saving ? null : _openAuditLogTable,
    ),
    _ShowTool.controlSheets: _buildSettingsActionTile(
      icon: Icons.description_outlined,
      title: 'Control Sheets',
      subtitle: 'Print judging control sheets in table and breed order',
      onTap: _saving ? null : () => _openPrintPacks(controlSheetsOnly: true),
    ),
    _ShowTool.changeRequests: _buildSettingsActionTile(
      icon: Icons.playlist_add_check,
      title: 'Check-In Change Requests',
      subtitle: 'Review exhibitor corrections and requests',
      onTap: _saving ? null : _openChangeRequests,
    ),
  };

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 12),
        ],
      ),
      child: AppTheme.surfaceTextScope(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.text),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: .05)),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _statusBadge({
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner({required bool updated}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: .05)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _statusBadge(
            text: _published ? 'Published' : 'Draft',
            icon: _published ? Icons.public : Icons.edit_note,
            color: updated
                ? (_published ? AppColors.success : AppColors.muted)
                : (_published ? Colors.green : Colors.grey),
          ),
          if (_isFinalized)
            _statusBadge(
              text: 'Finalized',
              icon: Icons.verified,
              color: updated ? AppColors.success : Colors.green,
            )
          else if (_isLocked)
            _statusBadge(
              text: 'Locked',
              icon: Icons.lock,
              color: updated ? AppColors.warning : Colors.orange,
            ),
        ],
      ),
    );
  }

  bool _stripeReadyForPayments() {
    if (_stripeStatus == null) return true;

    final status = (_stripeStatus?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (status == 'not_connected' || status.isEmpty) return true;

    final chargesEnabled = _stripeStatus?['charges_enabled'] == true;
    final payoutsEnabled = _stripeStatus?['payouts_enabled'] == true;
    final detailsSubmitted = _stripeStatus?['details_submitted'] == true;
    final cardPaymentsActive = _stripeStatus?['card_payments_active'] == true;
    final disabledReason = (_stripeStatus?['disabled_reason'] ?? '')
        .toString()
        .trim();

    return status == 'ready' &&
        chargesEnabled &&
        payoutsEnabled &&
        detailsSubmitted &&
        cardPaymentsActive &&
        disabledReason.isEmpty;
  }

  Widget _buildStripeAdminWarningBanner() {
    if (_loadingStripeStatus) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: .05)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checking Stripe account status…',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            LinearProgressIndicator(),
          ],
        ),
      );
    }

    if (_stripeStatus == null || _stripeReadyForPayments()) {
      return const SizedBox.shrink();
    }

    final status = (_stripeStatus?['status'] ?? 'not_connected').toString();
    final showPaymentAccount =
        _stripeStatus?['show_payment_account'] as Map<String, dynamic>?;
    final connectedAccountId =
        (showPaymentAccount?['provider_account_id'] ??
                showPaymentAccount?['stripe_account_id'] ??
                '')
            .toString()
            .trim();

    if (connectedAccountId.isEmpty || status == 'not_connected') {
      return const SizedBox.shrink();
    }

    final chargesEnabled = _stripeStatus?['charges_enabled'] == true;
    final payoutsEnabled = _stripeStatus?['payouts_enabled'] == true;
    final detailsSubmitted = _stripeStatus?['details_submitted'] == true;
    final cardPaymentsActive = _stripeStatus?['card_payments_active'] == true;
    final disabledReason = (_stripeStatus?['disabled_reason'] ?? '')
        .toString()
        .trim();

    final requirements =
        (_stripeStatus?['requirements'] as Map<String, dynamic>?) ?? {};
    final currentlyDue =
        (requirements['currently_due'] as List?)?.cast<dynamic>() ?? const [];
    final pastDue =
        (requirements['past_due'] as List?)?.cast<dynamic>() ?? const [];
    final pendingVerification =
        (requirements['pending_verification'] as List?)?.cast<dynamic>() ??
        const [];

    final issues = <String>[];
    if (!chargesEnabled) issues.add('charges are not enabled');
    if (!payoutsEnabled) issues.add('payouts are not enabled');
    if (!detailsSubmitted) issues.add('details are incomplete');
    if (!cardPaymentsActive) issues.add('card payments are not active');
    if (disabledReason.isNotEmpty) issues.add(disabledReason);
    if (currentlyDue.isNotEmpty) {
      issues.add(
        '${currentlyDue.length} Stripe requirement${currentlyDue.length == 1 ? '' : 's'} currently due',
      );
    }
    if (pastDue.isNotEmpty) {
      issues.add(
        '${pastDue.length} Stripe requirement${pastDue.length == 1 ? '' : 's'} past due',
      );
    }
    if (pendingVerification.isNotEmpty) {
      issues.add(
        '${pendingVerification.length} Stripe item${pendingVerification.length == 1 ? '' : 's'} pending verification',
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC928)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stripe account needs attention',
                      style: TextStyle(
                        color: const Color(0xFFFFC928),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Online payments may not work for exhibitors until this is resolved. Open Show Fees & Payments, continue Stripe setup if needed, then refresh the status.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Current issue${issues.length == 1 ? '' : 's'}: ${issues.join(', ')}.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: (_saving || _isReadOnly) ? null : _openFees,
                icon: const Icon(Icons.attach_money),
                label: const Text('Open Show Fees & Payments'),
              ),
              OutlinedButton.icon(
                onPressed: (_saving || _isReadOnly || _loadingStripeStatus)
                    ? null
                    : _refreshStripeStatusFromBanner,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Stripe Status'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updated = !widget.demoMode && ShowLayoutScope.isUpdated(context);
    final available = _workspaceTools();
    final selected = available.containsKey(_workspaceArea)
        ? _workspaceArea
        : _ShowWorkspaceArea.overview;
    final showingSetup = !updated || selected == _ShowWorkspaceArea.setup;
    final pageTitle = updated
        ? '$_showNameForTitle · ${selected.label}'
        : 'Show Settings — $_showNameForTitle';
    final tools = _buildTools(updated: updated);
    ShowAssistantController.instance.register(
      context,
      updated ? 'Show Workspace · ${selected.label}' : pageTitle,
      widget.showId,
    );
    final canManageShow = _permissions.canManageShow;
    final canManageShowSettings = _permissions.canManageShowSettings;
    final canManageEntries = _permissions.canManageEntries;
    final canEnterResults = _permissions.canEnterResults;
    final canFinalizeShow = _permissions.canFinalizeShow;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            if (!updated || MediaQuery.sizeOf(context).width >= 600) ...[
              Image.asset(
                'assets/images/RingMaster_One_Show_Transparent.png',
                excludeFromSemantics: true,
                height: 42,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                pageTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
                maxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: updated ? 'Exhibitor home' : 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const ShowListScreen()),
                      (route) => false,
                    );
                  },
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _saving ? null : _load,
          ),
          IconButton(
            tooltip: 'Report an issue',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => HelpReportDialog(
                pageTitle: pageTitle,
                pageRoute: ModalRoute.of(context)?.settings.name,
                showId: widget.showId,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: (_loading || _loadingPermissions)
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : !canManageShow
            ? const Center(
                child: Text(
                  'You do not have permission to manage this show.',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : SafeArea(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: _buildWorkspaceBody(
                    selected: updated ? selected : null,
                    areas: available.keys,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const RMTimezoneNoticeBanner(),
                        if (!updated || selected == _ShowWorkspaceArea.overview)
                          _buildStatusBanner(updated: updated),
                        if (canManageShowSettings &&
                            (!updated ||
                                selected == _ShowWorkspaceArea.overview ||
                                selected == _ShowWorkspaceArea.finances))
                          _buildStripeAdminWarningBanner(),
                        if (AppSession.supportReadOnly)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.support_agent, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Support Mode — You are managing this show as an admin while viewing another user.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_isReadOnly)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lock, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _isFinalized
                                        ? 'This show has been finalized. Show settings are view-only.'
                                        : 'This show is locked. Show settings are view-only.',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_msg != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  (_msg == 'Saved.' ||
                                      _msg == 'Show locked.' ||
                                      _msg == 'Show unlocked.')
                                  ? Colors.green.withValues(alpha: .08)
                                  : Colors.red.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    (_msg == 'Saved.' ||
                                        _msg == 'Show locked.' ||
                                        _msg == 'Show unlocked.')
                                    ? Colors.green.withValues(alpha: .25)
                                    : Colors.red.withValues(alpha: .25),
                              ),
                            ),
                            child: Text(
                              _msg!,
                              style: TextStyle(
                                color:
                                    (_msg == 'Saved.' ||
                                        _msg == 'Show locked.' ||
                                        _msg == 'Show unlocked.')
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        if (showingSetup &&
                            (canManageShow ||
                                canEnterResults ||
                                canFinalizeShow))
                          _buildSectionCard(
                            title: 'Staff Approval PINs',
                            subtitle:
                                'Use these codes to approve corrections during judging.',
                            children: [
                              if (_loadingPins) const LinearProgressIndicator(),
                              if (!_loadingPins && _myStaffPin == null)
                                const Text(
                                  'No active approval PIN was found for your account on this show.',
                                ),
                              if (!_loadingPins && _myStaffPin != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .04),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        ((_myStaffPin!['role'] ?? '')
                                                .toString())
                                            .replaceAll('_', ' ')
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (_myStaffPin!['pin_code'] ?? '')
                                            .toString(),
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!_loadingPins) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        (_saving ||
                                            _isReadOnly ||
                                            _loadingPins ||
                                            _regeneratingPins)
                                        ? null
                                        : _regenerateStaffPins,
                                    icon: _regeneratingPins
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.refresh),
                                    label: Text(
                                      _regeneratingPins
                                          ? 'Generating…'
                                          : _myStaffPin == null
                                          ? 'Generate My PIN'
                                          : 'Regenerate My PIN',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),

                        if (showingSetup && canManageShow)
                          _buildSectionCard(
                            title: 'Basic Show Info',
                            children: [
                              TextField(
                                controller: _name,
                                enabled:
                                    !_saving &&
                                    !_isReadOnly &&
                                    canManageShowSettings,
                                decoration: const InputDecoration(
                                  labelText: 'Show name (required)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _location,
                                enabled:
                                    !_saving &&
                                    !_isReadOnly &&
                                    canManageShowSettings,
                                decoration: const InputDecoration(
                                  labelText: 'Location (required)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_loadingClubs)
                                const LinearProgressIndicator(),
                              DropdownButtonFormField<String>(
                                initialValue:
                                    _clubs.any(
                                      (club) =>
                                          club['id']?.toString() ==
                                          _selectedClubId,
                                    )
                                    ? _selectedClubId
                                    : null,
                                decoration: InputDecoration(
                                  labelText: 'Hosting Club',
                                  border: const OutlineInputBorder(),
                                  helperText: _clubs.isEmpty
                                      ? 'No active clubs found. Add your first hosting club to continue.'
                                      : _canSwitchHostingClub
                                      ? 'Select a hosting club, add a new club, or manage your existing clubs.'
                                      : 'Locked to your account. A Secretary License is required to change this.',
                                ),
                                items: [
                                  ..._clubs.map((club) {
                                    return DropdownMenuItem<String>(
                                      value: club['id'].toString(),
                                      enabled: ClubService.canManageClubRecord(
                                        club,
                                      ),
                                      child: Text(
                                        (club['name'] ?? 'Club').toString(),
                                      ),
                                    );
                                  }),
                                  if (_canManageHostingClubs)
                                    const DropdownMenuItem<String>(
                                      value: _addClubActionValue,
                                      child: Row(
                                        children: [
                                          Icon(Icons.add, size: 18),
                                          SizedBox(width: 8),
                                          Text('Add New Club'),
                                        ],
                                      ),
                                    ),
                                  if (_canManageHostingClubs &&
                                      _clubs.any(
                                        ClubService.canManageClubRecord,
                                      ))
                                    const DropdownMenuItem<String>(
                                      value: _manageClubsActionValue,
                                      child: Row(
                                        children: [
                                          Icon(Icons.settings, size: 18),
                                          SizedBox(width: 8),
                                          Text('Manage Clubs'),
                                        ],
                                      ),
                                    ),
                                ],
                                onChanged:
                                    (_saving ||
                                        _isReadOnly ||
                                        _loadingClubs ||
                                        !_canManageHostingClubs ||
                                        !canManageShowSettings)
                                    ? null
                                    : (value) async {
                                        if (value == null) return;

                                        if (value == _addClubActionValue) {
                                          await _showAddClubDialog();
                                          return;
                                        }

                                        if (value == _manageClubsActionValue) {
                                          await _showManageClubsDialog();
                                          return;
                                        }

                                        setState(() {
                                          _selectedClubId = value;

                                          final selected = _clubs.firstWhere(
                                            (c) => c['id'].toString() == value,
                                            orElse: () => <String, dynamic>{},
                                          );

                                          _selectedClubName =
                                              (selected['name'] ?? '')
                                                  .toString();
                                        });
                                      },
                              ),
                            ],
                          ),

                        if (showingSetup && canManageShowSettings)
                          _buildSectionCard(
                            title: 'Show Date',
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Show Start: ${_startDate == null ? '(required)' : _fmtDate(_startDate)}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: (_saving || _isReadOnly)
                                        ? null
                                        : _pickStartDate,
                                    child: const Text('Pick'),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Show End: ${_endDate == null ? '(required)' : _fmtDate(_endDate)}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: (_saving || _isReadOnly)
                                        ? null
                                        : _pickEndDate,
                                    child: const Text('Pick'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        if (showingSetup && canManageShowSettings)
                          _buildSectionCard(
                            title: 'Entry Window',
                            subtitle:
                                'Date and time for when exhibitors can begin and stop entering.',
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Entry open: ${_fmtDateTime(_entryOpenAt)}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: (_saving || _isReadOnly)
                                        ? null
                                        : _pickEntryOpenAt,
                                    child: const Text('Pick'),
                                  ),
                                  TextButton(
                                    onPressed: (_saving || _isReadOnly)
                                        ? null
                                        : () => setState(
                                            () => _entryOpenAt = null,
                                          ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Entry close: ${_fmtDateTime(_entryCloseAt)}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: (_saving || _isReadOnly)
                                        ? null
                                        : _pickEntryCloseAt,
                                    child: const Text('Pick'),
                                  ),
                                  TextButton(
                                    onPressed: (_saving || _isReadOnly)
                                        ? null
                                        : () => setState(
                                            () => _entryCloseAt = null,
                                          ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Timezone: $_timezone',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        if (showingSetup && canManageShowSettings)
                          _buildSectionCard(
                            title: 'Publication & Awards',
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Published'),
                                subtitle: const Text(
                                  'Controls whether this show is published.',
                                ),
                                value: _published,
                                onChanged: (_saving || _isReadOnly)
                                    ? null
                                    : (v) async {
                                        final previous = _published;

                                        setState(() {
                                          _published = v;
                                          _saving = true;
                                          _msg = null;
                                        });

                                        try {
                                          await supabase
                                              .from('shows')
                                              .update({'is_published': v})
                                              .eq('id', widget.showId);

                                          if (!mounted) return;
                                          setState(() {
                                            _saving = false;
                                            _msg = v
                                                ? 'Show published.'
                                                : 'Show unpublished.';
                                          });
                                        } catch (e) {
                                          if (!mounted) return;
                                          setState(() {
                                            _published = previous;
                                            _saving = false;
                                            _msg =
                                                'Failed to update publish status: $e';
                                          });
                                        }
                                      },
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('National Show'),
                                subtitle: const Text(
                                  'Enables national show reporting rules, including Top 10 Breed reporting.',
                                ),
                                value: _isNationalShow,
                                onChanged: (_saving || _isReadOnly)
                                    ? null
                                    : (v) => setState(() {
                                        _isNationalShow = v;
                                        if (!v) {
                                          _nationalShowSectionId = null;
                                        }
                                      }),
                              ),
                              if (_isNationalShow) ...[
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      _showSections.any(
                                        (section) =>
                                            section['id']?.toString() ==
                                            _nationalShowSectionId,
                                      )
                                      ? _nationalShowSectionId
                                      : null,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Which show is the national show?',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _showSections
                                      .map(
                                        (section) => DropdownMenuItem<String>(
                                          value: section['id']?.toString(),
                                          child: Text(
                                            (section['display_name'] ??
                                                    '${section['kind']} ${section['letter']}')
                                                .toString(),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (_saving || _isReadOnly)
                                      ? null
                                      : (value) => setState(
                                          () => _nationalShowSectionId = value,
                                        ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _finalAwardMode,
                                decoration: const InputDecoration(
                                  labelText: 'Final award format',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: [
                                  for (final mode in [
                                    'four_six_bis',
                                    'bis_ris',
                                    'bis_1ris_2ris',
                                    if (_canConfigureBestOpposite ||
                                        _finalAwardMode ==
                                            bestOppositeFinalAwardMode)
                                      bestOppositeFinalAwardMode,
                                  ])
                                    DropdownMenuItem(
                                      value: mode,
                                      child: Text(
                                        finalAwardFormatLabel(mode),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (_saving || _isReadOnly)
                                    ? null
                                    : (v) => setState(
                                        () => _finalAwardMode =
                                            v ?? 'four_six_bis',
                                      ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Current mode: ${_finalAwardModeLabel(_finalAwardMode)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),

                        if (!updated) ...[
                          _buildSectionCard(
                            title: 'Admin Operations (Pre-show)',
                            children: [
                              tools[_ShowTool.judges]!,
                              if (canManageEntries || canManageShowSettings)
                                tools[_ShowTool.balances]!,
                              if (canManageEntries) tools[_ShowTool.entries]!,
                              if (canManageShow) tools[_ShowTool.breedCounts]!,
                              if (canManageEntries)
                                tools[_ShowTool.coopNumbers]!,
                              if (canManageShow) tools[_ShowTool.printPacks]!,
                              if (_isCheckinPortalEnabled &&
                                  (canManageEntries || canManageShowSettings))
                                tools[_ShowTool.checkIn]!,
                            ],
                          ),

                          if (canEnterResults ||
                              canFinalizeShow ||
                              canManageShowSettings)
                            _buildSectionCard(
                              title: 'Post-Show Operations',
                              children: [
                                if (canEnterResults) tools[_ShowTool.results]!,
                                if (_showLegacyCloseoutActions &&
                                    canFinalizeShow)
                                  tools[_ShowTool.legacyCloseout]!,
                                if (canFinalizeShow) tools[_ShowTool.closeout]!,
                                if (_showLegacyCloseoutActions &&
                                    canManageShowSettings)
                                  tools[_ShowTool.lock]!,
                                if (_showLegacyCloseoutActions &&
                                    _isLocked &&
                                    canManageShowSettings)
                                  tools[_ShowTool.export]!,
                              ],
                            ),

                          if (canManageShowSettings)
                            _buildSectionCard(
                              title: 'Show Settings',
                              children: [
                                tools[_ShowTool.breeds]!,
                                tools[_ShowTool.sections]!,
                                tools[_ShowTool.sanctions]!,
                                tools[_ShowTool.fees]!,
                                if (_canConfigureBestOpposite)
                                  tools[_ShowTool.waves]!,
                                if (canManageShowSettings) ...[
                                  tools[_ShowTool.contests]!,
                                  tools[_ShowTool.addOns]!,
                                ],
                                if (_canManageCheckinSettings)
                                  tools[_ShowTool.checkInSettings]!,
                                tools[_ShowTool.paybacks]!,
                                tools[_ShowTool.lineup]!,
                                if (canManageShowSettings)
                                  tools[_ShowTool.roles]!,
                                if (canManageShowSettings)
                                  tools[_ShowTool.audit]!,
                              ],
                            ),
                        ] else if (selected == _ShowWorkspaceArea.overview)
                          _buildWorkspaceOverview(available)
                        else if (selected != _ShowWorkspaceArea.setup)
                          _buildSectionCard(
                            title: selected.label,
                            children: [
                              for (final tool in available[selected]!)
                                tools[tool]!,
                            ],
                          )
                        else if (available[selected]!.isNotEmpty)
                          _buildSectionCard(
                            title: 'Configuration',
                            children: [
                              for (final tool in available[selected]!)
                                tools[tool]!,
                            ],
                          ),

                        const SizedBox(height: 8),

                        if (showingSetup && canManageShowSettings)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryButton,
                              foregroundColor: AppColors.primaryButtonText,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: (_saving || _isReadOnly) ? null : _save,
                            child: Text(
                              _saving
                                  ? 'Saving…'
                                  : _isReadOnly
                                  ? 'View Only'
                                  : 'Save Changes',
                            ),
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
