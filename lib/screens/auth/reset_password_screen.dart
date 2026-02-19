// lib/screens/auth/reset_password_screen.dart
//
// ✅ FIXED FULL FILE (ADD HOME BUTTON)
// - เพิ่มปุ่ม "ขอรหัส OTP" -> เรียก POST /forgot-password
// - กันกดซ้ำ + แสดงสถานะ + นับถอยหลัง resend (60s)
// - ใช้ ApiConfig.authBaseUrl เดิมของคุณ
// - Reset ใช้ POST /reset-password { emailOrPhone, code, newPassword }
// - ✅ NEW: มีปุ่ม Home กลับหน้า HomeScreen ได้ทันที (ล้าง stack)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/screens/auth/login_screen.dart';

// ✅ NEW: เพื่อกลับหน้า HomeScreen ได้ทันที
import 'package:clinic_smart_staff/screens/home_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _idCtrl = TextEditingController(); // email หรือ phone
  final _codeCtrl = TextEditingController(); // OTP 6 หลัก
  final _pwCtrl = TextEditingController(); // new password

  bool _loading = false; // ใช้กับปุ่ม reset
  bool _otpLoading = false; // ใช้กับปุ่มขอ OTP

  // resend cooldown
  static const int _cooldownSeconds = 60;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

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

  // ✅ NEW: กลับหน้า HomeScreen แบบชัวร์ (ล้าง stack)
  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _goLoginSafe() {
    // ✅ กันจอแดง: ถ้า pop ได้ก็ pop, ถ้า pop ไม่ได้ให้ replace ไป Login
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
  // ✅ ขอรหัส OTP
  // =========================
  Future<void> _requestOtp() async {
    FocusScope.of(context).unfocus();
    if (_otpLoading) return;

    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      _snack('กรอก Email หรือ Phone ก่อน');
      return;
    }
    if (_cooldownLeft > 0) {
      _snack('รอสักครู่ ($_cooldownLeft วินาที) แล้วค่อยขอ OTP ใหม่');
      return;
    }

    setState(() => _otpLoading = true);
    try {
      // POST /forgot-password { emailOrPhone }
      final res = await http.post(
        _u('/forgot-password'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'emailOrPhone': id}),
      );

      if (res.statusCode != 200) {
        throw Exception('forgot failed: ${res.statusCode} ${res.body}');
      }

      _snack('ส่งรหัส OTP แล้ว ✅ (ดูที่ backend log หรือ SMS)');
      _startCooldown();
    } catch (e) {
      _snack('ขอ OTP ไม่สำเร็จ: $e');
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

    final id = _idCtrl.text.trim(); // email หรือ phone
    final code = _codeCtrl.text.trim();
    final pw = _pwCtrl.text.trim();

    if (id.isEmpty || code.isEmpty || pw.isEmpty) {
      _snack('กรอก Email/Phone, รหัส OTP และรหัสใหม่ให้ครบ');
      return;
    }
    if (code.length < 4) {
      _snack('OTP ไม่ถูกต้อง');
      return;
    }
    if (pw.length < 4) {
      _snack('รหัสใหม่ต้องอย่างน้อย 4 ตัวอักษร');
      return;
    }

    setState(() => _loading = true);
    try {
      // POST /reset-password { emailOrPhone, code, newPassword }
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
        throw Exception('reset failed: ${res.statusCode} ${res.body}');
      }

      _snack('ตั้งรหัสใหม่สำเร็จ ✅');
      _goLoginSafe();
    } catch (e) {
      _snack('Reset ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUrl = ApiConfig.authBaseUrl;

    final otpBtnText =
        _cooldownLeft > 0 ? 'ขอรหัส OTP อีกครั้ง ($_cooldownLeft)' : 'ขอรหัส OTP';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งรหัสผ่านใหม่'),
        // ✅ NEW: ปุ่มกลับหน้า Home แบบชัวร์
        leading: IconButton(
          tooltip: 'กลับหน้า Home',
          icon: const Icon(Icons.home),
          onPressed: _goHome,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              'Auth: $authUrl',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _idCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email หรือ Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_otpLoading || _cooldownLeft > 0) ? null : _requestOtp,
                icon: _otpLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sms_outlined),
                label: Text(otpBtnText),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'รหัส OTP',
                border: OutlineInputBorder(),
                helperText: 'กด “ขอรหัส OTP” ก่อน แล้วนำรหัส 6 หลักมาใส่',
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _pwCtrl,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'รหัสใหม่',
                border: OutlineInputBorder(),
                helperText: 'อย่างน้อย 4 ตัวอักษร',
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
