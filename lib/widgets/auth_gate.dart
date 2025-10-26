import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import '../screens/login_screen.dart';
import '../screens/admin_dashboard.dart';
import '../screens/user_dashboard.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AuthState>().loadSession());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (!auth.isAuthed) return const LoginScreen();
    return auth.isAdmin ? const AdminDashboard() : const UserDashboard();
  }
}
