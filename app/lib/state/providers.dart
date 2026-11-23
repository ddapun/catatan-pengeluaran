import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_services.dart';
import '../core/format.dart';
import '../data/auth_service.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/sync_service.dart';

final repositoryProvider =
    Provider<ExpenseRepository>((ref) => AppServices.repo);

final authServiceProvider = Provider<AuthService>((ref) => AppServices.auth);

final syncServiceProvider = Provider<SyncService>((ref) => AppServices.sync);

final notificationsProvider =
    Provider((ref) => AppServices.notifications);

final initialThemeProvider =
    Provider<ThemeMode>((ref) => AppServices.initialTheme);

final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ref.watch(initialThemeProvider),
);

final selectedMonthProvider =
    StateProvider<DateTime>((ref) => DateTime.now().monthStart);

final monthSummaryProvider = StreamProvider.autoDispose<MonthSummary>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(repositoryProvider).watchMonth(month);
});

final categoriesProvider = StreamProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(repositoryProvider).watchCategories(),
);

final allCategoriesProvider = StreamProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(repositoryProvider).watchCategories(includeArchived: true),
);

final budgetsProvider =
    StreamProvider.autoDispose.family<List<BudgetProgress>, DateTime>(
  (ref, month) => ref.watch(repositoryProvider).watchBudgets(month),
);

class TxFilter {
  const TxFilter({
    required this.from,
    required this.to,
    this.type,
    this.categoryName,
    this.search = '',
  });

  final DateTime from;
  final DateTime to;
  final String? type;
  final String? categoryName;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is TxFilter &&
      other.from == from &&
      other.to == to &&
      other.type == type &&
      other.categoryName == categoryName &&
      other.search == search;

  @override
  int get hashCode => Object.hash(from, to, type, categoryName, search);
}

final transactionsProvider =
    StreamProvider.autoDispose.family<List<TxWithCategory>, TxFilter>(
  (ref, filter) => ref.watch(repositoryProvider).watchTransactions(
        from: filter.from,
        to: filter.to,
        type: filter.type,
        categoryName: filter.categoryName,
        search: filter.search,
      ),
);

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).statusStream,
);

/// Pengguna aktif; null saat mode lokal atau belum masuk.
final userProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return (() async* {
    yield auth.currentUser;
    await for (final state in auth.changes) {
      yield state.session?.user;
    }
  })();
});
