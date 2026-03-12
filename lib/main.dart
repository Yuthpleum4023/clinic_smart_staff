import 'package:flutter/material.dart';

// ================================
// Screens
// ================================
import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';
import 'package:clinic_smart_staff/screens/home/home_screen.dart';
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

  // 🔥 ม่วงสด
  static const Color _purplePrimary = Color(0xFF7C3AED);

  // 💜 Lavender Background
  static const Color _bgLavender = Color(0xFFFBF7FF);

  // 🧊 Surface ขาว
  static const Color _surface = Colors.white;

  // 🟣 Outline นิ่ม
  static const Color _outlineSoft = Color(0xFFE9D5FF);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _purplePrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary: _purplePrimary,
      secondary: _purplePrimary,
      tertiary: _purplePrimary,
      surface: _surface,
      background: _bgLavender,
    );

    return MaterialApp(
      title: 'Clinic Smart Staff',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _bgLavender,
        appBarTheme: const AppBarTheme(
          backgroundColor: _surface,
          foregroundColor: Colors.black,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: _surface,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _outlineSoft, width: 1),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _outlineSoft, width: 1),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: _surface,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
        ),
        dividerTheme: const DividerThemeData(
          color: _outlineSoft,
          thickness: 1,
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF2E1065),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _purplePrimary,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _purplePrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _purplePrimary,
            side: const BorderSide(color: _purplePrimary, width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _purplePrimary,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _purplePrimary,
        ),
        checkboxTheme: const CheckboxThemeData(
          fillColor: WidgetStatePropertyAll(_purplePrimary),
          checkColor: WidgetStatePropertyAll(Colors.white),
        ),
        switchTheme: const SwitchThemeData(
          thumbColor: WidgetStatePropertyAll(_purplePrimary),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFFE9D5FF),
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