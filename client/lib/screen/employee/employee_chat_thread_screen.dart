import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/chat_message_model.dart';
import '../../services/chat_service.dart';

class EmployeeChatThreadScreen extends StatefulWidget {
  final String threadId;
  final String userId;
  final String userRole;
  final String? title;

  const EmployeeChatThreadScreen({
    super.key,
    required this.threadId,
    required this.userId,
    required this.userRole,
    this.title,
  });

  @override
  State<EmployeeChatThreadScreen> createState() =>
      _EmployeeChatThreadScreenState();
}

class _EmployeeChatThreadScreenState extends State<EmployeeChatThreadScreen> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSending = false;
  String? _error;
  String? _lastReadMessageId;
  final TextEditingController _inputController = TextEditingController();
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  Timer? _typingDebounce;
  bool _showDebugIds = false;
  bool _typingStateSent = false;

  @override
  void initState() {
    super.initState();
    ChatService.setPresence(
      userId: widget.userId,
      userRole: widget.userRole,
      isOnline: true,
    ).catchError((_) {});
    _loadMessages(initial: true);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingDebounce?.cancel();
    _setTypingState(false, force: true);
    ChatService.setPresence(
      userId: widget.userId,
      userRole: widget.userRole,
      isOnline: false,
    ).catchError((_) {});
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _startRealtimeWatch() {
    _messageSubscription?.cancel();
    final sinceId = _messages.isNotEmpty ? _messages.last.id : null;
    _messageSubscription =
        ChatService.watchThreadMessages(
          threadId: widget.threadId,
          userId: widget.userId,
          userRole: widget.userRole,
          initialSinceMessageId: sinceId,
        ).listen((updates) {
          if (!mounted || updates.isEmpty) return;

          final unique = <ChatMessage>[];
          for (final m in updates) {
            if (_messages.any((e) => e.id == m.id)) continue;
            unique.add(m);
          }

          if (unique.isEmpty) return;

          setState(() {
            _messages.addAll(unique);
          });

          _scrollToBottom();

          final incoming = unique
              .where((m) => m.senderId != widget.userId)
              .toList();
          if (incoming.isNotEmpty) {
            final latestIncoming = incoming.last;
            _fireAndForget(
              ChatService.markMessageDelivered(
                threadId: widget.threadId,
                messageId: latestIncoming.id,
                userId: widget.userId,
                userRole: widget.userRole,
              ),
            );
          }

          if (_messages.isNotEmpty) {
            final last = _messages.last;
            if (_lastReadMessageId != last.id) {
              _lastReadMessageId = last.id;
              _fireAndForget(
                ChatService.markThreadRead(
                  threadId: widget.threadId,
                  userId: widget.userId,
                  userRole: widget.userRole,
                  lastReadMessageId: last.id,
                ),
              );
              if (last.senderId != widget.userId) {
                _fireAndForget(
                  ChatService.markMessageSeen(
                    threadId: widget.threadId,
                    messageId: last.id,
                    userId: widget.userId,
                    userRole: widget.userRole,
                  ),
                );
              }
            }
          }
        });
  }

  Future<void> _loadMessages({required bool initial}) async {
    if (_isRefreshing && !initial) return;
    _isRefreshing = true;

    setState(() {
      if (initial) {
        _isLoading = true;
        _error = null;
      }
    });
    try {
      final sinceId = initial || _messages.isEmpty ? null : _messages.last.id;
      final newMessages = await ChatService.getMessages(
        threadId: widget.threadId,
        userId: widget.userId,
        userRole: widget.userRole,
        sinceMessageId: sinceId,
        limit: initial ? 80 : 30,
      );
      if (!mounted) return;
      if (initial) {
        _messages
          ..clear()
          ..addAll(newMessages);
        _isLoading = false;
      } else if (newMessages.isNotEmpty) {
        _messages.addAll(newMessages);
      }

      if (newMessages.isNotEmpty) {
        _scrollToBottom();
      }

      final incoming = newMessages
          .where((m) => m.senderId != widget.userId)
          .toList();
      if (incoming.isNotEmpty) {
        final latestIncoming = incoming.last;
        _fireAndForget(
          ChatService.markMessageDelivered(
            threadId: widget.threadId,
            messageId: latestIncoming.id,
            userId: widget.userId,
            userRole: widget.userRole,
          ),
        );
      }

      if (_messages.isNotEmpty) {
        final last = _messages.last;
        if (_lastReadMessageId != last.id) {
          _lastReadMessageId = last.id;
          _fireAndForget(
            ChatService.markThreadRead(
              threadId: widget.threadId,
              userId: widget.userId,
              userRole: widget.userRole,
              lastReadMessageId: last.id,
            ),
          );
          if (last.senderId != widget.userId) {
            _fireAndForget(
              ChatService.markMessageSeen(
                threadId: widget.threadId,
                messageId: last.id,
                userId: widget.userId,
                userRole: widget.userRole,
              ),
            );
          }
        }
      }
      setState(() {});
      if (initial) {
        _startRealtimeWatch();
      }
      _isRefreshing = false;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
      _isRefreshing = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;
    _isSending = true;
    final localId =
        'local-${widget.userId}-${DateTime.now().microsecondsSinceEpoch}';
    final localMessage = ChatMessage(
      id: localId,
      threadId: widget.threadId,
      senderId: widget.userId,
      senderRole: widget.userRole,
      body: text,
      createdAt: DateTime.now(),
      sentAt: DateTime.now(),
      deliveredAt: null,
      seenAt: null,
      reactions: const [],
    );

    _inputController.clear();
    setState(() {
      _messages.add(localMessage);
    });
    _scrollToBottom();

    _setTypingState(false);

    try {
      final msg = await ChatService.sendMessage(
        threadId: widget.threadId,
        senderId: widget.userId,
        senderRole: widget.userRole,
        body: text,
        clientMessageId: localId,
      );
      if (!mounted) return;
      final index = _messages.indexWhere((m) => m.id == localId);
      setState(() {
        if (index >= 0) {
          _messages[index] = msg;
        } else {
          _messages.add(msg);
        }
      });
      _lastReadMessageId = msg.id;
      _fireAndForget(
        ChatService.markThreadRead(
          threadId: widget.threadId,
          userId: widget.userId,
          userRole: widget.userRole,
          lastReadMessageId: msg.id,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == localId);
      });
      if (_inputController.text.trim().isEmpty) {
        _inputController.text = text;
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
        _onInputChanged(_inputController.text);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
        ),
      );
    } finally {
      _isSending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title?.isNotEmpty == true ? widget.title! : 'Chat';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text(
              'Fast chat mode',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showDebugIds ? 'Hide debug IDs' : 'Show debug IDs',
            icon: Icon(
              _showDebugIds ? Icons.bug_report : Icons.bug_report_outlined,
            ),
            onPressed: () {
              setState(() {
                _showDebugIds = !_showDebugIds;
              });
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7F3E7), Color(0xFFFFFFFF)],
          ),
        ),
        child: Column(
          children: [
            if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildMessagesBody()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _loadMessages(initial: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 60,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'No messages yet.\nStart the conversation.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.senderId == widget.userId;
        final showDateHeader = _shouldShowDateHeader(index);
        final groupedWithPrev = _isGroupedWithPrevious(index);
        final groupedWithNext = _isGroupedWithNext(index);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateHeader)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _dayHeaderLabel(msg.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => _showReactionPicker(msg),
                child: Container(
                  margin: EdgeInsets.only(
                    top: groupedWithPrev ? 1 : 6,
                    bottom: groupedWithNext ? 1 : 4,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFFceb56e).withValues(alpha: 0.85)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(
                        isMe ? 14 : (groupedWithNext ? 6 : 14),
                      ),
                      bottomRight: Radius.circular(
                        isMe ? (groupedWithNext ? 6 : 14) : 14,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_senderLabel(msg, isMe)} -> ${_receiverLabel(msg, isMe)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.white70 : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.body,
                        style: TextStyle(
                          fontSize: 13,
                          color: isMe ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (_showDebugIds) ...[
                        const SizedBox(height: 4),
                        Text(
                          'debug current=${widget.userId} sender=${msg.senderId} receiver=${msg.receiverId ?? '-'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                      if (msg.reactions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children: msg.reactions
                              .map(
                                (reaction) => Text(
                                  reaction.emoji,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(msg.createdAt),
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                _statusIcon(msg),
                                size: 13,
                                color: msg.seenAt != null
                                    ? Colors.lightBlueAccent
                                    : (isMe
                                          ? Colors.white70
                                          : Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onChanged: _onInputChanged,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              color: const Color(0xFFceb56e),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '$hh:$mm';
    }
    if (dt.year == now.year) {
      return '${dt.day}/${dt.month} $hh:$mm';
    }
    return '${dt.day}/${dt.month}/${dt.year} $hh:$mm';
  }

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    final current = _messages[index].createdAt;
    final prev = _messages[index - 1].createdAt;
    return current.year != prev.year ||
        current.month != prev.month ||
        current.day != prev.day;
  }

  bool _isGroupedWithPrevious(int index) {
    if (index == 0) return false;
    final current = _messages[index];
    final prev = _messages[index - 1];
    if (current.senderId != prev.senderId) return false;
    final diff = current.createdAt.difference(prev.createdAt).inMinutes.abs();
    return diff <= 3;
  }

  bool _isGroupedWithNext(int index) {
    if (index >= _messages.length - 1) return false;
    final current = _messages[index];
    final next = _messages[index + 1];
    if (current.senderId != next.senderId) return false;
    final diff = next.createdAt.difference(current.createdAt).inMinutes.abs();
    return diff <= 3;
  }

  String _dayHeaderLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _statusIcon(ChatMessage msg) {
    if (msg.seenAt != null) return Icons.done_all;
    if (msg.deliveredAt != null) return Icons.done_all;
    return Icons.done;
  }

  Future<void> _showReactionPicker(ChatMessage message) async {
    const emojis = ['👍', '❤️', '😂', '😮', '🙏'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: emojis
                .map(
                  (emoji) => ListTile(
                    title: Text(emoji, style: const TextStyle(fontSize: 24)),
                    onTap: () => Navigator.of(context).pop(emoji),
                  ),
                )
                .toList(),
          ),
        );
      },
    );

    if (selected == null) return;

    try {
      final updatedReactions = await ChatService.addReaction(
        threadId: widget.threadId,
        messageId: message.id,
        userId: widget.userId,
        userRole: widget.userRole,
        emoji: selected,
      );

      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index < 0) return;
      final current = _messages[index];
      setState(() {
        _messages[index] = ChatMessage(
          id: current.id,
          threadId: current.threadId,
          senderId: current.senderId,
          senderRole: current.senderRole,
          body: current.body,
          taskId: current.taskId,
          subtaskIndex: current.subtaskIndex,
          createdAt: current.createdAt,
          sentAt: current.sentAt,
          deliveredAt: current.deliveredAt,
          seenAt: current.seenAt,
          isDeleted: current.isDeleted,
          reactions: updatedReactions,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
        ),
      );
    }
  }

  void _fireAndForget(Future<void> future) {
    future.catchError((_) {});
  }

  void _setTypingState(bool isTyping, {bool force = false}) {
    if (!force && _typingStateSent == isTyping) return;
    _typingStateSent = isTyping;
    _fireAndForget(
      ChatService.setTyping(
        threadId: widget.threadId,
        userId: widget.userId,
        userRole: widget.userRole,
        isTyping: isTyping,
      ),
    );
  }

  void _onInputChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    _typingDebounce?.cancel();

    if (!hasText) {
      _setTypingState(false);
      return;
    }

    _setTypingState(true);
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _setTypingState(false);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _senderLabel(ChatMessage msg, bool isMe) {
    return msg.displaySenderName(isMe: isMe);
  }

  String _receiverLabel(ChatMessage msg, bool isMe) {
    return msg.displayReceiverName(isMe: isMe, threadTitle: widget.title);
  }
}
