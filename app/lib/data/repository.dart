import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/format.dart';
import '../core/stream_utils.dart';
import 'database.dart';
import 'models.dart';

class ExpenseRepository {
  ExpenseRepository(this.db);

  final AppDatabase db;
  static const _uuid = Uuid();

  String userId = AppConfig.localUserId;

  void setUserId(String id) => userId = id;

  // -------------------------------------------------------------------------
  // Baca
  // -------------------------------------------------------------------------

  Stream<List<Category>> watchCategories({
    String? type,
    bool includeArchived = false,
  }) {
    final query = db.select(db.categories)..where((c) => c.deletedAt.isNull());
    if (!includeArchived) query.where((c) => c.archivedAt.isNull());
    if (type != null) query.where((c) => c.type.equals(type));
    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch();
  }

  Future<List<Category>> categories({String? type}) {
    final query = db.select(db.categories)
      ..where((c) => c.deletedAt.isNull() & c.archivedAt.isNull());
    if (type != null) query.where((c) => c.type.equals(type));
    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.get();
  }

  Future<Category?> categoryById(String id) =>
      (db.select(db.categories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Stream<MonthSummary> watchMonth(DateTime month) =>
      _monthQuery(month).watch().map((rows) => _summarize(month, rows));

  Future<MonthSummary> summaryFor(DateTime month) async =>
      _summarize(month, await _monthQuery(month).get());

  JoinedSelectStatement _monthQuery(DateTime month) {
    final start = month.prevMonth.monthStart;
    final end = _endOfDay(month.monthEnd);
    return db.select(db.transactions).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
    ])
      ..where(db.transactions.deletedAt.isNull() &
          db.transactions.occurredOn.isBetweenValues(start, end))
      ..orderBy([
        OrderingTerm.desc(db.transactions.occurredOn),
        OrderingTerm.desc(db.transactions.createdAt),
      ]);
  }

  MonthSummary _summarize(DateTime month, List<TypedResult> rows) {
    var expense = 0;
    var income = 0;
    var prevExpense = 0;
    final perCategory = <String, CategoryTotal>{};
    final daily = List<int>.filled(month.monthEnd.day, 0);
    final recent = <TxWithCategory>[];

    for (final row in rows) {
      final tx = row.readTable(db.transactions);
      final category = row.readTableOrNull(db.categories);
      if (tx.occurredOn.sameMonth(month)) {
        if (tx.type == 'expense') {
          expense += tx.amount;
          daily[tx.occurredOn.day - 1] += tx.amount;
          final current = perCategory[tx.categoryId];
          perCategory[tx.categoryId] = CategoryTotal(
            categoryId: tx.categoryId,
            name: category?.name ?? 'Lainnya',
            colorHex: category?.color,
            total: (current?.total ?? 0) + tx.amount,
          );
        } else {
          income += tx.amount;
        }
        if (recent.length < 5) recent.add(TxWithCategory(tx, category));
      } else if (tx.occurredOn.sameMonth(month.prevMonth) &&
          tx.type == 'expense') {
        prevExpense += tx.amount;
      }
    }

    final byCategory = perCategory.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return MonthSummary(
      month: month,
      expense: expense,
      income: income,
      prevExpense: prevExpense,
      byCategory: byCategory,
      daily: daily,
      recent: recent,
    );
  }

