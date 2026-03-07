// lib/screens/auth/login_screen.dart
//
// ✅ FULL FILE (FIX invite signup "silent" + FIX sheet overflow / yellow bar)
// - ✅ token save หลาย key
// - ✅ Signup ด้วย Invite: แสดง error/success "ในแผ่น" (ไม่ถูก bottom sheet บัง)
// - ✅ useSafeArea + SafeArea + keyboardDismissBehavior
// - ✅ _u() กัน double slash
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

  // ✅ กัน baseUrl มี / ท้าย แล้ว path มี / หน้า -> จะไม่กลายเป็น //
  Uri _u(String path) {
    final base = ApiConfig.authBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

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
    await AuthStorage.saveToken(token);

    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ];
    for (final k in keys) {
      await prefs.setString(k, token);
    }
  }

  Future<void> _syncTokenToPrefs() async {
    final token = await AuthStorage.getToken();
    if (token == null || token.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ];
    for (final k in keys) {
      await prefs.setString(k, token);
    }
  }

  // ===================== LOGIN =====================
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
      await AuthApi.login(email: id, password: pw);
      await _syncTokenToPrefs();
      await AuthApi.me();

      _snack('เข้าสู่ระบบสำเร็จ ✅');
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
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ForgotPasswordSheet(initialId: _idCtrl.text.trim(), u: _u),
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

  // ===================== SIGN UP: INVITE =====================
  Future<void> _openSignupInvite() async {
    if (_loading) return;

    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SignupInviteSheet(u: _u),
    );

    if (!mounted) return;
    if (token == null || token.isEmpty) return;

    _snack('สมัครสำเร็จ ✅ กำลังเข้าสู่ระบบ...');
    await _saveToken(token);
    await _goGate();
  }

  // ===================== SIGN UP: CLINIC ADMIN =====================
  Future<void> _openSignupClinicAdmin() async {
    if (_loading) return;

    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SignupClinicAdminSheet(u: _u),
    );

    if (!mounted) return;
    if (token == null || token.isEmpty) return;

    _snack('สมัครคลินิกสำเร็จ ✅ กำลังเข้าสู่ระบบ...');
    await _saveToken(token);
    await _goGate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เข้าสู่ระบบ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
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
// ======================================================================

class _ForgotResult {
  final bool sentOk;
  const _ForgotResult({required this.sentOk});
}

class _ForgotPasswordSheet extends StatefulWidget {
  final String initialId;
  final Uri Function(String) u;
  const _ForgotPasswordSheet({required this.initialId, required this.u});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _idCtrl;
  bool _loading = false;
  String _err = '';

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

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _err = 'กรอก Email/Phone');
      return;
    }

    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final res = await http
          .post(
            widget.u('/forgot-password'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'emailOrPhone': id}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception('ส่งไม่สำเร็จ (${res.statusCode})');
      }

      if (!mounted) return;
      Navigator.pop(context, const _ForgotResult(sentOk: true));
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'ขอรีเซ็ตรหัสผ่านไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          shrinkWrap: true,
          children: [
            const Text('ลืมรหัสผ่าน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: 'Email หรือ Phone',
                border: OutlineInputBorder(),
              ),
            ),
            if (_err.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _err,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
                label: Text(_loading ? 'กำลังส่ง...' : 'ขอรหัส OTP'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Sheet: Signup with invite  POST /register-with-invite
// ✅ FIX: ไม่ใช้ SnackBar เป็นหลัก (ถูกบัง) -> แสดง error ในแผ่น
// ======================================================================

class _SignupInviteSheet extends StatefulWidget {
  final Uri Function(String) u;
  const _SignupInviteSheet({required this.u});

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
  String _err = '';

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  String _pickMessageFromBody(String body) {
    try {
      final any = jsonDecode(body);
      if (any is Map && any['message'] != null) return any['message'].toString();
    } catch (_) {}
    return '';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final code = _codeCtrl.text.trim().toUpperCase();
    final pw = _pwCtrl.text.trim();

    if (code.isEmpty || pw.isEmpty) {
      setState(() => _err = 'กรอก Invite Code และ Password');
      return;
    }

    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final res = await http
          .post(
            widget.u('/register-with-invite'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'inviteCode': code,
              'password': pw,
              'fullName': _nameCtrl.text.trim(),
              'email': _emailCtrl.text.trim(),
              'phone': _phoneCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode != 200 && res.statusCode != 201) {
        final m = _pickMessageFromBody(res.body);
        throw Exception(m.isNotEmpty ? m : 'สมัครไม่สำเร็จ (${res.statusCode})');
      }

      final dataAny = jsonDecode(res.body);
      if (dataAny is! Map) throw Exception('รูปแบบผลลัพธ์ไม่ถูกต้อง');

      final data = Map<String, dynamic>.from(dataAny as Map);
      final token = (data['token'] ?? data['jwt'] ?? '').toString().trim();

      if (token.isEmpty) {
        throw Exception('สมัครสำเร็จ แต่ไม่พบ token');
      }

      if (!mounted) return;
      Navigator.pop(context, token); // ✅ เด้งกลับไปหน้า Login แน่นอน
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'สมัครไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pwCtrl,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),

            if (_err.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _err,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],

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
                label: Text(_loading ? 'กำลังสมัคร...' : 'สมัคร'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Sheet: Clinic admin signup  POST /register-clinic-admin
// (คงเดิม แต่ปรับให้แสดง error ในแผ่นเช่นกัน)
// ======================================================================

class _SignupClinicAdminSheet extends StatefulWidget {
  final Uri Function(String) u;
  const _SignupClinicAdminSheet({required this.u});

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
  String _err = '';

  @override
  void dispose() {
    _clinicNameCtrl.dispose();
    _adminFullNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPhoneCtrl.dispose();
    _adminPasswordCtrl.dispose();
    super.dispose();
  }

  String _pickMessageFromBody(String body) {
    try {
      final any = jsonDecode(body);
      if (any is Map && any['message'] != null) return any['message'].toString();
    } catch (_) {}
    return '';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    final clinicName = _clinicNameCtrl.text.trim();
    final adminPassword = _adminPasswordCtrl.text.trim();

    if (clinicName.isEmpty || adminPassword.isEmpty) {
      setState(() => _err = 'กรอกชื่อคลินิก และรหัสผ่าน');
      return;
    }

    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final res = await http
          .post(
            widget.u('/register-clinic-admin'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'clinicName': clinicName,
              'adminPassword': adminPassword,
              'adminFullName': _adminFullNameCtrl.text.trim(),
              'adminEmail': _adminEmailCtrl.text.trim(),
              'adminPhone': _adminPhoneCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode != 200 && res.statusCode != 201) {
        final m = _pickMessageFromBody(res.body);
        throw Exception(m.isNotEmpty ? m : 'สมัครคลินิกไม่สำเร็จ (${res.statusCode})');
      }

      final dataAny = jsonDecode(res.body);
      if (dataAny is! Map) throw Exception('รูปแบบผลลัพธ์ไม่ถูกต้อง');

      final data = Map<String, dynamic>.from(dataAny as Map);
      final token = (data['token'] ?? data['jwt'] ?? '').toString().trim();

      if (token.isEmpty) throw Exception('สมัครสำเร็จ แต่ไม่พบ token');

      if (!mounted) return;
      Navigator.pop(context, token);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'สมัครคลินิกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _adminPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _adminPasswordCtrl,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),

            if (_err.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _err,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],

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
                label: Text(_loading ? 'กำลังสมัคร...' : 'สมัครคลินิก'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}