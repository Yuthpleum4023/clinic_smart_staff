import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

class TrustScoreLookupScreen extends StatefulWidget {
  const TrustScoreLookupScreen({super.key});

  @override
  State<TrustScoreLookupScreen> createState() => _TrustScoreLookupScreenState();
}

class _TrustScoreLookupScreenState extends State<TrustScoreLookupScreen> {
  final _idCtrl = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _data;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _u(String path) => Uri.parse('${ApiConfig.scoreBaseUrl}$path');

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ]) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Future<void> _fetch() async {
    final staffId = _idCtrl.text.trim();
    if (staffId.isEmpty) {
      _snack('กรอก staffId ก่อน');
      return;
    }

    setState(() {
      _loading = true;
      _data = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('no token (กรุณา login ก่อน)');
      }

      // ✅ ใช้ endpoint ที่ถูกต้องจริง
      final path = ApiConfig.staffScore(staffId); // /staff/:id/score
      final res = await http.get(
        _u(path),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      _snack('ดึง TrustScore ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _line(String k) => (_data == null) ? '-' : (_data![k] ?? '-').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TrustScore ผู้ช่วย (รายคน)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              'Score API: ${ApiConfig.scoreBaseUrl}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: 'staffId',
                border: OutlineInputBorder(),
                hintText: 'เช่น stf_xxx',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _fetch,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('ดูคะแนน'),
              ),
            ),
            const SizedBox(height: 12),
            if (_data != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'trustScore: ${_line('trustScore')}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('staffId: ${_line('staffId')}'),
                      const SizedBox(height: 6),
                      Text('totalShifts: ${_line('totalShifts')}'),
                      Text('completed: ${_line('completed')}'),
                      Text('late: ${_line('late')}'),
                      Text('cancelled: ${_line('cancelled')}'),
                      Text('noShow: ${_line('noShow')}'),
                      const SizedBox(height: 6),
                      if (_data!['badges'] != null)
                        Text('badges: ${_data!['badges']}'),
                      if (_data!['flags'] != null)
                        Text('flags: ${_data!['flags']}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
