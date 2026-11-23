/// Konfigurasi build. Tanpa nilai ini aplikasi berjalan 100% lokal (offline).
///
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// ID pengguna saat aplikasi dipakai tanpa akun (mode lokal).
  static const localUserId = 'local';
}
