import 'package:uuid/uuid.dart';

class StudySession {
  final String id;
  final String subject;
  final int durationMinutes;
  final String sessionType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String notes;

  StudySession({
    String? id,
    required this.subject,
    required this.durationMinutes,
    this.sessionType = 'pomodoro',
    DateTime? startedAt,
    this.endedAt,
    this.notes = '',
  })  : id = id ?? const Uuid().v4(),
        startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'subject': subject,
    'duration_minutes': durationMinutes,
    'session_type': sessionType,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'notes': notes,
  };

  factory StudySession.fromMap(Map<String, dynamic> map) => StudySession(
    id: map['id'] as String,
    subject: map['subject'] as String,
    durationMinutes: map['duration_minutes'] as int,
    sessionType: map['session_type'] as String? ?? 'pomodoro',
    startedAt: DateTime.parse(map['started_at'] as String),
    endedAt: map['ended_at'] != null ? DateTime.tryParse(map['ended_at'] as String) : null,
    notes: map['notes'] as String? ?? '',
  );
}
