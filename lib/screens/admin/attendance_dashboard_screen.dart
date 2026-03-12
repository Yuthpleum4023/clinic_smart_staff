import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/attendance_analytics_service.dart';

class AttendanceDashboardScreen extends StatefulWidget {
  const AttendanceDashboardScreen({super.key});

  @override
  State<AttendanceDashboardScreen> createState() =>
      _AttendanceDashboardScreenState();
}

class _AttendanceDashboardScreenState extends State<AttendanceDashboardScreen> {
  static const List<String> _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
    'auth_token',
  ];

  bool _loading = true;
  bool _refreshing = false;
  String _error = '';

  String _month = _currentMonthKey();
  String _clinicId = '';
  String _token = '';

  Map<String, dynamic> _raw = const {};
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _topRiskStaff = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  static String _currentMonthKey() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    return '${now.year}-$mm';
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      String token = '';
      for (final k in _tokenKeys) {
        final v = (prefs.getString(k) ?? '').trim();
        if (v.isNotEmpty) {
          token = v;
          break;
        }
      }

      final clinicId = (prefs.getString('app_clinic_id') ?? '').trim();

      if (!mounted) return;

      setState(() {
        _token = token;
        _clinicId = clinicId;
      });

      await _loadAnalytics(showRefreshing: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลดข้อมูลเริ่มต้นไม่สำเร็จ: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadAnalytics({required bool showRefreshing}) async {
    if (_token.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'ไม่พบ token กรุณาเข้าสู่ระบบใหม่';
        _loading = false;
        _refreshing = false;
      });
      return;
    }

    if (showRefreshing) {
      setState(() {
        _refreshing = true;
        _error = '';
      });
    } else {
      setState(() {
        _error = '';
      });
    }

    try {
      final service = AttendanceAnalyticsService(
        baseUrl: ApiConfig.payrollBaseUrl,
        token: _token,
      );

      final data = await service.fetchClinicAnalytics(_month);

      final summary = (data['summary'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(data['summary'] as Map<String, dynamic>)
          : <String, dynamic>{};

      final topRiskRaw = data['topRiskStaff'];
      final List<Map<String, dynamic>> topRisk = [];

      if (topRiskRaw is List) {
        for (final item in topRiskRaw) {
          if (item is Map<String, dynamic>) {
            topRisk.add(Map<String, dynamic>.from(item));
          } else if (item is Map) {
            topRisk.add(Map<String, dynamic>.from(item));
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _raw = Map<String, dynamic>.from(data);
        _summary = summary;
        _topRiskStaff = topRisk;
        _error = '';
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลด analytics ไม่สำเร็จ: $e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  int _intVal(String key) {
    final v = _summary[key];
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  double _doubleVal(String key) {
    final v = _summary[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('${v ?? 0}') ?? 0;
  }

  String _minutesToHourText(int minutes) {
    if (minutes <= 0) return '0 ชม.';
    final hours = minutes / 60.0;
    return '${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} ชม.';
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final initial = _parseMonth(_month) ?? DateTime(now.year, now.month);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'เลือกเดือน',
      fieldLabelText: 'เดือน',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked == null) return;

    final mm = picked.month.toString().padLeft(2, '0');
    final newMonth = '${picked.year}-$mm';

    if (!mounted) return;

    setState(() {
      _month = newMonth;
    });

    await _loadAnalytics(showRefreshing: true);
  }

  DateTime? _parseMonth(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return null;

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return null;

    return DateTime(y, m, 1);
  }

  String _monthLabel(String month) {
    final dt = _parseMonth(month);
    if (dt == null) return month;

    const months = [
      '',
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];

    return '${months[dt.month]} ${dt.year}';
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    Color? iconColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildTopRiskCard(Map<String, dynamic> item, int index) {
    final principalId = '${item['principalId'] ?? '-'}';
    final sessions = int.tryParse('${item['sessions'] ?? 0}') ?? 0;
    final riskScore = double.tryParse('${item['riskScore'] ?? 0}') ?? 0;
    final abnormal = int.tryParse('${item['abnormal'] ?? 0}') ?? 0;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text('${index + 1}'),
        ),
        title: Text(
          principalId,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'sessions: $sessions • abnormal: $abnormal',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Risk',
              style: TextStyle(fontSize: 12),
            ),
            Text(
              riskScore.toStringAsFixed(riskScore % 1 == 0 ? 0 : 1),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final totalSessions = _intVal('totalSessions');
    final lateCount = _intVal('lateCount');
    final earlyLeaveCount = _intVal('earlyLeaveCount');
    final abnormalCount = _intVal('abnormalCount');
    final suspiciousCount = _intVal('suspiciousCount');
    final totalOtMinutes = _intVal('totalOtMinutes');
    final totalWorkedMinutes = _intVal('totalWorkedMinutes');
    final attendanceRate = _doubleVal('attendanceRate');

    return RefreshIndicator(
      onRefresh: () => _loadAnalytics(showRefreshing: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เดือนที่กำลังดู',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _monthLabel(_month),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickMonth,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('เลือกเดือน'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _refreshing
                            ? null
                            : () => _loadAnalytics(showRefreshing: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('รีเฟรช'),
                      ),
                    ],
                  ),
                  if (_clinicId.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'clinicId: $_clinicId',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('ภาพรวม Attendance'),
          _summaryCard(
            icon: Icons.fact_check_outlined,
            title: 'จำนวน Session ทั้งหมด',
            value: '$totalSessions',
            subtitle: 'รวม session attendance ในเดือนนี้',
          ),
          _summaryCard(
            icon: Icons.access_time,
            title: 'มาสาย',
            value: '$lateCount',
            subtitle: 'จำนวนครั้งที่ lateMinutes มากกว่า 0',
            iconColor: Colors.orange,
          ),
          _summaryCard(
            icon: Icons.logout,
            title: 'กลับก่อนเวลา',
            value: '$earlyLeaveCount',
            subtitle: 'จำนวนครั้งที่ leftEarly เป็นจริง',
            iconColor: Colors.deepOrange,
          ),
          _summaryCard(
            icon: Icons.warning_amber_rounded,
            title: 'Abnormal',
            value: '$abnormalCount',
            subtitle: 'จำนวน session ที่ระบบมองว่าผิดปกติ',
            iconColor: Colors.red,
          ),
          _summaryCard(
            icon: Icons.gpp_maybe_outlined,
            title: 'Suspicious',
            value: '$suspiciousCount',
            subtitle: 'จำนวน session ที่มี suspiciousFlags',
            iconColor: Colors.purple,
          ),
          _summaryCard(
            icon: Icons.timer_outlined,
            title: 'OT รวม',
            value: _minutesToHourText(totalOtMinutes),
            subtitle: '$totalOtMinutes นาที',
            iconColor: Colors.blue,
          ),
          _summaryCard(
            icon: Icons.work_history_outlined,
            title: 'เวลาทำงานรวม',
            value: _minutesToHourText(totalWorkedMinutes),
            subtitle: '$totalWorkedMinutes นาที',
            iconColor: Colors.green,
          ),
          _summaryCard(
            icon: Icons.verified_outlined,
            title: 'Attendance Rate',
            value: '${(attendanceRate * 100).toStringAsFixed(0)}%',
            subtitle: 'คำนวณจาก (totalSessions - abnormalCount) / totalSessions',
            iconColor: Colors.teal,
          ),
          const SizedBox(height: 12),
          _sectionTitle('Top Risk Staff'),
          if (_topRiskStaff.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _loading
                      ? 'กำลังโหลดข้อมูล...'
                      : 'ยังไม่มีข้อมูลพนักงานที่มีความเสี่ยงในเดือนนี้',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            ...List.generate(
              _topRiskStaff.length,
              (index) => _buildTopRiskCard(_topRiskStaff[index], index),
            ),
          if (_raw.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'โหลดข้อมูลสำเร็จ',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Dashboard'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _refreshing
                ? null
                : () => _loadAnalytics(showRefreshing: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'เกิดข้อผิดพลาด',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(_error),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: _bootstrap,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('ลองใหม่'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _pickMonth,
                                  icon: const Icon(Icons.calendar_month),
                                  label: const Text('เปลี่ยนเดือน'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Stack(
                  children: [
                    _buildBody(),
                    if (_refreshing)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
    );
  }
}