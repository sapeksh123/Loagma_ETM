class NotificationModel {
  final String id;
  final String employeeId;
  final String taskId;
  final int? subtaskIndex;
  final String? chatThreadId;
  final String? chatMessageId;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  static DateTime _parseApiTime(dynamic raw) {
    final source = raw?.toString().trim() ?? '';
    if (source.isEmpty) return DateTime.now();

    final parsed = DateTime.tryParse(source);
    if (parsed == null) return DateTime.now();

    // Backend often returns naive UTC timestamps (without Z/offset).
    final hasExplicitTimezone = RegExp(r'(Z|[+\-]\d{2}:?\d{2})$', caseSensitive: false)
        .hasMatch(source);
    if (!hasExplicitTimezone && !parsed.isUtc) {
      return DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      ).toLocal();
    }

    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  NotificationModel({
    required this.id,
    required this.employeeId,
    required this.taskId,
    this.subtaskIndex,
    this.chatThreadId,
    this.chatMessageId,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      employeeId: json['employee_id']?.toString() ?? '',
      taskId: json['task_id']?.toString() ?? '',
      subtaskIndex: json['subtask_index'] != null
          ? int.tryParse(json['subtask_index'].toString())
          : null,
      chatThreadId: json['chat_thread_id']?.toString(),
      chatMessageId: json['chat_message_id']?.toString(),
      type: json['type']?.toString() ?? 'reminder',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isRead: json['is_read'] == 1 ||
          json['is_read'] == true ||
          json['is_read']?.toString() == 'true',
      createdAt: _parseApiTime(json['created_at']),
    );
  }
}

