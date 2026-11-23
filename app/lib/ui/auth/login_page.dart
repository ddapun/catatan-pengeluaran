import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Isi email dan kata sandi.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    try {
      if (_signUp) {
        await auth.signUp(_email.text, _password.text, _name.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
      await _afterAuth();
    } catch (error) {
      setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      await _afterAuth();
    } catch (error) {
      setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterAuth() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _error = 'Cek email untuk konfirmasi, lalu masuk kembali.');
      }
      return;
    }
    final repo = ref.read(repositoryProvider);
    await repo.migrateToUser(user.id);
    ref.read(syncServiceProvider).start();
    if (mounted) Navigator.of(context).pop();
  }

  String _readableError(Object error) {
    final text = error.toString();
    if (text.contains('Invalid login credentials')) {
      return 'Email atau kata sandi salah.';
    }
    if (text.contains('already registered')) {
      return 'Email ini sudah terdaftar. Coba masuk.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text(
            _signUp ? 'Buat akun' : 'Masuk',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Data lama di perangkat ini ikut dipindahkan ke akun Anda.',
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 22),
          if (_signUp) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Nama'),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Kata sandi'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: c.warn),
            ),
          ],
          const SizedBox(height: 18),
          PrimaryButton(
            label: _signUp ? 'Daftar' : 'Masuk',
            busy: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _signUp = !_signUp;
                _error = null;
              }),
              child: Text(
                _signUp ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Divider(color: c.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('atau', style: TextStyle(fontSize: 12, color: c.muted)),
              ),
              Expanded(child: Divider(color: c.line)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _google,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: c.line),
              foregroundColor: c.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Masuk dengan Google'),
          ),
        ],
      ),
    );
  }
}
