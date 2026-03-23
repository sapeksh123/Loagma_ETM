import 'package:flutter/material.dart';

import '../../models/chat_thread_model.dart';
import '../chat/chat_thread_screen.dart';

class EmployeeChatThreadScreen extends StatelessWidget {
  const EmployeeChatThreadScreen({
    super.key,
    required this.threadId,
    required this.userId,
    required this.userRole,
    this.title,
  });

  final String threadId;
  final String userId;
  final String userRole;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return ChatThreadScreen(
      thread: ChatThread(
        id: threadId,
        type: 'direct',
        title: title?.trim().isNotEmpty == true ? title!.trim() : 'Chat',
        createdBy: userId,
        unreadCount: 0,
      ),
      userId: userId,
      userRole: userRole,
    );
  }
}
