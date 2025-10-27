import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart'; // ✅ để truy cập AuthState
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

  /// ✅ Thêm nhân viên mới
  Future<void> addEmployee() async {
    final token = context.read<AuthState>().token; // ✅ Lấy token thật
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Bạn chưa đăng nhập!")),
      );
      return;
    }

    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _hourlyRateController.text.isEmpty) {
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
        setState(() {
          newEmployeeId = data["employee"]["employeeId"];
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✅ Thêm nhân viên thành công, hãy quét thẻ NFC!"),
          duration: Duration(seconds: 3),
        ));

        startNfcScan(); // ✅ Gọi quét NFC
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

  /// ✅ Bắt đầu quét thẻ NFC
  void startNfcScan() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("📡 Đang chờ quét thẻ NFC..."),
      duration: Duration(seconds: 5),
    ));

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      final nfcId = tag.data["nfca"]?["identifier"];
      if (nfcId != null) {
        final uidHex = nfcId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join("")
            .toUpperCase();

        await assignNfcToEmployee(uidHex);
        NfcManager.instance.stopSession();
        setState(() => isScanning = false);
      }
    });
  }

  /// ✅ Gán UID NFC cho nhân viên vừa thêm
  Future<void> assignNfcToEmployee(String uid) async {
    final token = context.read<AuthState>().token; // ✅ Lấy token thật
    if (token == null || newEmployeeId == null) return;

    final uri = Uri.parse("${AppConfig.baseUrl}/api/employee/scan-nfc");

    try {
      final res = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode({
          "employeeId": newEmployeeId,
          "nfcTagId": uid,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "✅ Đã gán thẻ NFC: ${data['nfcTagId']} cho ${data['fullName']}"),
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
