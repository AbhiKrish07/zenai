import 'package:uuid/uuid.dart';

class Task {
  final String id;
  final String title;
  final String description;
  final String priority;
  final DateTime? dueDate;
  final bool completed;
  final DateTime? completedAt;
  final String? recurring;
  final String energyLevel;
  final double aiScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  Task({
    String? id,
    required this.title,
    this.description = '',
    this.priority = 'medium',
    this.dueDate,
    this.completed = false,
    this.completedAt,
    this.recurring,
    this.energyLevel = 'any',
    this.aiScore = 0.5,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'priority': priority,
    'due_date': dueDate?.toIso8601String(),
    'completed': completed ? 1 : 0,
    'completed_at': completedAt?.toIso8601String(),
    'recurring': recurring,
    'energy_level': energyLevel,
    'ai_score': aiScore,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Task.fromMap(Map<String, dynamic> map) => Task(
    id: map['id']?.toString() ?? const Uuid().v4(),
    title: map['title']?.toString() ?? 'Untitled Task',
    description: map['description']?.toString() ?? '',
    priority: map['priority']?.toString() ?? 'medium',
    dueDate: map['due_date'] != null ? DateTime.tryParse(map['due_date'].toString()) : null,
    completed: map['completed'] == 1 || map['completed'] == true,
    completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'].toString()) : null,
    recurring: map['recurring']?.toString(),
    energyLevel: map['energy_level']?.toString() ?? 'any',
    aiScore: (map['ai_score'] as num?)?.toDouble() ?? 0.5,
    createdAt: map['created_at'] != null ? (DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()) : DateTime.now(),
    updatedAt: map['updated_at'] != null ? (DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()) : DateTime.now(),
  );

  Task copyWith({
    String? title,
    String? description,
    String? priority,
    DateTime? dueDate,
    bool? completed,
    DateTime? completedAt,
    String? recurring,
    String? energyLevel,
    double? aiScore,
  }) => Task(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    dueDate: dueDate ?? this.dueDate,
    completed: completed ?? this.completed,
    completedAt: completedAt ?? this.completedAt,
    recurring: recurring ?? this.recurring,
    energyLevel: energyLevel ?? this.energyLevel,
    aiScore: aiScore ?? this.aiScore,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}
