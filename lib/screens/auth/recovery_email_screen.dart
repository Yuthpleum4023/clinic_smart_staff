import 'dart:async';

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/recovery_email_api.dart';

class RecoveryEmailScreen extends StatefulWidget {
  const RecoveryEmailScreen({super.key});

  @override
  State<RecoveryEmailScreen> createState() => _RecoveryEmailScreenState();
}

class _RecoveryEmailScreenState extends State<RecoveryEmailScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  bool _verifying = false;

  String _error = '';
  String _success = '';
  String _emailMasked = '';
  bool _hasEmail = false;
  bool _phoneOnly = false;

  static const int _cooldownSeconds = 60;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();

    setState(() => _cooldownLeft = _cooldownSeconds);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_cooldownLeft <= 1) {
        timer.cancel();
        setState(() => _cooldownLeft = 0);
      } else {
        setState(() => _cooldownLeft -= 1);
      }
    });
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = '';
      _success = '';
    });

    try {
      final s = await RecoveryEmailApi.status();

      if (!mounted) return;
      setState(() {
        _hasEmail = s.hasEmail;
        _emailMasked = s.emailMasked;
        _phoneOnly = s.phoneOnly;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลดสถานะอีเมลกู้คืนไม่สำเร็จ';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _looksLikeEmail(String v) {
    final email = v.trim().toLowerCase();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  Future<void> _requestOtp() async {
    FocusScope.of(context).unfocus();

    if (_sending) return;

    final email = _emailCtrl.text.trim().toLowerCase();

    if (!_looksLikeEmail(email)) {
      setState(() => _error = 'กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }

    if (_cooldownLeft > 0) {
      _snack('รอสักครู่ ($_cooldownLeft วินาที) แล้วค่อยขอรหัสใหม่');
      return;
    }

    setState(() {
      _sending = true;
      _error = '';
      _success = '';
    });

    try {
      await RecoveryEmailApi.requestOtp(email: email);

      if (!mounted) return;
      setState(() {
        _success = 'ส่งรหัสยืนยันไปที่อีเมลแล้ว กรุณาตรวจสอบ Inbox หรือ Spam';
      });

      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final msg = e.toString();
        if (msg.contains('409')) {
          _error = 'อีเมลนี้ถูกใช้กับบัญชีอื่นแล้ว';
        } else if (msg.contains('503')) {
          _error = 'ระบบส่งอีเมลยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง';
        } else {
          _error = 'ส่งรหัสยืนยันไม่สำเร็จ กรุณาลองใหม่';
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();

    if (_verifying) return;

    final email = _emailCtrl.text.trim().toLowerCase();
    final code = _codeCtrl.text.trim();

    if (!_looksLikeEmail(email) || code.isEmpty) {
      setState(() => _error = 'กรอกอีเมลและรหัสยืนยันให้ครบ');
      return;
    }

    setState(() {
      _verifying = true;
      _error = '';
      _success = '';
    });

    try {
      final json = await RecoveryEmailApi.verifyOtp(
        email: email,
        code: code,
      );

      final masked = (json['emailMasked'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _hasEmail = true;
        _phoneOnly = false;
        _emailMasked = masked;
        _codeCtrl.clear();
        _success = 'ยืนยันอีเมลกู้คืนสำเร็จ';
      });

      _snack('บันทึกอีเมลกู้คืนแล้ว');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final msg = e.toString();
        if (msg.contains('409')) {
          _error = 'อีเมลนี้ถูกใช้กับบัญชีอื่นแล้ว';
        } else if (msg.contains('400')) {
          _error = 'รหัสยืนยันไม่ถูกต้องหรือหมดอายุ';
        } else {
          _error = 'ยืนยันอีเมลไม่สำเร็จ กรุณาลองใหม่';
        }
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cooldownText = _cooldownLeft > 0
        ? 'ขอรหัสอีกครั้ง ($_cooldownLeft)'
        : 'ส่งรหัสยืนยัน';

    return Scaffold(
      appBar: AppBar(
        title: const Text('อีเมลกู้คืนบัญชี'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'อีเมลกู้คืนบัญชี',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ใช้สำหรับรับรหัสยืนยันเมื่อลืมรหัสผ่าน '
                          'ระบบจะไม่แสดงรหัสผ่านเดิม และไม่ส่งรหัสผ่านเดิมให้ผู้ใช้',
                          style: TextStyle(height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        if (_hasEmail)
                          Row(
                            children: [
                              const Icon(Icons.verified, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ผูกอีเมลแล้ว: $_emailMasked',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'ยังไม่มีอีเมลกู้คืน หากลืมรหัสผ่านจะกู้บัญชีเองไม่ได้',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        if (_phoneOnly) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'บัญชีนี้สมัครด้วยเบอร์โทร กรุณาเพิ่มอีเมลกู้คืนเพื่อใช้ลืมรหัสผ่านในอนาคต',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'อีเมลกู้คืน',
                    hintText: 'example@email.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (_sending || _cooldownLeft > 0)
                        ? null
                        : _requestOtp,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.email_outlined),
                    label: Text(_sending ? 'กำลังส่ง...' : cooldownText),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'รหัสยืนยันจากอีเมล',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _verifying ? null : _verifyOtp,
                    icon: _verifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(_verifying ? 'กำลังยืนยัน...' : 'ยืนยันอีเมล'),
                  ),
                ),
                if (_success.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _success,
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
