import 'package:uuid/uuid.dart';

class MoodEntry {
  final String id;
  final int moodScore;     // 1-10
  final int energyLevel;   // 1-10
  final String notes;
  final String tags;        // comma-separated
  final DateTime date;
  final DateTime createdAt;

  MoodEntry({
    String? id,
    required this.moodScore,
    required this.energyLevel,
    this.notes = '',
    this.tags = '',
    DateTime? date,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'mood_score': moodScore,
    'energy_level': energyLevel,
    'notes': notes,
    'tags': tags,
    'date': date.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory MoodEntry.fromMap(Map<String, dynamic> map) => MoodEntry(
    id: map['id'] as String,
    moodScore: map['mood_score'] as int,
    energyLevel: map['energy_level'] as int,
    notes: map['notes'] as String? ?? '',
    tags: map['tags'] as String? ?? '',
    date: DateTime.parse(map['date'] as String),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  String get moodEmoji {
    if (moodScore >= 9) return '🌟';
    if (moodScore >= 7) return '😊';
    if (moodScore >= 5) return '😐';
    if (moodScore >= 3) return '😔';
    return '😢';
  }

  String get energyEmoji {
    if (energyLevel >= 8) return '⚡';
    if (energyLevel >= 6) return '🔋';
    if (energyLevel >= 4) return '🔌';
    return '😴';
  }
}
