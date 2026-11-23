# PRD: Aplikasi Catatan Pengeluaran Harian

Versi 0.1 | 22 November 2026 | Status: Draft untuk review

## 1. Ringkasan

Aplikasi mobile pribadi untuk mencatat pemasukan dan pengeluaran harian dengan cepat, bisa dipakai tanpa internet, dan menampilkan dashboard ringkasan bulanan. Pencatatan juga bisa dilakukan lewat bot WhatsApp (opsional).

**Keputusan stack:** Flutter (Android/iOS), Supabase (PostgreSQL, Auth, Storage, Edge Functions), database lokal SQLite di perangkat untuk mode offline.

## 2. Tujuan dan Non-Tujuan

**Tujuan**
- Mencatat satu transaksi dalam kurang dari 10 detik.
- Pengguna tahu ke mana uangnya pergi setiap bulan lewat dashboard.
- Tetap bisa mencatat saat offline; data tersinkron otomatis saat online.
- Memberi peringatan saat pengeluaran mendekati atau melewati anggaran.

**Non-tujuan (versi pertama)**
- Berbagi akun dengan pasangan/keluarga.
- Integrasi rekening bank atau e-wallet.
- OCR otomatis pada foto struk (foto hanya disimpan sebagai lampiran).
- Multi mata uang. Default Rupiah (IDR).

## 3. Pengguna

Satu pengguna pribadi (single user) dengan satu akun. Bahasa antarmuka Indonesia. Pemakaian utama di HP, sering di tempat dengan sinyal tidak stabil.

## 4. Ruang Lingkup MVP

| Area | Fitur |
|---|---|
| Transaksi | Tambah, ubah, hapus pengeluaran dan pemasukan; catatan; tanggal; foto struk |
| Kategori | Kategori bawaan + kategori buatan sendiri |
| Anggaran | Batas bulanan per kategori, peringatan 80% dan 100% |
| Dashboard | Ringkasan bulanan, grafik harian, rincian per kategori, perbandingan dengan bulan lalu |
| Ekspor | Laporan bulanan ke PDF dan CSV |
| Offline | Input dan lihat data tanpa internet, sinkron otomatis |
| WhatsApp (opsional) | Catat transaksi lewat pesan teks, perintah rekap |

## 5. Kebutuhan Fungsional

### 5.1 Autentikasi
- FR-01: Pendaftaran dan masuk dengan email + kata sandi, atau Google Sign-In, lewat Supabase Auth.
- FR-02: Sesi tersimpan di perangkat; kunci aplikasi opsional dengan biometrik.

### 5.2 Transaksi
- FR-10: Tambah transaksi dengan jumlah, jenis (keluar/masuk), kategori, catatan, tanggal (default hari ini).
- FR-11: Ubah dan hapus transaksi. Penghapusan bersifat soft delete agar sinkron antar perangkat.
- FR-12: Lampirkan satu foto struk (kompres di perangkat sebelum unggah).
- FR-13: Riwayat dengan filter tanggal, kategori, jenis, serta pencarian catatan.
- FR-14: Jumlah disimpan sebagai bilangan bulat (Rupiah tanpa desimal).

### 5.3 Kategori
- FR-20: Kategori bawaan: Makan, Transport, Belanja, Tagihan, Kesehatan, Hiburan, Lainnya; pemasukan: Gaji, Lainnya.
- FR-21: Tambah, ubah nama, arsipkan kategori. Kategori yang dipakai transaksi tidak dihapus permanen.

### 5.4 Anggaran
- FR-30: Atur batas bulanan per kategori; bisa disalin otomatis ke bulan berikutnya.
- FR-31: Notifikasi lokal saat pengeluaran kategori mencapai 80% dan 100% batas.
- FR-32: Halaman anggaran menampilkan progres, sisa, dan jumlah lewat batas.

### 5.5 Dashboard bulanan
- FR-40: Pemilih bulan; default bulan berjalan.
- FR-41: Kartu ringkasan: total pengeluaran, total pemasukan, sisa, selisih persen terhadap bulan lalu.
- FR-42: Grafik batang pengeluaran per hari.
- FR-43: Rincian per kategori (jumlah dan proporsi), diurutkan dari terbesar.
- FR-44: Daftar transaksi terbaru dan tombol tambah cepat.
- FR-45: Semua angka dihitung dari database lokal sehingga dashboard tetap berfungsi offline.

