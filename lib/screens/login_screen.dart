import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import 'register_screen.dart';
import 'nfc_checkin_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    final err = await auth.doLogin(_email.text.trim(), _password.text.trim());
    if (err != null) {
      setState(() => _error = err);
    } else {
      // Đăng nhập xong -> sang quét NFC
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NfcCheckinScreen()),
            (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthState>().loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || v.isEmpty) ? 'Nhập email' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Mật khẩu'),
                obscureText: true,
                validator: (v) => (v == null || v.isEmpty) ? 'Nhập mật khẩu' : null,
              ),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: loading ? null : _submit,
                child: Text(loading ? 'Đang đăng nhập...' : 'Đăng nhập'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
                child: const Text('Chưa có tài khoản? Đăng ký'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
