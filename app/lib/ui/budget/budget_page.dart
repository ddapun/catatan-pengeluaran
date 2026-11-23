import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/input_formatters.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class BudgetPage extends ConsumerWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final budgets = ref.watch(budgetsProvider(month));
    final previous = ref.watch(budgetsProvider(month.prevMonth)).valueOrNull ??
        const <BudgetProgress>[];
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Row(
              children: [
                const Text(
                  'Anggaran',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Opsi anggaran',
                  onSelected: (value) {
                    if (value == 'next') _copy(context, ref, month, month.nextMonth);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'next',
                      child: Text('Salin ke bulan berikutnya'),
                    ),
                  ],
                ),
              ],
            ),
            MonthSwitcher(
              month: month,
              onChanged: (value) =>
                  ref.read(selectedMonthProvider.notifier).state = value,
            ),
            const SizedBox(height: 10),
            budgets.when(
              data: (list) => _BudgetContent(
                month: month,
                budgets: list,
                previous: previous,
                categories: categories,
              ),
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Gagal memuat anggaran',
                message: error.toString(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    DateTime from,
    DateTime to,
  ) async {
    await ref.read(repositoryProvider).copyBudgets(from, to);
    ref.read(syncServiceProvider).scheduleSync();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Anggaran disalin ke ${monthName(to)}.')),
    );
  }
}

class _BudgetContent extends ConsumerWidget {
  const _BudgetContent({
    required this.month,
    required this.budgets,
    required this.previous,
    required this.categories,
  });

  final DateTime month;
  final List<BudgetProgress> budgets;
  final List<BudgetProgress> previous;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final over = budgets.where((b) => b.isOver).toList();
    final near = budgets.where((b) => b.isNearLimit).toList();
    final now = DateTime.now();
    final daysLeft =
        month.monthEnd.day - (month.sameMonth(now) ? now.day : 0);

    String? banner;
    if (over.isNotEmpty) {
      banner = '${over.map((b) => b.name).join(', ')} sudah lewat anggaran.';
      if (near.isNotEmpty) {
        banner += ' ${near.first.name} tersisa ${rupiah(near.first.remaining)}.';
      }
    } else if (near.isNotEmpty) {
      banner = '${near.first.name} tersisa ${rupiah(near.first.remaining)}'
          '${daysLeft > 0 ? ' untuk $daysLeft hari' : ''}.';
    }

    final withBudget = budgets.map((b) => b.budget.categoryId).toSet();
    final available = categories
        .where((c) => c.type == 'expense' && !withBudget.contains(c.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (banner != null)
          InfoBanner(text: banner, warn: over.isNotEmpty)
        else if (budgets.isEmpty)
          InfoBanner(
            text: 'Belum ada anggaran bulan ini.',
            actionLabel: previous.isNotEmpty
                ? 'Salin dari ${monthName(month.prevMonth)}'
                : null,
            onAction: previous.isEmpty
                ? null
                : () => BudgetPage._copy(
                      context,
                      ref,
                      month.prevMonth,
                      month,
                    ),
          )
        else
          InfoBanner(
            text: 'Semua kategori masih di bawah 80% dari anggaran.',
          ),
        if (budgets.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final budget in budgets) ...[
            _BudgetRow(
              progress: budget,
              onTap: () => _edit(context, ref, budget.category, budget.budget),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (available.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionTitle('Kategori tanpa anggaran'),
          const SizedBox(height: 8),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < available.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: context.colors.line),
                  InkWell(
                    onTap: () => _edit(context, ref, available[i], null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          CategoryAvatar(
                            name: available[i].name,
                            colorHex: available[i].color,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              available[i].name,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Text(
                            'Atur',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.colors.accent,
                            ),
                          ),
                        ],
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

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Category? category,
    Budget? existing,
  ) async {
    if (category == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _BudgetDialog(
        category: category,
        month: month,
        existing: existing,
      ),
    );
    if (changed == true) {
      ref.read(syncServiceProvider).scheduleSync();
    }
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.progress, required this.onTap});

  final BudgetProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${thousands(progress.spent)} / ${thousands(progress.budget.limitAmount)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: c.soft,
              color: progress.isOver ? c.warn : c.accent,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              progress.isOver
                  ? 'Lewat ${rupiah(-progress.remaining)}'
                  : 'Sisa ${rupiah(progress.remaining)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    progress.isOver ? FontWeight.w600 : FontWeight.w400,
                color: progress.isOver ? c.warn : c.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetDialog extends ConsumerStatefulWidget {
  const _BudgetDialog({
    required this.category,
    required this.month,
    this.existing,
  });

  final Category category;
  final DateTime month;
  final Budget? existing;

  @override
  ConsumerState<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends ConsumerState<_BudgetDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : thousands(widget.existing!.limitAmount),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value =
        int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (value <= 0) {
      setState(() => _error = 'Isi batas anggaran lebih dari 0.');
      return;
    }
    await ref.read(repositoryProvider).setBudget(
          categoryId: widget.category.id,
          month: widget.month,
          limitAmount: value,
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    await ref.read(repositoryProvider).deleteBudget(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Anggaran ${widget.category.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batas pengeluaran ${monthLabel(widget.month)}',
            style: TextStyle(
              fontSize: 12,
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter()],
            decoration: InputDecoration(
              prefixText: 'Rp ',
              hintText: '0',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _delete,
            child: Text(
              'Hapus',
              style: TextStyle(color: context.colors.warn),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}
