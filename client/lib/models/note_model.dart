class Note {
  final String id;
  final String userId;
  final String folderName;
  final String title;
  final String content;
  final String? createdAt;
  final String? updatedAt;

  Note({
    required this.id,
    required this.userId,
    required this.folderName,
    required this.title,
    required this.content,
    this.createdAt,
    this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      folderName: json['folder_name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'folder_name': folderName,
      'title': title,
      'content': content,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  Note copyWith({
    String? id,
    String? userId,
    String? folderName,
    String? title,
    String? content,
    String? createdAt,
    String? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      folderName: folderName ?? this.folderName,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
