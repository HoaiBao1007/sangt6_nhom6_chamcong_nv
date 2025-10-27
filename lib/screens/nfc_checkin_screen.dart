import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart'; // bản 3.x cần import này
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_state.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'admin_add_employee_screen.dart';
import 'admin_dashboard.dart';
class NfcCheckinScreen extends StatefulWidget {
  const NfcCheckinScreen({super.key});

  @override
  State<NfcCheckinScreen> createState() => _NfcCheckinScreenState();
}

class _NfcCheckinScreenState extends State<NfcCheckinScreen> {
  final _api = ApiClient();
  bool _isScanning = false;
  String? _lastUid;
  String? _status;

  // Nếu thẻ in UID theo MSB->LSB, bật true để đảo byte cho khớp
  static const bool REVERSE_ANDROID_BYTES = true;

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  String _bytesToHexNoColon(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  Uint8List _maybeReverse(Uint8List src) =>
      REVERSE_ANDROID_BYTES ? Uint8List.fromList(src.reversed.toList()) : src;

  /// Lấy UID qua các công nghệ (3.x: dùng platform_tags.*)
  Uint8List? _getUidFromTag(NfcTag tag) {
    final nfcA = NfcA.from(tag);
    if (nfcA?.identifier != null) return nfcA!.identifier;

    final mful = MifareUltralight.from(tag);
    if (mful?.identifier != null) return mful!.identifier;

    final mfc = MifareClassic.from(tag);
    if (mfc?.identifier != null) return mfc!.identifier;

    final isoDep = IsoDep.from(tag);
    if (isoDep?.identifier != null) return isoDep!.identifier;

    final nfcb = NfcB.from(tag);
    if (nfcb?.identifier != null) return nfcb!.identifier;

    final nfcf = NfcF.from(tag);
    if (nfcf?.identifier != null) return nfcf!.identifier;

    final nfcv = NfcV.from(tag); // ISO15693
    if (nfcv?.identifier != null) return nfcv!.identifier;

    final ndef = Ndef.from(tag);
    if (ndef?.additionalData['identifier'] is Uint8List) {
      return ndef!.additionalData['identifier'] as Uint8List;
    }

    // Fallback: một số máy map UID ở root
    final data = tag.data;
    if (data is Map && data['id'] is Uint8List) {
      return data['id'] as Uint8List;
    }
    return null;
  }

  Future<void> _startScan() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      setState(() => _status = '⚠️ NFC không khả dụng hoặc đang tắt.');
      return;
    }

    setState(() {
      _isScanning = true;
      _status = '🔄 Đang chờ thẻ... (đặt thẻ sát vùng ăng-ten)';
    });

    await NfcManager.instance.startSession(
      // 3.3.0: không cần pollingOptions
      onDiscovered: (NfcTag tag) async {
        try {
          Uint8List? uid = _getUidFromTag(tag);
          if (uid == null) throw Exception('Không đọc được UID từ thẻ.');

          uid = _maybeReverse(uid);
          final hexUid = _bytesToHexNoColon(uid);

          setState(() {
            _lastUid = hexUid;
            _status = 'UID: $hexUid – đang gửi API...';
          });

          final res = await _api.tapByNfc(hexUid);
          final action = (res['action'] ?? '').toString().toLowerCase();
          final msg = action == 'checkin'
              ? (res['message']?.toString() ?? '✅ Check-in thành công!')
              : action == 'checkout'
              ? (res['message']?.toString() ?? '✅ Check-out thành công!')
              : (res['message']?.toString() ?? '✅ Thành công.');

          if (!mounted) return;
          setState(() => _status = msg);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        } catch (e) {
          if (!mounted) return;
          setState(() => _status = '❌ Lỗi: $e');
        } finally {
          await NfcManager.instance.stopSession();
          if (mounted) setState(() => _isScanning = false);
        }
      },
    );
  }

  // ===== Nút Người dùng trên AppBar =====
  void _openUserMenu(BuildContext context) {
    final auth = context.read<AuthState>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final isAuthed = auth.isAuthed;
        final isAdmin = auth.isAdmin;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAuthed ? 'Tài khoản' : 'Người dùng',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),

              if (!isAuthed) ...[
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                  child: const Text('Đăng nhập'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen()));
                  },
                  child: const Text('Đăng ký'),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user),
                  title: Text('Role: ${auth.role ?? 'UNKNOWN'}'),
                ),

                if (isAdmin) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.analytics),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminDashboard()),
                      );
                    },
                    label: const Text('Bảng chấm công (ADMIN)'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.group_add),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminAddEmployeeScreen()),
                      );
                    },
                    label: const Text('Thêm nhân viên'),
                  ),
                ],

                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await context.read<AuthState>().doLogout();
                    if (context.mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã đăng xuất')),
                    );
                  },
                  label: const Text('Đăng xuất'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chấm công NFC'),
        actions: [
          IconButton(
            tooltip: auth.isAuthed ? 'Tài khoản' : 'Người dùng',
            icon: const Icon(Icons.person),
            onPressed: () => _openUserMenu(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.nfc),
              onPressed: _isScanning ? null : _startScan,
              label: Text(_isScanning ? 'Đang quét...' : 'Quét thẻ để Check-in/Out'),
            ),
            const SizedBox(height: 16),
            if (_lastUid != null) SelectableText('UID: $_lastUid'),
            const SizedBox(height: 8),
            if (_status != null) Text(_status!),
            const Spacer(),
            Text(
              'UID HEX ${REVERSE_ANDROID_BYTES ? "(đã đảo byte MSB←LSB)" : "(giữ nguyên Android)"} – chữ HOA, không dấu ":"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