### 5.6 Ekspor
- FR-50: Ekspor transaksi sebulan atau rentang tanggal ke CSV.
- FR-51: Ekspor laporan ringkas ke PDF (ringkasan, per kategori, daftar transaksi).
- FR-52: Bagikan file lewat share sheet bawaan perangkat.

### 5.7 Offline dan sinkronisasi
- FR-60: Semua operasi tulis masuk ke database lokal terlebih dahulu.
- FR-61: Antrian perubahan dikirim ke Supabase saat online; indikator status sinkron terlihat di beranda.
- FR-62: ID transaksi berupa UUID yang dibuat di perangkat agar tidak bentrok.
- FR-63: Penyelesaian konflik: perubahan dengan `updated_at` terbaru menang (last-write-wins).
- FR-64: Foto struk diunggah belakangan, hanya saat ada koneksi.

### 5.8 Integrasi WhatsApp (opsional)
- FR-70: Pengguna menautkan nomor WhatsApp di pengaturan lewat kode verifikasi sekali pakai.
- FR-71: Pesan teks seperti `makan siang 25rb` diparse menjadi transaksi: jumlah, kategori, catatan.
- FR-72: Format jumlah yang dikenali: `25rb`, `25k`, `25.000`, `1,5jt`, `2jt`.
- FR-73: Kata `gaji`, `masuk`, `terima` menandai pemasukan; selain itu dianggap pengeluaran.
- FR-74: Jika kategori tidak jelas, bot membalas pilihan bernomor.
- FR-75: Perintah: `batal` (hapus transaksi terakhir), `rekap` (ringkasan bulan ini), `sisa` (sisa anggaran).
- FR-76: Hanya nomor yang sudah tertaut yang diproses; pesan dari nomor lain diabaikan.
- FR-77: Fitur dapat dimatikan penuh tanpa memengaruhi aplikasi utama.

**Rekomendasi jalur WhatsApp**

| Opsi | Kelebihan | Kekurangan | Saran |
|---|---|---|---|
| WhatsApp Cloud API (Meta, resmi) | Stabil, sesuai kebijakan, webhook langsung ke Supabase Edge Function | Perlu akun Meta Business dan setup awal; ada aturan jendela 24 jam untuk pesan balasan | **Direkomendasikan** |
| Gateway pihak ketiga (misal Fonnte) | Setup cepat, cocok untuk prototipe | Tidak resmi, biaya bulanan, ketergantungan pihak ketiga | Alternatif untuk prototipe cepat |
| Library tidak resmi (Baileys, whatsapp-web.js) | Gratis | Risiko nomor diblokir, perlu server berjalan terus | Tidak disarankan |

Untuk satu pengguna pribadi, nomor uji dari Cloud API umumnya cukup dan tidak perlu verifikasi bisnis penuh. Tarif dan batasan terbaru perlu dicek di dokumentasi Meta saat implementasi.

Alur: pesan WhatsApp → webhook Edge Function (verifikasi tanda tangan) → cocokkan nomor ke akun → parser → simpan ke tabel `transactions` → balas konfirmasi. Parser awal berbasis aturan (regex + kamus kata kunci kategori). Parser berbasis LLM bisa ditambahkan nanti sebagai cadangan untuk kalimat yang ambigu.

## 6. Kebutuhan Non-Fungsional

- **Kinerja:** aplikasi terbuka di bawah 2 detik; simpan transaksi terasa instan (tulis lokal).
- **Keandalan:** tidak ada data hilang saat aplikasi ditutup atau koneksi putus di tengah sinkron.
- **Keamanan:** Row Level Security aktif di semua tabel (`user_id = auth.uid()`); bucket struk privat dengan URL bertanda tangan; rahasia WhatsApp hanya di Edge Function.
- **Privasi:** data hanya milik pengguna; ada opsi ekspor dan hapus akun beserta seluruh data.
- **Platform:** Android 8+ dan iOS 15+. Prioritas pertama Android.
- **Aksesibilitas:** kontras memadai, ukuran sentuh minimal 44 px, mendukung mode gelap.

## 7. Arsitektur

```
Flutter App
 ├─ UI (Riverpod, go_router)
 ├─ Database lokal (SQLite via Drift)  ◄── sumber data untuk UI
 └─ Sync engine ─────────────► Supabase
                                ├─ Auth
                                ├─ PostgreSQL (RLS)
                                ├─ Storage (foto struk)
                                └─ Edge Functions
                                     └─ Webhook WhatsApp ◄── WhatsApp Cloud API
```

