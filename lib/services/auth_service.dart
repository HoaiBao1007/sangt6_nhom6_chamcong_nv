import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decode/jwt_decode.dart';
import '../config.dart';

class AuthService {
  static const _kTokenKey = 'auth_token';

  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/api/Auth/login');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'passwordHash': password}),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final token = data['token'] as String;
      await _saveToken(token);
      final role = (data['role'] as String?)?.toUpperCase() ?? extractRoleFromToken(token);
      return {'success': true, 'token': token, 'role': role};
    }
    return {'success': false, 'message': res.body};
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String role = 'EMPLOYEE',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/api/Auth/register');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'passwordHash': password, 'role': role.toUpperCase()}),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Backend không trả token => đăng nhập ngay để lấy token
      return await login(email, password);
    }
    return {'success': false, 'message': res.body};
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kTokenKey);
  }

  Future<String?> getToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kTokenKey);
  }

  String? extractRoleFromToken(String token) {
    try {
      final payload = Jwt.parseJwt(token);
      final r = payload['role'] ??
          payload['Role'] ??
          payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'];
      return r?.toString().toUpperCase();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kTokenKey, token);
  }

  Future<http.Response> authedGet(String path) async {
    final token = await getToken();
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    return http.get(uri, headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });
  }
}
