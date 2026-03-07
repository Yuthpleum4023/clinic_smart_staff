// lib/screens/clinic_need_list_screen.dart
//
// ✅ Clinic Need List Screen — Commercial Polish Mode (PROD CLEAN)
// - ดูรายการประกาศงานว่าง (ShiftNeed)
// - Filter เดือน + Filter สถานะ (ทั้งหมด/เปิดรับ/ปิดรับแล้ว/ยกเลิก)
// - ยกเลิกงาน (PATCH /shift-needs/:id/cancel)
// - สร้างกะงานจริง (POST /shift-needs/:id/generate-shifts)
// - ใช้ Bearer token จาก SharedPreferences (หลาย key)
// - ไม่ใช้ Provider
//
// ✅ FIX 404 (เดิม):
// - ดึง baseUrl จาก prefs ก่อน -> fallback ApiConfig.payrollBaseUrl
// - sanitize baseUrl ตัด /api /payroll /shift-needs กัน path ซ้ำ
//
// ✅ UI THEME:
// - ไม่ hardcode Colors.blue
// - ใช้ Theme (ม่วง) ให้เหมือนหน้าอื่นทั้งระบบ
//
// ✅ Commercial Polish:
// - ❌ ไม่โชว์ endpoint / clinicId / id / GET/POST/PATCH / status=open/filled/cancelled
// - ✅ ข้อความเป็นภาษา user-friendly
// - ✅ error message ไม่หลุดเทคนิค
//

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

class ClinicNeedListScreen extends StatefulWidget {
  final String clinicId; // ใช้ภายในเท่านั้น (ไม่โชว์ UI)
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

  String _fmtMonth(DateTime d) => '${d.month}/${d.year}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _NeedApi.init();
      if (!mounted) return;
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

  String _statusToLabel(String raw) {
    final s = raw.toString().trim().toLowerCase();
    if (s == 'cancelled' || s == 'canceled') return 'ยกเลิก';
    if (s == 'filled' || s == 'closed' || s == 'done') return 'ปิดรับแล้ว';
    return 'เปิดรับ';
  }

