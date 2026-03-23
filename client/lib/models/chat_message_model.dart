import 'dart:convert';

class ChatMessageReaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  const ChatMessageReaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory ChatMessageReaction.fromJson(
    Map<String, dynamic> json, {
    bool assumeUtcForNaiveTimes = true,
  }) {
    final parseTime = assumeUtcForNaiveTimes
        ? ChatMessage.parseApiTime
        : ChatMessage.parseServerTime;
    return ChatMessageReaction(
      id: json['id']?.toString() ?? '',
      messageId: json['message_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      createdAt: parseTime(json['created_at']?.toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message_id': messageId,
      'user_id': userId,
      'emoji': emoji,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ChatMessage {
  static final RegExp _explicitTimezoneSuffix = RegExp(
    r'(Z|[+\-]\d{2}:?\d{2})$',
    caseSensitive: false,
  );

  final String id;
  final String threadId;
  final String senderId;
  final String senderRole;
  final String body;
  final String? taskId;
  final int? subtaskIndex;
  final String? clientMessageId;
  final int? sortKey;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? seenAt;
  final bool isDeleted;
  final List<ChatMessageReaction> reactions;
  final String? senderName;
  final String? receiverId;
  final String? receiverName;
  final String status;
  final bool isPending;
  final bool isFailed;

  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.taskId,
    this.subtaskIndex,
    this.clientMessageId,
    this.sortKey,
    this.sentAt,
    this.deliveredAt,
    this.seenAt,
    this.isDeleted = false,
    this.reactions = const [],
    this.senderName,
    this.receiverId,
    this.receiverName,
    this.status = 'sent',
    this.isPending = false,
    this.isFailed = false,
  });

  static DateTime? parseServerTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  /// Parse API timestamp values.
  ///
  /// The backend uses UTC timezone and often emits DB-style strings without an
  /// explicit timezone suffix (for example `YYYY-MM-DD HH:mm:ss`). For those
  /// values, assume UTC and convert to device local time before rendering.
  static DateTime? parseApiTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;

    if (_explicitTimezoneSuffix.hasMatch(value)) {
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }

    final utcValue = DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
    return utcValue.toLocal();
  }

  static ChatMessage _fromMap(
    Map<String, dynamic> json, {
    required bool assumeUtcForNaiveTimes,
  }) {
    final parseTime = assumeUtcForNaiveTimes ? parseApiTime : parseServerTime;

    final reactionsJson = json['reactions'];
    final parsedReactions = reactionsJson is List
        ? reactionsJson
              .whereType<Map>()
              .map(
                (e) => ChatMessageReaction.fromJson(
                  Map<String, dynamic>.from(e),
                  assumeUtcForNaiveTimes: assumeUtcForNaiveTimes,
                ),
              )
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
      clientMessageId: json['client_message_id']?.toString(),
      sortKey: json['sort_key'] != null
          ? int.tryParse(json['sort_key'].toString())
          : null,
      createdAt: parseTime(json['created_at']?.toString()) ?? DateTime.now(),
      sentAt: parseTime(json['sent_at']?.toString()),
      deliveredAt: parseTime(json['delivered_at']?.toString()),
      seenAt: parseTime(json['seen_at']?.toString()),
      isDeleted:
          json['is_deleted'] == 1 ||
          json['is_deleted'] == true ||
          json['is_deleted']?.toString() == 'true',
      reactions: parsedReactions,
      senderName: json['sender_name']?.toString(),
      receiverId: json['receiver_id']?.toString(),
      receiverName: json['receiver_name']?.toString(),
      status: (json['status']?.toString().trim().isNotEmpty ?? false)
          ? json['status'].toString().trim()
          : 'sent',
      isPending: json['is_pending'] == true || json['status'] == 'sending',
      isFailed: json['is_failed'] == true || json['status'] == 'failed',
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return _fromMap(json, assumeUtcForNaiveTimes: true);
  }

  factory ChatMessage.optimistic({
    required String localId,
    required String threadId,
    required String senderId,
    required String senderRole,
    required String body,
    required String senderName,
  }) {
    final now = DateTime.now();
    return ChatMessage(
      id: localId,
      threadId: threadId,
      senderId: senderId,
      senderRole: senderRole,
      body: body,
      clientMessageId: localId,
      sortKey: now.microsecondsSinceEpoch,
      createdAt: now,
      sentAt: now,
      senderName: senderName,
      status: 'sending',
      isPending: true,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? threadId,
    String? senderId,
    String? senderRole,
    String? body,
    String? taskId,
    int? subtaskIndex,
    String? clientMessageId,
    int? sortKey,
    DateTime? createdAt,
    DateTime? sentAt,
    DateTime? deliveredAt,
    DateTime? seenAt,
    bool? isDeleted,
    List<ChatMessageReaction>? reactions,
    String? senderName,
    String? receiverId,
    String? receiverName,
    String? status,
    bool? isPending,
    bool? isFailed,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      body: body ?? this.body,
      taskId: taskId ?? this.taskId,
      subtaskIndex: subtaskIndex ?? this.subtaskIndex,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      sortKey: sortKey ?? this.sortKey,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      seenAt: seenAt ?? this.seenAt,
      isDeleted: isDeleted ?? this.isDeleted,
      reactions: reactions ?? this.reactions,
      senderName: senderName ?? this.senderName,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      status: status ?? this.status,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'thread_id': threadId,
      'sender_id': senderId,
      'sender_role': senderRole,
      'body': body,
      'task_id': taskId,
      'subtask_index': subtaskIndex,
      'client_message_id': clientMessageId,
      'sort_key': sortKey,
      'created_at': createdAt.toIso8601String(),
      'sent_at': sentAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'seen_at': seenAt?.toIso8601String(),
      'is_deleted': isDeleted,
      'reactions': reactions.map((item) => item.toJson()).toList(),
      'sender_name': senderName,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'status': status,
      'is_pending': isPending,
      'is_failed': isFailed,
    };
  }

  String toStorageJson() => jsonEncode(toJson());

  static ChatMessage fromStorageJson(String raw) {
    return _fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
      assumeUtcForNaiveTimes: false,
    );
  }

  String displaySenderName({required bool isMe}) {
    if (isMe) return 'You';
    final trimmed = senderName?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    return 'Unknown';
  }

  String displayReceiverName({required bool isMe, String? threadTitle}) {
    if (!isMe) return 'You';
    final trimmed = receiverName?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    final fallback = threadTitle?.trim() ?? '';
    if (fallback.isNotEmpty) return fallback;
    return 'User';
  }
}
