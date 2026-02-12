// lib/main.dart
import 'package:flutter/material.dart';

// ================================
// Screens
// ================================

// ✅ Auth Gate (router หลัก)
import 'package:clinic_payroll/screens/auth/auth_gate_screen.dart';

// ✅ Home (CLEAN version ที่คุณส่งมา)
import 'package:clinic_payroll/screens/home_screen.dart';

// (ถ้ามี login screen แยก)
import 'package:clinic_payroll/screens/auth/login_screen.dart';

// ------------------------------------------------------------
// NOTE (ARCHITECTURE)
// ------------------------------------------------------------
// - AuthGateScreen = router หลัก (ตัดสิน login / logout / redirect)
// - HomeScreen     = UI shell (Home/My tabs) ❌ ไม่ใช่ router
// - main.dart      = กำหนด named routes กลางเท่านั้น
// ------------------------------------------------------------

void main() {
  runApp(const MyApp());
}

/// ============================================================
/// ✅ Route Names (ล็อกชื่อกลาง ใช้ทั้งแอป)
/// ============================================================
class AppRoutes {
  static const String authGate = '/';
  static const String home = '/home';

  // optional / future
  static const String login = '/login';
  static const String signup = '/signup';

  static const String clinicGate = '/clinic-gate';
  static const String trustScore = '/trustscore';
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clinic Payroll',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      // ✅ เริ่มที่ AuthGate เสมอ
      initialRoute: AppRoutes.authGate,

      // ✅ ใช้ named routes เท่านั้น
      routes: {
        // -------------------------------
        // AUTH FLOW
        // -------------------------------
        AppRoutes.authGate: (_) => const AuthGateScreen(),
        AppRoutes.login: (_) => const LoginScreen(),

        // -------------------------------
        // MAIN APP
        // -------------------------------
        // ✅ Home จริง (ไม่ใช่ placeholder แล้ว)
        AppRoutes.home: (_) => const HomeScreen(),

        // -------------------------------
        // FUTURE / OPTIONAL
        // (ยังไม่ผูกจริง แต่กันแดงไว้)
        // -------------------------------
        AppRoutes.clinicGate: (_) => const _PlaceholderScreen(
              title: 'CLINIC GATE',
              subtitle: 'หน้าขอรหัสคลินิกก่อนเข้า TrustScore',
            ),
        AppRoutes.trustScore: (_) => const _PlaceholderScreen(
              title: 'TRUSTSCORE',
              subtitle: 'หน้าดู TrustScore (รอผูกหน้าจริง)',
            ),
      },
    );
  }
}

/// ============================================================
/// ✅ Placeholder (ใช้เฉพาะ route ที่ยังไม่ผูกจริง)
/// ============================================================
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PlaceholderScreen({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
