import 'package:flutter/material.dart';

import '../../models/chat_thread_model.dart';
import '../chat/chat_thread_screen.dart';

class AdminChatThreadScreen extends StatelessWidget {
  const AdminChatThreadScreen({
    super.key,
    required this.thread,
    required this.userId,
    required this.userRole,
  });

  final ChatThread thread;
  final String userId;
  final String userRole;

  @override
  Widget build(BuildContext context) {
    return ChatThreadScreen(
      thread: thread,
      userId: userId,
      userRole: userRole,
    );
  }
}
