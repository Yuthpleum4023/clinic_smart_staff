// lib/main.dart
import 'package:flutter/material.dart';

// ================================
// Screens
// ================================
import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';
import 'package:clinic_smart_staff/screens/home_screen.dart';
import 'package:clinic_smart_staff/screens/auth/login_screen.dart';

void main() {
  runApp(const MyApp());
}

/// ============================================================
class AppRoutes {
  static const String authGate = '/';
  static const String home = '/home';
  static const String login = '/login';

  static const String clinicGate = '/clinic-gate';
  static const String trustScore = '/trustscore';
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// ✅ ม่วงหลัก (ตัวกำหนดทั้งระบบ)
  static const Color _purplePrimary = Color(0xFF6A1B9A);

  /// ✅ พื้นหลังม่วงอ่อน
  static const Color _bgLavender = Color(0xFFF6F1FF);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _purplePrimary,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Clinic Smart Staff',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,

      theme: ThemeData(
        useMaterial3: true,

        /// ✅ ตัวล็อกสีจริง (กัน Android ฟ้า)
        colorScheme: scheme.copyWith(
          primary: _purplePrimary,
          secondary: _purplePrimary,
        ),

        primaryColor: _purplePrimary,

        scaffoldBackgroundColor: _bgLavender,

        /// ✅ AppBar ม่วงนิ่ง
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),

        /// ✅ FAB ไม่ฟ้าแน่นอน
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _purplePrimary,
          foregroundColor: Colors.white,
        ),

        /// ✅ ElevatedButton ม่วงตายตัว
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _purplePrimary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        /// ✅ OutlinedButton ขอบม่วง (กันฟ้า)
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _purplePrimary,
            side: const BorderSide(color: _purplePrimary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        /// ✅ Progress / Switch / Checkbox = ม่วง
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _purplePrimary,
        ),

        checkboxTheme: const CheckboxThemeData(
          fillColor: WidgetStatePropertyAll(_purplePrimary),
        ),

        switchTheme: const SwitchThemeData(
          thumbColor: WidgetStatePropertyAll(_purplePrimary),
          trackColor: WidgetStatePropertyAll(Color(0xFFCE93D8)),
        ),

        /// ✅ TextField โทนม่วง
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: _purplePrimary,
              width: 2,
            ),
          ),
        ),
      ),

      initialRoute: AppRoutes.authGate,

      routes: {
        AppRoutes.authGate: (_) => const AuthGateScreen(),
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.home: (_) => const HomeScreen(),

        AppRoutes.clinicGate: (_) => const _PlaceholderScreen(
              title: 'CLINIC GATE',
              subtitle: 'หน้าขอรหัสคลินิก',
            ),
        AppRoutes.trustScore: (_) => const _PlaceholderScreen(
              title: 'TRUSTSCORE',
              subtitle: 'หน้าดู TrustScore',
            ),
      },
    );
  }
}

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
      body: Center(child: Text(subtitle)),
    );
  }
}
