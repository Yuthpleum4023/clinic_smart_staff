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

  // ✅ สีม่วงหลักของแอป (ปรับ hex ได้ตามที่ท่านต้องการ)
  static const Color _purplePrimary = Color(0xFF6A1B9A);

  // ✅ สีพื้นหลังม่วงอ่อน (ให้ vibe เหมือนในภาพ)
  static const Color _bgLavender = Color(0xFFF6F1FF);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _purplePrimary,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Clinic Payroll',
      debugShowCheckedModeBanner: false,

      // ✅ ล็อค Light Mode กันสีเพี้ยนตอน deploy (ไม่ตาม Dark Mode เครื่อง)
      themeMode: ThemeMode.light,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,

        // ✅ พื้นหลังโดยรวม
        scaffoldBackgroundColor: _bgLavender,

        // ✅ AppBar ให้ดูสะอาด + โทนเข้ากับม่วง
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),

        // ✅ ปุ่มหลักให้ม่วงชัด (กันบางเครื่องปรับสีเอง)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _purplePrimary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),

        // ✅ TextField ให้โทนม่วง (optional แต่ช่วยให้ “ทั้งระบบ” ไปทางเดียวกัน)
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _purplePrimary, width: 2),
          ),
        ),
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
