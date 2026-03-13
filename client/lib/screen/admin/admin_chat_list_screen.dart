import 'package:flutter/material.dart';

import '../../models/chat_thread_model.dart';
import '../../services/chat_service.dart';
import 'admin_chat_thread_screen.dart';

class AdminChatListScreen extends StatefulWidget {
  final String userId;
  final String userRole;

  const AdminChatListScreen({
    super.key,
    required this.userId,
    required this.userRole,
  });

  @override
  State<AdminChatListScreen> createState() => _AdminChatListScreenState();
}

class _AdminChatListScreenState extends State<AdminChatListScreen> {
  bool _isLoading = true;
  String? _error;
  List<ChatThread> _threads = [];

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
      final data = await ChatService.getThreads(
        userId: widget.userId,
        role: widget.userRole,
      );
      if (!mounted) return;
      setState(() {
        _threads = data;
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
    if (_threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No conversations yet',
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
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _threads.length,
        itemBuilder: (context, index) {
          final t = _threads[index];
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminChatThreadScreen(
                      thread: t,
                      userId: widget.userId,
                      userRole: widget.userRole,
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
                        ? 'Broadcast: All employees'
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t.unreadCount > 9
                            ? '9+'
                            : t.unreadCount.toString(),
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
        },
      ),
    );
  }

  String? _buildSubtitle(ChatThread t) {
    if (t.lastMessageAt == null) return null;
    final dt = t.lastMessageAt!;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return 'Last message at $hh:$mm';
  }
}

