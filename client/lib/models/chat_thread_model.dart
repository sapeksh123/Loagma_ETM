class ChatThread {
  final String id;
  final String type;
  final String title;
  final String createdBy;
  final String? targetUserId;
  final String? targetRole;
  final DateTime? lastMessageAt;
  final int unreadCount;

  ChatThread({
    required this.id,
    required this.type,
    required this.title,
    required this.createdBy,
    this.targetUserId,
    this.targetRole,
    this.lastMessageAt,
    required this.unreadCount,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return ChatThread(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'direct',
      title: json['title']?.toString() ?? '',
      createdBy: json['created_by']?.toString() ?? '',
      targetUserId: json['target_user_id']?.toString(),
      targetRole: json['target_role']?.toString(),
      lastMessageAt: parseDate(json['last_message_at']),
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
    );
  }
}

