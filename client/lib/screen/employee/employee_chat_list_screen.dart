import 'package:flutter/material.dart';

import '../../models/chat_thread_model.dart';
import '../../models/chat_user_model.dart';
import '../../services/chat_service.dart';
import 'employee_chat_thread_screen.dart';

class EmployeeChatListScreen extends StatefulWidget {
  final String userId;
  final String userRole;

  const EmployeeChatListScreen({
    super.key,
    required this.userId,
    required this.userRole,
  });

  @override
  State<EmployeeChatListScreen> createState() =>
      _EmployeeChatListScreenState();
}

class _EmployeeChatListScreenState extends State<EmployeeChatListScreen> {
  bool _isLoading = true;
  String? _error;
  List<ChatThread> _threads = [];
  List<ChatUser> _users = [];

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ChatService.getThreads(
          userId: widget.userId,
          role: widget.userRole,
        ),
        ChatService.getChatUsers(currentUserId: widget.userId),
      ]);

      final data = results[0] as List<ChatThread>;
      final users = results[1] as List<ChatUser>;

      if (!mounted) return;
      setState(() {
        _threads = data;
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
              onPressed: _loadThreads,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_threads.isEmpty && _users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No users available for chat',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadThreads,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          if (_threads.isNotEmpty)
            ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Conversations',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              ..._threads.map(_buildThreadTile),
              const SizedBox(height: 14),
            ],
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'People',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          ..._users.map(_buildUserTile),
        ],
      ),
    );
  }

  Widget _buildThreadTile(ChatThread t) {
    final isBroadcastAll = t.type == 'broadcast_all';
    final isBroadcastRole = t.type == 'broadcast_role';
    final isDirect = t.type == 'direct';

    IconData icon;
    Color color;
    if (isDirect) {
      icon = Icons.person_outline;
      color = Colors.blue;
    } else if (isBroadcastRole) {
      icon = Icons.groups_outlined;
      color = Colors.deepOrange;
    } else {
      icon = Icons.campaign_outlined;
      color = Colors.green;
    }

    final subtitle = _buildSubtitle(t);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EmployeeChatThreadScreen(
                threadId: t.id,
                userId: widget.userId,
                userRole: widget.userRole,
                title: t.title,
              ),
            ),
          );
          _loadThreads();
        },
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          t.title.isNotEmpty
              ? t.title
              : (isBroadcastAll
                  ? 'Broadcast: All'
                  : isBroadcastRole
                      ? 'Broadcast: ${t.targetRole ?? ''}'
                      : 'Direct chat'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: t.unreadCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t.unreadCount > 9 ? '9+' : t.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildUserTile(ChatUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openDirectChat(user),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFceb56e).withValues(alpha: 0.2),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Color(0xFF8d7536),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(user.name),
        subtitle: Text(user.displayRole),
        trailing: const Icon(Icons.chat_outlined, size: 20),
      ),
    );
  }

  Future<void> _openDirectChat(ChatUser user) async {
    try {
      final thread = await ChatService.openDirectThread(
        userAId: widget.userId,
        userBId: user.id,
        userRole: widget.userRole,
        title: user.name,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmployeeChatThreadScreen(
            threadId: thread.id,
            userId: widget.userId,
            userRole: widget.userRole,
            title: user.name,
          ),
        ),
      );
      _loadThreads();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '').trim())),
      );
    }
  }

  String? _buildSubtitle(ChatThread t) {
    if (t.lastMessageAt == null) return null;
    final dt = t.lastMessageAt!;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return 'Last message at $hh:$mm';
  }
}

