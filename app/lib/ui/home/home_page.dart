import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthSummaryProvider);
    final c = context.colors;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: () => ref.read(syncServiceProvider).syncNow(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: [
              Row(
                children: [
                  MonthSwitcher(
                    month: month,
                    onChanged: (value) =>
                        ref.read(selectedMonthProvider.notifier).state = value,
                  ),
                  const Spacer(),
                  const SyncBadge(),
                ],
              ),
              const SizedBox(height: 20),
              summary.when(
                data: (data) => _HomeContent(summary: data),
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Gagal memuat ringkasan',
                  message: error.toString(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final change = summary.changePercent;
    final changeText = change == null
        ? 'Belum ada data ${monthName(summary.month.prevMonth)}'
        : change < 0
            ? '${(change.abs() * 100).round()}% lebih rendah dari '
                '${monthName(summary.month.prevMonth)}'
            : '${(change * 100).round()}% lebih tinggi dari '
                '${monthName(summary.month.prevMonth)}';
    final changeColor =
        change != null && change > 0 ? c.warn : c.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pengeluaran bulan ini',
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 2),
        Text(
          rupiah(summary.expense),
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFeatures: tabularFigures,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          changeText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: changeColor,
          ),
        ),
        const SizedBox(height: 18),
        _DailyBars(summary: summary),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Stat(label: 'Pemasukan', value: rupiah(summary.income)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(label: 'Sisa', value: rupiah(summary.balance)),
            ),
          ],
        ),
        if (summary.byCategory.isNotEmpty) ...[
          const SizedBox(height: 22),
          const SectionTitle('Per kategori'),
          const SizedBox(height: 12),
          for (final item in summary.byCategory.take(5))
            _CategoryBar(
              item: item,
              max: summary.byCategory.first.total,
            ),
        ],
        const SizedBox(height: 22),
        const SectionTitle('Transaksi terbaru'),
        const SizedBox(height: 8),
        if (summary.recent.isEmpty)
          SurfaceCard(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Belum ada transaksi bulan ini',
              message: 'Tekan tombol + untuk mencatat pengeluaran pertama.',
            ),
          )
        else
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < summary.recent.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.line),
                  TxTile(item: summary.recent[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxDaily = summary.maxDaily;
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              'Grafik pengeluaran harian, total ${rupiah(summary.expense)}',
          child: SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < summary.daily.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: maxDaily == 0
                            ? 3
                            : (summary.daily[i] / maxDaily * 56)
                                .clamp(3.0, 56.0),
                        decoration: BoxDecoration(
                          color: summary.daily[i] == 0
                              ? c.line
                              : c.accent.withValues(
                                  alpha: summary.month.sameMonth(today) &&
                                          i + 1 == today.day
                                      ? 1
                                      : 0.45,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pengeluaran harian · ${summary.daily.length} hari',
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.item, required this.max});

  final CategoryTotal item;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = colorFromHex(item.colorHex, fallback: c.accent);
    final factor = max == 0 ? 0.0 : item.total / max;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                thousands(item.total),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: c.soft,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor.clamp(0.02, 1.0),
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
