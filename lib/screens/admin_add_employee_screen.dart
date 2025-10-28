import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/config.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({Key? key}) : super(key: key);

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _hourlyRateController = TextEditingController();

  bool isScanning = false;
  int? newEmployeeId;

  // ---------- Helpers: chuẩn hoá UID ----------
  Uint8List _reverse(Uint8List src) =>
      Uint8List.fromList(src.reversed.toList());

  String _bytesToHex(Uint8List b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  /// Lấy UID từ nhiều loại tag, sau đó **đảo byte** để trùng format DB.
  String? _uidHexFromTag(NfcTag tag) {
    Uint8List? id;

    final nfcA = NfcA.from(tag);
    if (nfcA?.identifier != null) id = nfcA!.identifier;

    final mful = MifareUltralight.from(tag);
    if (id == null && mful?.identifier != null) id = mful!.identifier;

    final mfc = MifareClassic.from(tag);
    if (id == null && mfc?.identifier != null) id = mfc!.identifier;

    final isoDep = IsoDep.from(tag);
    if (id == null && isoDep?.identifier != null) id = isoDep!.identifier;

    final nfcV = NfcV.from(tag);
    if (id == null && nfcV?.identifier != null) id = nfcV!.identifier;

    final nfcF = NfcF.from(tag);
    if (id == null && nfcF?.identifier != null) id = nfcF!.identifier;

    if (id == null) return null;

    // ⭐ ĐẢO BYTE (LSB→MSB) để giống chuỗi đang lưu trong DB
    id = _reverse(id);
    return _bytesToHex(id); // UPPER, không dấu ':'
  }

  // ---------- API ----------
  Future<void> addEmployee() async {
    final token = context.read<AuthState>().token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Bạn chưa đăng nhập!")),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _hourlyRateController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Vui lòng nhập đầy đủ thông tin")),
      );
      return;
    }

    final uri = Uri.parse("${AppConfig.baseUrl}/api/employee");
    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          "fullName": _nameController.text.trim(),
          "email": _emailController.text.trim(),
          "hourlyRate": double.parse(_hourlyRateController.text.trim()),
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => newEmployeeId = data["employee"]["employeeId"]);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✅ Thêm nhân viên thành công, hãy quét thẻ NFC!"),
          duration: Duration(seconds: 3),
        ));

        startNfcScan(); // bắt đầu quét để gán thẻ
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi thêm nhân viên: ${res.body}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Lỗi kết nối server: $e")),
      );
    }
  }

  void startNfcScan() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("📡 Đang chờ quét thẻ NFC..."),
      duration: Duration(seconds: 5),
    ));

    await NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      try {
        final uidHex = _uidHexFromTag(tag); // ⭐ đã đảo byte
        if (uidHex == null) throw Exception('Không đọc được UID.');

        await assignNfcToEmployee(uidHex);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Đã đọc UID: $uidHex")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Lỗi NFC: $e")),
          );
        }
      } finally {
        await NfcManager.instance.stopSession();
        if (mounted) setState(() => isScanning = false);
      }
    });
  }

  Future<void> assignNfcToEmployee(String uidHex) async {
    final token = context.read<AuthState>().token;
    if (token == null || newEmployeeId == null) return;

    final uri = Uri.parse("${AppConfig.baseUrl}/api/employee/scan-nfc");
    try {
      final res = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          "employeeId": newEmployeeId,
          "nfcTagId": uidHex, // ⭐ gửi đúng format đã đảo
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
          Text("✅ Đã gán thẻ ${data['nfcTagId']} cho ${data['fullName']}"),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi gán NFC: ${res.body}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Lỗi kết nối: $e")),
      );
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Thêm nhân viên")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Họ tên"),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: _hourlyRateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Lương/giờ"),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: addEmployee,
              icon: const Icon(Icons.add),
              label: const Text("Thêm nhân viên"),
            ),
            if (isScanning)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