  Stream<List<TxWithCategory>> watchTransactions({
    DateTime? from,
    DateTime? to,
    String? type,
    String? categoryName,
    String search = '',
  }) {
    final query = db.select(db.transactions).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
    ])
      ..where(db.transactions.deletedAt.isNull());

    if (from != null) {
      query.where(db.transactions.occurredOn.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where(
        db.transactions.occurredOn.isSmallerOrEqualValue(_endOfDay(to)),
      );
    }
    if (type != null) query.where(db.transactions.type.equals(type));
    if (categoryName != null) {
      // Filter per nama: chip "Lainnya" mewakili kategori pengeluaran dan pemasukan.
      query.where(db.categories.name.equals(categoryName));
    }
    if (search.trim().isNotEmpty) {
      query.where(db.transactions.note.like('%${search.trim()}%'));
    }
    query.orderBy([
      OrderingTerm.desc(db.transactions.occurredOn),
      OrderingTerm.desc(db.transactions.createdAt),
    ]);

    return query.watch().map(
          (rows) => rows
              .map((row) => TxWithCategory(
                    row.readTable(db.transactions),
                    row.readTableOrNull(db.categories),
                  ))
              .toList(),
        );
  }

  Future<List<TxWithCategory>> transactionsBetween(
    DateTime from,
    DateTime to,
  ) async {
    final query = db.select(db.transactions).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
    ])
      ..where(db.transactions.deletedAt.isNull() &
          db.transactions.occurredOn.isBetweenValues(
            from.dateOnly,
            _endOfDay(to),
          ))
      ..orderBy([OrderingTerm.asc(db.transactions.occurredOn)]);

    final rows = await query.get();
    return rows
        .map((row) => TxWithCategory(
              row.readTable(db.transactions),
              row.readTableOrNull(db.categories),
            ))
        .toList();
  }

  Stream<List<BudgetProgress>> watchBudgets(DateTime month) {
    final query = db.select(db.budgets).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.budgets.categoryId),
      ),
    ])
      ..where(db.budgets.month.equals(month.monthStart));

    final budgets = query.watch().map(
          (rows) => rows
              .map((row) => (
                    row.readTable(db.budgets),
                    row.readTableOrNull(db.categories),
                  ))
              .toList(),
        );

    return combine2(budgets, _watchSpentByCategory(month), (rows, spent) {
      final list = rows
          .map((row) => BudgetProgress(
                budget: row.$1,
                category: row.$2,
                spent: spent[row.$1.categoryId] ?? 0,
              ))
          .toList()
        ..sort((a, b) => b.ratio.compareTo(a.ratio));
      return list;
    });
  }

  Stream<Map<String, int>> _watchSpentByCategory(DateTime month) {
    final query = db.select(db.transactions)
      ..where((t) =>
          t.deletedAt.isNull() &
          t.type.equals('expense') &
          t.occurredOn.isBetweenValues(
            month.monthStart,
            _endOfDay(month.monthEnd),
          ));
    return query.watch().map((rows) {
      final map = <String, int>{};
      for (final row in rows) {
        map[row.categoryId] = (map[row.categoryId] ?? 0) + row.amount;
      }
      return map;
    });
  }

  // -------------------------------------------------------------------------
  // Tulis transaksi
  // -------------------------------------------------------------------------

  Future<String> addTransaction({
    required String type,
    required int amount,
    required String categoryId,
    required DateTime occurredOn,
    String? note,
    String source = 'app',
    Uint8List? receipt,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await db.transaction(() async {
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              userId: Value(userId),
              type: type,
              amount: amount,
              categoryId: categoryId,
              note: Value(note),
              occurredOn: occurredOn.dateOnly,
              source: Value(source),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (receipt != null) {
        await db.into(db.receipts).insert(
              ReceiptsCompanion.insert(
                transactionId: id,
                bytes: receipt,
                updatedAt: now,
              ),
            );
      }
    });
    return id;
  }

  Future<void> updateTransaction({
    required String id,
    required String type,
    required int amount,
    required String categoryId,
    required DateTime occurredOn,
    String? note,
    Uint8List? receipt,
    bool removeReceipt = false,
  }) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          type: Value(type),
          amount: Value(amount),
          categoryId: Value(categoryId),
          note: Value(note),
          occurredOn: Value(occurredOn.dateOnly),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      if (receipt != null) {
        await db.into(db.receipts).insertOnConflictUpdate(
              ReceiptsCompanion.insert(
                transactionId: id,
                bytes: receipt,
                updatedAt: now,
              ),
            );
      } else if (removeReceipt) {
        await (db.delete(db.receipts)
              ..where((r) => r.transactionId.equals(id)))
            .go();
      }
    });
  }

  Future<void> deleteTransaction(String id) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        synced: const Value(false),
      ),
    );
  }

  Future<Txn?> transactionById(String id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<Uint8List?> receiptBytes(String transactionId) async {
    final row = await (db.select(db.receipts)
          ..where((r) => r.transactionId.equals(transactionId)))
        .getSingleOrNull();
    return row?.bytes;
  }

  // -------------------------------------------------------------------------
  // Kategori
  // -------------------------------------------------------------------------

  Future<String> addCategory({
    required String name,
    required String type,
    String? color,
    String? icon,
  }) async {
    final id = _uuid.v4();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            userId: Value(userId),
            name: name.trim(),
            type: type,
            color: Value(color),
            icon: Value(icon),
            updatedAt: DateTime.now(),
          ),
        );
    return id;
  }

  Future<void> renameCategory(String id, String name) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
        synced: const Value(false),
      ),
    );
  }

  Future<void> archiveCategory(String id, {bool archived = true}) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        archivedAt: Value(archived ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
        synced: const Value(false),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Anggaran
  // -------------------------------------------------------------------------

  Future<void> setBudget({
    required String categoryId,
    required DateTime month,
    required int limitAmount,
  }) async {
    final existing = await (db.select(db.budgets)
          ..where((b) =>
              b.categoryId.equals(categoryId) &
              b.month.equals(month.monthStart)))
        .getSingleOrNull();
    final now = DateTime.now();
    if (existing != null) {
      await (db.update(db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(
        BudgetsCompanion(
          limitAmount: Value(limitAmount),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
    } else {
      await db.into(db.budgets).insert(
            BudgetsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(userId),
              categoryId: categoryId,
              month: month.monthStart,
              limitAmount: limitAmount,
              updatedAt: now,
            ),
          );
    }
  }

  Future<void> deleteBudget(String id) =>
      (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();

  Future<void> copyBudgets(DateTime from, DateTime to) async {
    final source = await (db.select(db.budgets)
          ..where((b) => b.month.equals(from.monthStart)))
        .get();
    final existing = await (db.select(db.budgets)
          ..where((b) => b.month.equals(to.monthStart)))
        .get();
    final taken = existing.map((b) => b.categoryId).toSet();
    for (final budget in source) {
      if (taken.contains(budget.categoryId)) continue;
      await db.into(db.budgets).insert(
            BudgetsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(userId),
              categoryId: budget.categoryId,
              month: to.monthStart,
              limitAmount: budget.limitAmount,
              updatedAt: DateTime.now(),
            ),
          );
    }
  }

  /// Peringatan 80%/100% sekali per ambang per bulan.
  Future<String?> checkBudgetAlert({
    required String categoryId,
    required DateTime month,
  }) async {
    final budget = await (db.select(db.budgets)
          ..where((b) =>
              b.categoryId.equals(categoryId) &
              b.month.equals(month.monthStart)))
        .getSingleOrNull();
    if (budget == null) return null;

    final row = await (db.selectOnly(db.transactions)
          ..addColumns([db.transactions.amount.sum()])
          ..where(db.transactions.deletedAt.isNull() &
              db.transactions.type.equals('expense') &
              db.transactions.categoryId.equals(categoryId) &
              db.transactions.occurredOn.isBetweenValues(
                month.monthStart,
                _endOfDay(month.monthEnd),
              )))
        .getSingle();
    final spent = row.read(db.transactions.amount.sum()) ?? 0;

    final ratio = spent / budget.limitAmount;
    final threshold = ratio >= 1 ? 100 : (ratio >= 0.8 ? 80 : 0);
    if (threshold == 0) return null;

    final key = 'alert_${budget.id}_${fileStamp(month)}';
    final last = int.tryParse(await getSetting(key) ?? '') ?? 0;
    if (threshold <= last) return null;
    await setSetting(key, '$threshold');

    final category = await categoryById(categoryId);
    final name = category?.name ?? 'Kategori';
    return threshold == 100
        ? 'Anggaran $name sudah lewat ${rupiah(spent - budget.limitAmount)}.'
        : 'Anggaran $name terpakai ${(ratio * 100).round()}%. '
            'Sisa ${rupiah(budget.limitAmount - spent)}.';
  }

  // -------------------------------------------------------------------------
  // Pengaturan & data awal
  // -------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final row = await (db.select(db.settings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(
            Setting(key: key, value: value),
          );

  Future<void> seedDefaultsIfNeeded() async {
    final existing = await db.select(db.categories).get();
    if (existing.isNotEmpty) return;

    const defaults = <(String, String, String, String)>[
      ('Makan', 'expense', '#1F6F5C', 'restaurant'),
      ('Transport', 'expense', '#3B6FD4', 'directions_bus'),
      ('Belanja', 'expense', '#B7791F', 'shopping_bag'),
      ('Tagihan', 'expense', '#8B5CF6', 'receipt_long'),
      ('Kesehatan', 'expense', '#0E7490', 'health_and_safety'),
      ('Hiburan', 'expense', '#BE185D', 'movie'),
      ('Lainnya', 'expense', '#9AA3AF', 'more_horiz'),
      ('Gaji', 'income', '#1F6F5C', 'payments'),
      ('Lainnya', 'income', '#9AA3AF', 'more_horiz'),
    ];

    final now = DateTime.now();
    for (final item in defaults) {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: _uuid.v4(),
              userId: Value(userId),
              name: item.$1,
              type: item.$2,
              color: Value(item.$3),
              icon: Value(item.$4),
              updatedAt: now,
              isDefault: const Value(true),
            ),
          );
    }
  }

  /// Data contoh untuk mencoba tampilan tanpa mengisi manual.
  Future<void> seedDemoData() async {
    final cats = await categories();
    if (cats.isEmpty) return;
    final expense = cats.where((c) => c.type == 'expense').toList();
    final income = cats.where((c) => c.type == 'income').toList();
    final random = Random(7);
    final now = DateTime.now();

    for (var monthOffset = 1; monthOffset >= 0; monthOffset--) {
      final month = DateTime(now.year, now.month - monthOffset);
      final days = month.monthEnd.day;
      final count = monthOffset == 0 ? 18 : 24;
      for (var i = 0; i < count; i++) {
        final category = expense[random.nextInt(expense.length)];
        final day = min(monthOffset == 0 ? now.day : days, 1 + random.nextInt(days));
        await addTransaction(
          type: 'expense',
          amount: (1 + random.nextInt(60)) * 5000,
          categoryId: category.id,
          occurredOn: DateTime(month.year, month.month, day),
          note: _demoNote(category.name),
          source: random.nextInt(5) == 0 ? 'whatsapp' : 'app',
        );
      }
      if (income.isNotEmpty) {
        await addTransaction(
          type: 'income',
          amount: 6000000,
          categoryId: income.first.id,
          occurredOn: DateTime(month.year, month.month, 1),
          note: 'Gaji bulanan',
        );
      }
      for (final category in expense.take(4)) {
        await setBudget(
          categoryId: category.id,
          month: month,
          limitAmount: (3 + random.nextInt(5)) * 250000,
        );
      }
    }
  }

  String _demoNote(String category) {
    return switch (category) {
      'Makan' => 'Makan siang',
      'Transport' => 'Ojek ke kampus',
      'Belanja' => 'Belanja bulanan',
      'Tagihan' => 'Token listrik',
      'Kesehatan' => 'Beli obat',
      'Hiburan' => 'Nonton bioskop',
      _ => 'Pengeluaran lain',
    };
  }

  Future<void> wipeLocal() async {
    await db.transaction(() async {
      await db.delete(db.receipts).go();
      await db.delete(db.transactions).go();
      await db.delete(db.budgets).go();
      await db.delete(db.categories).go();
      await db.delete(db.settings).go();
    });
  }

  /// Data yang dibuat sebelum masuk akun ikut dipindahkan ke user tersebut.
  Future<void> migrateToUser(String newUserId) async {
    if (userId == newUserId) return;
    userId = newUserId;
    await db.customUpdate(
      'UPDATE categories SET user_id = ?, synced = 0',
      variables: [Variable.withString(newUserId)],
      updates: {db.categories},
    );
    await db.customUpdate(
      'UPDATE transactions SET user_id = ?, synced = 0',
      variables: [Variable.withString(newUserId)],
      updates: {db.transactions},
    );
    await db.customUpdate(
      'UPDATE budgets SET user_id = ?, synced = 0',
      variables: [Variable.withString(newUserId)],
      updates: {db.budgets},
    );
  }

  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);
}
