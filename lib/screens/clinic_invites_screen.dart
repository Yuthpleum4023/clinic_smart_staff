// lib/screens/clinic_invites_screen.dart
//
// ✅ Clinic Invites (Commercial Polish Mode)
// - ✅ ไม่โชว์คำเทคนิค/endpoint/field ดิบ
// - ✅ UX ดีขึ้น: สถานะเป็นภาษาอ่านง่าย + format วันเวลา + copy/revoke ชัดเจน
// - ✅ สร้าง invite: ต้องกรอกอย่างน้อย 1 อย่าง (ชื่อ/อีเมล/เบอร์)
// - ✅ เลือกประเภท Invite ได้ (พนักงาน/ผู้ช่วย) แล้วส่ง role ไป backend
//
// ✅ FIX: แผ่นสีเหลืองบังตอนกรอก (Android Autofill overlay)
// - ✅ ปิด autofill/suggestion ในช่อง email/phone ที่ dialog
// - ✅ ทำ dialog ให้เลื่อนหลบคีย์บอร์ด: AnimatedPadding(viewInsets) + ScrollView
//
// NOTE: ใช้ http + SharedPreferences แบบเดิม (ไม่เพิ่ม package)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

class ClinicInvitesScreen extends StatefulWidget {
  const ClinicInvitesScreen({super.key});

  @override
  State<ClinicInvitesScreen> createState() => _ClinicInvitesScreenState();
}

class _ClinicInvitesScreenState extends State<ClinicInvitesScreen> {
  bool _loading = true;
  bool _acting = false;

