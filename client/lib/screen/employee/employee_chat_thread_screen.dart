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
  bool _isLoading = true;
  String? _error;
  final TextEditingController _inputController = TextEditingController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages(initial: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _loadMessages(initial: false);
    });
  }

  Future<void> _loadMessages({required bool initial}) async {
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
      if (_messages.isNotEmpty) {
        final last = _messages.last;
        await ChatService.markThreadRead(
          threadId: widget.threadId,
          userId: widget.userId,
          lastReadMessageId: last.id,
        );
      }
      setState(() {});
      if (initial) {
        _startPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    try {
      final msg = await ChatService.sendMessage(
        threadId: widget.threadId,
        senderId: widget.userId,
        senderRole: widget.userRole,
        body: text,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
      });
      await ChatService.markThreadRead(
        threadId: widget.threadId,
        userId: widget.userId,
        lastReadMessageId: msg.id,
      );
    } catch (e) {
      if (!mounted) return;
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
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessagesBody(),
          ),
          _buildInputBar(),
        ],
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.senderId == widget.userId;
        return Align(
          alignment:
              isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                  msg.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: isMe ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    _formatTime(msg.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white70
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
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
}

