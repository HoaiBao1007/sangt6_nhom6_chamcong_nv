import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/auth_state.dart';
import 'screens/nfc_checkin_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthState()..loadSession(), // tải token (nếu có) nhưng KHÔNG chặn điều hướng
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
      home: const NfcCheckinScreen(), // ← MỞ TRỰC TIẾP NFC
      // LƯU Ý: KHÔNG dùng initialRoute, onGenerateInitialRoutes, hay AuthGate ở đây.
    );
  }
}
