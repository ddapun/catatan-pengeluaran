import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../state/providers.dart';
import '../../wa/wa_parser.dart';
import '../widgets.dart';

class WhatsAppPage extends ConsumerStatefulWidget {
  const WhatsAppPage({super.key});

  @override
  ConsumerState<WhatsAppPage> createState() => _WhatsAppPageState();
}

class _WhatsAppPageState extends ConsumerState<WhatsAppPage> {
  final _input = TextEditingController();
  final _phone = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[
    const _Msg(
      'Halo! Kirim catatan seperti "makan siang 25rb".\n'
      'Perintah: rekap, sisa, batal.',
      mine: false,
    ),
  ];

  Future<Map<String, dynamic>?>? _link;
  _Pending? _pending;
  String? _lastTxId;
  bool _sending = false;

  bool get _canLink =>
      AppConfig.hasSupabase &&
      ref.read(authServiceProvider).currentUser != null;

  @override
  void initState() {
    super.initState();
    if (_canLink) _refreshLink();
  }

  @override
  void dispose() {
    _input.dispose();
    _phone.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refreshLink() {
    final client = ref.read(authServiceProvider).client;
    if (client == null) return;
    setState(() {
      _link = client.from('wa_links').select().maybeSingle();
    });
  }

  Future<void> _requestCode() async {
    final client = ref.read(authServiceProvider).client;
    if (client == null) return;
    try {
      await client.rpc(
        'request_whatsapp_link',
        params: {'p_phone': _phone.text},
      );
      _refreshLink();
      if (mounted) _snack('Kode dibuat. Kirim kode itu ke bot lewat WhatsApp.');
    } catch (error) {
      if (mounted) _snack('Gagal membuat kode: $error');
    }
  }

  Future<void> _unlink() async {
    final client = ref.read(authServiceProvider).client;
    if (client == null) return;
    try {
      await client.rpc('unlink_whatsapp');
      _refreshLink();
      if (mounted) _snack('Nomor diputuskan.');
    } catch (error) {
      if (mounted) _snack('Gagal memutuskan: $error');
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_Msg(text, mine: true));
      _input.clear();
      _sending = true;
    });
    _scrollDown();

