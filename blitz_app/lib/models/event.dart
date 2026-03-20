import 'package:uuid/uuid.dart';

class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String eventType;
  final String location;
  final String? briefing;
  final bool synced;
  final String? deviceEventId;
  final DateTime createdAt;

  CalendarEvent({
    String? id,
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
    this.eventType = 'general',
    this.location = '',
    this.briefing,
    this.synced = false,
    this.deviceEventId,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'event_type': eventType,
    'location': location,
    'briefing': briefing,
    'synced': synced ? 1 : 0,
    'device_event_id': deviceEventId,
    'created_at': createdAt.toIso8601String(),
  };

  factory CalendarEvent.fromMap(Map<String, dynamic> map) => CalendarEvent(
    id: map['id'] as String,
    title: map['title'] as String,
    description: map['description'] as String? ?? '',
    startTime: DateTime.parse(map['start_time'] as String),
    endTime: DateTime.parse(map['end_time'] as String),
    eventType: map['event_type'] as String? ?? 'general',
    location: map['location'] as String? ?? '',
    briefing: map['briefing'] as String?,
    synced: map['synced'] == 1,
    deviceEventId: map['device_event_id'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
