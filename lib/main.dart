import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/auth_state.dart';
import 'widgets/auth_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance NFC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const AuthGate(), // bước chốt điều hướng
    );
  }
}
