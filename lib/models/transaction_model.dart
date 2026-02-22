import 'package:isar/isar.dart';

part 'transaction_model.g.dart';

@collection
class Transaction {
  Transaction();

  Id id = Isar.autoIncrement;

  late double amount;

  String? merchant;

  late DateTime date;

  String? category;

  String? originalSmsBody;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'merchant': merchant,
      'date': date.toIso8601String(),
      'category': category,
      'originalSmsBody': originalSmsBody,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final t = Transaction();
    t.id = json['id'] as int? ?? Isar.autoIncrement;
    t.amount = (json['amount'] as num).toDouble();
    t.merchant = json['merchant'] as String?;
    t.date = DateTime.parse(json['date'] as String);
    t.category = json['category'] as String?;
    t.originalSmsBody = json['originalSmsBody'] as String?;
    return t;
  }

  @override
  String toString() {
    return 'Transaction(id: $id, amount: $amount, merchant: $merchant, date: $date, category: $category)';
  }
}
