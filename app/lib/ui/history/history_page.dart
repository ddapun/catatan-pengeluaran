import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../transactions/add_transaction_page.dart';
import '../widgets.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _search = TextEditingController();
  String? _type;
  String? _categoryName;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    // Nama sama (mis. "Lainnya") cukup tampil sekali di baris filter.
    final uniqueCategories = <String, Category>{};
    for (final category in categories) {
      if (_type == null || category.type == _type) {
        uniqueCategories.putIfAbsent(category.name, () => category);
      }
    }
    final visibleCategories = uniqueCategories.values;

    final items = ref.watch(
      transactionsProvider(
        TxFilter(
          from: month.monthStart,
          to: month.monthEnd,
          type: _type,
          categoryName: _categoryName,
          search: _search.text,
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  const Text(
                    'Riwayat',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  MonthSwitcher(
                    month: month,
                    onChanged: (value) =>
                        ref.read(selectedMonthProvider.notifier).state = value,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Cari catatan…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _search.clear()),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  AppChoiceChip(
                    label: 'Semua',
                    selected: _type == null,
                    onTap: () => setState(() {
                      _type = null;
                      _categoryName = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                  AppChoiceChip(
                    label: 'Pengeluaran',
                    selected: _type == 'expense',
                    onTap: () => setState(() {
                      _type = 'expense';
                      _categoryName = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                  AppChoiceChip(
                    label: 'Pemasukan',
                    selected: _type == 'income',
                    onTap: () => setState(() {
                      _type = 'income';
                      _categoryName = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  AppChoiceChip(
                    label: 'Semua kategori',
                    selected: _categoryName == null,
                    onTap: () => setState(() => _categoryName = null),
                  ),
                  for (final category in visibleCategories) ...[
                    const SizedBox(width: 8),
                    AppChoiceChip(
                      label: category.name,
                      selected: _categoryName == category.name,
                      onTap: () => setState(() => _categoryName = category.name),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: items.when(
                data: (list) => list.isEmpty
                    ? ListView(
                        children: const [
                          EmptyState(
                            icon: Icons.search_off,
                            title: 'Tidak ada transaksi',
                            message:
                                'Coba ubah filter, atau catat transaksi baru lewat tombol +.',
                          ),
                        ],
                      )
                    : _GroupedList(items: list),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Gagal memuat riwayat',
                  message: error.toString(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.items});

  final List<TxWithCategory> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = <DateTime, List<TxWithCategory>>{};
    for (final item in items) {
      groups.putIfAbsent(item.tx.occurredOn.dateOnly, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
            child: Row(
              children: [
                Text(
                  weekdayLabel(entry.key),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
                const Spacer(),
                if (entry.value.any((e) => e.tx.type == 'expense'))
                  Text(
                    '−${thousands(entry.value.where((e) => e.tx.type == 'expense').fold(0, (sum, e) => sum + e.tx.amount))}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.muted,
                      fontFeatures: tabularFigures,
                    ),
                  ),
              ],
            ),
          ),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.line),
                  TxTile(
                    item: entry.value[i],
                    showDate: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => AddTransactionPage(
                          transactionId: entry.value[i].tx.id,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