    final reply = await _respond(text);
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(reply, mine: false));
      _sending = false;
    });
    _scrollDown();
  }

  Future<String> _respond(String text) async {
    final repo = ref.read(repositoryProvider);
    final command = detectWaCommand(text);

    if (command == WaCommand.bantuan) {
      return 'Contoh:\n- makan siang 25rb\n- ojek 18k\n- gaji 6jt masuk\n'
          'Perintah: rekap, sisa, batal.';
    }
    if (command == WaCommand.batal) {
      if (_lastTxId == null) {
        return 'Tidak ada transaksi simulator yang bisa dibatalkan.';
      }
      await repo.deleteTransaction(_lastTxId!);
      _lastTxId = null;
      ref.read(syncServiceProvider).scheduleSync();
      return 'Transaksi terakhir dibatalkan.';
    }
    if (command == WaCommand.rekap) {
      final summary = await repo.summaryFor(DateTime.now().monthStart);
      if (summary.expense == 0 && summary.income == 0) {
        return 'Belum ada transaksi bulan ini.';
      }
      final top = summary.byCategory.isEmpty ? null : summary.byCategory.first;
      return '${monthName(summary.month)}: keluar ${rupiah(summary.expense)}, '
          'masuk ${rupiah(summary.income)}.'
          '${top == null ? '' : '\nTerbesar: ${top.name} ${rupiah(top.total)}.'}';
    }
    if (command == WaCommand.sisa) {
      final budgets =
          await repo.watchBudgets(DateTime.now().monthStart).first;
      if (budgets.isEmpty) return 'Belum ada anggaran bulan ini.';
      return 'Sisa anggaran:\n${budgets.map((b) => b.isOver ? '${b.name}: lewat ${rupiah(-b.remaining)}' : '${b.name}: sisa ${rupiah(b.remaining)}').join('\n')}';
    }

    if (_pending != null && RegExp(r'^\d{1,2}$').hasMatch(text)) {
      final index = int.parse(text) - 1;
      final pending = _pending!;
      if (index < 0 || index >= pending.options.length) {
        return 'Pilihan tidak ada. Balas angka sesuai daftar, atau "batal".';
      }
      _pending = null;
      return _save(pending.parsed, pending.options[index]);
    }

    final parsed = parseWaMessage(text);
    if (!parsed.ok) {
      if (parsed.reason == WaFailReason.ambiguous) {
        final options =
            (await repo.categories(type: 'expense')).take(6).toList();
        if (options.isEmpty) return 'Kategori belum tersedia.';
        _pending = _Pending(parsed, options);
        final list =
            options.asMap().entries.map((e) => '${e.key + 1}. ${e.value.name}');
        return 'Kategori belum jelas untuk ${rupiah(parsed.amount!)}.\n'
            'Balas nomor:\n${list.join('\n')}';
      }
      return 'Jumlahnya belum terbaca. Contoh: "makan siang 25rb".';
    }

    return _save(parsed, null);
  }

  Future<String> _save(WaParseResult parsed, Category? category) async {
    final repo = ref.read(repositoryProvider);
    final categories = await repo.categories(type: parsed.type);
    if (categories.isEmpty) return 'Kategori belum tersedia.';

    final chosen = category ??
        categories.firstWhere(
          (c) => c.name == parsed.categoryHint,
          orElse: () => categories.first,
        );

    final id = await repo.addTransaction(
      type: parsed.type,
      amount: parsed.amount!,
      categoryId: chosen.id,
      occurredOn: DateTime.now(),
      note: parsed.note,
      source: 'whatsapp',
    );
    _lastTxId = id;
    ref.read(syncServiceProvider).scheduleSync();

    final kind = parsed.type == 'income' ? 'pemasukan' : 'pengeluaran';
    return 'Tercatat $kind ${rupiah(parsed.amount!)} — ${chosen.name}.\n'
        'Balas "batal" untuk menghapus.';
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: c.accent,
              child: Text(
                'C',
                style: TextStyle(
                  color: c.accentInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bot Catatan'),
                Text(
                  'Opsional, terhubung ke akunmu',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _linkSection(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(child: SectionTitle('Simulator lokal')),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'tanpa biaya',
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pesan di bawah diproses dengan parser yang sama seperti bot, '
                  'lalu disimpan sebagai transaksi WhatsApp.',
                  style: TextStyle(fontSize: 12, color: c.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                for (final message in _messages) _Bubble(message: message),
                if (_sending)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'mengetik…',
                        style: TextStyle(fontSize: 11, color: c.muted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final example in const [
                      'makan siang 25rb',
                      'ojek 18k',
                      'gaji 6jt masuk',
                      'rekap',
                    ]) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(example),
                          onPressed: () => _send(example),
                          backgroundColor: c.soft,
                          side: BorderSide.none,
                          labelStyle: TextStyle(fontSize: 12, color: c.ink),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Tulis pesan…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    tooltip: 'Kirim',
                    style: IconButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.accentInk,
                    ),
                    icon: const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkSection() {
    final c = context.colors;
    if (!AppConfig.hasSupabase) {
      return const InfoBanner(
        text:
            'Integrasi WhatsApp memerlukan server Supabase dan WhatsApp Cloud API. '
            'Simulator di bawah tetap bisa dipakai untuk mencoba pencatatan.',
      );
    }
    if (ref.read(authServiceProvider).currentUser == null) {
      return const InfoBanner(
        text: 'Masuk ke akun dulu untuk menautkan nomor WhatsApp.',
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _link,
      builder: (context, snapshot) {
        final row = snapshot.data;
        final verified = row?['verified_at'] != null;
        return SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verified ? 'Nomor tertaut' : 'Tautkan nomor WhatsApp',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              if (verified)
                Text(
                  row!['phone_e164'] as String,
                  style: TextStyle(fontSize: 13, color: c.muted),
                )
              else if (row != null && row['verify_code'] != null)
                Text(
                  'Kirim kode ${row['verify_code']} ke bot lewat WhatsApp '
                  'dalam 15 menit.',
                  style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
                )
              else
                Text(
                  'Masukkan nomor, lalu kirim kode verifikasi ke bot.',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              const SizedBox(height: 10),
              if (verified)
                OutlinedButton(
                  onPressed: _unlink,
                  child: const Text('Putuskan nomor'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '08xxxxxxxxxx',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _requestCode,
                      child: const Text('Minta kode'),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Msg {
  const _Msg(this.text, {required this.mine});

  final String text;
  final bool mine;
}

class _Pending {
  _Pending(this.parsed, this.options);

  final WaParseResult parsed;
  final List<Category> options;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Msg message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: message.mine ? c.accent : c.soft,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.mine ? 16 : 4),
            bottomRight: Radius.circular(message.mine ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: message.mine ? c.accentInk : c.ink,
          ),
        ),
      ),
    );
  }
}
