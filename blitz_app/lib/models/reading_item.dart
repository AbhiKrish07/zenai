import 'package:uuid/uuid.dart';

class ReadingItem {
  final String id;
  final String title;
  final String url;
  final String itemType; // article, book, paper, video
  final String status;   // queued, in_progress, completed, archived
  final String notes;
  final String summary;
  final String author;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReadingItem({
    String? id,
    required this.title,
    this.url = '',
    this.itemType = 'article',
    this.status = 'queued',
    this.notes = '',
    this.summary = '',
    this.author = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'url': url,
    'item_type': itemType,
    'status': status,
    'notes': notes,
    'summary': summary,
    'author': author,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ReadingItem.fromMap(Map<String, dynamic> map) => ReadingItem(
    id: map['id'] as String,
    title: map['title'] as String,
    url: map['url'] as String? ?? '',
    itemType: map['item_type'] as String? ?? 'article',
    status: map['status'] as String? ?? 'queued',
    notes: map['notes'] as String? ?? '',
    summary: map['summary'] as String? ?? '',
    author: map['author'] as String? ?? '',
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );

  String get typeEmoji {
    switch (itemType) {
      case 'book': return '📖';
      case 'paper': return '📄';
      case 'video': return '🎥';
      default: return '📰';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'queued': return 'Queued';
      case 'in_progress': return 'Reading';
      case 'completed': return 'Done';
      case 'archived': return 'Archived';
      default: return status;
    }
  }
}
