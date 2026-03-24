import 'dart:convert';

class DailyStatusEntry {
  final String date; // 'YYYY-MM-DD'
  final String status; // assigned/in_progress/...
  final String? note;

  DailyStatusEntry({
    required this.date,
    required this.status,
    this.note,
  });

  factory DailyStatusEntry.fromJson(Map<String, dynamic> json) {
    return DailyStatusEntry(
      date: json['date']?.toString() ?? '',
      status: json['status']?.toString() ?? 'assigned',
      note: json['note']?.toString(),
    );
  }
}

/// A single subtask with status and optional need_help_note when status is need_help.
class SubtaskItem {
  final String text;
  final String status;
  final String? needHelpNote;

  SubtaskItem({required this.text, this.status = 'assigned', this.needHelpNote});

  factory SubtaskItem.fromJson(dynamic json) {
    if (json is Map) {
      final text = json['text']?.toString() ?? '';
      final status = _parseStatus(json['status']);
      final needHelpNote = _parseOptionalString(json['need_help_note']);
      return SubtaskItem(text: text, status: status, needHelpNote: needHelpNote);
    }
    if (json is String) {
      return SubtaskItem(text: json, status: 'assigned');
    }
    return SubtaskItem(text: json.toString(), status: 'assigned');
  }

  static String _parseStatus(dynamic s) {
    if (s == null) return 'assigned';
    final v = s.toString();
    const valid = ['assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore'];
    if (valid.contains(v)) return v;
    return 'assigned';
  }

  static String? _parseOptionalString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'text': text, 'status': status};
    if (needHelpNote != null && needHelpNote!.isNotEmpty) {
      m['need_help_note'] = needHelpNote;
    }
    return m;
  }
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
  final String? creatorRole;
  final String? assigneeName;
  final String? assigneeCode;
  final String? needHelpNote;
  final String? hiddenAt;
  final String createdAt;
  final String updatedAt;
  final List<DailyStatusEntry>? taskHistory;
  final Map<int, List<DailyStatusEntry>>? subtaskHistory;

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
    this.creatorRole,
    this.assigneeName,
    this.assigneeCode,
    this.needHelpNote,
    this.hiddenAt,
    required this.createdAt,
    required this.updatedAt,
    this.taskHistory,
    this.subtaskHistory,
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

    List<DailyStatusEntry>? parseTaskHistory(dynamic v) {
      if (v is List) {
        return v
            .whereType<Map>()
            .map((e) => DailyStatusEntry.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList();
      }
      return null;
    }

    Map<int, List<DailyStatusEntry>>? parseSubtaskHistory(dynamic v) {
      // Backend currently sends subtask_history as a JSON array of arrays,
      // where the outer index is the subtask index. Older versions might send
      // it as an object/map keyed by subtask index. Support both shapes.
      if (v is List) {
        final map = <int, List<DailyStatusEntry>>{};
        for (var i = 0; i < v.length; i++) {
          final value = v[i];
          if (value is List) {
            map[i] = value
                .whereType<Map>()
                .map(
                  (e) => DailyStatusEntry.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList();
          }
        }
        return map;
      }

      if (v is Map) {
        final map = <int, List<DailyStatusEntry>>{};
        v.forEach((key, value) {
          final idx = int.tryParse(key.toString());
          if (idx == null) return;
          if (value is List) {
            map[idx] = value
                .whereType<Map>()
                .map(
                  (e) => DailyStatusEntry.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList();
          }
        });
        return map;
      }

      return null;
    }

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
      creatorRole: json['creator_role']?.toString(),
      assigneeName: json['assignee_name'],
      assigneeCode: json['assignee_code'],
      needHelpNote: json['need_help_note'],
      hiddenAt: json['hidden_at']?.toString(),
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
      taskHistory: parseTaskHistory(json['task_history']),
      subtaskHistory: parseSubtaskHistory(json['subtask_history']),
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

  bool get isAssignedToSelf => createdBy.isNotEmpty && createdBy == assignedTo;

  String get normalizedCreatorRole {
    final role = (creatorRole ?? '').trim().toLowerCase();
    if (role == 'admin' || role == 'subadmin' || role == 'techincharge' || role == 'employee') {
      return role;
    }
    return '';
  }

  String assignmentByLabel({bool includeEmployeeNameForSelf = false}) {
    if (isAssignedToSelf) {
      if (includeEmployeeNameForSelf && assigneeName != null && assigneeName!.trim().isNotEmpty) {
        return 'Assigned to Self (${assigneeName!.trim()})';
      }
      return 'Assigned to Self';
    }

    switch (normalizedCreatorRole) {
      case 'admin':
        return 'Assigned by Admin';
      case 'subadmin':
        return 'Assigned by Sub-Admin';
      case 'techincharge':
        return 'Assigned by Tech Incharge';
      case 'employee':
        return 'Assigned by Employee';
      default:
        if (creatorName != null && creatorName!.trim().isNotEmpty) {
          return 'Assigned by ${creatorName!.trim()}';
        }
        return 'Assigned by Manager';
    }
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
