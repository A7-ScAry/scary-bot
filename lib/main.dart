import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ScAryBotApp());
}

class ScAryBotApp extends StatelessWidget {
  const ScAryBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScAry Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool isLoading = false;

  static const String _storageKey = 'scary_bot_chats';
  static const String _activeChatKey = 'scary_bot_active_chat_id';

  final List<Map<String, dynamic>> chats = [];
  String? activeChatId;

  List<Map<String, String>> messages = [
    {
      'sender': 'bot',
      'text': 'Hey! I’m **ScAry Bot**. How can I help you?',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Map<String, dynamic> _newChatRecord() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return {
      'id': id,
      'title': 'New Chat',
      'messages': [
        {'sender': 'bot', 'text': 'Hey! I’m **ScAry Bot**. How can I help you?'}
      ],
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);

    if (saved != null && saved.isNotEmpty) {
      try {
        final decoded = jsonDecode(saved) as List<dynamic>;
        chats
          ..clear()
          ..addAll(decoded.map((chat) => Map<String, dynamic>.from(chat as Map)));
      } catch (_) {
        chats.clear();
      }
    }

    if (chats.isEmpty) {
      chats.add(_newChatRecord());
    }

    final savedActiveId = prefs.getString(_activeChatKey);
    activeChatId = chats.any((chat) => chat['id'] == savedActiveId)
        ? savedActiveId
        : chats.first['id'] as String;

    _loadActiveChatIntoMessages();

    if (mounted) {
      setState(() {});
    }

    await _saveChats();
  }

  void _loadActiveChatIntoMessages() {
    final chat = chats.firstWhere(
      (item) => item['id'] == activeChatId,
      orElse: () => chats.first,
    );

    final rawMessages = (chat['messages'] as List<dynamic>? ?? []);
    messages = rawMessages.map((message) {
      final map = Map<String, dynamic>.from(message as Map);
      return {
        'sender': map['sender'].toString(),
        'text': map['text'].toString(),
      };
    }).toList();

    if (messages.isEmpty) {
      messages = [
        {'sender': 'bot', 'text': 'Hey! I’m **ScAry Bot**. How can I help you?'}
      ];
    }
  }

  Future<void> _saveChats() async {
    if (activeChatId == null) return;

    final index = chats.indexWhere((chat) => chat['id'] == activeChatId);
    if (index != -1) {
      chats[index]['messages'] =
          messages.map((message) => Map<String, String>.from(message)).toList();
      chats[index]['updatedAt'] = DateTime.now().toIso8601String();

      final userMessages =
          messages.where((message) => message['sender'] == 'user').toList();

      if (userMessages.isNotEmpty &&
          (chats[index]['title'] == 'New Chat' ||
              (chats[index]['title'] as String).trim().isEmpty)) {
        final firstUserText = userMessages.first['text'] ?? 'New Chat';
        chats[index]['title'] = firstUserText.length > 32
            ? '${firstUserText.substring(0, 32)}…'
            : firstUserText;
      }
    }

    chats.sort((a, b) {
      final aDate = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(chats));
    await prefs.setString(_activeChatKey, activeChatId!);
  }

  Future<void> createNewChat() async {
    await _saveChats();
    final newChat = _newChatRecord();

    setState(() {
      chats.insert(0, newChat);
      activeChatId = newChat['id'] as String;
      _loadActiveChatIntoMessages();
      isLoading = false;
    });

    await _saveChats();
  }

  Future<void> switchChat(String chatId) async {
    if (chatId == activeChatId) return;
    await _saveChats();

    setState(() {
      activeChatId = chatId;
      _loadActiveChatIntoMessages();
      isLoading = false;
    });

    await _saveChats();

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> deleteChat(String chatId) async {
    final wasActive = activeChatId == chatId;

    setState(() {
      chats.removeWhere((chat) => chat['id'] == chatId);

      if (chats.isEmpty) {
        chats.add(_newChatRecord());
      }

      if (wasActive) {
        activeChatId = chats.first['id'] as String;
        _loadActiveChatIntoMessages();
      }
    });

    await _saveChats();
  }

  Future<String> getAIReply() async {
    final models = [
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-3.6-flash',
      'gemini-3.5-flash',
    ];

    final List<Map<String, dynamic>> contents = [];

    for (final message in messages) {
      contents.add({
        'role': message['sender'] == 'user' ? 'user' : 'model',
        'parts': [
          {
            'text': message['text'],
          }
        ],
      });
    }

    final latestMessage =
        messages.isNotEmpty ? messages.last['text'] ?? '' : '';

    final deepPattern = RegExp(
      r'solve|equation|calculate|calculation|math|algebra|geometry|'
      r'integral|derivative|probability|statistics|code|coding|program|'
      r'programming|algorithm|debug|logic|reasoning|prove|proof|'
      r'[\dA-Za-z]\s*[\^\+\-\*\/=]\s*[\dA-Za-z(]',
      caseSensitive: false,
    );

    final needsDeepReasoning = deepPattern.hasMatch(latestMessage);

    for (final model in models) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await http
              .post(
                Uri.parse(
                  'https://scary-bot.bakhtiarahmed011.workers.dev',
                ),
                headers: {
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': model,
                  'deep': needsDeepReasoning,
                  'contents': contents,
                }),
              )
              .timeout(const Duration(seconds: 90));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);

            final candidates = data['candidates'];

            if (candidates != null && candidates.isNotEmpty) {
              final parts = candidates[0]['content']?['parts'];

              if (parts != null && parts.isNotEmpty) {
                final textParts = <String>[];

                for (final part in parts) {
                  if (part is Map && part['text'] != null) {
                    textParts.add(part['text'].toString());
                  }
                }

                if (textParts.isNotEmpty) {
                  return textParts.join('\n');
                }
              }
            }
          }

          if (response.statusCode == 429 ||
              response.statusCode == 500 ||
              response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504) {
            if (attempt == 0) {
              await Future.delayed(const Duration(seconds: 1));
              continue;
            }
          }

          break;
        } catch (_) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          break;
        }
      }
    }

    throw Exception('All AI models are temporarily unavailable.');
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();

    if (text.isEmpty || isLoading) return;

    controller.clear();

    setState(() {
      messages.add({
        'sender': 'user',
        'text': text,
      });

      isLoading = true;
    });

    scrollToBottom();

    try {
      final reply = await getAIReply();

      if (!mounted) return;

      setState(() {
        messages.add({
          'sender': 'bot',
          'text': reply,
        });

        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        messages.add({
          'sender': 'bot',
          'text':
              'Sorry, I couldn’t respond right now. Please try again in a moment.',
        });

        isLoading = false;
      });
    }

    scrollToBottom();
  }


  Future<void> copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> regenerateLastResponse() async {
    if (isLoading) return;

    int lastBotIndex = -1;

    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['sender'] == 'bot') {
        lastBotIndex = i;
        break;
      }
    }

    if (lastBotIndex <= 0) return;

    int previousUserIndex = -1;

    for (int i = lastBotIndex - 1; i >= 0; i--) {
      if (messages[i]['sender'] == 'user') {
        previousUserIndex = i;
        break;
      }
    }

    if (previousUserIndex == -1) return;

    final originalBotMessage = messages.removeAt(lastBotIndex);

    setState(() {
      isLoading = true;
    });

    scrollToBottom();

    try {
      final reply = await getAIReply();

      if (!mounted) return;

      setState(() {
        messages.add({
          'sender': 'bot',
          'text': reply,
        });
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        messages.add(originalBotMessage);
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t regenerate. Please try again.'),
        ),
      );
    }

    await _saveChats();
    scrollToBottom();
  }

  Future<void> clearChat() async {
    setState(() {
      messages
        ..clear()
        ..add({
          'sender': 'bot',
          'text': 'Chat cleared. What would you like to talk about?',
        });
    });
    await _saveChats();
  }

  void scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Widget buildMessageBubble(Map<String, String> message) {
    final isUser = message['sender'] == 'user';
    final messageText = message['text']!;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0xFF651922)
            : const Color(0xFF242424),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser ? 20 : 5),
          bottomRight: Radius.circular(isUser ? 5 : 20),
        ),
      ),
      child: isUser
          ? Text(
              messageText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
              ),
            )
          : BotMessageContent(
              text: messageText,
            ),
    );

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: bubble,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bubble,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: () => copyMessage(messageText),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: Colors.grey,
                  ),
                ),
                IconButton(
                  tooltip: 'Regenerate',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: isLoading ? null : regenerateLastResponse,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingDot(delay: 0),
            SizedBox(width: 5),
            TypingDot(delay: 200),
            SizedBox(width: 5),
            TypingDot(delay: 400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: Drawer(
        backgroundColor: const Color(0xFF171717),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Chats',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: createNewChat,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: chats.isEmpty
                    ? const Center(
                        child: Text(
                          'No chats yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final chatId = chat['id'] as String;
                          final isActive = chatId == activeChatId;

                          return ListTile(
                            selected: isActive,
                            selectedTileColor: const Color(0xFF242424),
                            leading: const Icon(Icons.chat_bubble_outline),
                            title: Text(
                              chat['title']?.toString() ?? 'New Chat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => switchChat(chatId),
                            trailing: IconButton(
                              tooltip: 'Delete chat',
                              onPressed: () => deleteChat(chatId),
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF171717),
        elevation: 0,
        centerTitle: true,
        title: const Column(
          children: [
            Text(
              'ScAry Bot',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            Text(
              'AI Assistant',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: createNewChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Clear chat',
            onPressed: clearChat,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              itemCount: messages.length + (isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (isLoading && index == messages.length) {
                  return buildTypingIndicator();
                }

                return buildMessageBubble(messages[index]);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: const BoxDecoration(
                color: Color(0xFF171717),
                border: Border(
                  top: BorderSide(
                    color: Color(0xFF292929),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !isLoading,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: isLoading
                            ? 'ScAry Bot is thinking...'
                            : 'Message ScAry Bot...',
                        hintStyle: const TextStyle(
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF242424),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: isLoading
                          ? const Color(0xFF402326)
                          : const Color(0xFF651922),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: isLoading ? null : sendMessage,
                      icon: const Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class BotMessageContent extends StatelessWidget {
  final String text;

  const BotMessageContent({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final parts = _splitTextAndMath(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts.map((part) {
        if (part['type'] == 'math') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                part['content']!,
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ),
          );
        }

        return MarkdownBody(
          data: part['content']!,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.4,
            ),
            strong: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            code: const TextStyle(
              color: Color(0xFFE7B0B4),
              backgroundColor: Color(0xFF181818),
              fontFamily: 'monospace',
            ),
          ),
        );
      }).toList(),
    );
  }

  List<Map<String, String>> _splitTextAndMath(String input) {
    final regex = RegExp(
      r'(\$\$[\s\S]*?\$\$|\$[^$]+\$)',
    );

    final result = <Map<String, String>>[];
    int lastIndex = 0;

    for (final match in regex.allMatches(input)) {
      if (match.start > lastIndex) {
        result.add({
          'type': 'text',
          'content': input.substring(lastIndex, match.start),
        });
      }

      var math = match.group(0)!;

      if (math.startsWith(r'$$')) {
        math = math.substring(2, math.length - 2);
      } else {
        math = math.substring(1, math.length - 1);
      }

      result.add({
        'type': 'math',
        'content': math.trim(),
      });

      lastIndex = match.end;
    }

    if (lastIndex < input.length) {
      result.add({
        'type': 'text',
        'content': input.substring(lastIndex),
      });
    }

    return result;
  }
}

class TypingDot extends StatefulWidget {
  final int delay;

  const TypingDot({
    super.key,
    required this.delay,
  });

  @override
  State<TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  late final Animation<double> animation;

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    animation = Tween<double>(
      begin: 0.35,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeInOut,
      ),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        animationController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Colors.grey,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}