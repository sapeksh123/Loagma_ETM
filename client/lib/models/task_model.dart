class Task {
  final String id;
  final String title;
  final String? description;
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
    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
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
      'category': category,
      'priority': priority,
      'status': status,
      'deadline_date': deadlineDate,
      'deadline_time': deadlineTime,
      'created_by': createdBy,
      'assigned_to': assignedTo,
    };
  }
}
