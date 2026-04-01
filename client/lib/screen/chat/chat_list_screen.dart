import 'package:flutter/material.dart';

import '../../chat/chat_list_controller.dart';
import '../../models/chat_thread_model.dart';
import '../../models/chat_user_model.dart';
import '../../widgets/calculator_app_bar_action.dart';
import '../../widgets/notepad_app_bar_action.dart';
import 'chat_thread_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.userId,
    required this.userRole,
  });

  final String userId;
  final String userRole;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late final ChatListController _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _controller = ChatListController(
      userId: widget.userId,
      userRole: widget.userRole,
    )..init();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 180) {
      _controller.loadMoreUsers();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F1EA),
          appBar: AppBar(
            elevation: 0,
            title: const Text(
              'Chats',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              buildNotepadAppBarAction(
                context,
                userId: widget.userId,
                userRole: widget.userRole,
              ),
              buildCalculatorAppBarAction(context),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => _controller.refresh(),
            child: _buildBody(context),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    if (_controller.isLoading && _controller.threads.isEmpty) {
      return _buildInitialLoadingView(bottomInset);
    }

    if (_controller.error != null &&
        _controller.threads.isEmpty &&
        _controller.users.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 160),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _controller.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(10, 10, 10, 24 + bottomInset),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
           
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome to Loagma Chat!',
                style: TextStyle(
                  color: Color.fromARGB(255, 61, 54, 127),
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
             
             
            ],
          ),
        ),
        
        if (_controller.isRefreshing) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 12),
        if (_controller.threads.isNotEmpty) ...[
          const Text(
            'Conversations',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ..._controller.threads.map((thread) => _buildThreadTile(context, thread)),
          const SizedBox(height: 16),
        ],
        const Text(
          'People',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (_controller.users.isEmpty && !_controller.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No people found.'),
          ),
        ..._controller.users.map((user) => _buildUserTile(context, user)),
        if (_controller.isLoadingMoreUsers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_controller.hasMoreUsers && _controller.users.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton.icon(
                onPressed: _controller.loadMoreUsers,
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more people'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitialLoadingView(double bottomInset) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(10, 10, 10, 24 + bottomInset),
      children: [
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Text(
            'Loading chats...',
            style: TextStyle(
              color: Color.fromARGB(255, 61, 54, 127),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F7F3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7E0D0)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThreadTile(BuildContext context, ChatThread thread) {
    return InkWell(
      onTap: () => _openThread(context, thread),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFE9DFC4),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Text(
                        (thread.title.isNotEmpty ? thread.title[0] : '?').toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF6C5624),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (thread.type == 'direct' && thread.counterpartIsOnline)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F8B4C),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (thread.lastMessageAt != null)
                          Text(
                            _threadTime(thread.lastMessageAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      thread.previewText(widget.userId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: thread.unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (thread.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F8B4C),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    thread.unreadCount > 99 ? '99+' : '${thread.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, ChatUser user) {
    return InkWell(
      onTap: () async {
        try {
          final thread = await _controller.openDirectThread(user);
          if (!context.mounted) return;
          await _openThread(context, thread);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7F3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7E0D0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.displayRole,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chat_bubble_outline_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openThread(BuildContext context, ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          thread: thread,
          userId: widget.userId,
          userRole: widget.userRole,
        ),
      ),
    );
    if (!mounted) return;
    await _controller.refresh();
  }

  String _threadTime(DateTime dt) {
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '$hh:$mm';
    }
    return '${dt.day}/${dt.month}';
  }
}
