import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/show_layout_rollout.dart';
import '../services/role_service.dart';
import '../services/support_impersonation_session.dart';

class ShowLayoutHost extends StatefulWidget {
  const ShowLayoutHost({super.key, required this.child, required this.rollout});

  final Widget child;
  final ShowLayoutRollout rollout;

  @override
  State<ShowLayoutHost> createState() => _ShowLayoutHostState();
}

class _ShowLayoutHostState extends State<ShowLayoutHost> {
  StreamSubscription<AuthState>? _auth;
  String? _actorId;
  bool _inSupport = false;
  bool _isSuperAdmin = false;
  bool _optedIn = false;
  bool _ready = false;
  bool _saving = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _auth = ringMasterClient.auth.onAuthStateChange.listen((event) {
      _sync(checkRole: event.event == AuthChangeEvent.tokenRefreshed);
    });
    SupportImpersonationSession.current.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _auth?.cancel();
    SupportImpersonationSession.current.removeListener(_sync);
    super.dispose();
  }

  String _preferenceKey(String actorId) => 'updated_show_layout.$actorId';

  Future<void> _sync({bool checkRole = false}) async {
    final actorId = ringMasterClient.auth.currentUser?.id;
    final inSupport = SupportImpersonationSession.isActive;
    final changed = actorId != _actorId || inSupport != _inSupport;
    final refreshRole =
        checkRole && widget.rollout == ShowLayoutRollout.superAdminPreview;
    if (!changed && !refreshRole) return;

    final revision = ++_revision;
    if (changed) {
      setState(() {
        _actorId = actorId;
        _inSupport = inSupport;
        _isSuperAdmin = false;
        _optedIn = false;
        _ready = false;
        _saving = false;
      });
    }

    if (actorId == null ||
        inSupport ||
        widget.rollout == ShowLayoutRollout.launched ||
        widget.rollout == ShowLayoutRollout.classic) {
      return;
    }

    final isSuperAdmin =
        widget.rollout == ShowLayoutRollout.superAdminPreview &&
        await RoleService.isSuperAdmin();
    final loadPreference = changed || !_ready || !_isSuperAdmin;
    var optedIn = false;
    if (loadPreference &&
        widget.rollout.canChoose(isSuperAdmin: isSuperAdmin)) {
      try {
        final preferences = await SharedPreferences.getInstance();
        optedIn = preferences.getBool(_preferenceKey(actorId)) ?? false;
      } catch (_) {
        // Unavailable browser storage starts this session in the classic layout.
      }
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _isSuperAdmin = isSuperAdmin;
      if (loadPreference) _optedIn = optedIn;
      _ready = true;
    });
  }

  bool get _canChoose =>
      _actorId != null &&
      !_inSupport &&
      _ready &&
      widget.rollout.canChoose(isSuperAdmin: _isSuperAdmin);

  Future<bool> _choose(bool value) async {
    final actorId = _actorId;
    if (actorId == null || !_canChoose || _saving) return false;
    setState(() => _saving = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setBool(_preferenceKey(actorId), value)) {
        return false;
      }
      if (!mounted || _actorId != actorId || !_canChoose) return false;
      setState(() => _optedIn = value);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mounted && _actorId == actorId) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ShowLayoutScope(
    updated:
        _actorId != null &&
        widget.rollout.usesUpdated(
          isSuperAdmin: _isSuperAdmin,
          optedIn: _optedIn && !_inSupport,
        ),
    canChoose: _canChoose,
    saving: _saving,
    onChoose: _choose,
    child: widget.child,
  );
}

class ShowLayoutScope extends InheritedWidget {
  const ShowLayoutScope({
    super.key,
    required this.updated,
    required this.canChoose,
    required this.saving,
    required this.onChoose,
    required super.child,
  });

  final bool updated;
  final bool canChoose;
  final bool saving;
  final Future<bool> Function(bool) onChoose;

  static ShowLayoutScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShowLayoutScope>();

  static bool isUpdated(BuildContext context) => of(context)?.updated ?? false;

  @override
  bool updateShouldNotify(ShowLayoutScope oldWidget) =>
      updated != oldWidget.updated ||
      canChoose != oldWidget.canChoose ||
      saving != oldWidget.saving;
}
