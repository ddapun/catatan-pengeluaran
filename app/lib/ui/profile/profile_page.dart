import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/export_service.dart';
import '../../state/providers.dart';
import '../auth/login_page.dart';
import '../widgets.dart';
import 'categories_page.dart';
import 'whatsapp_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _snack('Gagal: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              action,
              style: TextStyle(color: context.colors.warn),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(userProvider).valueOrNull;
    final auth = ref.watch(authServiceProvider);
    final month = ref.watch(selectedMonthProvider);
    final themeMode = ref.watch(themeModeProvider);
    final export = ExportService(ref.read(repositoryProvider));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Row(
              children: [
                const Text(
                  'Profil',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (_busy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (!auth.enabled)
              InfoBanner(
                text:
                    'Mode lokal. Data tersimpan di perangkat ini dan tetap bisa dipakai tanpa internet. '
                    'Hubungkan Supabase untuk sinkron antar perangkat dan bot WhatsApp.',
              )
            else if (user == null)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Belum masuk',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Masuk agar data tersinkron dan bisa menautkan WhatsApp.',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Masuk / Daftar',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                    ),
                  ],
                ),
              )
            else
              SurfaceCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: c.accent,
                      child: Text(
                        (user.email ?? 'U').substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: c.accentInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.userMetadata?['full_name'] as String? ??
                                'Pengguna',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            user.email ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _run(() async {
                        await auth.signOut();
                        ref.read(repositoryProvider).setUserId(
                              AppConfig.localUserId,
                            );
                        _snack('Sudah keluar.');
                      }),
                      child: const Text('Keluar'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            const SectionTitle('Tampilan'),
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tema',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AppChoiceChip(
                        label: 'Sistem',
                        selected: themeMode == ThemeMode.system,
                        onTap: () => _setTheme(ThemeMode.system),
                      ),
                      const SizedBox(width: 8),
                      AppChoiceChip(
                        label: 'Terang',
                        selected: themeMode == ThemeMode.light,
                        onTap: () => _setTheme(ThemeMode.light),
                      ),
                      const SizedBox(width: 8),
                      AppChoiceChip(
                        label: 'Gelap',
                        selected: themeMode == ThemeMode.dark,
                        onTap: () => _setTheme(ThemeMode.dark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionTitle('Pengaturan'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.category_outlined,
                    title: 'Kategori',
                    subtitle: 'Tambah, ubah nama, atau arsipkan',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CategoriesPage()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _MenuRow(
                    icon: Icons.chat_outlined,
                    title: 'WhatsApp',
                    subtitle: !auth.enabled
                        ? 'Opsional · simulator tersedia'
                        : user == null
                            ? 'Masuk dulu untuk menautkan nomor'
                            : 'Opsional · tautkan nomor',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WhatsAppPage()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionTitle('Ekspor'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.table_chart_outlined,
                    title: 'Ekspor CSV',
                    subtitle: monthLabel(month),
                    onTap: () => _run(() => export.shareCsv(month)),
                  ),
                  Divider(height: 1, color: c.line),
                  _MenuRow(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Ekspor PDF',
                    subtitle: 'Ringkasan, kategori, dan transaksi',
                    onTap: () => _run(() => export.sharePdf(month)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionTitle('Data'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Isi data contoh',
                    subtitle: 'Menambah transaksi dua bulan terakhir',
                    onTap: () async {
                      final ok = await _confirm(
                        'Isi data contoh?',
                        'Data contoh ditambahkan ke bulan ini dan bulan lalu. '
                            'Data yang sudah ada tidak dihapus.',
                        'Tambahkan',
                      );
                      if (!ok) return;
                      await _run(() async {
                        await ref.read(repositoryProvider).seedDemoData();
                        _snack('Data contoh ditambahkan.');
                      });
                    },
                  ),
                  Divider(height: 1, color: c.line),
                  _MenuRow(
                    icon: Icons.delete_sweep_outlined,
                    title: 'Hapus semua data lokal',
                    subtitle: 'Transaksi, anggaran, dan kategori',
                    danger: true,
                    onTap: () async {
                      final ok = await _confirm(
                        'Hapus semua data?',
                        'Seluruh transaksi, anggaran, dan kategori di perangkat ini '
                            'akan dihapus. Tindakan ini tidak bisa dibatalkan.',
                        'Hapus',
                      );
                      if (!ok) return;
                      await _run(() async {
                        final repo = ref.read(repositoryProvider);
                        await repo.wipeLocal();
                        await repo.seedDefaultsIfNeeded();
                        _snack('Data lokal sudah dihapus.');
                      });
                    },
                  ),
                ],
              ),
            ),
            if (auth.enabled && user != null) ...[
              const SizedBox(height: 18),
              const SectionTitle('Akun'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: _MenuRow(
                  icon: Icons.person_off_outlined,
                  title: 'Hapus akun',
                  subtitle: 'Menghapus akun dan seluruh data di server',
                  danger: true,
                  onTap: () async {
                    final ok = await _confirm(
                      'Hapus akun?',
                      'Akun beserta seluruh data di server akan dihapus permanen.',
                      'Hapus akun',
                    );
                    if (!ok) return;
                    await _run(() async {
                      final repo = ref.read(repositoryProvider);
                      await auth.deleteAccount();
                      await repo.wipeLocal();
                      await repo.seedDefaultsIfNeeded();
                      repo.setUserId(AppConfig.localUserId);
                      _snack('Akun sudah dihapus.');
                    });
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Catatan Pengeluaran 1.0.0\nData milik Anda, tersimpan di perangkat.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.muted, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setTheme(ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).state = mode;
    await ref.read(repositoryProvider).setSetting('theme', mode.name);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? c.warn : c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: danger ? c.warn : c.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }
}