  Color _statusColor(String raw, ColorScheme cs) {
    final s = raw.toString().trim().toLowerCase();
    if (s == 'cancelled' || s == 'canceled') return Colors.red;
    if (s == 'filled' || s == 'closed' || s == 'done') return Colors.green;
    return cs.primary;
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _load() async {
    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) {
      setState(() {
        _loading = false;
        _items = [];
      });
      _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
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
    } catch (e) {
      _snack(_NeedApi.toUserMessage(e, fallback: 'โหลดรายการไม่สำเร็จ กรุณาลองใหม่'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    if (_acting) return;

    final id = (item['_id'] ?? item['id'] ?? '').toString();
    if (id.isEmpty) {
      _snack('ไม่สามารถทำรายการได้ (ข้อมูลไม่ครบ)');
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
      _snack('ยกเลิกเรียบร้อย');
      await _load();
    } catch (e) {
      _snack(_NeedApi.toUserMessage(e, fallback: 'ยกเลิกไม่สำเร็จ กรุณาลองใหม่'));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _generate(Map<String, dynamic> item) async {
    if (_acting) return;

    final id = (item['_id'] ?? item['id'] ?? '').toString();
    if (id.isEmpty) {
      _snack('ไม่สามารถทำรายการได้ (ข้อมูลไม่ครบ)');
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
      _snack('ยังไม่มีผู้ช่วยตอบรับงานนี้');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สร้างกะงานจริง'),
        content: Text(
          'ต้องการสร้างกะงานจริงจากประกาศนี้ใช่ไหม?\n'
          '$title\n$date $start-$end\n'
          'ผู้ช่วยที่ตอบรับ: $accepted คน\n\n'
          'หมายเหตุ: ระบบจะสร้างกะงานให้ผู้ช่วยแต่ละคน',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('สร้างกะงาน'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _acting = true);
    try {
      final res = await _NeedApi.generateShifts(id);
      final shifts = (res['shifts'] as List?) ?? [];
      _snack('สร้างกะงานสำเร็จ ${shifts.isEmpty ? '' : '(${shifts.length} รายการ)'}');
      await _load();
    } catch (e) {
      _snack(_NeedApi.toUserMessage(e, fallback: 'สร้างกะงานไม่สำเร็จ กรุณาลองใหม่'));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ Commercial: ไม่โชว์ clinicId
    final clinicLabel = widget.clinicName.trim().isNotEmpty
        ? widget.clinicName.trim()
        : 'คลินิกของฉัน';

    final monthItems = _items.where((e) => _isInMonth(e, _month)).toList();

    String filterLabel(String v) {
      switch (v) {
        case 'open':
          return 'เปิดรับ';
        case 'filled':
          return 'ปิดรับแล้ว';
        case 'cancelled':
          return 'ยกเลิก';
        default:
          return 'ทั้งหมด';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายการประกาศงาน'),
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
                  clinicLabel,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'เดือนที่เลือก: ${_fmtMonth(_month)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
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
                    Text(
                      'สถานะ: ',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('ทั้งหมด')),
                        DropdownMenuItem(value: 'open', child: Text('เปิดรับ')),
                        DropdownMenuItem(value: 'filled', child: Text('ปิดรับแล้ว')),
                        DropdownMenuItem(value: 'cancelled', child: Text('ยกเลิก')),
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
                  Text(
                    'ยังไม่มีประกาศงานในเดือนนี้ (${filterLabel(_statusFilter)})',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                  )
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

                    final rawStatus = (n['status'] ?? 'open').toString();
                    final statusLabel = _statusToLabel(rawStatus);
                    final statusColor = _statusColor(rawStatus, cs);

                    final hours = _calcHours(start, end);
                    final note = (n['note'] ?? '').toString().trim();

                    final isCancelled = statusLabel == 'ยกเลิก';
                    final canCancel = !isCancelled;
                    final canGenerate = accepted > 0 && !isCancelled;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$date  $start-$end',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                _chip(statusLabel, statusColor),
                              ],
                            ),
                            const SizedBox(height: 8),

                            Text(
                              '$title • $role',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withOpacity(0.85),
                              ),
                            ),
                            const SizedBox(height: 6),

                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _chip('เรท ${hourlyRate.toStringAsFixed(0)} บ./ชม.', cs.primary),
                                _chip('${hours.toStringAsFixed(2)} ชม.', cs.secondary),
                                _chip('ต้องการ $requiredCount คน', cs.primary),
                                _chip('ตอบรับ $accepted คน', cs.secondary),
                              ],
                            ),

                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                'หมายเหตุ: $note',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: (_acting || !canGenerate)
                                        ? null
                                        : () => _generate(n),
                                    icon: const Icon(Icons.playlist_add_check),
                                    label: const Text('สร้างกะงาน'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: (_acting || !canCancel)
                                        ? null
                                        : () => _cancel(n),
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('ยกเลิกประกาศ'),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
    if (token == null) throw Exception('AUTH_REQUIRED');
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
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('SERVER_ERROR:${res.statusCode}:${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  static Future<Map<String, dynamic>> cancelNeed(String needId) async {
    if (_baseUrl.isEmpty) await init();

    final uri = _u('/shift-needs/$needId/cancel');
    _log('PATCH $uri');

    final res = await http
        .patch(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('SERVER_ERROR:${res.statusCode}:${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  static Future<Map<String, dynamic>> generateShifts(String needId) async {
    if (_baseUrl.isEmpty) await init();

    final uri = _u('/shift-needs/$needId/generate-shifts');
    _log('POST $uri');

    final res = await http
        .post(uri, headers: await _headers())
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('SERVER_ERROR:${res.statusCode}:${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  /// ✅ Commercial: แปลง error ให้เป็นภาษาผู้ใช้
  static String toUserMessage(Object e, {String fallback = 'ทำรายการไม่สำเร็จ'}) {
    final raw = e.toString();
    final s = raw.toLowerCase();

    if (s.contains('auth_required') || s.contains('401') || s.contains('403')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }

    if (s.contains('timeout') || s.contains('socket') || s.contains('network')) {
      return 'เชื่อมต่อไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    }

    if (s.contains('server_error:')) {
      // ลองอ่าน message จาก body ถ้ามี
      try {
        final parts = raw.split(':');
        final body = parts.isNotEmpty ? parts.last : '';
        final decoded = jsonDecode(body);
        if (decoded is Map && (decoded['message'] != null || decoded['error'] != null)) {
          final msg = (decoded['message'] ?? decoded['error']).toString().trim();
          if (msg.isNotEmpty) return msg;
        }
      } catch (_) {}
      return 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง';
    }

    return fallback;
  }
}