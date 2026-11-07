import 'dart:async';
import 'package:flutter/foundation.dart';

/// Only foreground input calls activity; polling never renews this deadline.
class SupportIdleController extends ChangeNotifier {
  SupportIdleController({
    required DateTime expiresAt,
    required this.renew,
    DateTime Function()? now,
  }) : _expiresAt = expiresAt,
       _now = now ?? DateTime.now {
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }
  final Future<DateTime> Function() renew;
  final DateTime Function() _now;
  DateTime _expiresAt;
  DateTime? _lastSent;
  DateTime? _lastInput;
  Timer? _ticker;
  Timer? _pending;
  bool _stopped = false;
  bool busy = false;
  String? error;
  Duration get remaining => _expiresAt.difference(_now());
  bool get expired => remaining <= Duration.zero;
  bool get warning => remaining <= const Duration(minutes: 2);

  void activity() {
    if (_stopped || expired || warning || busy) return;
    _lastInput = _now();
    final elapsed = _lastSent == null
        ? const Duration(minutes: 1)
        : _now().difference(_lastSent!);
    if (elapsed >= const Duration(seconds: 30)) {
      unawaited(continueSession());
    } else {
      // One trailing renewal represents input, never an automatic heartbeat.
      _pending ??= Timer(const Duration(seconds: 30) - elapsed, () {
        _pending = null;
        if (!_stopped &&
            !expired &&
            _lastInput != null &&
            _now().difference(_lastInput!) <= const Duration(minutes: 1)) {
          unawaited(continueSession());
        }
      });
    }
  }

  Future<void> continueSession() async {
    if (_stopped || expired || busy) return;
    _pending?.cancel();
    _pending = null;
    _lastSent = _now();
    busy = true;
    error = null;
    notifyListeners();
    try {
      final deadline = await renew();
      if (_stopped) return;
      _expiresAt = deadline;
    } catch (e) {
      if (!_stopped) {
        error =
            'Could not extend Support Mode. Try Continue again, or exit and reopen Support Mode.';
      }
    } finally {
      if (!_stopped) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void stop() {
    _stopped = true;
    _ticker?.cancel();
    _pending?.cancel();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
