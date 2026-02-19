// lib/screens/clinic_need_list_screen.dart
//
// ✅ Clinic Need List Screen (คลินิก/แอดมิน)
// - ดูรายการประกาศงานว่าง (ShiftNeed)
// - Filter เดือน + Filter status (open/filled/cancelled/all)
// - ยกเลิกงาน (PATCH /shift-needs/:id/cancel)
// - Generate เป็น Shift จริง (POST /shift-needs/:id/generate-shifts)
// - ใช้ Bearer token จาก SharedPreferences (หลาย key)
// - ไม่ใช้ Provider
//
// ✅ FIX 404:
// - ❌ เลิก hardcode 'https://YOUR-PAYROLL-SERVICE.onrender.com'
// - ✅ ดึง baseUrl จาก prefs ก่อน -> fallback ไป ApiConfig.payrollBaseUrl
// - ✅ sanitize baseUrl ตัด /api /payroll /shift-needs กัน path ซ้ำ
// - ✅ แสดง API ที่ใช้งานจริงบนหน้าจอ
//
// ✅ UI THEME:
// - ❌ ไม่ hardcode Colors.blue
// - ✅ ใช้ Theme (ม่วง) ให้เหมือนหน้าอื่นทั้งระบบ
//

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

class ClinicNeedListScreen extends StatefulWidget {
  final String clinicId;
  final String clinicName;

  const ClinicNeedListScreen({
    super.key,
    required this.clinicId,
    this.clinicName = '',
  });

  @override
  State<ClinicNeedListScreen> createState() => _ClinicNeedListScreenState();
}

class _ClinicNeedListScreenState extends State<ClinicNeedListScreen> {
  bool _loading = true;
  bool _acting = false;

  List<Map<String, dynamic>> _items = [];
  late DateTime _month;

  // status filter: '' = all, 'open','filled','cancelled'
  String _statusFilter = '';

  // ✅ show resolved API on UI
  String _apiBase = '';

