class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final String? metadata;
  final String? sessionId;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.metadata,
    this.sessionId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
    'session_id': sessionId,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as String,
    role: map['role'] as String,
    content: map['content'] as String,
    timestamp: DateTime.parse(map['timestamp'] as String),
    metadata: map['metadata'] as String?,
    sessionId: map['session_id'] as String?,
  );

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}
