class ChatMessageReaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  ChatMessageReaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory ChatMessageReaction.fromJson(Map<String, dynamic> json) {
    return ChatMessageReaction(
      id: json['id']?.toString() ?? '',
      messageId: json['message_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatMessage {
  final String id;
  final String threadId;
  final String senderId;
  final String senderRole;
  final String body;
  final String? taskId;
  final int? subtaskIndex;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? seenAt;
  final bool isDeleted;
  final List<ChatMessageReaction> reactions;
  final String? senderName;
  final String? receiverId;
  final String? receiverName;

  ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    this.taskId,
    this.subtaskIndex,
    required this.createdAt,
    this.sentAt,
    this.deliveredAt,
    this.seenAt,
    this.isDeleted = false,
    this.reactions = const [],
    this.senderName,
    this.receiverId,
    this.receiverName,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final reactionsJson = json['reactions'];
    final parsedReactions = reactionsJson is List
      ? reactionsJson
        .whereType<Map>()
        .map((e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      : const <ChatMessageReaction>[];

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      threadId: json['thread_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderRole: json['sender_role']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      taskId: json['task_id']?.toString(),
      subtaskIndex: json['subtask_index'] != null
          ? int.tryParse(json['subtask_index'].toString())
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
        sentAt: DateTime.tryParse(json['sent_at']?.toString() ?? ''),
        deliveredAt: DateTime.tryParse(json['delivered_at']?.toString() ?? ''),
        seenAt: DateTime.tryParse(json['seen_at']?.toString() ?? ''),
        isDeleted: json['is_deleted'] == 1 ||
          json['is_deleted'] == true ||
          json['is_deleted']?.toString() == 'true',
        reactions: parsedReactions,
        senderName: json['sender_name']?.toString(),
        receiverId: json['receiver_id']?.toString(),
        receiverName: json['receiver_name']?.toString(),
    );
  }
}

