import 'package:flutter/material.dart';

import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../widgets/calculator_app_bar_action.dart';
import '../../widgets/notepad_app_bar_action.dart';
import 'employee_chat_thread_screen.dart';

class EmployeeNotificationsScreen extends StatefulWidget {
  final String userId;
  final String userRole;

  const EmployeeNotificationsScreen({
    super.key,
    required this.userId,
    required this.userRole,
  });

  @override
  State<EmployeeNotificationsScreen> createState() =>
      _EmployeeNotificationsScreenState();
}

class _EmployeeNotificationsScreenState
    extends State<EmployeeNotificationsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<NotificationModel> _notifications = [];

  Color _noteColor(NotificationModel n) {
    final text = n.message.toLowerCase();
    if (text.contains('completed') || text.contains('done')) {
      return const Color(0xFF1B7F3A);
    }
    if (text.contains('deadline') || text.contains('urgent') || text.contains('overdue')) {
      return const Color(0xFFB45309);
    }
    if (text.contains('pending') || text.contains('review') || text.contains('status')) {
      return const Color(0xFFD97706);
    }
    if (text.contains('update') || n.type == 'update') {
      return const Color(0xFF1D4ED8);
    }
    return const Color(0xFF374151);
  }

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await NotificationService.fetchNotifications(widget.userId);
      if (!mounted) return;
      setState(() {
        _notifications = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(NotificationModel notification) async {
    if (notification.isRead) return;
    try {
      await NotificationService.markNotificationRead(
        notificationId: notification.id,
        employeeId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map(
              (n) => n.id == notification.id
                  ? NotificationModel(
                      id: n.id,
                      employeeId: n.employeeId,
                      taskId: n.taskId,
                      subtaskIndex: n.subtaskIndex,
                      type: n.type,
                      title: n.title,
                      message: n.message,
                      isRead: true,
                      createdAt: n.createdAt,
                    )
                  : n,
            )
            .toList();
      });
    } catch (_) {
      // Ignore mark-read failures in UI for now.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
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
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadNotifications,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No notifications yet',
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
      onRefresh: _loadNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final n = _notifications[index];
          final isReminder = n.type == 'reminder';
          final icon = isReminder ? Icons.alarm : Icons.update;
          final color = isReminder ? Colors.orange : Colors.blue;
          final noteColor = _noteColor(n);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.04),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _markAsRead(n),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: n.isRead
                      ? const Color(0xFFFCFAF5)
                      : color.withValues(alpha: 0.08),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!n.isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Message from admin',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            n.message,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              color: noteColor,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatTimestamp(n.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (n.chatThreadId != null &&
                              n.chatThreadId!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _openChatFromNotification(n),
                                icon: const Icon(
                                  Icons.chat_bubble_outline,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Reply',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
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
      ),
    );
  }

  Future<void> _openChatFromNotification(NotificationModel n) async {
    if (n.chatThreadId == null || n.chatThreadId!.isEmpty) {
      await _markAsRead(n);
      return;
    }
    await _markAsRead(n);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeChatThreadScreen(
          threadId: n.chatThreadId!,
          userId: widget.userId,
          userRole: widget.userRole,
          title: n.title,
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    final isToday = dateOnly == today;
    final isYesterday =
        dateOnly == today.subtract(const Duration(days: 1));

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';

    if (isToday) {
      return 'Today • $time';
    }
    if (isYesterday) {
      return 'Yesterday • $time';
    }
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    return '$dd/$mo/$yyyy • $time';
  }
}

