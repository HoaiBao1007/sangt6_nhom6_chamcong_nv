import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import 'nfc_checkin_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String role = 'EMPLOYEE'; // hoặc cho chọn ADMIN/EMPLOYEE nếu cần
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    final err = await auth.doRegister(_email.text.trim(), _password.text.trim(), role: role);
    if (err != null) {
      setState(() => _error = err);
    } else {
      // Đăng ký xong (đã tự login) -> sang quét NFC
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
      appBar: AppBar(title: const Text('Đăng ký')),
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
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'EMPLOYEE', child: Text('Nhân viên (EMPLOYEE)')),
                  DropdownMenuItem(value: 'ADMIN', child: Text('Quản trị (ADMIN)')),
                ],
                onChanged: (v) => setState(() => role = v ?? 'EMPLOYEE'),
                decoration: const InputDecoration(labelText: 'Vai trò'),
              ),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: loading ? null : _submit,
                child: Text(loading ? 'Đang đăng ký...' : 'Đăng ký'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
