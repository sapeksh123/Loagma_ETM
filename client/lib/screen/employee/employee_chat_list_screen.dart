import 'package:flutter/material.dart';
import 'dart:async';

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
  bool _isRefreshing = false;
  String? _error;
  List<ChatThread> _threads = [];
  List<ChatUser> _users = [];
  StreamSubscription<List<ChatThread>>? _threadsSubscription;

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadThreads(initial: true);
    _startThreadWatcher();
  }

  @override
  void dispose() {
    _threadsSubscription?.cancel();
    super.dispose();
  }

  void _startThreadWatcher() {
    _threadsSubscription?.cancel();
    _threadsSubscription = ChatService.watchThreads(
      userId: widget.userId,
      role: widget.userRole,
    ).listen((threads) {
      if (!mounted) return;
      setState(() {
        _threads = threads;
      });
    });
  }

  void _hydrateFromCache() {
    final cachedThreads = ChatService.getCachedThreads(
      userId: widget.userId,
      role: widget.userRole,
    );
    final cachedUsers = ChatService.getCachedUsers(currentUserId: widget.userId);

    if (cachedThreads == null && cachedUsers == null) {
      return;
    }

    setState(() {
      if (cachedThreads != null) {
        _threads = cachedThreads;
      }
      if (cachedUsers != null) {
        _users = cachedUsers;
      }
      _isLoading = _threads.isEmpty && _users.isEmpty;
    });
  }

  Future<void> _loadThreads({bool initial = false}) async {
    setState(() {
      if (initial && _threads.isEmpty && _users.isEmpty) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
      _error = null;
    });
    try {
      final data = await ChatService.getThreads(
        userId: widget.userId,
        role: widget.userRole,
        forceRefresh: true,
      );

      if (!mounted) return;
      setState(() {
        _threads = data;
        _isLoading = false;
        _isRefreshing = false;
      });

      final users = await ChatService.getChatUsers(
        currentUserId: widget.userId,
        forceRefresh: true,
      );

      if (!mounted) return;
      setState(() {
        _users = users;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
        _isRefreshing = false;
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
      return _buildLoadingSkeleton();
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
                onPressed: () => _loadThreads(initial: false),
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
        onRefresh: () => _loadThreads(initial: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
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
          _loadThreads(initial: false);
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (t.unreadCount > 0)
              const Text(
                'New messages',
                style: TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
          ],
        ),
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
      _loadThreads(initial: false);
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
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today, $hh:$mm';
    }
    if (dt.year == now.year) {
      return '${dt.day}/${dt.month}, $hh:$mm';
    }
    return '${dt.day}/${dt.month}/${dt.year}, $hh:$mm';
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: const ListTile(
            leading: CircleAvatar(backgroundColor: Color(0xFFEAEAEA)),
            title: SizedBox(
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFEAEAEA)),
              ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFFF2F2F2)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

