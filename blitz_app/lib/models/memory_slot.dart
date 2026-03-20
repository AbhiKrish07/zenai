class MemorySlot {
  final String id;
  final String key;
  final String value;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;

  MemorySlot({
    required this.id,
    required this.key,
    required this.value,
    this.category = 'general',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'key': key,
    'value': value,
    'category': category,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory MemorySlot.fromMap(Map<String, dynamic> map) => MemorySlot(
    id: map['id'] as String,
    key: map['key'] as String,
    value: map['value'] as String,
    category: map['category'] as String? ?? 'general',
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );
}
