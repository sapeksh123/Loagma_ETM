import 'dart:convert';

import 'chat_message_model.dart';

class ChatThread {
  final String id;
  final String type;
  final String title;
  final String createdBy;
  final String? targetUserId;
  final String? targetRole;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String? counterpartUserId;
  final String? counterpartName;
  final bool counterpartIsOnline;
  final DateTime? counterpartLastSeenAt;
  final String? lastMessageBody;
  final String? lastMessageSenderId;
  final int? lastMessageSortKey;

  const ChatThread({
    required this.id,
    required this.type,
    required this.title,
    required this.createdBy,
    required this.unreadCount,
    this.targetUserId,
    this.targetRole,
    this.lastMessageAt,
    this.counterpartUserId,
    this.counterpartName,
    this.counterpartIsOnline = false,
    this.counterpartLastSeenAt,
    this.lastMessageBody,
    this.lastMessageSenderId,
    this.lastMessageSortKey,
  });

  static ChatThread _fromMap(
    Map<String, dynamic> json, {
    required bool assumeUtcForNaiveTimes,
  }) {
    final parseTime = assumeUtcForNaiveTimes
        ? ChatMessage.parseApiTime
        : ChatMessage.parseServerTime;

    return ChatThread(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'direct',
      title: json['title']?.toString() ?? '',
      createdBy: json['created_by']?.toString() ?? '',
      targetUserId: json['target_user_id']?.toString(),
      targetRole: json['target_role']?.toString(),
      lastMessageAt: parseTime(
        json['last_message_at']?.toString(),
      ),
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      counterpartUserId: json['counterpart_user_id']?.toString(),
      counterpartName: json['counterpart_name']?.toString(),
      counterpartIsOnline:
          json['counterpart_is_online'] == true ||
          json['counterpart_is_online'] == 1,
      counterpartLastSeenAt: parseTime(
        json['counterpart_last_seen_at']?.toString(),
      ),
      lastMessageBody: json['last_message_body']?.toString(),
      lastMessageSenderId: json['last_message_sender_id']?.toString(),
      lastMessageSortKey: json['last_message_sort_key'] != null
          ? int.tryParse(json['last_message_sort_key'].toString())
          : null,
    );
  }

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return _fromMap(json, assumeUtcForNaiveTimes: true);
  }

  ChatThread copyWith({
    String? id,
    String? type,
    String? title,
    String? createdBy,
    String? targetUserId,
    String? targetRole,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? counterpartUserId,
    String? counterpartName,
    bool? counterpartIsOnline,
    DateTime? counterpartLastSeenAt,
    String? lastMessageBody,
    String? lastMessageSenderId,
    int? lastMessageSortKey,
  }) {
    return ChatThread(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      createdBy: createdBy ?? this.createdBy,
      targetUserId: targetUserId ?? this.targetUserId,
      targetRole: targetRole ?? this.targetRole,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      counterpartUserId: counterpartUserId ?? this.counterpartUserId,
      counterpartName: counterpartName ?? this.counterpartName,
      counterpartIsOnline: counterpartIsOnline ?? this.counterpartIsOnline,
      counterpartLastSeenAt:
          counterpartLastSeenAt ?? this.counterpartLastSeenAt,
      lastMessageBody: lastMessageBody ?? this.lastMessageBody,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageSortKey: lastMessageSortKey ?? this.lastMessageSortKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'created_by': createdBy,
      'target_user_id': targetUserId,
      'target_role': targetRole,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'unread_count': unreadCount,
      'counterpart_user_id': counterpartUserId,
      'counterpart_name': counterpartName,
      'counterpart_is_online': counterpartIsOnline,
      'counterpart_last_seen_at': counterpartLastSeenAt?.toIso8601String(),
      'last_message_body': lastMessageBody,
      'last_message_sender_id': lastMessageSenderId,
      'last_message_sort_key': lastMessageSortKey,
    };
  }

  String toStorageJson() => jsonEncode(toJson());

  static ChatThread fromStorageJson(String raw) {
    return _fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
      assumeUtcForNaiveTimes: false,
    );
  }

  String previewText(String currentUserId) {
    final body = lastMessageBody?.trim() ?? '';
    if (body.isEmpty) {
      return type == 'direct' ? 'Start chatting' : 'No messages yet';
    }
    if (lastMessageSenderId == currentUserId) {
      return 'You: $body';
    }
    return body;
  }
}
