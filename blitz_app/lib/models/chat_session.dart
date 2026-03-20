class ChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final String? folderId;
  final bool isArchived;
  final bool isDeleted;

  ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.folderId,
    this.isArchived = false,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'updated_at': updatedAt.toIso8601String(),
        'folder_id': folderId,
        'is_archived': isArchived ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory ChatSession.fromMap(Map<String, dynamic> map) => ChatSession(
        id: map['id'] as String,
        title: map['title'] as String,
        updatedAt: DateTime.parse(map['updated_at'] as String),
        folderId: map['folder_id'] as String?,
        isArchived: (map['is_archived'] as int? ?? 0) == 1,
        isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      );

  ChatSession copyWith({String? title, String? folderId, bool? isArchived, bool? isDeleted}) => ChatSession(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt,
    folderId: folderId ?? this.folderId,
    isArchived: isArchived ?? this.isArchived,
    isDeleted: isDeleted ?? this.isDeleted,
  );
}
