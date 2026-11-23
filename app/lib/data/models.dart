import 'database.dart';

class TxWithCategory {
  const TxWithCategory(this.tx, this.category);

  final Txn tx;
  final Category? category;

  String get categoryName => category?.name ?? 'Lainnya';
  String? get colorHex => category?.color;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.colorHex,
    required this.total,
  });

  final String categoryId;
  final String name;
  final String? colorHex;
  final int total;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.expense,
    required this.income,
    required this.prevExpense,
    required this.byCategory,
    required this.daily,
    required this.recent,
  });

  final DateTime month;
  final int expense;
  final int income;
  final int prevExpense;
  final List<CategoryTotal> byCategory;
  final List<int> daily;
  final List<TxWithCategory> recent;

  int get balance => income - expense;

  /// Perubahan pengeluaran dibanding bulan lalu; null bila bulan lalu kosong.
  double? get changePercent {
    if (prevExpense == 0) return null;
    return (expense - prevExpense) / prevExpense;
  }

  int get maxDaily => daily.fold(0, (a, b) => a > b ? a : b);
}

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spent,
  });

  final Budget budget;
  final Category? category;
  final int spent;

  String get name => category?.name ?? 'Lainnya';
  String? get colorHex => category?.color;
  double get ratio =>
      budget.limitAmount == 0 ? 0 : spent / budget.limitAmount;
  int get remaining => budget.limitAmount - spent;
  bool get isOver => spent > budget.limitAmount;
  bool get isNearLimit => !isOver && ratio >= 0.8;
}