  String _fmtMonth(DateTime d) => '${d.month}/${d.year}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _NeedApi.init(); // ✅ load baseUrl + keep in memory
      if (!mounted) return;
      setState(() => _apiBase = _NeedApi.baseUrl);
      await _load();
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 3),
      helpText: 'เลือกเดือน (เลือกวันใดก็ได้)',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month, 1));
    }
  }

  bool _isInMonth(Map<String, dynamic> n, DateTime m) {
    final date = (n['date'] ?? '').toString(); // yyyy-MM-dd
    final p = date.split('-');
    if (p.length < 2) return false;
    final y = int.tryParse(p[0]) ?? 0;
    final mo = int.tryParse(p[1]) ?? 0;
    return y == m.year && mo == m.month;
  }

  double _calcHours(String start, String end) {
    int toMin(String hhmm) {
      final p = hhmm.split(':');
      if (p.length != 2) return 0;
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      return h * 60 + m;
    }

    int diff = toMin(end) - toMin(start);
    if (diff < 0) diff += 24 * 60;
    return diff / 60.0;
  }

  Future<void> _load() async {
    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) {
      setState(() {
        _loading = false;
        _items = [];
      });
      _snack('ไม่พบ clinicId');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _NeedApi.listNeeds(
        clinicId: clinicId,
        status: _statusFilter, // '' = all
      );

      final list = (res['items'] as List?) ?? (res['data'] as List?) ?? [];
      _items = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // sort by date+start
      _items.sort((a, b) {
        final da = (a['date'] ?? '').toString();
        final sa = (a['start'] ?? '').toString();
        final db = (b['date'] ?? '').toString();
        final sb = (b['start'] ?? '').toString();
        return (da + sa).compareTo(db + sb);
      });

      if (mounted) setState(() => _apiBase = _NeedApi.baseUrl);
    } catch (e) {
      _snack('โหลดรายการไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    if (_acting) return;

    final id = (item['_id'] ?? item['id'] ?? '').toString();
    if (id.isEmpty) {
      _snack('ไม่พบ id ของงาน');
      return;
    }

    final title = (item['title'] ?? 'งาน').toString();
    final date = (item['date'] ?? '').toString();
    final start = (item['start'] ?? '').toString();
    final end = (item['end'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันยกเลิกประกาศ'),
        content: Text('ต้องการยกเลิกงานนี้ใช่ไหม?\n$title\n$date $start-$end'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่ยกเลิก'),
          ),
          // ✅ ปุ่มยืนยันเป็น primary (ม่วงตาม Theme)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยกเลิกงาน'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _acting = true);
    try {
      await _NeedApi.cancelNeed(id);
      _snack('ยกเลิกแล้ว');
      await _load();
    } catch (e) {
      _snack('ยกเลิกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _generate(Map<String, dynamic> item) async {
    if (_acting) return;

    final id = (item['_id'] ?? item['id'] ?? '').toString();
    if (id.isEmpty) {
      _snack('ไม่พบ id ของงาน');
      return;
    }

    final title = (item['title'] ?? 'งาน').toString();
    final date = (item['date'] ?? '').toString();
    final start = (item['start'] ?? '').toString();
    final end = (item['end'] ?? '').toString();

    final accepted = (item['acceptedStaffIds'] is List)
        ? (item['acceptedStaffIds'] as List).length
        : 0;

    if (accepted == 0) {
      _snack('ยังไม่มีผู้ช่วยรับงาน');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate เป็น Shift จริง'),
        content: Text(
          'ต้องการสร้าง Shift จริงจากงานนี้ใช่ไหม?\n'
          '$title\n$date $start-$end\n'
          'ผู้ช่วยที่รับแล้ว: $accepted คน\n\n'
          'หมายเหตุ: จะสร้าง 1 Shift ต่อ 1 ผู้ช่วยที่รับงาน',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          // ✅ ปุ่มยืนยันเป็น primary (ม่วงตาม Theme)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _acting = true);
    try {
      final res = await _NeedApi.generateShifts(id);
      final shifts = (res['shifts'] as List?) ?? [];
      _snack('Generate สำเร็จ: ${shifts.length} shifts');
      await _load();
    } catch (e) {
      _snack('Generate ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicLabel = widget.clinicName.trim().isEmpty
        ? widget.clinicId
        : '${widget.clinicName} (${widget.clinicId})';

    final monthItems = _items.where((e) => _isInMonth(e, _month)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('คลินิก: รายการประกาศงาน (ShiftNeed)'),
        // ✅ ไม่ hardcode สี → ใช้ Theme (ม่วง) เหมือนหน้าอื่น
        actions: [
          IconButton(
            tooltip: 'เปลี่ยนเดือน',
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'คลินิก: $clinicLabel',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),

                // ✅ show actual API
                Text(
                  'API: ${(_apiBase.isEmpty ? "(loading...)" : _apiBase)}/shift-needs',
                  style: const TextStyle(fontSize: 12),
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'เดือนที่เลือก: ${_fmtMonth(_month)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickMonth,
                      child: const Text('เปลี่ยนเดือน'),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    const Text('สถานะ: '),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('ทั้งหมด')),
                        DropdownMenuItem(value: 'open', child: Text('open')),
                        DropdownMenuItem(value: 'filled', child: Text('filled')),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('cancelled'),
                        ),
                      ],
                      onChanged: (v) async {
                        setState(() => _statusFilter = v ?? '');
                        await _load();
                      },
                    ),
                    const Spacer(),
                    if (_acting)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                if (monthItems.isEmpty)
                  const Text('ยังไม่มีประกาศงานในเดือนนี้')
                else
                  ...monthItems.map((n) {
                    final title = (n['title'] ?? 'ต้องการผู้ช่วย').toString();
                    final role = (n['role'] ?? 'ผู้ช่วย').toString();
                    final date = (n['date'] ?? '').toString();
                    final start = (n['start'] ?? '').toString();
                    final end = (n['end'] ?? '').toString();

                    final hourlyRate =
                        (n['hourlyRate'] as num?)?.toDouble() ??
                            (n['rate'] as num?)?.toDouble() ??
                            0.0;
                    final requiredCount =
                        (n['requiredCount'] as num?)?.toInt() ?? 1;

                    final accepted = (n['acceptedStaffIds'] is List)
                        ? (n['acceptedStaffIds'] as List).length
                        : 0;

                    final status = (n['status'] ?? 'open').toString();
                    final hours = _calcHours(start, end);
                    final note = (n['note'] ?? '').toString();

                    final canCancel = status != 'cancelled';
                    final canGenerate = accepted > 0 && status != 'cancelled';

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text('$date  $start-$end'),
                          subtitle: Text(
                            '$title • $role\n'
                            'เรท ${hourlyRate.toStringAsFixed(0)} บ./ชม. • ${hours.toStringAsFixed(2)} ชม.\n'
                            'รับแล้ว $accepted / ต้องการ $requiredCount • status=$status'
                            '${note.isNotEmpty ? '\nหมายเหตุ: $note' : ''}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 110,
                                // ✅ ปุ่มหลักให้เป็นม่วงชัดตาม Theme
                                child: FilledButton(
                                  onPressed: (_acting || !canGenerate)
                                      ? null
                                      : () => _generate(n),
                                  child: const Text('Generate'),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 110,
                                // ✅ OutlinedButton ขอบม่วงตาม Theme
                                child: OutlinedButton(
                                  onPressed: (_acting || !canCancel)
                                      ? null
                                      : () => _cancel(n),
                                  child: const Text('ยกเลิก'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _NeedApi {
  // ---------------------------
  // ✅ PREF KEYS
  // ---------------------------
  static const List<String> _payrollUrlKeys = [
    'payrollBaseUrl',
    'payroll_base_url',
    'PAYROLL_BASE_URL',
    'api_payroll_base_url',
  ];

  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
  ];

  // ---------------------------
  // ✅ runtime baseUrl
  // ---------------------------
  static String _baseUrl = '';
  static String get baseUrl => _baseUrl;

  static void _log(String msg) {
    if (kDebugMode) debugPrint('🧩 [NeedApi] $msg');
  }

  static Future<void> init() async {
    _baseUrl = await _getPayrollBaseUrl();
  }

  static Future<String> _getPayrollBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();

    String? raw;
    for (final k in _payrollUrlKeys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty && v != 'null') {
        raw = v.trim();
        break;
      }
    }

    raw ??= ApiConfig.payrollBaseUrl;

    var base = raw.trim();
    base = base.replaceAll(RegExp(r'\/+$'), '');

    base = _stripSuffix(base, '/api');
    base = _stripSuffix(base, '/payroll');
    base = _stripSuffix(base, '/shift-needs');
    base = _stripSuffix(base, '/shift_needs');

    _log('baseUrl(raw)=$raw');
    _log('baseUrl(sanitized)=$base');

    return base;
  }

  static String _stripSuffix(String base, String suffix) {
    if (base.toLowerCase().endsWith(suffix.toLowerCase())) {
      return base
          .substring(0, base.length - suffix.length)
          .replaceAll(RegExp(r'\/+$'), '');
    }
    return base;
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    if (token == null) throw Exception('no token (กรุณา login ก่อน)');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Uri _u(String path) {
    final b = _baseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

  static Future<Map<String, dynamic>> listNeeds({
    required String clinicId,
    String status = '',
  }) async {
    if (_baseUrl.isEmpty) await init();

    final qs = <String, String>{
      'clinicId': clinicId,
      if (status.trim().isNotEmpty) 'status': status.trim(),
    };

    final uri = _u('/shift-needs').replace(queryParameters: qs);

    _log('GET $uri');
    final res = await http.get(uri, headers: await _headers());
    _log('status=${res.statusCode} body=${res.body}');

    if (res.statusCode != 200) {
      throw Exception('listNeeds failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  static Future<Map<String, dynamic>> cancelNeed(String needId) async {
    if (_baseUrl.isEmpty) await init();

    final uri = _u('/shift-needs/$needId/cancel');
    _log('PATCH $uri');

    final res = await http.patch(uri, headers: await _headers());
    _log('status=${res.statusCode} body=${res.body}');

    if (res.statusCode != 200) {
      throw Exception('cancelNeed failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  static Future<Map<String, dynamic>> generateShifts(String needId) async {
    if (_baseUrl.isEmpty) await init();

    final uri = _u('/shift-needs/$needId/generate-shifts');
    _log('POST $uri');

    final res = await http.post(uri, headers: await _headers());
    _log('status=${res.statusCode} body=${res.body}');

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('generateShifts failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }
}
