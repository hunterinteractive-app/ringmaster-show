import '../services/assistant_transcript.dart';
import '../services/assistant_support.dart';
import '../services/assistant_guide_links.dart';
import '../services/assistant_links.dart';
import '../services/assistant_suggestions.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../services/show_assistant_service.dart';
import '../services/household_session.dart';
import '../services/support_impersonation_session.dart';

class ShowAssistantOverlay extends StatefulWidget {
  const ShowAssistantOverlay({super.key, required this.child});
  final Widget child;
  @override
  State<ShowAssistantOverlay> createState() => _ShowAssistantOverlayState();
}

class _ShowAssistantOverlayState extends State<ShowAssistantOverlay> {
  final controller = ShowAssistantController.instance;
  StreamSubscription<AuthState>? _auth;
  String? _actor;
  int _session = 0;
  @override
  void initState() {
    super.initState();
    _actor = Supabase.instance.client.auth.currentUser?.id;
    controller.addListener(_refresh);
    HouseholdSession.selection.addListener(_reset);
    SupportImpersonationSession.current.addListener(_reset);
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (_actor != s.session?.user.id) {
        _actor = s.session?.user.id;
        _reset();
      }
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _reset() {
    _session++;
    controller.resetChat();
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    HouseholdSession.selection.removeListener(_reset);
    SupportImpersonationSession.current.removeListener(_reset);
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final mobile = box.maxWidth < 600;
      return Stack(
        children: [
          widget.child,
          if (controller.isOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: controller.close,
                child: Container(color: Colors.black26),
              ),
            ),
            Positioned(
              top: mobile ? 0 : 24,
              right: mobile ? 0 : 20,
              bottom:
                  MediaQuery.viewInsetsOf(context).bottom + (mobile ? 0 : 24),
              width: mobile ? box.maxWidth : 410,
              child: SafeArea(
                child: Material(
                  elevation: 12,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(mobile ? 0 : 22),
                  clipBehavior: Clip.antiAlias,
                  child: HeroControllerScope.none(
                    child: Navigator(
                      key: ValueKey(
                        '$_session:${controller.page.showId}:${controller.page.title}',
                      ),
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => AssistantPanel(
                          gateway: SupabaseAssistantGateway(),
                          chat: controller.chat,
                          page: controller.page,
                          onClose: controller.close,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ] else
            Positioned(
              right: 16,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 72,
              child: SafeArea(
                child: Semantics(
                  container: true,
                  label: 'Ask Chester',
                  button: true,
                  child: FloatingActionButton(
                    key: const ValueKey('assistant-launcher'),
                    heroTag: 'ringmaster-assistant',
                    onPressed: controller.open,
                    child: const ExcludeSemantics(
                      child: RabbitAvatar(size: 50),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Bundled rabbit portrait: animation runs locally without AI calls.
class RabbitAvatar extends StatefulWidget {
  const RabbitAvatar({super.key, this.thinking = false, this.size = 40});
  final double size;
  final bool thinking;
  @override
  State<RabbitAvatar> createState() => _RabbitAvatarState();
}

class _RabbitAvatarState extends State<RabbitAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.thinking ? 'Chester is thinking' : 'Chester the rabbit',
    child: AnimatedBuilder(
      animation: _motion,
      builder: (_, _) {
        final phase = _motion.value;
        final seconds = phase * 18;
        // Sit for ten seconds, bring out a snack, chew, then put it away.
        final reveal = ((seconds - 10) / .45).clamp(0.0, 1.0);
        final hide = ((16 - seconds) / .45).clamp(0.0, 1.0);
        final carrotOpacity = Curves.easeInOut.transform(
          math.min(reveal, hide),
        );
        final nibbling = seconds >= 10.45 && seconds < 15.55;
        final frame = nibbling ? ((seconds - 10.45) * 5).floor() % 2 : 0;
        final tilt =
            math.sin(phase * math.pi * 2) * (widget.thinking ? .13 : .09);
        return Transform.rotate(
          angle: tilt,
          alignment: Alignment.bottomCenter,
          child: Transform.translate(
            offset: Offset(0, nibbling ? -frame * .6 : 0),
            child: SizedBox.square(
              dimension: widget.size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: 1 - carrotOpacity,
                    child: Image.asset(
                      'assets/images/assistant-rabbit-realistic.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ),
                  Opacity(
                    opacity: carrotOpacity,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        (1 - carrotOpacity) * widget.size * .06,
                      ),
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: frame == 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          minWidth: widget.size * 2,
                          maxWidth: widget.size * 2,
                          minHeight: widget.size,
                          maxHeight: widget.size,
                          child: Image.asset(
                            'assets/images/assistant-rabbit-carrot-sprite.png',
                            width: widget.size * 2,
                            height: widget.size,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

const assistantTopics = {
  'help': 'General questions',
  'entries': 'My entries',
  'reports': 'My reports & legs',
  'household': 'My exhibitors',
  'setup': 'Show setup',
  'closeout': 'Show report status',
};
// Route only the subject of the current question. Authorization stays on the server.
String assistantTopicForQuestion(String message) {
  final q = message.toLowerCase();
  if (RegExp(r'\b(how do|how can|how to|where do|where can)\b').hasMatch(q)) {
    return 'help';
  }
  if (RegExp(
    r'\b(closeout|close out|report status|reports ready|reports generated)\b',
  ).hasMatch(q)) {
    return 'closeout';
  }
  if (RegExp(r'\b(report|reports|leg|legs)\b').hasMatch(q)) return 'reports';
  if (RegExp(r'\b(section|sections|setup|set up|judging date)\b').hasMatch(q)) {
    return 'setup';
  }
  if (RegExp(
    r'\b(entry|entries|entered|registered|registration)\b',
  ).hasMatch(q)) {
    return 'entries';
  }
  if (RegExp(r'\b(household|exhibitors|linked accounts)\b').hasMatch(q)) {
    return 'household';
  }
  return 'help';
}

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.gateway,
    required this.page,
    required this.onClose,
    this.chat,
  });
  final AssistantChatSession? chat;
  final AssistantGateway gateway;
  final AssistantPage page;
  final VoidCallback onClose;
  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final AssistantChatSession _chat = widget.chat ?? AssistantChatSession();
  List<Map<String, String>> get _messages => _chat.messages;
  String get _conversation => _chat.conversationId;
  set _conversation(String value) => _chat.conversationId = value;
  String get _topic => _chat.topic;
  set _topic(String value) => _chat.topic = value;
  String? get _showId => _chat.showId;
  set _showId(String? value) => _chat.showId = value;
  String? get _showLabel => _chat.showLabel;
  set _showLabel(String? value) => _chat.showLabel = value;
  String? _notice;
  bool _busy = false;
  bool _guide = false;
  String _faqSearch = '';
  String? get _pendingQuestion => _chat.pendingQuestion;
  set _pendingQuestion(String? value) => _chat.pendingQuestion = value;
  @override
  void initState() {
    super.initState();
    _input.text = _chat.draft;
    if (_pendingQuestion == null &&
        widget.page.showId != null &&
        widget.page.showId != _showId) {
      _showId = widget.page.showId;
      _showLabel = 'Current show';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _chat.draft = _input.text;
    if (_busy) {
      _addMessage({
        'role': 'assistant',
        'content':
            'This question was interrupted when you left the chat. Please ask again if you still need help.',
      });
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _addMessage(Map<String, String> message) {
    _messages.add(message);
    _saveInteraction(
      message['role']!,
      message['content']!,
      message['source'] ?? 'chat',
    );
  }

  void _saveInteraction(String role, String content, String source) {
    if (widget.gateway is! SupabaseAssistantGateway) return;
    final transcript = _chat.transcript ??= AssistantTranscript(_conversation);
    unawaited(
      transcript
          .append(
            role: role,
            content: content,
            page: widget.page.title,
            topic: _topic,
            source: source,
          )
          .then((_) {
            if (mounted && transcript.failed) {
              setState(
                () => _notice =
                    'This chat could not be saved for support review. Contact support can still include the full conversation.',
              );
            }
          }),
    );
  }

  void _clear() {
    _input.clear();
    _chat.draft = '';
    _messages.clear();
    _conversation = const Uuid().v4();
    _chat.transcript = null;
    _notice = null;
    _pendingQuestion = null;
    _topic = 'help';
  }

  Future<void> _send([String? suggestion, bool resume = false]) async {
    final message = (suggestion ?? _input.text).trim();
    if (_busy || message.isEmpty) return;
    String? reviewed;
    if (!resume &&
        widget.gateway is ReviewedAnswerGateway &&
        widget.gateway.canAsk) {
      setState(() => _busy = true);
      try {
        reviewed = await (widget.gateway as ReviewedAnswerGateway)
            .reviewedAnswer(message);
      } catch (_) {
        // Reviewed-answer lookup failure still allows built-in help and AI.
      }
      if (!mounted) return;
      setState(() => _busy = false);
    }
    final prepared = resume
        ? null
        : reviewed ?? assistantPreparedAnswer(message);
    if (prepared != null) {
      setState(() {
        _pendingQuestion = null;
        _topic = 'help';
        _guide = false;
        _notice = null;
        _input.clear();
        _addMessage({'role': 'user', 'content': message});
        _addMessage({
          'role': 'assistant',
          'content':
              prepared +
              (reviewed == null ? preparedGuideCitation(message) : ''),
          'source': 'prepared',
        });
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
      return;
    }
    if (!widget.gateway.canAsk) return;
    if (_pendingQuestion != null && !resume) {
      // A typed show name is resolved through the same authorized picker.
      await _chooseShow(message);
      return;
    }
    if (!resume) _topic = assistantTopicForQuestion(message);
    if (!['help', 'household'].contains(_topic) && _showId == null) {
      setState(() {
        _pendingQuestion = message;
        _guide = false;
        _notice = null;
        _input.clear();
        _addMessage({'role': 'user', 'content': message});
        _addMessage({
          'role': 'assistant',
          'content':
              'Which show is this about? Type its name or choose it below.',
        });
      });
      return;
    }
    final history = _messages
        .skip(math.max(0, _messages.length - 6))
        .map(
          (m) => {
            'role': m['role']!,
            'content': m['content']!.substring(
              0,
              math.min(1800, m['content']!.length),
            ),
          },
        )
        .toList();
    setState(() {
      _busy = true;
      _notice = null;
      _guide = false;
      if (!resume) _addMessage({'role': 'user', 'content': message});
      _pendingQuestion = null;
      _input.clear();
    });
    try {
      final result = await widget.gateway.ask(
        message: message,
        conversationId: _conversation,
        topic: _topic,
        page: widget.page.title,
        showId: _showId,
        history: history,
      );
      if (!mounted) return;
      setState(
        () => _addMessage({
          'role': 'assistant',
          'content':
              result['answer'] as String? ?? 'Please contact support for help.',
          'source': 'ai',
        }),
      );
    } catch (_) {
      _saveInteraction(
        'event',
        'AI help was unavailable for this question.',
        'error',
      );
      if (!mounted) return;
      setState(
        () => _notice =
            'AI help is unavailable right now. Use the FAQ below or contact support.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    }
  }

  Future<void> _chooseShow([String? query]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _ShowPicker(gateway: widget.gateway, initialQuery: query ?? ''),
    );
    if (result != null && mounted) {
      _saveInteraction(
        'event',
        'Selected show: ${result['name']} (${result['id']})',
        'chat',
      );
      final pending = _pendingQuestion;
      setState(() {
        _showId = result['id'] as String;
        _showLabel = result['name'] as String;
        _addMessage({'role': 'user', 'content': 'For $_showLabel.'});
      });
      if (pending != null) await _send(pending, true);
    }
  }

  Widget _answerLinks(String answer) => Wrap(
    spacing: 8,
    children: [
      for (final guide in assistantGuideLinks(answer).entries)
        TextButton(
          onPressed: () async {
            final opened = await launchUrl(
              Uri.parse(guide.value),
              mode: LaunchMode.externalApplication,
            );
            if (!opened && mounted) {
              setState(
                () => _notice =
                    'The guide could not open. Try Secretary Resources or the website help pages.',
              );
            }
          },
          child: Text(
            guide.key,
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        ),
      for (final link in assistantPageLinks(answer).entries)
        TextButton(
          onPressed: () {
            final navigator =
                ShowAssistantController.instance.navigatorKey.currentState;
            if (navigator == null) return;
            widget.onClose();
            navigator.pushNamed(link.value, arguments: _showId);
          },
          child: Text(
            link.key,
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        ),
    ],
  );

  Future<void> _support() async {
    _saveInteraction('event', 'Opened contact support', 'support');
    final body = assistantSupportBody(
      page: widget.page.title,
      topic: assistantTopics[_topic] ?? _topic,
      conversationId: _conversation,
      show: _showLabel,
      messages: _messages,
      draft: _input.text,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contact support'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review the full conversation below. Open email creates a draft for you to review and send. For long chats, copy the full message and paste it into your email.',
                ),
                const SizedBox(height: 16),
                SelectableText(body),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: body));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Full support message copied.')),
                );
              }
            },
            child: const Text('Copy full message'),
          ),
          FilledButton(
            onPressed: () async {
              final opened = await launchUrl(
                assistantSupportEmail(widget.page.title, body),
                mode: LaunchMode.externalApplication,
              );
              if (!opened && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Copy the full message and email support@ringmasterone.com.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Open email'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final compact = bounds.maxHeight < 420;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const RabbitAvatar(),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ask Chester',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close assistant',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'A friendly ring assistant',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (!widget.gateway.canAsk)
                  const Text(
                    'AI questions require a signed-in account with support mode turned off. You can still use the FAQ or contact support.',
                  ),
                if (_messages.isEmpty && !_guide) ...[
                  const Text(
                    "Hi, I’m Chester. What can I help you with today?",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ask me a question. I’ll ask for any details I need along the way.',
                  ),
                  const SizedBox(height: 12),
                  for (final q in assistantSuggestions(widget.page.title))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _send(q),
                        child: Text(q),
                      ),
                    ),
                ],
                for (final message
                    in (_guide ? <Map<String, String>>[] : _messages))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: message['role'] == 'user'
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message['role'] == 'user' ? 'You' : 'Chester',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 5),
                          SelectableText(
                            assistantVisibleAnswer(message['content']!),
                          ),
                          if (message['role'] == 'assistant')
                            _answerLinks(message['content']!),
                        ],
                      ),
                    ),
                  ),
                if (!_guide &&
                    _showId != null &&
                    _messages.isNotEmpty &&
                    _pendingQuestion == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _chooseShow(),
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(
                        '${_showLabel ?? "Current show"} · Change show',
                      ),
                    ),
                  ),
                if (!_guide && _pendingQuestion != null)
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _chooseShow(),
                        icon: const Icon(Icons.event),
                        label: const Text('Choose a show'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _pendingQuestion = null;
                          _addMessage({
                            'role': 'assistant',
                            'content': 'No problem. What else can I help with?',
                          });
                        }),
                        child: const Text('Ask something else'),
                      ),
                    ],
                  ),
                if (_guide)
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () {
                          final nav = ShowAssistantController
                              .instance
                              .navigatorKey
                              .currentState;
                          if (nav != null) {
                            widget.onClose();
                            nav.pushNamed('/assistant/resources');
                          }
                        },
                        child: const Text('Secretary Resources'),
                      ),
                      for (final item in const {
                        'Exhibitor help on website':
                            'https://www.ringmasterone.com/help_exhibitors.html',
                        'Secretary help on website':
                            'https://www.ringmasterone.com/help_secretaries.html',
                      }.entries)
                        TextButton(
                          onPressed: () async {
                            final opened = await launchUrl(
                              Uri.parse(item.value),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!opened && mounted) {
                              setState(
                                () => _notice =
                                    'The website could not open. Please try again.',
                              );
                            }
                          },
                          child: Text(item.key),
                        ),
                    ],
                  ),
                if (_busy)
                  const Row(
                    children: [
                      RabbitAvatar(thinking: true),
                      SizedBox(width: 10),
                      Text('Thinking…'),
                    ],
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_notice!, semanticsLabel: _notice),
                  ),
                if (_guide) ...[
                  const Text(
                    'Frequently asked questions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Quick answers for exhibitors and show secretaries. Questions for this screen appear first.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: _faqSearch,
                    decoration: const InputDecoration(
                      labelText: 'Search FAQs',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _faqSearch = value.toLowerCase().trim()),
                  ),
                  const SizedBox(height: 8),
                  if (!assistantPreparedAnswers.entries.any(
                    (e) => '${e.key} ${e.value}'.toLowerCase().contains(
                      _faqSearch,
                    ),
                  ))
                    const Text(
                      'No matching FAQs. Try another phrase or ask Chester in the chat.',
                    ),
                  for (final question in {
                    ...assistantSuggestions(widget.page.title),
                    ...assistantPreparedAnswers.keys,
                  })
                    if (assistantPreparedAnswers.containsKey(question) &&
                        '$question ${assistantPreparedAnswers[question]}'
                            .toLowerCase()
                            .contains(_faqSearch))
                      ExpansionTile(
                        key: ValueKey('faq-$question'),
                        onExpansionChanged: (open) {
                          if (open) {
                            _saveInteraction(
                              'event',
                              '$question\n\n${assistantPreparedAnswers[question]}${preparedGuideCitation(question)}',
                              'faq',
                            );
                          }
                        },
                        title: Text(question),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(assistantPreparedAnswers[question]!),
                          _answerLinks(
                            assistantPreparedAnswers[question]! +
                                preparedGuideCitation(question),
                          ),
                        ],
                      ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 1800,
                    maxLines: 3,
                    minLines: 1,
                    enabled: !_busy && widget.gateway.canAsk,
                    inputFormatters: [LengthLimitingTextInputFormatter(1800)],
                    decoration: const InputDecoration(
                      hintText: 'Ask a question…',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  tooltip: 'Send question',
                  onPressed: _busy || !widget.gateway.canAsk
                      ? null
                      : () => _send(),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => _guide = !_guide);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _scroll.hasClients) {
                        _scroll.jumpTo(
                          _guide ? 0 : _scroll.position.maxScrollExtent,
                        );
                      }
                    });
                  },
                  child: Text(_guide ? 'Back to chat' : 'FAQ'),
                ),
                TextButton(
                  onPressed: _support,
                  child: const Text('Contact support'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(_clear),
                  child: const Text('Clear chat'),
                ),
              ],
            ),
          ),
          if (!compact)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Chester is an AI assistant—even a helpful rabbit can make mistakes between carrot breaks! Please contact support if something looks wrong or you need an extra paw. Signed-in chats are saved for support review.',
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      );
    },
  );
}

class _ShowPicker extends StatefulWidget {
  const _ShowPicker({required this.gateway, this.initialQuery = ''});
  final String initialQuery;
  final AssistantGateway gateway;
  @override
  State<_ShowPicker> createState() => _ShowPickerState();
}

class _ShowPickerState extends State<_ShowPicker> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _search.text = widget.initialQuery;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.gateway.shows(_search.text);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Shows could not be loaded. Try again or contact support.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose a show'),
    content: SizedBox(
      width: 340,
      height: 360,
      child: Column(
        children: [
          TextField(
            controller: _search,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'Search shows',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _load(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Text(_error!)
                : ListView(
                    children: [
                      if (_rows.isEmpty)
                        const Text('No matching shows. Try another name.'),
                      for (final s in _rows)
                        ListTile(
                          title: Text(s['name'] as String),
                          subtitle: Text('${s['start_date'] ?? ""}'),
                          onTap: () => Navigator.pop(context, s),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
