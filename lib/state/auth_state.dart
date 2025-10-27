import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../widgets/config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthState extends ChangeNotifier {
  final _auth = AuthService();

  String? token;          // JWT hiện tại
  String? role;           // 'ADMIN' | 'EMPLOYEE'
  String? email;          // Email người dùng
  String? fullName;       // Họ tên nhân viên (nếu có)
  bool loading = false;   // trạng thái gọi API

  /// Tải session từ SharedPreferences khi mở app
  Future<void> loadSession() async {
    token = await _auth.getToken();
    if (token != null) {
      role = _auth.extractRoleFromToken(token!)?.toUpperCase();
      email = _auth.extractEmailFromToken(token!);
      // ✅ Nếu là nhân viên, gọi thêm để lấy tên
      if (isEmployee) await fetchProfile();
    }
    notifyListeners();
  }

  /// Đăng nhập
  Future<String?> doLogin(String email, String password) async {
    loading = true; notifyListeners();
    try {
      final res = await _auth.login(email, password);
      if (res['success'] == true) {
        token = res['token'] as String;
        role  = (res['role'] as String?)?.toUpperCase();
        this.email = res['email'];

        // ✅ Nếu là EMPLOYEE, lấy tên thật từ API /api/employee/me
        if (isEmployee && token != null) {
          await fetchProfile();
        }

        notifyListeners();
        return null;
      }
      return res['message']?.toString() ?? 'Login failed';
    } catch (e) {
      return 'Không thể đăng nhập: $e';
    } finally {
      loading = false; notifyListeners();
    }
  }

  /// Đăng ký
  Future<String?> doRegister(String email, String password, {String role = 'EMPLOYEE'}) async {
    loading = true; notifyListeners();
    try {
      final res = await _auth.register(email: email, password: password, role: role);
      if (res['success'] == true) {
        token = res['token'] as String?;
        this.role = (res['role'] as String?)?.toUpperCase();
        this.email = email;

        if (isEmployee && token != null) {
          await fetchProfile();
        }

        notifyListeners();
        return null;
      }
      return res['message']?.toString() ?? 'Register failed';
    } catch (e) {
      return 'Không thể đăng ký: $e';
    } finally {
      loading = false; notifyListeners();
    }
  }

  /// Gọi API để lấy thông tin nhân viên (FullName, Email, ...)
  Future<void> fetchProfile() async {
    if (token == null) return;
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}/api/employee/me');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      });

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        fullName = data['fullName'];
        email = data['email'];
      }
    } catch (e) {
      if (kDebugMode) print("fetchProfile error: $e");
    }
  }

  /// Đăng xuất
  Future<void> doLogout() async {
    await _auth.logout();
    token = null;
    role = null;
    email = null;
    fullName = null;
    notifyListeners();
  }

  // Helpers
  bool get isAdmin    => (role ?? '') == 'ADMIN';
  bool get isEmployee => (role ?? '') == 'EMPLOYEE';
  bool get isAuthed   => token != null;
}
