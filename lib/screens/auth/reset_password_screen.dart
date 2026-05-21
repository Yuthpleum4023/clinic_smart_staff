import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/screens/auth/login_screen.dart';

// ✅ FIX: path ใหม่ของ HomeScreen
import 'package:clinic_smart_staff/screens/home/home_screen.dart';

// ✅ STORE SAFE: DebugOnly
import 'package:clinic_smart_staff/widgets/debug_only.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String initialId;

  const ResetPasswordScreen({
    super.key,
    this.initialId = '',
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _idCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  bool _loading = false;
  bool _otpLoading = false;

  static const int _cooldownSeconds = 60;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialId.trim();
    if (initial.isNotEmpty) {
      _idCtrl.text = initial;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _idCtrl.dispose();
    _codeCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  // ✅ กลับหน้า HomeScreen แบบล้าง stack
  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _goLoginSafe() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();

    setState(() => _cooldownLeft = _cooldownSeconds);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      if (_cooldownLeft <= 1) {
        t.cancel();
        setState(() => _cooldownLeft = 0);
      } else {
        setState(() => _cooldownLeft -= 1);
      }
    });
  }

  // =========================
  // ขอ OTP
  // =========================

  Future<void> _requestOtp() async {
    FocusScope.of(context).unfocus();

    if (_otpLoading) return;

    final id = _idCtrl.text.trim();

    if (id.isEmpty) {
      _snack('กรอกอีเมลหรือเบอร์โทรที่ใช้สมัครก่อน');
      return;
    }

    if (_cooldownLeft > 0) {
      _snack('รอสักครู่ ($_cooldownLeft วินาที) แล้วค่อยขอ OTP ใหม่');
      return;
    }

    setState(() => _otpLoading = true);

    try {
      final res = await http.post(
        _u('/forgot-password'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'emailOrPhone': id}),
      );

      if (res.statusCode != 200) {
        throw Exception('forgot failed: ${res.statusCode}');
      }

      _snack('หากบัญชีนี้มีอีเมลกู้คืน ระบบจะส่งรหัสยืนยันไปทางอีเมล');

      _startCooldown();
    } catch (e) {
      _snack('ขอรหัสยืนยันไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _otpLoading = false);
    }
  }

  // =========================
  // Reset password
  // =========================

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_loading) return;

    final id = _idCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final pw = _pwCtrl.text.trim();

    if (id.isEmpty || code.isEmpty || pw.isEmpty) {
      _snack('กรอกอีเมล/เบอร์โทร รหัสยืนยัน และรหัสใหม่ให้ครบ');
      return;
    }

    if (pw.length < 6) {
      _snack('รหัสใหม่ต้องอย่างน้อย 6 ตัวอักษร');
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await http.post(
        _u('/reset-password'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'emailOrPhone': id,
          'code': code,
          'newPassword': pw,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception('reset failed');
      }

      _snack('ตั้งรหัสใหม่สำเร็จ');

      _goLoginSafe();
    } catch (e) {
      _snack('Reset ไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUrl = ApiConfig.authBaseUrl;

    final otpBtnText = _cooldownLeft > 0
        ? 'ขอรหัสอีกครั้ง ($_cooldownLeft)'
        : 'ขอรหัสยืนยันทางอีเมล';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งรหัสผ่านใหม่'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: _goHome,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            DebugOnly(
              child: Text(
                'Auth: $authUrl',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'ระบบจะส่งรหัสยืนยันไปยังอีเมลกู้คืนของบัญชี '
              'หากบัญชีสมัครด้วยเบอร์อย่างเดียวและยังไม่มีอีเมล '
              'กรุณาติดต่อผู้ดูแลเพื่อผูกอีเมลก่อน',
              style: TextStyle(height: 1.35, color: Colors.black54),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: 'อีเมลหรือเบอร์โทรที่ใช้สมัคร',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    (_otpLoading || _cooldownLeft > 0) ? null : _requestOtp,
                icon: _otpLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.email_outlined),
                label: Text(otpBtnText),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'รหัสยืนยันจากอีเมล',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _pwCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'รหัสใหม่',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('ตั้งรหัสใหม่'),
              ),
            ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: (_loading || _otpLoading) ? null : _goLoginSafe,
              child: const Text('กลับไปหน้า Login'),
            ),
          ],
        ),
      ),
    );
  }
}