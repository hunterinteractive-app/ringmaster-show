import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'support_idle_controller.dart';

/// The real login stays in the SDK's usual storage. The support client exists
/// only in memory, and can reach application data only through the broker.
class RingMasterData {
  static SupabaseClient? _delegated;
  static SupportTransport? _transport;
  static String? _sessionId;
  static SupportIdleController? idle;
  static SupabaseClient get client => _delegated ?? Supabase.instance.client;
  static bool get delegated => _delegated != null;

  static Future<Map<String, dynamic>> control(
    String action, {
    String? target,
    String? session,
  }) async {
    try {
      final result = await Supabase.instance.client.functions.invoke(
        'support-session',
        body: {
          'action': action,
          if (target != null) 'target_id': target,
          if (session != null) 'session_id': session,
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      throw StateError(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Support session unavailable.',
      );
    }
  }

  static Future<void> attach(
    Map<String, dynamic> grant, {
    http.Client? transportClient,
  }) async {
    final actor = Supabase.instance.client;
    final actorId = actor.auth.currentUser?.id;
    final id = grant['id'] as String;
    final user = Map<String, dynamic>.from(grant['user'] as Map);
    final expiry = (grant['expires_at'] as num).floor();
    if (actorId == null ||
        actorId == user['id'] ||
        expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw StateError('The support session has expired.');
    }
    final transport = SupportTransport(
      project: Uri.parse(SupabaseConfig.url),
      sessionId: id,
      expiresAt: expiry,
      inner: transportClient,
      actorBearer: () async {
        if (actor.auth.currentUser?.id != actorId) return null;
        var session = actor.auth.currentSession;
        if (session?.isExpired == true) {
          session = (await actor.auth.refreshSession()).session;
        }
        return session?.user.id == actorId ? session?.accessToken : null;
      },
    );
    final displayUser = User.fromJson({
      ...user,
      'app_metadata': <String, dynamic>{},
      'user_metadata': Map<String, dynamic>.from(
        user['user_metadata'] as Map? ?? {},
      ),
    });
    if (displayUser == null) throw StateError('Invalid delegated user.');
    final target = _SupportClient(transport, displayUser, id);
    _transport = transport;
    _delegated = target;
    _sessionId = id;
    idle?.dispose();
    idle = SupportIdleController(
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry * 1000),
      renew: () async {
        final result = await control('activity', session: id);
        if (_transport != transport || result['id'] != id) {
          throw StateError('Support session changed.');
        }
        final seconds = (result['expires_at'] as num).floor();
        transport.expiresAt = seconds;
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      },
    );
  }

  static Future<http.Response> refreshBreederConnection(String body) async {
    final req =
        http.Request(
            'POST',
            Uri.parse('${SupabaseConfig.url}/partner/v1/breeder-refresh'),
          )
          ..headers['Content-Type'] = 'application/json'
          ..body = body;
    return http.Response.fromStream(await _transport!.send(req));
  }

  /// Disable the transport before performing any asynchronous teardown.
  static Future<void> end() async {
    final id = _sessionId;
    if (id == null) return;
    idle?.stop();
    _transport?.close();
    await control('end', session: id);
  }

  static Future<void> detach() async {
    idle?.dispose();
    idle = null;
    _transport?.close();
    final old = _delegated;
    _delegated = null;
    _sessionId = null;
    _transport = null;
    await old?.dispose();
  }
}

// Give the existing SDK consumers the selected user, without replacing the
// administrator's Auth session or broadcasting a target login to other tabs.
class _SupportClient extends SupabaseClient {
  _SupportClient(SupportTransport transport, User user, String sessionId)
    : _identity = _SupportIdentity(user, transport, sessionId),
      super(
        SupabaseConfig.url,
        SupabaseConfig.anonKey,
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        accessToken: () async => 'support-display-only',
      );
  final _SupportIdentity _identity;
  @override
  GoTrueClient get auth => _identity;
  @override
  Future<void> dispose() async {
    _identity.dispose();
    await super.dispose();
  }
}

class _SupportIdentity extends GoTrueClient {
  _SupportIdentity(User user, SupportTransport transport, String id)
    : _display = Session(
        accessToken: 'support-display-only',
        tokenType: 'bearer',
        user: user,
      ),
      super(
        url: 'https://support-$id.invalid',
        httpClient: transport,
        autoRefreshToken: false,
      );
  final Session _display;
  @override
  User get currentUser => _display.user;
  @override
  Session get currentSession => _display;
}

class SupportTransport extends http.BaseClient {
  SupportTransport({
    required this.project,
    required this.sessionId,
    required this.expiresAt,
    required this.actorBearer,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();
  final Uri project;
  final String sessionId;
  int expiresAt;
  final Future<String?> Function() actorBearer;
  final http.Client _inner;
  bool _closed = false;
  static const forwarded = {
    'accept',
    'accept-profile',
    'content-profile',
    'content-type',
    'prefer',
    'range',
    'range-unit',
    'x-upsert',
    'cache-control',
    'if-match',
    'if-none-match',
  };
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    if (_closed || DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt) {
      throw http.ClientException(
        'Support session ended. Return to your administrator account.',
      );
    }
    if (url.origin != project.origin ||
        (![
              '/rest/v1/',
              '/functions/v1/',
              '/storage/v1/',
            ].any(url.path.startsWith) &&
            url.path != '/partner/v1/breeder-refresh')) {
      throw http.ClientException(
        'This operation is outside the support session.',
      );
    }
    final bearer = await actorBearer();
    if (_closed || bearer == null) {
      throw http.ClientException('Administrator sign-in required.');
    }
    // Avoid nesting /functions/v1/ inside the gateway's function route.
    final proxyPath = url.path.startsWith('/functions/v1/')
        ? url.path.replaceFirst('/functions/v1/', '/invoke/')
        : url.path;
    final dest = url.replace(
      path: '/functions/v1/support-session/proxy$proxyPath',
    );
    final out = http.Request(request.method, dest);
    // Finalizing MultipartRequest sets its boundary in the Content-Type header.
    final bytes = await request.finalize().toBytes();
    for (final e in request.headers.entries) {
      if (forwarded.contains(e.key.toLowerCase())) out.headers[e.key] = e.value;
    }
    out.headers.addAll({
      'Authorization': 'Bearer $bearer',
      'apikey': SupabaseConfig.anonKey,
      'x-rm-session': sessionId,
    });
    out.bodyBytes = bytes;
    if (_closed) throw http.ClientException('Support session ended.');
    return _inner.send(out);
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
  }
}
