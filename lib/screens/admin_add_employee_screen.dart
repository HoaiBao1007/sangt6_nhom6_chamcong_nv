import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../state/auth_state.dart';
// NOTE: bạn đang để config.dart trong thư mục widgets (theo screenshot)
// nếu của bạn ở chỗ khác, chỉnh đường dẫn cho đúng:
import 'package:sangt6_nhom6_chamcong_nv/widgets/config.dart';


class AdminAddEmployeeScreen extends StatefulWidget {
  const AdminAddEmployeeScreen({super.key});

  @override
  State<AdminAddEmployeeScreen> createState() => _AdminAddEmployeeScreenState();
}

class _AdminAddEmployeeScreenState extends State<AdminAddEmployeeScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _nfcTagId = TextEditingController(); // HEX UPPER, không có dấu ':'
  final _hourlyRate = TextEditingController(text: '50000');
  bool _isBanned = false;

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_fullName.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Nhập Họ tên và Email.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = context.read<AuthState>().token;
      final uri = Uri.parse('${AppConfig.baseUrl}/api/Employees'); // ⚠️ ĐỔI nếu route khác
      final body = jsonEncode({
        'fullName': _fullName.text.trim(),
        'email': _email.text.trim(),
        'nfcTagId': _nfcTagId.text.trim().toUpperCase(),
        'hourlyRate': double.tryParse(_hourlyRate.text) ?? 0,
        'isBanned': _isBanned,
      });

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: body,
      );

      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã thêm nhân viên.')),
        );
        Navigator.pop(context);
      } else {
        setState(() => _error = 'HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthState>().isAdmin;

    return Scaffold(
      appBar: AppBar(title: const Text('Thêm nhân viên')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isAdmin
            ? ListView(
          children: [
            TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: 'Họ tên'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nfcTagId,
              decoration: const InputDecoration(
                labelText: 'NFC Tag ID (HEX, UPPER, không ":")',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hourlyRate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Lương theo giờ'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Cấm (IsBanned)'),
              value: _isBanned,
              onChanged: (v) => setState(() => _isBanned = v),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: Text(_loading ? 'Đang lưu...' : 'Lưu'),
            ),
          ],
        )
            : const Center(
          child: Text(
            'Chỉ ADMIN mới được thêm nhân viên.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
