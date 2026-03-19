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
  String? _error;
  String? _lastReadMessageId;
  final TextEditingController _inputController = TextEditingController();
  Timer? _pollTimer;
  Timer? _typingDebounce;
  bool _showDebugIds = false;

  @override
  void initState() {
    super.initState();
    ChatService.setPresence(userId: widget.userId, userRole: widget.userRole, isOnline: true).catchError((_) {});
    _loadMessages(initial: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    ChatService.setTyping(threadId: widget.threadId, userId: widget.userId, userRole: widget.userRole, isTyping: false).catchError((_) {});
    ChatService.setPresence(userId: widget.userId, userRole: widget.userRole, isOnline: false).catchError((_) {});
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isRefreshing) return;
      _loadMessages(initial: false);
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
      final sinceId =
          initial || _messages.isEmpty ? null : _messages.last.id;
      final newMessages = await ChatService.getMessages(
        threadId: widget.threadId,
        userId: widget.userId,
        userRole: widget.userRole,
        sinceMessageId: sinceId,
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

      final incoming = newMessages.where((m) => m.senderId != widget.userId).toList();
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
        _startPolling();
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
    if (text.isEmpty) return;
    final localId = 'local-${DateTime.now().millisecondsSinceEpoch}';
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

    ChatService.setTyping(threadId: widget.threadId, userId: widget.userId, userRole: widget.userRole, isTyping: false).catchError((_) {});

    try {
      final msg = await ChatService.sendMessage(
        threadId: widget.threadId,
        senderId: widget.userId,
        senderRole: widget.userRole,
        body: text,
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
      _fireAndForget(ChatService.markThreadRead(
        threadId: widget.threadId,
        userId: widget.userId,
        userRole: widget.userRole,
        lastReadMessageId: msg.id,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == localId);
      });
      _inputController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title?.isNotEmpty == true
        ? widget.title!
        : 'Chat';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Fast chat mode',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showDebugIds ? 'Hide debug IDs' : 'Show debug IDs',
            icon: Icon(_showDebugIds ? Icons.bug_report : Icons.bug_report_outlined),
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
            Expanded(
              child: _buildMessagesBody(),
            ),
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
            Icon(Icons.chat_bubble_outline,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No messages yet.\nStart the conversation.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
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
        return Align(
          alignment:
              isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () => _showReactionPicker(msg),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
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
                borderRadius: BorderRadius.circular(14),
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
                          .map((reaction) => Text(reaction.emoji, style: const TextStyle(fontSize: 12)))
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
                            color: isMe ? Colors.white70 : Colors.grey.shade600,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _statusIcon(msg),
                            size: 13,
                            color: msg.seenAt != null
                                ? Colors.lightBlueAccent
                                : (isMe ? Colors.white70 : Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                onChanged: (value) {
                  final isTyping = value.trim().isNotEmpty;
                  _typingDebounce?.cancel();
                  ChatService.setTyping(
                    threadId: widget.threadId,
                    userId: widget.userId,
                    userRole: widget.userRole,
                    isTyping: isTyping,
                  ).catchError((_) {});
                  _typingDebounce = Timer(const Duration(seconds: 2), () {
                    ChatService.setTyping(
                      threadId: widget.threadId,
                      userId: widget.userId,
                      userRole: widget.userRole,
                      isTyping: false,
                    ).catchError((_) {});
                  });
                },
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
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
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
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '').trim())),
      );
    }
  }

  void _fireAndForget(Future<void> future) {
    future.catchError((_) {});
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
    if (isMe) return 'You';
    if ((msg.senderName ?? '').trim().isNotEmpty) return msg.senderName!.trim();
    return _roleLabel(msg.senderRole);
  }

  String _receiverLabel(ChatMessage msg, bool isMe) {
    if (!isMe) return 'You';
    if ((msg.receiverName ?? '').trim().isNotEmpty) return msg.receiverName!.trim();
    return _peerLabelFromHistory();
  }

  String _peerLabelFromHistory() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.senderId != widget.userId) {
        if ((m.senderName ?? '').trim().isNotEmpty) return m.senderName!.trim();
        return _roleLabel(m.senderRole);
      }
    }
    return widget.title?.trim().isNotEmpty == true ? widget.title!.trim() : 'User';
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'subadmin':
        return 'Subadmin';
      case 'techincharge':
        return 'Technical Incharge';
      case 'employee':
        return 'Employee';
      default:
        return role;
    }
  }
}

