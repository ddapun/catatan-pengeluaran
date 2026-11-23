import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'core/notifications.dart';
import 'data/auth_service.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'data/sync_service.dart';

/// Objek global yang dibuat sekali saat aplikasi mulai.
class AppServices {
  static late final AppDatabase db;
  static late final ExpenseRepository repo;
  static late final AuthService auth;
  static late final SyncService sync;
  static late final NotificationService notifications;
  static late final ThemeMode initialTheme;

  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    db = AppDatabase();
    repo = ExpenseRepository(db);
    notifications = NotificationService();

    await repo.seedDefaultsIfNeeded();
    await notifications.init();
    initialTheme = switch (await repo.getSetting('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    if (AppConfig.hasSupabase) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      final client = Supabase.instance.client;
      auth = AuthService(client);
      sync = SyncService(db, client);
      final user = auth.currentUser;
      if (user != null) {
        await repo.migrateToUser(user.id);
        sync.start();
      }
    } else {
      auth = AuthService(null);
      sync = SyncService(db, null);
    }
  }
}
