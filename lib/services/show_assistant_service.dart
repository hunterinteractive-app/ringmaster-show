import 'assistant_transcript.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'household_session.dart';
import 'support_impersonation_session.dart';

class AssistantPage {
  const AssistantPage({this.title = 'RingMaster Show', this.showId});
  final String title;
  final String? showId;
}

/// Only explicit screen metadata; never scrapes widgets, forms or credentials.
class AssistantNavigation extends NavigatorObserver {
  final pages = <Route<dynamic>, AssistantPage>{};
  final _routes = <Route<dynamic>>[];
  AssistantPage get current {
    for (final route in _routes.reversed) {
      if (route is PageRoute) return pages[route] ?? const AssistantPage();
    }
    return const AssistantPage();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    pages.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    pages.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0) {
      if (newRoute != null) {
        _routes[i] = newRoute;
      } else {
        _routes.removeAt(i);
      }
    }
    pages.remove(oldRoute);
  }
}

/// In-memory chat for one signed-in account/household session.
class AssistantChatSession {
  final messages = <Map<String, String>>[];
  String conversationId = const Uuid().v4();
  AssistantTranscript? transcript;
  String topic = 'help';
  String? showId;
  String? showLabel;
  String? pendingQuestion;
  String draft = '';
}

class ShowAssistantController extends ChangeNotifier {
  static final instance = ShowAssistantController();
  final navigation = AssistantNavigation();
  final navigatorKey = GlobalKey<NavigatorState>();
  AssistantChatSession chat = AssistantChatSession();
  bool isOpen = false;
  AssistantPage page = const AssistantPage();
  void open({String? title, String? showId}) {
    page = title == null && showId == null
        ? navigation.current
        : AssistantPage(title: title ?? 'RingMaster Show', showId: showId);
    isOpen = true;
    notifyListeners();
  }

  void resetChat() {
    chat = AssistantChatSession();
    close();
  }

  void close() {
    isOpen = false;
    notifyListeners();
  }

  void register(BuildContext context, String title, String? showId) {
    final route = ModalRoute.of(context);
    if (route != null) {
      navigation.pages[route] = AssistantPage(title: title, showId: showId);
    }
  }
}

abstract class AssistantGateway {
  bool get canAsk;
  Future<Map<String, dynamic>> ask({
    required String message,
    required String conversationId,
    required String topic,
    required String page,
    String? showId,
    required List<Map<String, String>> history,
  });
  Future<List<Map<String, dynamic>>> shows(String query);
}

abstract class ReviewedAnswerGateway {
  Future<String?> reviewedAnswer(String question);
}

class SupabaseAssistantGateway
    implements AssistantGateway, ReviewedAnswerGateway {
  SupabaseClient get _client => Supabase.instance.client;
  @override
  bool get canAsk =>
      _client.auth.currentUser != null && !SupportImpersonationSession.isActive;
  @override
  Future<String?> reviewedAnswer(String question) async {
    if (!canAsk) return null;
    final result = await _client
        .rpc('chester_match_answer', params: {'p_question': question})
        .timeout(const Duration(seconds: 4));
    return result is Map ? result['answer'] as String? : null;
  }

  @override
  Future<List<Map<String, dynamic>>> shows(String query) async =>
      (await _client.rpc('assistant_show_options', params: {'p_search': query})
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> ask({
    required String message,
    required String conversationId,
    required String topic,
    required String page,
    String? showId,
    required List<Map<String, String>> history,
  }) async {
    if (!canAsk) {
      throw StateError('Sign in outside support mode to use AI help.');
    }
    final response = await _client.functions
        .invoke(
          'show-assistant',
          body: {
            'request_id': const Uuid().v4(),
            'conversation_id': conversationId,
            'message': message,
            'topic': topic,
            'page': page,
            'show_id': showId,
            'owner_id': HouseholdSession.ownerUserId,
            'history': history,
          },
        )
        .timeout(const Duration(seconds: 65));
    return Map<String, dynamic>.from(response.data as Map);
  }
}
