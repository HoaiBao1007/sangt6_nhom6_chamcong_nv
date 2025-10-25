import 'package:flutter/material.dart';
import 'screens/nfc_checkin_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance NFC',
      theme: ThemeData(useMaterial3: true),
      home: const NfcCheckinScreen(),
    );
  }
}
