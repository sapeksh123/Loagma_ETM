import 'dart:convert';

/// A single subtask with status same as task (assigned, in_progress, completed, paused, need_help).
class SubtaskItem {
  final String text;
  final String status;

  SubtaskItem({required this.text, this.status = 'assigned'});

  factory SubtaskItem.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return SubtaskItem(
        text: json['text']?.toString() ?? '',
        status: _parseStatus(json['status']),
      );
    }
    if (json is String) {
      return SubtaskItem(text: json, status: 'assigned');
    }
    return SubtaskItem(text: json.toString(), status: 'assigned');
  }

  static String _parseStatus(dynamic s) {
    if (s == null) return 'assigned';
    final v = s.toString();
    const valid = ['assigned', 'in_progress', 'completed', 'paused', 'need_help'];
    if (valid.contains(v)) return v;
    return 'assigned';
  }

  Map<String, dynamic> toJson() => {'text': text, 'status': status};
}

class Task {
  final String id;
  final String title;
  final String? description;
  final List<String>? subtasks;
  final List<SubtaskItem>? subtaskItems;
  final String category;
  final String priority;
  final String status;
  final String? deadlineDate;
  final String? deadlineTime;
  final String createdBy;
  final String assignedTo;
  final String? creatorName;
  final String? assigneeName;
  final String? assigneeCode;
  final String createdAt;
  final String updatedAt;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.subtasks,
    this.subtaskItems,
    required this.category,
    required this.priority,
    required this.status,
    this.deadlineDate,
    this.deadlineTime,
    required this.createdBy,
    required this.assignedTo,
    this.creatorName,
    this.assigneeName,
    this.assigneeCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    List<SubtaskItem>? parseSubtaskItems(dynamic v) {
      if (v == null) return null;
      if (v is List && v.isNotEmpty) {
        return v.map((e) => SubtaskItem.fromJson(e)).toList();
      }
      if (v is String && v.startsWith('[')) {
        try {
          final list = jsonDecode(v) as List<dynamic>?;
          return list?.map((e) => SubtaskItem.fromJson(e)).toList();
        } catch (_) {}
      }
      return null;
    }

    final items = parseSubtaskItems(json['subtasks']);
    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      subtasks: items?.map((e) => e.text).toList(),
      subtaskItems: items,
      category: json['category'] ?? '',
      priority: json['priority'] ?? 'medium',
      status: json['status'] ?? 'assigned',
      deadlineDate: json['deadline_date'],
      deadlineTime: json['deadline_time'],
      createdBy: json['created_by'] ?? '',
      assignedTo: json['assigned_to'] ?? '',
      creatorName: json['creator_name'],
      assigneeName: json['assignee_name'],
      assigneeCode: json['assignee_code'],
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'subtasks': subtasks,
      'category': category,
      'priority': priority,
      'status': status,
      'deadline_date': deadlineDate,
      'deadline_time': deadlineTime,
      'created_by': createdBy,
      'assigned_to': assignedTo,
    };
  }

  /// Description only (no subtasks). For legacy tasks with combined text, strips the "Subtasks:..." part.
  String? get descriptionOnly {
    if (description == null || description!.isEmpty) return null;
    if (subtasks != null && subtasks!.isNotEmpty) return description;
    final d = description!;
    const marker = '\n\nSubtasks:\n';
    final i = d.indexOf(marker);
    if (i >= 0) return d.substring(0, i).trim();
    return d;
  }

  /// Subtasks list (text only). From subtaskItems or legacy description.
  List<String> get subtasksOnly {
    if (subtaskItems != null && subtaskItems!.isNotEmpty) {
      return subtaskItems!.map((e) => e.text).toList();
    }
    if (subtasks != null && subtasks!.isNotEmpty) return subtasks!;
    if (description == null || description!.isEmpty) return [];
    const marker = '\n\nSubtasks:\n';
    final i = description!.indexOf(marker);
    if (i < 0) return [];
    final block = description!.substring(i + marker.length).trim();
    return block
        .split('\n')
        .map((s) => s.startsWith('• ') ? s.substring(2).trim() : s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Subtask items with status (for edit and display with colors).
  List<SubtaskItem> get subtasksWithStatus {
    if (subtaskItems != null && subtaskItems!.isNotEmpty) return subtaskItems!;
    return subtasksOnly.map((t) => SubtaskItem(text: t, status: 'assigned')).toList();
  }
}
