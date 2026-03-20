import 'package:uuid/uuid.dart';

class Expense {
  final String id;
  final double amount;
  final String category;
  final String description;
  final DateTime date;
  final bool recurring;
  final DateTime createdAt;

  Expense({
    String? id,
    required this.amount,
    required this.category,
    this.description = '',
    DateTime? date,
    this.recurring = false,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'amount': amount,
    'category': category,
    'description': description,
    'date': date.toIso8601String(),
    'recurring': recurring ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
    id: map['id'] as String,
    amount: (map['amount'] as num).toDouble(),
    category: map['category'] as String,
    description: map['description'] as String? ?? '',
    date: DateTime.parse(map['date'] as String),
    recurring: map['recurring'] == 1,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  String get categoryEmoji {
    switch (category.toLowerCase()) {
      case 'food': return '🍕';
      case 'transport': return '🚗';
      case 'shopping': return '🛍️';
      case 'entertainment': return '🎮';
      case 'bills': return '💡';
      case 'health': return '🏥';
      case 'education': return '📚';
      case 'startup': return '🚀';
      case 'savings': return '💰';
      default: return '💳';
    }
  }
}
