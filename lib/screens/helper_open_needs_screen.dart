// lib/screens/helper_open_needs_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

class HelperOpenNeedsScreen extends StatefulWidget {
  const HelperOpenNeedsScreen({super.key});

  @override
  State<HelperOpenNeedsScreen> createState() => _HelperOpenNeedsScreenState();
}

class _HelperOpenNeedsScreenState extends State<HelperOpenNeedsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  Future<String?> _getToken() async {
    const keys = ['jwtToken', 'token', 'authToken', 'userToken', 'jwt_token'];
    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) {
    // ✅ sanitize baseUrl กัน slash ซ้ำ
    final base = ApiConfig.payrollBaseUrl.trim().replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('no token (กรุณา login)');

      final res = await http.get(
        _u('/shift-needs/open'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('open needs failed: ${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body);
      final list = (data is Map && data['items'] is List)
          ? (data['items'] as List)
          : (data is List)
              ? data
              : [];

      final items = <Map<String, dynamic>>[];
      for (final it in list) {
        if (it is Map) items.add(Map<String, dynamic>.from(it));
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('โหลดงานว่างไม่สำเร็จ: $e');
    }
  }

  Future<void> _apply(String needId) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('no token (กรุณา login)');

      final res = await http.post(
        _u('/shift-needs/$needId/apply'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('apply failed: ${res.statusCode} ${res.body}');
      }

      _snack('สมัครงานสำเร็จ');
      await _load();
    } catch (e) {
      _snack('สมัครงานไม่สำเร็จ: $e');
    }
  }

  String _s(dynamic v) => (v ?? '').toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('งานว่างจากคลินิก (ShiftNeeds)'),
        // ✅ ไม่ hardcode Colors.blue → ใช้ Theme ม่วงเหมือนหน้าอื่น
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('ยังไม่มีงานว่าง'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final m = _items[i];

                    final id = _s(m['_id'] ?? m['id']);
                    final clinicId = _s(m['clinicId']);
                    final title = _s(m['title']);
                    final role = _s(m['role']);
                    final date = _s(m['date']);
                    final start = _s(m['start']);
                    final end = _s(m['end']);
                    final rate = _s(m['hourlyRate']);
                    final requiredCount = _s(m['requiredCount']);
                    final note = _s(m['note']);
                    final applied = m['_applied'] == true;

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isEmpty ? 'งานว่าง' : title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('คลินิก: ${clinicId.isEmpty ? '-' : clinicId}'),
                            Text('ตำแหน่ง: ${role.isEmpty ? '-' : role}'),
                            Text('วัน/เวลา: $date  $start-$end'),
                            Text('เรท: $rate บาท/ชม. • ต้องการ: $requiredCount คน'),
                            if (note.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'หมายเหตุ: $note',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              // ✅ ปุ่มหลักให้ม่วงชัด (Theme)
                              child: FilledButton.icon(
                                onPressed: (applied || id.isEmpty)
                                    ? null
                                    : () => _apply(id),
                                icon: Icon(applied ? Icons.check : Icons.send),
                                label: Text(applied ? 'สมัครแล้ว' : 'สมัครงานนี้'),
                              ),
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
