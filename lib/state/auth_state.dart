import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthState extends ChangeNotifier {
  final _auth = AuthService();

  String? token;              // JWT hiện tại
  String? role;               // 'ADMIN' | 'EMPLOYEE'
  bool loading = false;       // trạng thái gọi API

  /// Tải session từ SharedPreferences khi mở app
  Future<void> loadSession() async {
    token = await _auth.getToken();
    if (token != null) {
      role = _auth.extractRoleFromToken(token!)?.toUpperCase();
    }
    notifyListeners();
  }

  /// Đăng nhập -> lưu token + role
  /// Trả về null nếu OK, ngược lại trả message lỗi để hiển thị
  Future<String?> doLogin(String email, String password) async {
    loading = true; notifyListeners();
    try {
      final res = await _auth.login(email, password);
      if (res['success'] == true) {
        token = res['token'] as String;
        role  = (res['role'] as String?)?.toUpperCase();
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

  /// Đăng ký -> backend không trả token nên login lại để lấy token
  Future<String?> doRegister(String email, String password, {String role = 'EMPLOYEE'}) async {
    loading = true; notifyListeners();
    try {
      final res = await _auth.register(email: email, password: password, role: role);
      if (res['success'] == true) {
        token = res['token'] as String;
        this.role = (res['role'] as String?)?.toUpperCase();
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

  /// Đăng xuất
  Future<void> doLogout() async {
    await _auth.logout();
    token = null;
    role = null;
    notifyListeners();
  }

  // Helpers
  bool get isAdmin    => (role ?? '') == 'ADMIN';
  bool get isEmployee => (role ?? '') == 'EMPLOYEE';
  bool get isAuthed   => token != null;
}
