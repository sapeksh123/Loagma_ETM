import 'package:flutter/material.dart';

import '../chat/chat_list_screen.dart';

class AdminChatListScreen extends StatelessWidget {
  const AdminChatListScreen({
    super.key,
    required this.userId,
    required this.userRole,
  });

  final String userId;
  final String userRole;

  @override
  Widget build(BuildContext context) {
    return ChatListScreen(userId: userId, userRole: userRole);
  }
}
