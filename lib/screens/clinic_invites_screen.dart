// lib/screens/clinic_invites_screen.dart
//
// ✅ Clinic Invites — NO POPUP VERSION
// - ✅ เอา popup สร้าง invite ออกทั้งหมด
// - ✅ กด "สร้างโค้ดเชิญ" -> เปิดหน้าใหม่เต็มจอ
// - ✅ หลังสร้างสำเร็จ: แสดง bottom sheet สรุป + copy/share ได้
// - ✅ แชร์ผ่าน share sheet (Line / Messenger / อื่น ๆ)
// - ✅ ไม่โชว์คำเทคนิค/endpoint/field ดิบ
//
// ✅ FIX NEW:
// - แก้ปุ่ม "คัดลอกโค้ด" / "คัดลอกข้อความ" ที่เหมือนค้างใน bottom sheet
// - ใช้ root ScaffoldMessenger
// - มี busy guard กันกดซ้ำ
// - copy/share มี try/catch ครบ
//
// NOTE:
// - ต้องเพิ่ม dependency:
//   share_plus: ^10.0.2

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

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
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
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

  String _statusLabel(bool revoked, bool used) {
    if (revoked) return 'ถูกยกเลิกแล้ว';
    if (used) return 'ถูกใช้งานแล้ว';
    return 'ใช้งานได้';
  }

  String _inviteAudienceLabel({
    required String fullName,
    required String email,
    required String phone,
  }) {
    if (fullName.isNotEmpty) return fullName;
    if (phone.isNotEmpty) return phone;
    if (email.isNotEmpty) return email;
    return 'ผู้รับคำเชิญ';
  }

  String _buildShareMessage({
    required String code,
    required String role,
    required String fullName,
    required String email,
    required String phone,
  }) {
    final who = _inviteAudienceLabel(
      fullName: fullName,
      email: email,
      phone: phone,
    );

    final roleText = _roleShortLabel(role);

    final lines = <String>[
      'เชิญเข้าร่วมระบบคลินิก',
      'ประเภท: $roleText',
      'สำหรับ: $who',
      'Invite Code: ${code.toUpperCase()}',
      'กรุณาเปิดแอป แล้วกรอกรหัสเชิญนี้เพื่อเข้าร่วม',
    ];

    if (phone.isNotEmpty) {
      lines.insert(3, 'เบอร์โทร: $phone');
    }
    if (email.isNotEmpty) {
      lines.insert(phone.isNotEmpty ? 4 : 3, 'อีเมล: $email');
    }

    return lines.join('\n');
  }

  Future<void> _copyCode(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: c));
      _snack('คัดลอกโค้ดแล้ว');
    } catch (e) {
      _snack('คัดลอกโค้ดไม่สำเร็จ');
    }
  }

  Future<void> _copyMessage(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _snack('คัดลอกข้อความสำหรับส่งต่อแล้ว');
    } catch (e) {
      _snack('คัดลอกข้อความไม่สำเร็จ');
    }
  }

  Future<void> _shareInvite({
    required String code,
    required String role,
    required String fullName,
    required String email,
    required String phone,
  }) async {
    final text = _buildShareMessage(
      code: code,
      role: role,
      fullName: fullName,
      email: email,
      phone: phone,
    );
    try {
      await Share.share(text);
    } catch (e) {
      _snack('แชร์ไม่สำเร็จ');
    }
  }

  Future<void> _showInviteCreatedSheet({
    required String code,
    required String role,
    required String fullName,
    required String email,
    required String phone,
  }) async {
    final text = _buildShareMessage(
      code: code,
      role: role,
      fullName: fullName,
      email: email,
      phone: phone,
    );

    if (!mounted) return;

    final rootMessenger = ScaffoldMessenger.maybeOf(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final bottomSafe = MediaQuery.of(ctx).viewPadding.bottom;

        bool busy = false;

        Future<void> safeCopyCode(StateSetter setModalState) async {
          if (busy) return;
          setModalState(() => busy = true);
          try {
            final c = code.trim().toUpperCase();
            if (c.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: c));
            rootMessenger?.hideCurrentSnackBar();
            rootMessenger?.showSnackBar(
              const SnackBar(content: Text('คัดลอกโค้ดแล้ว')),
            );
          } catch (_) {
            rootMessenger?.hideCurrentSnackBar();
            rootMessenger?.showSnackBar(
              const SnackBar(content: Text('คัดลอกโค้ดไม่สำเร็จ')),
            );
          } finally {
            if ((ctx as Element).mounted) {
              setModalState(() => busy = false);
            }
          }
        }

        Future<void> safeCopyMessage(StateSetter setModalState) async {
          if (busy) return;
          setModalState(() => busy = true);
          try {
            await Clipboard.setData(ClipboardData(text: text));
            rootMessenger?.hideCurrentSnackBar();
            rootMessenger?.showSnackBar(
              const SnackBar(content: Text('คัดลอกข้อความสำหรับส่งต่อแล้ว')),
            );
          } catch (_) {
            rootMessenger?.hideCurrentSnackBar();
            rootMessenger?.showSnackBar(
              const SnackBar(content: Text('คัดลอกข้อความไม่สำเร็จ')),
            );
          } finally {
            if ((ctx as Element).mounted) {
              setModalState(() => busy = false);
            }
          }
        }

        Future<void> safeShare(StateSetter setModalState) async {
          if (busy) return;
          setModalState(() => busy = true);
          try {
            Navigator.of(ctx).pop();
            await Share.share(text);
          } catch (_) {
            rootMessenger?.hideCurrentSnackBar();
            rootMessenger?.showSnackBar(
              const SnackBar(content: Text('แชร์ไม่สำเร็จ')),
            );
          }
        }

        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottomSafe + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'สร้างโค้ดเชิญสำเร็จ',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Theme.of(ctx2).colorScheme.primary.withOpacity(0.08),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Invite Code',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              code.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'ข้อมูลผู้รับคำเชิญ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      _infoRow('ประเภท', _roleLabel(role)),
                      if (fullName.isNotEmpty) _infoRow('ชื่อ', fullName),
                      if (phone.isNotEmpty) _infoRow('เบอร์โทร', phone),
                      if (email.isNotEmpty) _infoRow('อีเมล', email),
                      const SizedBox(height: 14),
                      const Text(
                        'ข้อความสำหรับส่งต่อ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Theme.of(ctx2).dividerColor),
                        ),
                        child: SelectableText(text),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : () => safeCopyCode(setModalState),
                              icon: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.copy),
                              label: const Text('คัดลอกโค้ด'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : () => safeCopyMessage(setModalState),
                              icon: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.content_copy),
                              label: const Text('คัดลอกข้อความ'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => safeShare(setModalState),
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.share),
                          label: const Text('แชร์ผ่าน Line / Messenger / แอปอื่น'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

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
    } catch (_) {
      _snack('โหลดรายการเชิญไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- Create (NO POPUP) --------------------
  Future<void> _create() async {
    if (_acting) return;

    final result = await Navigator.push<_InviteCreateResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const _CreateInviteFullPage(),
      ),
    );

    if (result == null) return;

    setState(() => _acting = true);
    try {
      final res = await http.post(
        _u('/invites'),
        headers: await _headers(),
        body: jsonEncode({
          'fullName': result.fullName,
          'email': result.email,
          'phone': result.phone,
          'role': result.role,
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
      final createdRole =
          _normRole(inv['role']).isNotEmpty ? _normRole(inv['role']) : result.role;
      final createdName =
          _s(inv['fullName']).isNotEmpty ? _s(inv['fullName']) : result.fullName;
      final createdEmail =
          _s(inv['email']).isNotEmpty ? _s(inv['email']) : result.email;
      final createdPhone =
          _s(inv['phone']).isNotEmpty ? _s(inv['phone']) : result.phone;

      if (code.isEmpty) {
        _snack('สร้างสำเร็จ');
      } else {
        try {
          await Clipboard.setData(ClipboardData(text: code));
          _snack('สร้างโค้ดสำเร็จ • คัดลอกแล้ว');
        } catch (_) {
          _snack('สร้างโค้ดสำเร็จ');
        }
      }

      await _load();

      if (!mounted) return;
      if (code.isNotEmpty) {
        await _showInviteCreatedSheet(
          code: code,
          role: createdRole,
          fullName: createdName,
          email: createdEmail,
          phone: createdPhone,
        );
      }
    } catch (_) {
      _snack('สร้างโค้ดเชิญไม่สำเร็จ');
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
    } catch (_) {
      _snack('ยกเลิกโค้ดไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
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
                        Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 40,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
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
                    final createdAt = _fmtDateTime(inv['createdAt']);
                    final used = usedAt != '-';

                    final role = _normRole(inv['role']);
                    final status = _statusLabel(revoked, used);

                    final fullName = _s(inv['fullName']);
                    final email = _s(inv['email']);
                    final phone = _s(inv['phone']);

                    final canCopy = code.isNotEmpty;
                    final canRevoke = !revoked && code.isNotEmpty;
                    final canShare = code.isNotEmpty;

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
                                  _chip(
                                    _roleShortLabel(role),
                                    icon: Icons.badge_outlined,
                                  ),
                                if (expiresAt != '-') _chip('หมดอายุ: $expiresAt'),
                                if (usedAt != '-') _chip('ใช้แล้ว: $usedAt'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (fullName.isNotEmpty || phone.isNotEmpty || email.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withOpacity(0.6),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ข้อมูลผู้รับคำเชิญ',
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 6),
                                    if (fullName.isNotEmpty) _infoRow('ชื่อ', fullName),
                                    if (phone.isNotEmpty) _infoRow('เบอร์', phone),
                                    if (email.isNotEmpty) _infoRow('อีเมล', email),
                                    if (createdAt != '-') _infoRow('สร้างเมื่อ', createdAt),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: canCopy ? () => _copyCode(code) : null,
                                    icon: const Icon(Icons.copy),
                                    label: const Text('คัดลอก'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: canShare
                                        ? () => _shareInvite(
                                              code: code,
                                              role: role,
                                              fullName: fullName,
                                              email: email,
                                              phone: phone,
                                            )
                                        : null,
                                    icon: const Icon(Icons.share),
                                    label: const Text('แชร์'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: (_acting || !canRevoke)
                                        ? null
                                        : () => _revoke(code),
                                    icon: const Icon(Icons.block),
                                    label: const Text('ยกเลิก'),
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

class _InviteCreateResult {
  final String role;
  final String fullName;
  final String email;
  final String phone;

  const _InviteCreateResult({
    required this.role,
    required this.fullName,
    required this.email,
    required this.phone,
  });
}

class _CreateInviteFullPage extends StatefulWidget {
  const _CreateInviteFullPage();

  @override
  State<_CreateInviteFullPage> createState() => _CreateInviteFullPageState();
}

class _CreateInviteFullPageState extends State<_CreateInviteFullPage> {
  final fullNameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();

  String role = 'helper';
  bool saving = false;
  String errText = '';

  bool hasAny() {
    return fullNameCtrl.text.trim().isNotEmpty ||
        emailCtrl.text.trim().isNotEmpty ||
        phoneCtrl.text.trim().isNotEmpty;
  }

  String _titleForRole(String role) {
    if (role == 'helper') return 'สร้างโค้ดเชิญผู้ช่วย';
    if (role == 'employee') return 'สร้างโค้ดเชิญพนักงาน';
    return 'สร้างโค้ดเชิญ';
  }

  Future<void> submit() async {
    if (!hasAny()) {
      setState(() => errText = 'กรุณากรอกอย่างน้อย 1 ช่อง (ชื่อ/อีเมล/เบอร์)');
      return;
    }

    setState(() {
      saving = true;
      errText = '';
    });

    Navigator.pop(
      context,
      _InviteCreateResult(
        role: role,
        fullName: fullNameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    fullNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForRole(role)),
      ),
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: kb),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafe + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => role = v);
                        },
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [],
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'อีเมล (ถ้ามี)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [],
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'เบอร์โทร (ถ้ามี)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (errText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    errText,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving ? null : submit,
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('สร้าง'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}