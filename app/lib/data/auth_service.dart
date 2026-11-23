import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService(this.client);

  final SupabaseClient? client;

  bool get enabled => client != null;

  User? get currentUser => client?.auth.currentUser;

  Stream<AuthState> get changes =>
      client?.auth.onAuthStateChange ?? const Stream.empty();

  Future<void> signIn(String email, String password) =>
      client!.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signUp(String email, String password, String name) =>
      client!.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': name.trim()},
      );

  Future<void> signInWithGoogle() =>
      client!.auth.signInWithOAuth(OAuthProvider.google);

  Future<void> signOut() => client!.auth.signOut();

  Future<void> deleteAccount() => client!.rpc('delete_my_account');
}
