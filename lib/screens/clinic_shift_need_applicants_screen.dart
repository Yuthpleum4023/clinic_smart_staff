import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_payroll/api/api_config.dart';

class ClinicShiftNeedApplicantsScreen extends StatefulWidget {
  final String needId;
  final String title;

  const ClinicShiftNeedApplicantsScreen({
    super.key,
    required this.needId,
    required this.title,
  });

  @override
  State<ClinicShiftNeedApplicantsScreen> createState() =>
      _ClinicShiftNeedApplicantsScreenState();
}

class _ClinicShiftNeedApplicantsScreenState
    extends State<ClinicShiftNeedApplicantsScreen> {
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

  Uri _u(String path) => Uri.parse('${ApiConfig.payrollBaseUrl}$path');

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('no token (กรุณา login)');

      final res = await http.get(
        _u('/shift-needs/${widget.needId}/applicants'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('load applicants failed: ${res.statusCode} ${res.body}');
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
      _snack('โหลดผู้สมัครไม่สำเร็จ: $e');
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
        title: Text('ผู้สมัคร: ${widget.title}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('ยังไม่มีผู้สมัคร'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final m = _items[i];

                    // ปรับ key ตามที่ backend ส่งจริง (ผมเดาแบบปลอดภัย)
                    final name = _s(m['fullName'] ?? m['name'] ?? m['helperName']);
                    final staffId = _s(m['staffId'] ?? m['assistantId'] ?? m['userId']);
                    final phone = _s(m['phone'] ?? m['tel']);
                    final note = _s(m['note']);

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(name.isEmpty ? 'ผู้ช่วย' : name),
                        subtitle: Text(
                          'staffId: ${staffId.isEmpty ? '-' : staffId}\n'
                          'โทร: ${phone.isEmpty ? '-' : phone}'
                          '${note.trim().isEmpty ? '' : '\nหมายเหตุ: $note'}',
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
