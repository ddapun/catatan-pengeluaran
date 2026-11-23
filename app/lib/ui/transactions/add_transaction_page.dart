import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/input_formatters.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({super.key, this.transactionId});

  final String? transactionId;

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _picker = ImagePicker();

  String _type = 'expense';
  String? _categoryId;
  DateTime _date = DateTime.now();
  Uint8List? _receipt;
  bool _removeReceipt = false;
  bool _saving = false;

  bool get _isEditing => widget.transactionId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final tx = await repo.transactionById(widget.transactionId!);
    if (tx == null) return;
    final receipt = await repo.receiptBytes(tx.id);
    if (!mounted) return;
    setState(() {
      _type = tx.type;
      _amount.text = 'Rp ${thousands(tx.amount)}';
      _note.text = tx.note ?? '';
      _date = tx.occurredOn;
      _categoryId = tx.categoryId;
      _receipt = receipt;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _amountValue =>
      int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _pickReceipt() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 75,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _receipt = bytes;
        _removeReceipt = false;
      });
    } catch (error) {
      _snack('Gagal membuka foto: $error');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('id', 'ID'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider);
    final amount = _amountValue;
    if (amount <= 0) {
      _snack('Isi jumlah dulu, ya.');
      return;
    }
    if (_categoryId == null) {
      _snack('Pilih kategori.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await repo.updateTransaction(
          id: widget.transactionId!,
          type: _type,
          amount: amount,
          categoryId: _categoryId!,
          occurredOn: _date,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          receipt: _receipt,
          removeReceipt: _removeReceipt,
        );
      } else {
        await repo.addTransaction(
          type: _type,
          amount: amount,
          categoryId: _categoryId!,
          occurredOn: _date,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          receipt: _receipt,
        );
      }

      if (_type == 'expense') {
        final alert = await repo.checkBudgetAlert(
          categoryId: _categoryId!,
          month: _date.monthStart,
        );
        if (alert != null) {
          await ref.read(notificationsProvider).show('Anggaran', alert);
          if (mounted) _snack(alert);
        }
      }
      ref.read(syncServiceProvider).scheduleSync();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _snack('Gagal menyimpan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: const Text(
          'Transaksi ini akan dihapus dari daftar. Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Hapus',
              style: TextStyle(color: context.colors.warn),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repositoryProvider).deleteTransaction(widget.transactionId!);
    ref.read(syncServiceProvider).scheduleSync();
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = ref.watch(categoriesProvider).valueOrNull ??
        const <Category>[];
    final visible = categories.where((cat) => cat.type == _type).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Ubah transaksi' : 'Tambah transaksi'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Hapus transaksi',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        children: [
          _Segmented(
            left: 'Pengeluaran',
            right: 'Pemasukan',
            leftSelected: _type == 'expense',
            onChanged: (expense) {
              setState(() {
                _type = expense ? 'expense' : 'income';
                _categoryId = null;
              });
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Jumlah',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          TextField(
            controller: _amount,
            autofocus: !_isEditing,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter(prefix: 'Rp ')],
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              fontFeatures: tabularFigures,
              color: c.ink,
            ),
            decoration: InputDecoration(
              hintText: 'Rp 0',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Kategori',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in visible)
                AppChoiceChip(
                  label: category.name,
                  selected: _categoryId == category.id,
                  onTap: () => setState(() => _categoryId = category.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Catatan (opsional)',
              prefixIcon: Icon(Icons.edit_note, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          _RowField(
            icon: Icons.event_outlined,
            label: 'Tanggal',
            value: dateLabel(_date),
            onTap: _pickDate,
          ),
          const SizedBox(height: 10),
          _ReceiptField(
            bytes: _receipt,
            onPick: _pickReceipt,
            onRemove: () => setState(() {
              _receipt = null;
              _removeReceipt = true;
            }),
          ),
          const SizedBox(height: 18),
          Text(
            'Tersimpan di perangkat dulu, lalu sinkron saat online.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: PrimaryButton(
            label: 'Simpan transaksi',
            busy: _saving,
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.left,
    required this.right,
    required this.leftSelected,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool leftSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _item(context, left, leftSelected, () => onChanged(true)),
          _item(context, right, !leftSelected, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: selected ? Border.all(color: c.line) : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? c.ink : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowField extends StatelessWidget {
  const _RowField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.soft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.muted),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(value, style: TextStyle(fontSize: 13, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.bytes,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? bytes;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.soft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: bytes == null ? onPick : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 20, color: c.muted),
              const SizedBox(width: 10),
              const Text('Foto struk', style: TextStyle(fontSize: 14)),
              const Spacer(),
              if (bytes == null)
                Text('Tambah foto', style: TextStyle(fontSize: 13, color: c.muted))
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    bytes!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus foto',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(Icons.close, size: 18, color: c.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
