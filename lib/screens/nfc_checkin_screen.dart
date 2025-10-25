import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart'; // dùng với nfc_manager 3.x
import '../services/api_client.dart';

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

  // Đảo byte để trùng thứ tự in trên thẻ (MSB -> LSB)
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

  /// Lấy UID qua các công nghệ tag khác nhau
  Uint8List? _getUidFromTag(NfcTag tag) {
    final nfcA = NfcA.from(tag);
    if (nfcA?.identifier != null) return nfcA!.identifier;

    final mful = MifareUltralight.from(tag);
    if (mful?.identifier != null) return mful!.identifier;

    final mfc = MifareClassic.from(tag);
    if (mfc?.identifier != null) return mfc!.identifier;

    final isoDep = IsoDep.from(tag);
    if (isoDep?.identifier != null) return isoDep!.identifier;

    final nfcV = NfcV.from(tag); // ISO15693
    if (nfcV?.identifier != null) return nfcV!.identifier;

    final nfcF = NfcF.from(tag); // FeliCa
    if (nfcF?.identifier != null) return nfcF!.identifier;

    final ndef = Ndef.from(tag);
    if (ndef?.additionalData['identifier'] is Uint8List) {
      return ndef!.additionalData['identifier'] as Uint8List;
    }

    final data = tag.data;
    if (data is Map && data['id'] is Uint8List) {
      return data['id'] as Uint8List;
    }

    return null;
  }

  Future<void> _startScan() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      setState(() => _status = '⚠️ NFC không khả dụng hoặc đang tắt. Vào Cài đặt > NFC để bật.');
      return;
    }

    setState(() {
      _isScanning = true;
      _status = '🔄 Đang chờ thẻ... (hãy đưa thẻ sát vùng ăng-ten máy)';
    });

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          Uint8List? uid = _getUidFromTag(tag);
          if (uid == null) throw Exception('Không đọc được UID từ thẻ.');

          uid = _maybeReverse(uid);
          final hexUid = _bytesToHexNoColon(uid);

          setState(() {
            _lastUid = hexUid;
            _status = 'Đã đọc UID: $hexUid – đang gửi API...';
          });

          final res = await _api.tapByNfc(hexUid);

          final action = (res['action'] ?? '').toString().toLowerCase();
          String msg;
          if (action == 'checkin') {
            msg = res['message']?.toString() ?? '✅ Check-in thành công!';
          } else if (action == 'checkout') {
            msg = res['message']?.toString() ?? '✅ Check-out thành công!';
          } else {
            msg = '✅ Thành công.';
          }

          setState(() => _status = msg);

          // Thêm Snackbar cho trực quan
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        } catch (e) {
          setState(() => _status = '❌ Lỗi: $e');
        } finally {
          await NfcManager.instance.stopSession();
          setState(() => _isScanning = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chấm công NFC')),
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
              'UID HEX ${REVERSE_ANDROID_BYTES ? "(đã đảo byte MSB←LSB)" : "(giữ nguyên Android)"} – chữ HOA, không có dấu ":"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
