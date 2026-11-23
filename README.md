# Catatan Pengeluaran

Aplikasi catatan pengeluaran harian dengan dashboard bulanan, offline-first. Flutter + Drift (SQLite lokal), Supabase opsional untuk sinkron antar perangkat dan bot WhatsApp.

## Menjalankan

```bash
cd app
flutter pub get
flutter run                 # tanpa Supabase: mode lokal penuh
```

Mode lokal menyimpan semua data di perangkat (`userId = 'local'`), tanpa internet. Untuk web:

```bash
flutter run -d chrome       # atau: flutter build web --release
```

`app/web/sqlite3.wasm` dan `app/web/drift_worker.js` wajib ikut ter-deploy, jika tidak database web gagal dibuka.

## Android

APK release sudah tersedia di `dist/catatan-pengeluaran-1.0.0.apk` (minSdk 26, arm64/armv7/x86_64). Build ulang:

```bash
cd app
flutter build apk --release
# hasil: app/build/app/outputs/flutter-apk/app-release.apk
```

APK ini ditandatangani dengan debug key, cukup untuk install manual. Untuk Play Store, buat keystore lalu ganti `signingConfig` di `app/android/app/build.gradle.kts`. Ukuran bisa dikecilkan dengan `--split-per-abi` (satu APK per arsitektur).

## Supabase (opsional)

1. Buat project di [supabase.com](https://supabase.com), lalu jalankan migrasi:
   ```bash
   supabase link --project-ref <ref>
   supabase db push
   ```
   Migrasi `supabase/migrations/20261122000000_init.sql` membuat tabel, RLS, RPC (`request_whatsapp_link`, `unlink_whatsapp`, `delete_my_account`, `monthly_summary`), dan bucket storage `receipts`.
2. Jalankan aplikasi dengan kredensial:
   ```bash
   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
               --dart-define=SUPABASE_ANON_KEY=<anon-key>
   ```
   Tanpa dua nilai itu aplikasi tetap jalan penuh secara lokal.

## Bot WhatsApp (opsional)

Butuh WhatsApp Cloud API (Meta). Rahasia Edge Function:

```bash
supabase secrets set WA_VERIFY_TOKEN=<bebas> WA_APP_SECRET=<app-secret> \
  WA_TOKEN=<access-token> WA_PHONE_ID=<phone-number-id>
supabase functions deploy whatsapp-webhook --no-verify-jwt
```

Daftarkan URL `https://<ref>.supabase.co/functions/v1/whatsapp-webhook` di webhook Meta, dengan verify token yang sama. Perintah yang didukung: catat pengeluaran bebas ("makan siang 25rb"), `rekap`, `sisa`, `batal`. Parser yang sama dipakai simulator lokal di Profil → WhatsApp, jadi fitur ini bisa dicoba tanpa server.

## Struktur

- `app/lib/data/` — Drift schema, repository, sinkronisasi (outbox `synced`, last-write-wins, soft delete).
- `app/lib/ui/` — layar Beranda, Riwayat, Tambah/Edit, Anggaran, Profil, Kategori, WhatsApp.
- `app/lib/wa/wa_parser.dart` — port parser WhatsApp untuk simulator.
- `supabase/functions/_shared/parser.ts` — parser bersama + test (`node --test`).

## Batasan yang diketahui

- Sinkronisasi mengunduh transaksi, tetapi foto struk yang dibuat di perangkat lain belum diunduh ulang.
- Kunci biometrik belum diterapkan.
- Ekspor PDF/CSV di web bergantung pada dialog print/share browser.
- Bot WhatsApp hanya aktif bila Supabase dan Meta Cloud API sudah dikonfigurasi.
