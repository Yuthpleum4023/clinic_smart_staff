// lib/screens/auth/login_screen.dart
//
// ✅ FULL FILE (FIX "no token" after Signup)
// - เพิ่ม SharedPreferences และบันทึก token หลาย key ให้ทุกหน้าที่ดึง token ได้ตรงกัน
// - Login ใช้ AuthApi.login() (AuthApi เซฟ token เองแล้ว) แต่เรายัง "sync" key เพิ่มให้ชัวร์
// - Signup (Invite / Clinic Admin) ได้ token กลับมา -> เซฟครบทุก key แล้วไป AuthGate ได้เลย
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/auth_api.dart';
import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';
import 'package:clinic_smart_staff/screens/auth/reset_password_screen.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  Future<void> _goGate() async {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
      (_) => false,
    );
  }

  // ✅ IMPORTANT: เซฟ token ให้ครบทุกที่ที่แอปคุณอาจไปอ่าน
  Future<void> _saveToken(String token) async {
    // 1) storage หลัก
    await AuthStorage.saveToken(token);

    // 2) prefs หลาย key (รองรับหน้าที่ไปหา token หลายชื่อ)
    final prefs = await SharedPreferences.getInstance();
    const keys = ['jwtToken', 'token', 'authToken', 'userToken', 'jwt_token'];
    for (final k in keys) {
      await prefs.setString(k, token);
    }
  }

  // ✅ Sync token จาก AuthStorage -> prefs keys (กรณี login ผ่าน AuthApi.login ที่เซฟไว้แล้ว)
  Future<void> _syncTokenToPrefs() async {
    final token = await AuthStorage.getToken();
    if (token == null || token.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    const keys = ['jwtToken', 'token', 'authToken', 'userToken', 'jwt_token'];
    for (final k in keys) {
      await prefs.setString(k, token);
    }
  }

  // ===================== LOGIN (Regis → Login → Me → Home จบ) =====================
  Future<void> _doLogin() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text.trim();

    if (id.isEmpty || pw.isEmpty) {
      _snack('กรอก Email/Phone และ Password ให้ครบ');
      return;
    }

    setState(() => _loading = true);
    try {
      // ✅ ใช้ AuthApi (อย่ายิงด้วย scoreBaseUrl)
      await AuthApi.login(email: id, password: pw);

      // ✅ ทำให้มั่นใจว่า token ถูก sync ไปทุก key ที่ใช้ทั้งแอป
      await _syncTokenToPrefs();

      // ✅ ทดสอบ me ทันที เพื่อฟันธงว่ามีสิทธิ์/role และไม่ค้าง
      await AuthApi.me();

      // ✅ ไป gate ให้มันพาเข้าหน้าตาม role
      await _goGate();
    } catch (e) {
      _snack('Login ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===================== FORGOT PASSWORD =====================
  Future<void> _openForgotPasswordSheet() async {
    if (_loading) return;

    final result = await showModalBottomSheet<_ForgotResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ForgotPasswordSheet(
        initialId: _idCtrl.text.trim(),
      ),
    );

    if (!mounted) return;
    if (result == null) return;

    if (result.sentOk) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
    }
  }

  // ===================== SIGN UP: INVITE (EMPLOYEE) =====================
  Future<void> _openSignupInvite() async {
    if (_loading) return;

    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SignupInviteSheet(),
    );

    if (!mounted) return;
    if (token == null || token.isEmpty) return;

    await _saveToken(token);
    await _goGate();
  }

  // ===================== SIGN UP: CLINIC ADMIN =====================
  Future<void> _openSignupClinicAdmin() async {
    if (_loading) return;

    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SignupClinicAdminSheet(),
    );

    if (!mounted) return;
    if (token == null || token.isEmpty) return;

    await _saveToken(token);
    await _goGate();
  }

  @override
  Widget build(BuildContext context) {
    final authUrl = ApiConfig.authBaseUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('เข้าสู่ระบบ')),
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
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email หรือ Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pwCtrl,
              obscureText: true,
              onSubmitted: (_) => _doLogin(),
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading ? null : _openForgotPasswordSheet,
                child: const Text('ลืมรหัสผ่าน?'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _doLogin,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Login'),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'สมัครใช้งาน (Sign up)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _openSignupInvite,
              icon: const Icon(Icons.key),
              label: const Text('ผู้ช่วย: สมัครด้วย Invite'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : _openSignupClinicAdmin,
              icon: const Icon(Icons.local_hospital),
              label: const Text('คลินิก: สมัครเป็น Admin'),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// BottomSheet: Forgot password
// POST /forgot-password   { emailOrPhone }
// แล้วพาไปหน้า ResetPasswordScreen
// ======================================================================

class _ForgotResult {
  final bool sentOk;
  const _ForgotResult({required this.sentOk});
}

class _ForgotPasswordSheet extends StatefulWidget {
  final String initialId;
  const _ForgotPasswordSheet({required this.initialId});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _idCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.initialId);
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      _snack('กรอก Email/Phone');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await http
          .post(
            _u('/forgot-password'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'emailOrPhone': id}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('forgot-password failed: ${res.statusCode} ${res.body}');
      }

      if (!mounted) return;
      _snack('ส่งคำขอรีเซ็ตรหัสผ่านแล้ว ✅ (OTP อยู่ใน log ตอนนี้)');
      Navigator.pop(context, const _ForgotResult(sentOk: true));
    } catch (e) {
      _snack('ขอรีเซ็ตรหัสผ่านไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'ลืมรหัสผ่าน',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              labelText: 'Email หรือ Phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _send,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sms),
              label: const Text('ขอรหัส OTP'),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Sheet: Employee signup with invite  POST /register-with-invite
// คืนค่า token กลับไปที่หน้า Login
// ======================================================================

class _SignupInviteSheet extends StatefulWidget {
  const _SignupInviteSheet();

  @override
  State<_SignupInviteSheet> createState() => _SignupInviteSheetState();
}

class _SignupInviteSheetState extends State<_SignupInviteSheet> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final code = _codeCtrl.text.trim().toUpperCase();
    final pw = _pwCtrl.text.trim();

    if (code.isEmpty || pw.isEmpty) {
      _snack('กรอก Invite Code และ Password');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await http
          .post(
            _u('/register-with-invite'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'inviteCode': code,
              'password': pw,
              'fullName': _nameCtrl.text.trim(),
              'email': _emailCtrl.text.trim(),
              'phone': _phoneCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(
            'register-with-invite failed: ${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) {
        throw Exception('register response invalid');
      }

      final token = (data['token'] ?? data['jwt'] ?? '').toString();
      if (token.isEmpty) {
        _snack('สมัครสำเร็จ แต่ไม่พบ token — ให้ไป Login แทน');
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, token); // ✅ ส่ง token กลับไปหน้า Login
    } catch (e) {
      _snack('สมัครไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'ผู้ช่วย: สมัครด้วย Invite',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite Code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'ชื่อ-นามสกุล (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pwCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('สมัคร'),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Sheet: Clinic admin signup  POST /register-clinic-admin
// คืนค่า token กลับไปที่หน้า Login
// ======================================================================

class _SignupClinicAdminSheet extends StatefulWidget {
  const _SignupClinicAdminSheet();

  @override
  State<_SignupClinicAdminSheet> createState() => _SignupClinicAdminSheetState();
}

class _SignupClinicAdminSheetState extends State<_SignupClinicAdminSheet> {
  final _clinicNameCtrl = TextEditingController();
  final _adminFullNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPhoneCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _clinicNameCtrl.dispose();
    _adminFullNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPhoneCtrl.dispose();
    _adminPasswordCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final clinicName = _clinicNameCtrl.text.trim();
    final adminPassword = _adminPasswordCtrl.text.trim();

    if (clinicName.isEmpty || adminPassword.isEmpty) {
      _snack('กรอกชื่อคลินิก และรหัสผ่าน');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await http
          .post(
            _u('/register-clinic-admin'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'clinicName': clinicName,
              'adminPassword': adminPassword,
              'adminFullName': _adminFullNameCtrl.text.trim(),
              'adminEmail': _adminEmailCtrl.text.trim(),
              'adminPhone': _adminPhoneCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(
            'register-clinic-admin failed: ${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) {
        throw Exception('register response invalid');
      }

      final token = (data['token'] ?? data['jwt'] ?? '').toString();
      if (token.isEmpty) throw Exception('register ok but token missing');

      if (!mounted) return;
      Navigator.pop(context, token); // ✅ ส่ง token กลับไปหน้า Login
    } catch (e) {
      _snack('สมัครคลินิกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'คลินิก: สมัครเป็น Admin',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _clinicNameCtrl,
            decoration: const InputDecoration(
              labelText: 'ชื่อคลินิก',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adminFullNameCtrl,
            decoration: const InputDecoration(
              labelText: 'ชื่อผู้ดูแล (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adminEmailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adminPhoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adminPasswordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('สมัครคลินิก'),
            ),
          ),
        ],
      ),
    );
  }
}
