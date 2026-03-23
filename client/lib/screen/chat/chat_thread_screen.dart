import 'package:flutter/material.dart';

import '../../chat/chat_thread_controller.dart';
import '../../models/chat_message_model.dart';
import '../../models/chat_thread_model.dart';

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.thread,
    required this.userId,
    required this.userRole,
  });

  final ChatThread thread;
  final String userId;
  final String userRole;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final ChatThreadController _controller;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = ChatThreadController(
      thread: widget.thread,
      userId: widget.userId,
      userRole: widget.userRole,
    )..init();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.disposeController();
    _controller.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset < 120) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFECE5D8),
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _controller.thread.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _controller.headerSubtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (_controller.error != null)
                MaterialBanner(
                  backgroundColor: const Color(0xFFFFF3E0),
                  content: Text(_controller.error!),
                  actions: [
                    TextButton(
                      onPressed: _controller.refreshInitial,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              Expanded(child: _buildMessages()),
              _buildComposer(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessages() {
    if (_controller.isLoading && _controller.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.messages.isEmpty) {
      return Center(
        child: Text(
          'Start the conversation',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 20) {
          _controller.loadOlderMessages();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
        itemCount: _controller.messages.length + (_controller.isLoadingOlder ? 1 : 0),
        itemBuilder: (context, index) {
          if (_controller.isLoadingOlder && index == _controller.messages.length) {
            return const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final message = _controller.messages[_controller.messages.length - 1 - index];
          final isMe = message.senderId == widget.userId;
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              onTap: message.isFailed ? () => _controller.retryMessage(message) : null,
              child: Container(
                key: ValueKey(message.id),
                margin: const EdgeInsets.only(bottom: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.76,
                ),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFD9FDD3) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: message.isFailed
                      ? Border.all(color: Colors.redAccent.withValues(alpha: 0.5))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.body,
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                    if (message.isFailed) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to retry',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timeLabel(message.createdAt),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _buildStatus(message),
                        ],
                      ],
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

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: const BoxDecoration(color: Color(0xFFF7F4ED)),
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 5,
                  onChanged: _controller.onComposerChanged,
                  onSubmitted: (_) => _submit(),
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: 'Write a message',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: const Color(0xFF1F8B4C),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _submit,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(ChatMessage message) {
    if (message.isPending) {
      return Icon(Icons.schedule_rounded, size: 15, color: Colors.grey.shade600);
    }

    if (message.isFailed) {
      return const Icon(Icons.error_outline, size: 15, color: Colors.redAccent);
    }

    switch (message.status) {
      case 'seen':
        return const Icon(Icons.done_all_rounded, size: 16, color: Colors.blueAccent);
      case 'delivered':
        return Icon(Icons.done_all_rounded, size: 16, color: Colors.grey.shade600);
      default:
        return Icon(Icons.done_rounded, size: 16, color: Colors.grey.shade600);
    }
  }

  Future<void> _submit() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await _controller.sendMessage(text);
  }

  String _timeLabel(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
