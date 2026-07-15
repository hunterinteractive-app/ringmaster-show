import 'dart:async';

typedef CloseoutDashboardRefresh = Future<void> Function();

class CloseoutDashboardPoller {
  CloseoutDashboardPoller({
    required CloseoutDashboardRefresh onRefresh,
    this.interval = const Duration(seconds: 3),
  }) : _onRefresh = onRefresh;

  final CloseoutDashboardRefresh _onRefresh;
  final Duration interval;

  Timer? _timer;
  bool _visible = true;
  bool _active = false;
  bool _refreshInFlight = false;
  bool _refreshPending = false;
  bool _disposed = false;

  bool get isPolling => _timer?.isActive == true;
  bool get refreshInFlight => _refreshInFlight;

  void update({required bool active, required bool visible}) {
    if (_disposed) return;
    _active = active;
    _visible = visible;
    if (!_active || !_visible) {
      _cancelTimer();
      return;
    }
    _ensureTimer();
  }

  Future<void> resumeAndRefresh() async {
    if (_disposed) return;
    _visible = true;
    await refreshNow();
    if (_active && _visible) _ensureTimer();
  }

  void pause() {
    if (_disposed) return;
    _visible = false;
    _cancelTimer();
  }

  Future<void> refreshNow() async {
    if (_disposed) return;
    if (_refreshInFlight) {
      _refreshPending = true;
      return;
    }

    do {
      _refreshPending = false;
      _refreshInFlight = true;
      try {
        await _onRefresh();
      } finally {
        _refreshInFlight = false;
      }
    } while (_refreshPending && !_disposed);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(refreshNow()));
  }

  void dispose() {
    _disposed = true;
    _refreshPending = false;
    _cancelTimer();
  }
}
