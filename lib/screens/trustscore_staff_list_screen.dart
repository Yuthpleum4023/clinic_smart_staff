import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

class TrustScoreStaffListScreen extends StatefulWidget {
  const TrustScoreStaffListScreen({super.key});

  @override
  State<TrustScoreStaffListScreen> createState() =>
      _TrustScoreStaffListScreenState();
}

class _TrustScoreStaffListScreenState
    extends State<TrustScoreStaffListScreen> {
  bool _loadingStaff = true;
  bool _loadingScore = false;

  List<Map<String, dynamic>> _staffList = [];
  Map<String, dynamic>? _selectedStaff;
  Map<String, dynamic>? _score;

  // --------------------------------------------------
  // helpers
  // --------------------------------------------------
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

  // --------------------------------------------------
  // load staff list
  // --------------------------------------------------
  Future<void> _loadStaff() async {
    setState(() => _loadingStaff = true);

    try {
      final token = await _getToken();
      if (token == null) throw Exception('no token');

      // ✅ สมมติ route: GET /staff
      final res = await http.get(
        _u('/staff'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body);

      final list = (data is Map && data['items'] is List)
          ? data['items']
          : (data is List ? data : []);

      _staffList = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      _snack('โหลดรายชื่อผู้ช่วยไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  // --------------------------------------------------
  // load trust score
  // --------------------------------------------------
  Future<void> _loadScore(String staffId) async {
    setState(() {
      _loadingScore = true;
      _score = null;
    });

    try {
      final token = await _getToken();
      if (token == null) throw Exception('no token');

      final path = ApiConfig.staffScore(staffId);
      final res = await http.get(
        _u(path),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('${res.statusCode} ${res.body}');
      }

      _score = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      _snack('โหลด TrustScore ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingScore = false);
    }
  }

  // --------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _v(Map<String, dynamic>? m, String k) =>
      m == null ? '-' : (m[k] ?? '-').toString();

  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrustScore ผู้ช่วย'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Score API: ${ApiConfig.scoreBaseUrl}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),

            // ---------------- staff dropdown ----------------
            _loadingStaff
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<Map<String, dynamic>>(
                    value: _selectedStaff,
                    decoration: const InputDecoration(
                      labelText: 'เลือกผู้ช่วย',
                      border: OutlineInputBorder(),
                    ),
                    items: _staffList.map((s) {
                      final name =
                          s['fullName'] ?? s['name'] ?? s['staffId'];
                      return DropdownMenuItem(
                        value: s,
                        child: Text(name.toString()),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedStaff = v);
                      final staffId = v['staffId'] ?? v['_id'];
                      if (staffId != null) {
                        _loadScore(staffId.toString());
                      }
                    },
                  ),

            const SizedBox(height: 20),

            // ---------------- score card ----------------
            if (_loadingScore)
              const Center(child: CircularProgressIndicator())
            else if (_score != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TrustScore: ${_v(_score, 'trustScore')}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('staffId: ${_v(_score, 'staffId')}'),
                      const SizedBox(height: 6),
                      Text('totalShifts: ${_v(_score, 'totalShifts')}'),
                      Text('completed: ${_v(_score, 'completed')}'),
                      Text('late: ${_v(_score, 'late')}'),
                      Text('cancelled: ${_v(_score, 'cancelled')}'),
                      Text('noShow: ${_v(_score, 'noShow')}'),
                      if (_score!['badges'] != null)
                        Text('badges: ${_score!['badges']}'),
                      if (_score!['flags'] != null)
                        Text('flags: ${_score!['flags']}'),
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
