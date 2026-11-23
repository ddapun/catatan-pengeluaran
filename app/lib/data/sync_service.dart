import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/format.dart';
import 'database.dart';

enum SyncState { localOnly, idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.message,
  });

  final SyncState state;
  final DateTime? lastSyncedAt;
  final String? message;
}

/// Sinkronisasi dua arah: baris lokal yang belum terkirim didorong lebih dulu,
/// lalu perubahan server diambil. Konflik diselesaikan dengan `updated_at`
/// terbaru (last-write-wins), sesuai PRD.
class SyncService {
  SyncService(this.db, this.client);

  final AppDatabase db;
  final SupabaseClient? client;

  final _controller = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(state: SyncState.localOnly);
  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _running = false;

  bool get enabled => client != null;

  SyncStatus get status => _status;

  Stream<SyncStatus> get statusStream async* {
    yield _status;
    yield* _controller.stream;
  }

  void start() {
    if (!enabled) return;
    _connectivity ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) syncNow();
    });
    _periodic ??= Timer.periodic(const Duration(minutes: 3), (_) => syncNow());
    syncNow();
  }

  void scheduleSync() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    final supabase = client;
    if (supabase == null || _running) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      _emit(const SyncStatus(state: SyncState.localOnly));
      return;
    }

    _running = true;
    _emit(SyncStatus(state: SyncState.syncing, lastSyncedAt: _status.lastSyncedAt));
    try {
      await _push(supabase, user.id);
      await _pull(supabase, user.id);
      _emit(SyncStatus(state: SyncState.idle, lastSyncedAt: DateTime.now()));
    } catch (error) {
      final offline = error is PostgrestException
          ? false
          : error.toString().toLowerCase().contains('socket');
      _emit(SyncStatus(
        state: offline ? SyncState.offline : SyncState.error,
        lastSyncedAt: _status.lastSyncedAt,
        message: error.toString(),
      ));
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    _connectivity?.cancel();
    _controller.close();
  }

  void _emit(SyncStatus status) {
    _status = status;
    if (!_controller.isClosed) _controller.add(status);
  }

  // -------------------------------------------------------------------------
  // Dorong perubahan lokal
  // -------------------------------------------------------------------------

  Future<void> _push(SupabaseClient supabase, String userId) async {
    final categories = await (db.select(db.categories)
          ..where((c) => c.synced.equals(false)))
        .get();
    if (categories.isNotEmpty) {
      await supabase.from('categories').upsert(
            categories.map((c) => {
                  'id': c.id,
                  'user_id': userId,
                  'name': c.name,
                  'type': c.type,
                  'color': c.color,
                  'icon': c.icon,
                  'archived_at': c.archivedAt?.toUtc().toIso8601String(),
                  'deleted_at': c.deletedAt?.toUtc().toIso8601String(),
                  'updated_at': c.updatedAt.toUtc().toIso8601String(),
                }).toList(),
            onConflict: 'id',
          );
      for (final c in categories) {
        await (db.update(db.categories)
              ..where((t) => t.id.equals(c.id) & t.updatedAt.equals(c.updatedAt)))
            .write(const CategoriesCompanion(synced: Value(true)));
      }
    }

    final transactions = await (db.select(db.transactions)
          ..where((t) => t.synced.equals(false)))
        .get();
    if (transactions.isNotEmpty) {
      final payload = <Map<String, dynamic>>[];
      for (final tx in transactions) {
        var receiptPath = tx.receiptPath;
        final receipt = await (db.select(db.receipts)
              ..where((r) => r.transactionId.equals(tx.id)))
            .getSingleOrNull();
        if (receipt != null && !receipt.uploaded) {
          final path = '$userId/${tx.id}.jpg';
          await supabase.storage.from('receipts').uploadBinary(
                path,
                receipt.bytes,
                fileOptions: const FileOptions(
                  upsert: true,
                  contentType: 'image/jpeg',
                ),
              );
          receiptPath = path;
          await (db.update(db.receipts)
                ..where((r) => r.transactionId.equals(tx.id)))
              .write(
            ReceiptsCompanion(
              uploaded: const Value(true),
              updatedAt: Value(DateTime.now()),
            ),
          );
          await (db.update(db.transactions)..where((t) => t.id.equals(tx.id)))
              .write(TransactionsCompanion(receiptPath: Value(path)));
        }
        payload.add({
          'id': tx.id,
          'user_id': userId,
          'type': tx.type,
          'amount': tx.amount,
          'category_id': tx.categoryId,
          'note': tx.note,
          'occurred_on': isoDate(tx.occurredOn),
          'receipt_path': receiptPath,
          'source': tx.source,
          'created_at': tx.createdAt.toUtc().toIso8601String(),
          'updated_at': tx.updatedAt.toUtc().toIso8601String(),
          'deleted_at': tx.deletedAt?.toUtc().toIso8601String(),
        });
      }
      await supabase.from('transactions').upsert(payload, onConflict: 'id');
      for (final tx in transactions) {
        await (db.update(db.transactions)
              ..where((t) => t.id.equals(tx.id) & t.updatedAt.equals(tx.updatedAt)))
            .write(const TransactionsCompanion(synced: Value(true)));
      }
    }

    final budgets =
        await (db.select(db.budgets)..where((b) => b.synced.equals(false)))
            .get();
    if (budgets.isNotEmpty) {
      await supabase.from('budgets').upsert(
            budgets.map((b) => {
                  'id': b.id,
                  'user_id': userId,
                  'category_id': b.categoryId,
                  'month': isoDate(b.month),
                  'limit_amount': b.limitAmount,
                  'updated_at': b.updatedAt.toUtc().toIso8601String(),
                }).toList(),
            onConflict: 'id',
          );
      for (final b in budgets) {
        await (db.update(db.budgets)
              ..where((t) => t.id.equals(b.id) & t.updatedAt.equals(b.updatedAt)))
            .write(const BudgetsCompanion(synced: Value(true)));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Ambil perubahan server
  // -------------------------------------------------------------------------

  Future<void> _pull(SupabaseClient supabase, String userId) async {
    final lastPull = DateTime.tryParse(
          await _setting('last_pull') ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final since = lastPull.toUtc().toIso8601String();

    final remoteCategories = await supabase
        .from('categories')
        .select()
        .eq('user_id', userId)
        .gt('updated_at', since);
    for (final row in remoteCategories as List) {
      await _mergeCategory(Map<String, dynamic>.from(row as Map));
    }

    final remoteTransactions = await supabase
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .gt('updated_at', since);
    for (final row in remoteTransactions as List) {
      await _mergeTransaction(Map<String, dynamic>.from(row as Map));
    }

    final remoteBudgets = await supabase
        .from('budgets')
        .select()
        .eq('user_id', userId)
        .gt('updated_at', since);
    for (final row in remoteBudgets as List) {
      await _mergeBudget(Map<String, dynamic>.from(row as Map));
    }

    await _setSetting('last_pull', DateTime.now().toUtc().toIso8601String());
  }

  Future<void> _mergeCategory(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = DateTime.parse(row['updated_at'] as String);
    final local = await (db.select(db.categories)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !remoteUpdated.isAfter(local.updatedAt)) return;

    final companion = CategoriesCompanion(
      id: Value(id),
      userId: Value(row['user_id'] as String),
      name: Value(row['name'] as String),
      type: Value(row['type'] as String),
      color: Value(row['color'] as String?),
      icon: Value(row['icon'] as String?),
      archivedAt: Value(_date(row['archived_at'])),
      deletedAt: Value(_date(row['deleted_at'])),
      updatedAt: Value(remoteUpdated),
      isDefault: const Value(false),
      synced: const Value(true),
    );
    await db.into(db.categories).insertOnConflictUpdate(companion);
  }

  Future<void> _mergeTransaction(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = DateTime.parse(row['updated_at'] as String);
    final local = await (db.select(db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !remoteUpdated.isAfter(local.updatedAt)) return;

    await db.into(db.transactions).insertOnConflictUpdate(
          TransactionsCompanion(
            id: Value(id),
            userId: Value(row['user_id'] as String),
            type: Value(row['type'] as String),
            amount: Value((row['amount'] as num).toInt()),
            categoryId: Value(row['category_id'] as String),
            note: Value(row['note'] as String?),
            occurredOn: Value(DateTime.parse(row['occurred_on'] as String)),
            receiptPath: Value(row['receipt_path'] as String?),
            source: Value(row['source'] as String? ?? 'app'),
            createdAt: Value(
              _date(row['created_at']) ?? DateTime.now(),
            ),
            updatedAt: Value(remoteUpdated),
            deletedAt: Value(_date(row['deleted_at'])),
            synced: const Value(true),
          ),
        );
  }

  Future<void> _mergeBudget(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = DateTime.parse(row['updated_at'] as String);
    final local =
        await (db.select(db.budgets)..where((b) => b.id.equals(id)))
            .getSingleOrNull();
    if (local != null && !remoteUpdated.isAfter(local.updatedAt)) return;

    await db.into(db.budgets).insertOnConflictUpdate(
          BudgetsCompanion(
            id: Value(id),
            userId: Value(row['user_id'] as String),
            categoryId: Value(row['category_id'] as String),
            month: Value(DateTime.parse(row['month'] as String)),
            limitAmount: Value((row['limit_amount'] as num).toInt()),
            updatedAt: Value(remoteUpdated),
            synced: const Value(true),
          ),
        );
  }

  // -------------------------------------------------------------------------

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  Future<String?> _setting(String key) async {
    final row = await (db.select(db.settings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSetting(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(
            Setting(key: key, value: value),
          );
}
