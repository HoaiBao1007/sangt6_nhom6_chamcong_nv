import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthState extends ChangeNotifier {
  final _auth = AuthService();

  String? token;        // JWT hiện tại
  String? role;         // 'ADMIN' | 'EMPLOYEE'
  bool loading = false; // trạng thái đang gọi API

  /// Tải lại session từ SharedPreferences khi mở app
  Future<void> loadSession() async {
    token = await _auth.getToken();
    if (token != null) {
      role = _auth.extractRoleFromToken(token!)?.toUpperCase();
    }
    notifyListeners();
  }

  /// Đăng nhập -> lưu token + role, trả về null nếu OK, ngược lại trả message lỗi
  Future<String?> doLogin(String email, String password) async {
    loading = true;
    notifyListeners();

    final res = await _auth.login(email, password);

    loading = false;
    if (res['success'] == true) {
      token = res['token'] as String;
      role  = (res['role'] as String?)?.toUpperCase();
      notifyListeners();
      return null;
    }

    notifyListeners();
    return res['message']?.toString() ?? 'Login failed';
  }

  /// Đăng ký (backend không trả token) -> tự login lại để lấy token
  /// Trả về null nếu OK; nếu lỗi trả message
  Future<String?> doRegister(String email, String password, {String role = 'EMPLOYEE'}) async {
    loading = true;
    notifyListeners();

    final res = await _auth.register(email: email, password: password, role: role);

    loading = false;
    if (res['success'] == true) {
      token = res['token'] as String;
      this.role = (res['role'] as String?)?.toUpperCase();
      notifyListeners();
      return null;
    }

    notifyListeners();
    return res['message']?.toString() ?? 'Register failed';
  }

  /// Đăng xuất: xóa token và role khỏi bộ nhớ
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
