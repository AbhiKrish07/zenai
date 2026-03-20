import 'package:uuid/uuid.dart';

class StartupMetrics {
  final String id;
  final double mrr;
  final double burnRate;
  final double runwayMonths;
  final int totalUsers;
  final DateTime date;
  final String notes;

  StartupMetrics({
    String? id,
    this.mrr = 0,
    this.burnRate = 0,
    this.runwayMonths = 0,
    this.totalUsers = 0,
    DateTime? date,
    this.notes = '',
  })  : id = id ?? const Uuid().v4(),
        date = date ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'mrr': mrr,
    'burn_rate': burnRate,
    'runway_months': runwayMonths,
    'total_users': totalUsers,
    'date': date.toIso8601String(),
    'notes': notes,
  };

  factory StartupMetrics.fromMap(Map<String, dynamic> map) => StartupMetrics(
    id: map['id'] as String,
    mrr: (map['mrr'] as num?)?.toDouble() ?? 0,
    burnRate: (map['burn_rate'] as num?)?.toDouble() ?? 0,
    runwayMonths: (map['runway_months'] as num?)?.toDouble() ?? 0,
    totalUsers: map['total_users'] as int? ?? 0,
    date: DateTime.parse(map['date'] as String),
    notes: map['notes'] as String? ?? '',
  );

  double get monthlyProfit => mrr - burnRate;
  bool get isProfitable => mrr >= burnRate;
}
