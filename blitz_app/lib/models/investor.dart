import 'package:uuid/uuid.dart';

class Investor {
  final String id;
  final String name;
  final String firm;
  final String stage; // prospect, contacted, meeting, termsheet, closed, passed
  final double amount;
  final String notes;
  final DateTime? lastContact;
  final DateTime? nextFollowup;
  final DateTime createdAt;

  Investor({
    String? id,
    required this.name,
    this.firm = '',
    this.stage = 'prospect',
    this.amount = 0,
    this.notes = '',
    this.lastContact,
    this.nextFollowup,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'firm': firm,
    'stage': stage,
    'amount': amount,
    'notes': notes,
    'last_contact': lastContact?.toIso8601String(),
    'next_followup': nextFollowup?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory Investor.fromMap(Map<String, dynamic> map) => Investor(
    id: map['id'] as String,
    name: map['name'] as String,
    firm: map['firm'] as String? ?? '',
    stage: map['stage'] as String? ?? 'prospect',
    amount: (map['amount'] as num?)?.toDouble() ?? 0,
    notes: map['notes'] as String? ?? '',
    lastContact: map['last_contact'] != null ? DateTime.tryParse(map['last_contact'] as String) : null,
    nextFollowup: map['next_followup'] != null ? DateTime.tryParse(map['next_followup'] as String) : null,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  String get stageEmoji {
    switch (stage) {
      case 'prospect': return '🎯';
      case 'contacted': return '📧';
      case 'meeting': return '🤝';
      case 'termsheet': return '📄';
      case 'closed': return '✅';
      case 'passed': return '❌';
      default: return '⚪';
    }
  }
}
