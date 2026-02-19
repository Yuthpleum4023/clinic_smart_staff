// lib/screens/clinic_invites_screen.dart
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
  List<Map<String, dynamic>> _invites = [];

  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
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

  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  Future<Map<String, String>> _headers() async {
    final t = await _getToken();
    if (t == null) throw Exception('no token');
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(_u('/invites'), headers: await _headers());
      if (res.statusCode != 200) {
        throw Exception('listInvites failed: ${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['invites'] as List? ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

      if (!mounted) return;
      setState(() => _invites = list);
    } catch (e) {
      _snack('โหลด invites ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final fullNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สร้าง Invite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: fullNameCtrl,
              decoration: const InputDecoration(labelText: 'ชื่อผู้ช่วย (optional)'),
            ),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
            ),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('สร้าง')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final res = await http.post(
        _u('/invites'),
        headers: await _headers(),
        body: jsonEncode({
          'fullName': fullNameCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
        }),
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('createInvite failed: ${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final inv = (data['invite'] as Map?)?.cast<String, dynamic>() ?? {};
      final code = (inv['inviteCode'] ?? '').toString().toUpperCase();

      if (code.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: code));
        _snack('สร้างสำเร็จ • คัดลอกโค้ดแล้ว: $code');
      } else {
        _snack('สร้างสำเร็จ แต่ไม่พบ inviteCode ใน response');
      }

      await _load();
    } catch (e) {
      _snack('สร้าง invite ไม่สำเร็จ: $e');
    }
  }

  Future<void> _revoke(String code) async {
    final c = code.trim().toUpperCase();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิก Invite'),
        content: Text('ต้องการ revoke โค้ด “$c” ใช่ไหม?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await http.post(_u('/invites/$c/revoke'), headers: await _headers());
      if (res.statusCode != 200) {
        throw Exception('revokeInvite failed: ${res.statusCode} ${res.body}');
      }
      _snack('Revoke สำเร็จ');
      await _load();
    } catch (e) {
      _snack('Revoke ไม่สำเร็จ: $e');
    }
  }

  String _fmt(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เชิญผู้ช่วย (Invites)'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('สร้าง Invite'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invites.isEmpty
              ? const Center(child: Text('ยังไม่มี invite'))
              : ListView.builder(
                  itemCount: _invites.length,
                  itemBuilder: (_, i) {
                    final inv = _invites[i];
                    final code = _fmt(inv['inviteCode']).toUpperCase();
                    final revoked = inv['isRevoked'] == true;
                    final usedAt = _fmt(inv['usedAt']);
                    final expiresAt = _fmt(inv['expiresAt']);

                    return Card(
                      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: ListTile(
                        title: Text(
                          code.isEmpty ? '(no code)' : code,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: revoked ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          'expiresAt: ${expiresAt.isEmpty ? '-' : expiresAt}\n'
                          'usedAt: ${usedAt.isEmpty ? '-' : usedAt}\n'
                          'revoked: $revoked',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            IconButton(
                              tooltip: 'คัดลอกโค้ด',
                              icon: const Icon(Icons.copy),
                              onPressed: code.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(ClipboardData(text: code));
                                      _snack('คัดลอกแล้ว: $code');
                                    },
                            ),
                            IconButton(
                              tooltip: 'Revoke',
                              icon: const Icon(Icons.block, color: Colors.red),
                              onPressed: revoked || code.isEmpty ? null : () => _revoke(code),
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
