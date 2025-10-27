import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  // ⚠️ ĐỔI IP/PORT cho đúng máy chạy API của bạn
  // Ví dụ: http://192.168.110.144:7161
  static const String base = 'http://192.168.110.226:7161';
  final String _baseUrl = '$base/api';

  Future<Map<String, dynamic>> _postJson(
      String path, {
        Object? body,
        Map<String, String>? headers,
      }) async {
    final url = Uri.parse('$_baseUrl/$path');
    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        ...?headers,
      },
      body: body is String ? jsonEncode(body) : jsonEncode(body),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return {};
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } else {
      throw Exception('API ${res.statusCode}: ${res.body}');
    }
  }

  /// Quét NFC một chạm (toggle check-in/out)
  Future<Map<String, dynamic>> tapByNfc(String nfcHexUid) async {
    // Backend nhận body là string JSON (ví dụ: "047CDC...")
    return _postJson('attendance/tap', body: nfcHexUid);
  }
}
