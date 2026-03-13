class ChatMessage {
  final String id;
  final String threadId;
  final String senderId;
  final String senderRole;
  final String body;
  final String? taskId;
  final int? subtaskIndex;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    this.taskId,
    this.subtaskIndex,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
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
    );
  }
}

