import 'package:uuid/uuid.dart';

class Assignment {
  final String id;
  final String title;
  final String course;
  final DateTime dueDate;
  final double? grade;
  final double maxGrade;
  final double weight;
  final String status;
  final String notes;
  final DateTime createdAt;

  Assignment({
    String? id,
    required this.title,
    required this.course,
    required this.dueDate,
    this.grade,
    this.maxGrade = 100,
    this.weight = 1.0,
    this.status = 'pending',
    this.notes = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'course': course,
    'due_date': dueDate.toIso8601String(),
    'grade': grade,
    'max_grade': maxGrade,
    'weight': weight,
    'status': status,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };

  factory Assignment.fromMap(Map<String, dynamic> map) => Assignment(
    id: map['id'] as String,
    title: map['title'] as String,
    course: map['course'] as String,
    dueDate: DateTime.parse(map['due_date'] as String),
    grade: (map['grade'] as num?)?.toDouble(),
    maxGrade: (map['max_grade'] as num?)?.toDouble() ?? 100,
    weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
    status: map['status'] as String? ?? 'pending',
    notes: map['notes'] as String? ?? '',
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  double get percentage => grade != null ? (grade! / maxGrade * 100) : 0;
  bool get isOverdue => status == 'pending' && dueDate.isBefore(DateTime.now());
  Duration get timeUntilDue => dueDate.difference(DateTime.now());
}