Rekomendasi pustaka Flutter: Riverpod (state), Drift (SQLite), supabase_flutter, fl_chart (grafik), pdf + printing (ekspor PDF), flutter_local_notifications, image_picker + flutter_image_compress. Pustaka sinkronisasi siap pakai seperti PowerSync bisa dipertimbangkan jika sync buatan sendiri terlalu rumit.

## 8. Model Data (PostgreSQL)

**profiles**: `id` (uuid, = auth.users.id), `display_name`, `currency` (default `IDR`), `created_at`

**categories**: `id` (uuid), `user_id`, `name`, `type` (`expense`/`income`), `color`, `icon`, `archived_at`, `updated_at`

**transactions**: `id` (uuid, dibuat klien), `user_id`, `type`, `amount` (bigint, > 0), `category_id`, `note`, `occurred_on` (date), `receipt_path`, `source` (`app`/`whatsapp`), `created_at`, `updated_at`, `deleted_at`

**budgets**: `id`, `user_id`, `category_id`, `month` (date, tanggal 1), `limit_amount` (bigint), `updated_at`; unik pada (`user_id`, `category_id`, `month`)

**wa_links**: `user_id`, `phone_e164`, `verified_at`, `verify_code`, `verify_expires_at`

Indeks: `transactions (user_id, occurred_on)` dan `transactions (user_id, category_id, occurred_on)`. Ringkasan bulanan di server memakai fungsi SQL (RPC) untuk kebutuhan ekspor dan WhatsApp; di aplikasi dihitung dari database lokal.

## 9. Layar Utama

Rancangan visual ada di berkas `desain-catatan-pengeluaran.html` (mode terang dan gelap).

1. **Beranda**: ringkasan bulan, grafik harian, rincian kategori.
2. **Tambah transaksi**: jumlah, kategori, catatan, tanggal, foto struk.
3. **Riwayat**: daftar dengan filter dan pencarian.
4. **Anggaran**: progres per kategori dan peringatan.
5. **Profil/Pengaturan**: kategori, tautan WhatsApp, ekspor, tema, kunci aplikasi, hapus akun.

Gaya visual: minimalis, bersih, terang dengan opsi mode gelap; satu warna aksen hijau jade; angka memakai tabular figures.

## 10. Metrik Keberhasilan

- Median waktu mencatat transaksi di bawah 10 detik.
- Pencatatan setidaknya 5 hari dalam seminggu setelah 1 bulan pemakaian.
- Nol laporan data hilang akibat sinkronisasi.
- Untuk WhatsApp: minimal 90% pesan format umum terparse tanpa pertanyaan lanjutan.

## 11. Rencana Rilis

| Fase | Isi | Perkiraan |
|---|---|---|
| 0 | Setup proyek, skema Supabase + RLS, autentikasi | 1 minggu |
| 1 | Transaksi, kategori, database lokal, riwayat | 2 minggu |
| 2 | Dashboard bulanan, anggaran + notifikasi | 2 minggu |
| 3 | Sinkronisasi offline penuh, foto struk | 2 minggu |
| 4 | Ekspor CSV/PDF, mode gelap, polesan, uji | 1 minggu |
| 5 (opsional) | Bot WhatsApp: webhook, parser, penautan nomor | 2 minggu |

Perkiraan untuk satu pengembang paruh waktu; sesuaikan dengan waktu yang tersedia.

## 12. Risiko

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Sinkronisasi offline rumit dan rawan konflik | Data ganda atau hilang | UUID dari klien, soft delete, `updated_at`, uji skenario putus koneksi; pertimbangkan PowerSync |
| Kebijakan atau tarif WhatsApp berubah | Bot berhenti atau berbiaya | Fitur opsional dan terisolasi; jalur resmi; abstraksi penyedia pesan |
| Parser salah menafsirkan pesan | Catatan keliru | Selalu kirim konfirmasi dan perintah `batal`; pilihan bernomor untuk kasus ambigu |
| Batas paket gratis Supabase | Proyek dijeda bila tidak aktif | Pantau pemakaian; rencanakan upgrade bila perlu |
| Foto struk memakan penyimpanan | Kuota penuh | Kompres di perangkat, batasi resolusi |

## 13. Pertanyaan Terbuka

- Apakah perlu transaksi berulang (langganan, cicilan) setelah MVP?
- Apakah perlu fitur anggaran total bulanan selain per kategori?
- Platform pertama: Android saja, atau langsung iOS juga?
- Setelah MVP, apakah ingin menambah parser LLM untuk pesan WhatsApp bebas?
