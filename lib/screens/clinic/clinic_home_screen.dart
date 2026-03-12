import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class AttendanceDashboardScreen extends StatefulWidget {
  const AttendanceDashboardScreen({super.key});

  @override
  State<AttendanceDashboardScreen> createState() =>
      _AttendanceDashboardScreenState();
}

class _AttendanceDashboardScreenState extends State<AttendanceDashboardScreen> {
  bool _loading = true;
  String _err = '';
  String _month = _currentMonthYm();

  Map<String, dynamic> _summary = <String, dynamic>{};
  List<Map<String, dynamic>> _topRiskStaff = <Map<String, dynamic>>[];

  static String _currentMonthYm() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  Uri _payrollUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return qs == null ? uri : uri.replace(queryParameters: qs);
  }

  Future<String?> _getTokenAny() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty && t != 'null') return t;
    } catch (_) {}

    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
      'auth_token',
    ];

    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response> _tryGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
  }

  String _friendlyErr(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('token') || s.contains('401')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }
    if (s.contains('403') || s.contains('forbidden')) {
      return 'คุณไม่มีสิทธิ์ดูหน้าสถิติ Attendance';
    }
    if (s.contains('timeout')) {
      return 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่';
    }
    return 'ไม่สามารถโหลดข้อมูลได้ กรุณาลองใหม่อีกครั้ง';
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String _fmtMinutes(dynamic minutes) {
    final m = _asInt(minutes);
    if (m <= 0) return '0 นาที';
    final h = m ~/ 60;
    final r = m % 60;
    if (h <= 0) return '$r นาที';
    if (r == 0) return '$h ชม.';
    return '$h ชม. $r นาที';
    }

  String _fmtRate(dynamic value) {
    final d = _asDouble(value);
    final pct = d <= 1 ? d * 100 : d;
    return '${pct.toStringAsFixed(0)}%';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        throw Exception('no token');
      }

      final headers = _authHeaders(token);

      final candidates = <String>[
        '/attendance/analytics/clinic',
        '/api/attendance/analytics/clinic',
      ];

      http.Response? lastRes;

      for (final p in candidates) {
        final uri = _payrollUri(p, qs: {'month': _month});
        final res = await _tryGet(uri, headers: headers);
        lastRes = res;

        if (res.statusCode == 404) continue;
        if (res.statusCode == 401) throw Exception('401');
        if (res.statusCode == 403) throw Exception('403');

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final map = decoded is Map<String, dynamic>
              ? decoded
              : Map<String, dynamic>.from(decoded as Map);

          final summaryAny = map['summary'];
          final topRiskAny = map['topRiskStaff'];

          final summary = summaryAny is Map
              ? Map<String, dynamic>.from(summaryAny)
              : <String, dynamic>{};

          final topRisk = topRiskAny is List
              ? topRiskAny
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];

          if (!mounted) return;
          setState(() {
            _summary = summary;
            _topRiskStaff = topRisk;
            _loading = false;
            _err = '';
          });
          return;
        }

        break;
      }

      throw Exception(
        'bad status ${lastRes?.statusCode ?? 'unknown'}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = _friendlyErr(e);
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse('$_month-01') ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'เลือกเดือนที่ต้องการดู',
      fieldHintText: 'วว/ดด/ปปปป',
    );

    if (picked == null) return;

    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final ym = '$y-$m';

    if (!mounted) return;
    setState(() {
      _month = ym;
    });

    await _load();
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required String value,
    required Color tint,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tint.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tint),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: tint,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryGrid() {
    return Column(
      children: [
        Row(
          children: [
            _statCard(
              icon: Icons.people_alt_outlined,
              title: 'Sessions ทั้งหมด',
              value: '${_asInt(_summary['totalSessions'])}',
              tint: Colors.blue,
            ),
            const SizedBox(width: 10),
            _statCard(
              icon: Icons.schedule_outlined,
              title: 'มาสาย',
              value: '${_asInt(_summary['lateCount'])}',
              tint: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard(
              icon: Icons.logout_outlined,
              title: 'ออกก่อนเวลา',
              value: '${_asInt(_summary['earlyLeaveCount'])}',
              tint: Colors.red,
            ),
            const SizedBox(width: 10),
            _statCard(
              icon: Icons.warning_amber_rounded,
              title: 'ผิดปกติ',
              value: '${_asInt(_summary['abnormalCount'])}',
              tint: Colors.deepPurple,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard(
              icon: Icons.security_outlined,
              title: 'Suspicious',
              value: '${_asInt(_summary['suspiciousCount'])}',
              tint: Colors.pink,
            ),
            const SizedBox(width: 10),
            _statCard(
              icon: Icons.verified_outlined,
              title: 'Attendance Rate',
              value: _fmtRate(_summary['attendanceRate']),
              tint: Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard(
              icon: Icons.timer_outlined,
              title: 'เวลาทำงานรวม',
              value: _fmtMinutes(_summary['totalWorkedMinutes']),
              tint: Colors.teal,
            ),
            const SizedBox(width: 10),
            _statCard(
              icon: Icons.trending_up,
              title: 'OT รวม',
              value: _fmtMinutes(_summary['totalOtMinutes']),
              tint: Colors.indigo,
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpiStrip() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('ภาพรวมเดือน $_month'),
            const SizedBox(height: 8),
            Text(
              'ใช้สำหรับดูสุขภาพ attendance ของคลินิก เช่น มาสาย ออกก่อนเวลา ความผิดปกติ และความเสี่ยงโดยรวม',
              style: TextStyle(color: Colors.grey.shade700, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topRiskList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Top Risk Staff'),
            const SizedBox(height: 10),
            if (_topRiskStaff.isEmpty)
              Text(
                'ยังไม่พบรายการเสี่ยงในเดือนนี้',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ..._topRiskStaff.map((item) {
                final pid = (item['principalId'] ?? '-').toString();
                final sessions = _asInt(item['sessions']);
                final abnormal = _asInt(item['abnormal']);
                final riskScore = _asInt(item['riskScore']);

                Color riskColor;
                if (riskScore >= 70) {
                  riskColor = Colors.red;
                } else if (riskScore >= 40) {
                  riskColor = Colors.orange;
                } else {
                  riskColor = Colors.green;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: riskColor.withOpacity(0.16)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: riskColor.withOpacity(0.14),
                        child: Icon(Icons.person, color: riskColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pid,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sessions: $sessions • Abnormal: $abnormal',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: riskColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Risk $riskScore',
                          style: TextStyle(
                            color: riskColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _insightCard() {
    final totalSessions = _asInt(_summary['totalSessions']);
    final lateCount = _asInt(_summary['lateCount']);
    final earlyLeaveCount = _asInt(_summary['earlyLeaveCount']);
    final abnormalCount = _asInt(_summary['abnormalCount']);
    final suspiciousCount = _asInt(_summary['suspiciousCount']);

    final insights = <String>[];

    if (totalSessions == 0) {
      insights.add('เดือนนี้ยังไม่มี session attendance');
    } else {
      if (lateCount > 0) {
        insights.add('มีการมาสาย $lateCount ครั้ง');
      }
      if (earlyLeaveCount > 0) {
        insights.add('มีการออกก่อนเวลา $earlyLeaveCount ครั้ง');
      }
      if (abnormalCount > 0) {
        insights.add('พบรายการผิดปกติ $abnormalCount รายการ');
      }
      if (suspiciousCount > 0) {
        insights.add('มีรายการน่าสงสัย $suspiciousCount รายการ ควรตรวจสอบเพิ่มเติม');
      }
      if (insights.isEmpty) {
        insights.add('ภาพรวม attendance ของเดือนนี้อยู่ในเกณฑ์ดี');
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Insights'),
            const SizedBox(height: 10),
            ...insights.map(
              (x) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.check_circle_outline, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        x,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ยังไม่พร้อมใช้งาน',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  _err,
                  style: TextStyle(color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: _DashboardAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Dashboard'),
        actions: [
          IconButton(
            tooltip: 'เลือกเดือน',
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _err.isNotEmpty
          ? _errorBox()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _kpiStrip(),
                  const SizedBox(height: 12),
                  _summaryGrid(),
                  const SizedBox(height: 12),
                  _insightCard(),
                  const SizedBox(height: 12),
                  _topRiskList(),
                ],
              ),
            ),
    );
  }
}

class _DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DashboardAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Attendance Dashboard'),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}