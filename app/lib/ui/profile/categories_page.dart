import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/database.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    final expense = all
        .where((c) => c.type == 'expense' && c.archivedAt == null && c.deletedAt == null)
        .toList();
    final income = all
        .where((c) => c.type == 'income' && c.archivedAt == null && c.deletedAt == null)
        .toList();
    final archived =
        all.where((c) => c.archivedAt != null && c.deletedAt == null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Kategori')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tambah kategori',
        backgroundColor: context.colors.accent,
        foregroundColor: context.colors.accentInk,
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
        children: [
          const SectionTitle('Pengeluaran'),
          const SizedBox(height: 8),
          _CategoryList(
            items: expense,
            emptyText: 'Belum ada kategori pengeluaran.',
            onTap: (category) => _edit(context, ref, category),
          ),
          const SizedBox(height: 20),
          const SectionTitle('Pemasukan'),
          const SizedBox(height: 8),
          _CategoryList(
            items: income,
            emptyText: 'Belum ada kategori pemasukan.',
            onTap: (category) => _edit(context, ref, category),
          ),
          if (archived.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionTitle('Diarsipkan'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < archived.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: context.colors.line),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CategoryAvatar(
                        name: archived[i].name,
                        colorHex: archived[i].color,
                        size: 32,
                      ),
                      title: Text(archived[i].name),
                      trailing: TextButton(
                        onPressed: () async {
                          await ref
                              .read(repositoryProvider)
                              .archiveCategory(archived[i].id, archived: false);
                          ref.read(syncServiceProvider).scheduleSync();
                        },
                        child: const Text('Aktifkan'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Category? category,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(existing: category),
    );
    if (changed == true) {
      ref.read(syncServiceProvider).scheduleSync();
    }
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.items,
    required this.emptyText,
    required this.onTap,
  });

  final List<Category> items;
  final String emptyText;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SurfaceCard(
        child: Text(
          emptyText,
          style: TextStyle(fontSize: 13, color: context.colors.muted),
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.colors.line),
            InkWell(
              onTap: () => onTap(items[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    CategoryAvatar(
                      name: items[i].name,
                      colorHex: items[i].color,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        items[i].name,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (items[i].isDefault)
                      Text(
                        'Bawaan',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.muted,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: context.colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.existing});

  final Category? existing;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late String _type = widget.existing?.type ?? 'expense';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Nama kategori tidak boleh kosong.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    if (widget.existing == null) {
      await repo.addCategory(name: _name.text, type: _type);
    } else {
      await repo.renameCategory(widget.existing!.id, _name.text);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _archive() async {
    await ref.read(repositoryProvider).archiveCategory(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Tambah kategori' : 'Ubah kategori',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.existing == null) ...[
            Row(
              children: [
                AppChoiceChip(
                  label: 'Pengeluaran',
                  selected: _type == 'expense',
                  onTap: () => setState(() => _type = 'expense'),
                ),
                const SizedBox(width: 8),
                AppChoiceChip(
                  label: 'Pemasukan',
                  selected: _type == 'income',
                  onTap: () => setState(() => _type = 'income'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Nama kategori',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _archive,
            child: Text('Arsipkan', style: TextStyle(color: c.warn)),
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