  List<Map<String, dynamic>> _invites = [];

  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
  ];

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Uri _u(String path) {
    final base = ApiConfig.authBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<Map<String, String>> _headers() async {
    final t = await _getToken();
    if (t == null) {
      throw Exception('กรุณาเข้าสู่ระบบใหม่');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $t',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -------------------- Parsing helpers --------------------
  String _s(dynamic v) => (v ?? '').toString().trim();

  bool _truthy(dynamic v) => v == true || _s(v).toLowerCase() == 'true';

  DateTime? _tryParseDate(dynamic v) {
    final t = _s(v);
    if (t.isEmpty) return null;
    return DateTime.tryParse(t);
  }

  String _fmtDateTime(dynamic v) {
    final dt = _tryParseDate(v);
    if (dt == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}  ${two(dt.hour)}:${two(dt.minute)}';
  }

  // -------------------- Role helpers --------------------
  String _normRole(dynamic v) {
    final r = _s(v).toLowerCase();
    if (r == 'helper') return 'helper';
    if (r == 'employee') return 'employee';
    return '';
  }

  String _roleLabel(String role) {
    if (role == 'helper') return 'ผู้ช่วย (Helper)';
    if (role == 'employee') return 'พนักงาน (Employee)';
    return 'ไม่ระบุประเภท';
  }

  String _roleShortLabel(String role) {
    if (role == 'helper') return 'ผู้ช่วย';
    if (role == 'employee') return 'พนักงาน';
    return 'ไม่ระบุ';
  }

  String _dialogTitleForRole(String role) {
    if (role == 'helper') return 'สร้างโค้ดเชิญผู้ช่วย';
    if (role == 'employee') return 'สร้างโค้ดเชิญพนักงาน';
    return 'สร้างโค้ดเชิญ';
  }

  // -------------------- Load --------------------
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final res = await http.get(_u('/invites'), headers: await _headers());
      if (res.statusCode != 200) {
        throw Exception('โหลดรายการไม่สำเร็จ');
      }

      final dataAny = jsonDecode(res.body);
      final data = (dataAny is Map) ? Map<String, dynamic>.from(dataAny) : {};
      final raw = (data['invites'] as List?) ?? const [];

      final list = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() => _invites = list);
    } catch (e) {
      _snack('โหลดรายการเชิญไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- Create --------------------
  Future<void> _create() async {
    if (_acting) return;

    final fullNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    String role = 'helper'; // default ตาม flow เดิม

    bool loading = false;
    String errText = '';

    bool hasAny() {
      return fullNameCtrl.text.trim().isNotEmpty ||
          emailCtrl.text.trim().isNotEmpty ||
          phoneCtrl.text.trim().isNotEmpty;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            Future<void> submit() async {
              if (!hasAny()) {
                setSt(() => errText = 'กรุณากรอกอย่างน้อย 1 ช่อง (ชื่อ/อีเมล/เบอร์)');
                return;
              }

              setSt(() {
                loading = true;
                errText = '';
              });

              // ปิด dialog ก่อน เพื่อไม่ให้ค้างใน dialog
              Navigator.pop(ctx, true);
            }

            return AlertDialog(
              title: Text(_dialogTitleForRole(role)),
              content: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(
                          labelText: 'ประเภท Invite',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'helper',
                            child: Text('ผู้ช่วย (Helper)'),
                          ),
                          DropdownMenuItem(
                            value: 'employee',
                            child: Text('พนักงาน (Employee)'),
                          ),
                        ],
                        onChanged: loading
                            ? null
                            : (v) {
                                if (v == null) return;
                                setSt(() => role = v);
                              },
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: fullNameCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: role == 'helper'
                              ? 'ชื่อผู้ช่วย (ถ้ามี)'
                              : 'ชื่อพนักงาน (ถ้ามี)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ✅ FIX: กันแผ่นเหลือง (Autofill overlay) + suggestion
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [], // ✅ ปิด autofill
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'อีเมล (ถ้ามี)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ✅ FIX: กันแผ่นเหลือง (Autofill overlay) + suggestion
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [], // ✅ ปิด autofill
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'เบอร์โทร (ถ้ามี)',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => submit(),
                      ),

                      if (errText.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errText,
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: loading ? null : submit,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('สร้าง'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    setState(() => _acting = true);
    try {
      final res = await http.post(
        _u('/invites'),
        headers: await _headers(),
        body: jsonEncode({
          'fullName': fullNameCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'role': role, // ✅ ส่ง role ไป backend
        }),
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('สร้างไม่สำเร็จ');
      }

      final dataAny = jsonDecode(res.body);
      final data = (dataAny is Map) ? Map<String, dynamic>.from(dataAny) : {};
      final invAny = data['invite'];
      final inv = (invAny is Map) ? Map<String, dynamic>.from(invAny) : {};
      final code = _s(inv['inviteCode']).toUpperCase();

      if (code.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: code));
        _snack('สร้างโค้ดสำเร็จ • คัดลอกแล้ว');
      } else {
        _snack('สร้างสำเร็จ');
      }

      await _load();
    } catch (e) {
      _snack('สร้างโค้ดเชิญไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // -------------------- Revoke --------------------
  Future<void> _revoke(String code) async {
    if (_acting) return;

    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกโค้ดเชิญ'),
        content: Text('ต้องการยกเลิกโค้ดนี้ใช่ไหม?\n$c'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยกเลิกโค้ด'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _acting = true);
    try {
      final res = await http.post(
        _u('/invites/$c/revoke'),
        headers: await _headers(),
      );

      if (res.statusCode != 200) {
        throw Exception('ยกเลิกไม่สำเร็จ');
      }

      _snack('ยกเลิกโค้ดแล้ว');
      await _load();
    } catch (e) {
      _snack('ยกเลิกโค้ดไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _copyCode(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: c));
    _snack('คัดลอกโค้ดแล้ว');
  }

  // -------------------- UI helpers --------------------
  Widget _chip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _statusLabel(bool revoked, bool used) {
    if (revoked) return 'ถูกยกเลิกแล้ว';
    if (used) return 'ถูกใช้งานแล้ว';
    return 'ใช้งานได้';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('โค้ดเชิญ'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _acting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_loading || _acting) ? null : _create,
        icon: const Icon(Icons.add),
        label: const Text('สร้างโค้ดเชิญ'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invites.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_alt_1_outlined,
                            size: 40, color: cs.onSurface.withOpacity(0.5)),
                        const SizedBox(height: 10),
                        const Text(
                          'ยังไม่มีโค้ดเชิญ',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _acting ? null : _create,
                          icon: const Icon(Icons.add),
                          label: const Text('สร้างโค้ดแรก'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _invites.length,
                  itemBuilder: (_, i) {
                    final inv = _invites[i];

                    final code = _s(inv['inviteCode']).toUpperCase();
                    final revoked = _truthy(inv['isRevoked']);
                    final usedAt = _fmtDateTime(inv['usedAt']);
                    final expiresAt = _fmtDateTime(inv['expiresAt']);
                    final used = usedAt != '-';

                    final role = _normRole(inv['role']);
                    final status = _statusLabel(revoked, used);

                    final canCopy = code.isNotEmpty;
                    final canRevoke = !revoked && code.isNotEmpty;

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    code.isEmpty ? 'โค้ดเชิญ' : code,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (_acting)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _chip(
                                  status,
                                  icon: revoked
                                      ? Icons.block
                                      : (used ? Icons.check_circle : Icons.verified),
                                ),
                                if (role.isNotEmpty)
                                  _chip(_roleShortLabel(role), icon: Icons.badge_outlined),
                                if (expiresAt != '-') _chip('หมดอายุ: $expiresAt'),
                                if (usedAt != '-') _chip('ใช้แล้ว: $usedAt'),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: canCopy ? () => _copyCode(code) : null,
                                    icon: const Icon(Icons.copy),
                                    label: const Text('คัดลอกโค้ด'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: (_acting || !canRevoke)
                                        ? null
                                        : () => _revoke(code),
                                    icon: const Icon(Icons.block),
                                    label: const Text('ยกเลิกโค้ด'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
