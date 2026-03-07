// lib/screens/clinic/clinic_availabilities_screen.dart
//
// ✅ Clinic screen: ดู “ตารางว่างผู้ช่วย” + ✅ จองแล้วค้างไว้ + ✅ เคลียร์ได้
// - Tab 1: ว่าง (open)  -> GET /availabilities/open
// - Tab 2: จองแล้ว (booked) -> GET /availabilities/booked
// - จอง -> POST /availabilities/:id/book
// - เคลียร์ -> POST /availabilities/:id/clear
//
// REQUIRE:
// - ApiConfig.payrollBaseUrl
// - AuthStorage.getToken()
// - Availability.fromJson(Map<String,dynamic>)  (ใน availability_model.dart)
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

import 'package:clinic_smart_staff/models/availability_model.dart';

class ClinicAvailabilitiesScreen extends StatefulWidget {
  const ClinicAvailabilitiesScreen({super.key});

  @override
  State<ClinicAvailabilitiesScreen> createState() =>
      _ClinicAvailabilitiesScreenState();
}

class _ClinicAvailabilitiesScreenState extends State<ClinicAvailabilitiesScreen>
    with SingleTickerProviderStateMixin {
  // ----------------------------
  // State
  // ----------------------------
  bool _openLoading = true;
  bool _bookedLoading = true;

  String _openErr = '';
  String _bookedErr = '';

  List<Availability> _openItems = [];
  List<Availability> _bookedItems = [];

  // กันกดรัวต่อรายการ
  final Map<String, bool> _booking = {};
  final Map<String, bool> _clearing = {};

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ----------------------------
  // UI helpers
  // ----------------------------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _s(String v) => v.trim().isEmpty ? '-' : v.trim();

  // ----------------------------
  // Auth + JSON
  // ----------------------------
  Future<String> _needToken() async {
    final token = await AuthStorage.getToken();
    if (token == null || token.trim().isEmpty || token.trim() == 'null') {
      throw Exception('no token (โปรด login ใหม่)');
    }
    return token.trim();
  }

  Future<Map<String, dynamic>> _decodeJsonSafe(String body) async {
    try {
      final x = jsonDecode(body);
      if (x is Map) return x.cast<String, dynamic>();
      return <String, dynamic>{'data': x};
    } catch (_) {
      return <String, dynamic>{'raw': body};
    }
  }

  List<Availability> _parseAvailabilityList(dynamic itemsRaw) {
    if (itemsRaw is! List) return <Availability>[];
    final out = <Availability>[];
    for (final it in itemsRaw) {
      if (it is Map) {
        final m = it.cast<String, dynamic>();
        try {
          out.add(Availability.fromJson(m));
        } catch (_) {
          // ถ้า model ของท่าน strict มาก ให้ข้ามรายการที่ parse ไม่ได้ (กันทั้งหน้าพัง)
        }
      }
    }
    return out;
  }

  // ----------------------------
  // API Calls
  // ----------------------------
  Future<List<Availability>> _fetchList(String path) async {
    final token = await _needToken();
    final url = Uri.parse('${ApiConfig.payrollBaseUrl}$path');

    final resp = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final m = await _decodeJsonSafe(resp.body);
      final msg = (m['message'] ?? m['error'] ?? resp.body).toString();
      throw Exception('HTTP ${resp.statusCode} • $msg');
    }

    final m = await _decodeJsonSafe(resp.body);
    final items = m['items'];
    return _parseAvailabilityList(items);
  }

  Future<void> _loadOpen() async {
    if (!mounted) return;
    setState(() {
      _openLoading = true;
      _openErr = '';
      _openItems = [];
    });

    try {
      final list = await _fetchList('/availabilities/open');
      list.sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        return a.start.compareTo(b.start);
      });

      if (!mounted) return;
      setState(() {
        _openItems = list;
        _openLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openErr = e.toString();
        _openLoading = false;
      });
      _snack('โหลดตารางว่างไม่สำเร็จ: $e');
    }
  }

  Future<void> _loadBooked() async {
    if (!mounted) return;
    setState(() {
      _bookedLoading = true;
      _bookedErr = '';
      _bookedItems = [];
    });

    try {
      final list = await _fetchList('/availabilities/booked');
      list.sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        return a.start.compareTo(b.start);
      });

      if (!mounted) return;
      setState(() {
        _bookedItems = list;
        _bookedLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookedErr = e.toString();
        _bookedLoading = false;
      });
      _snack('โหลดรายการจองแล้วไม่สำเร็จ: $e');
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadOpen(),
      _loadBooked(),
    ]);
  }

  // ----------------------------
  // Status helpers
  // ----------------------------
  bool _isOpen(Availability a) {
    final st = a.status.toLowerCase().trim();
    return st.isEmpty || st == 'open';
  }

  bool _isBooked(Availability a) {
    final st = a.status.toLowerCase().trim();
    return st == 'booked';
  }

  String _statusLabel(Availability a) {
    final st = a.status.toLowerCase().trim();
    if (st.isEmpty || st == 'open') return 'ว่าง';
    if (st == 'booked') return 'จองแล้ว';
    if (st == 'cancelled' || st == 'canceled') return 'ยกเลิก';
    return a.status.trim().isEmpty ? '-' : a.status.trim();
  }

  Color _statusTextColor(Availability a) {
    final st = a.status.toLowerCase().trim();
    if (st.isEmpty || st == 'open') return Colors.green.shade700;
    if (st == 'booked') return Colors.blue.shade700;
    if (st == 'cancelled' || st == 'canceled') return Colors.red.shade700;
    return Colors.grey.shade700;
  }

  Color _statusBgColor(Availability a) {
    final st = a.status.toLowerCase().trim();
    if (st.isEmpty || st == 'open') return Colors.green.withOpacity(0.12);
    if (st == 'booked') return Colors.blue.withOpacity(0.12);
    if (st == 'cancelled' || st == 'canceled') return Colors.red.withOpacity(0.12);
    return Colors.grey.withOpacity(0.12);
  }

  // ----------------------------
  // BOOK
  // ----------------------------
  Future<void> _bookAvailability(Availability a) async {
    final id = a.id.trim();
    if (id.isEmpty) {
      _snack('❌ รายการนี้ไม่มี id จากระบบ');
      return;
    }
    if (_booking[id] == true) return;

    if (!_isOpen(a)) {
      _snack('รายการนี้ไม่ใช่สถานะ "ว่าง" แล้ว');
      return;
    }

    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการจองผู้ช่วย?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('วันที่ ${_s(a.date)}'),
            Text('เวลา ${_s(a.start)}-${_s(a.end)}'),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุถึงผู้ช่วย (ไม่บังคับ)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check),
            label: const Text('ยืนยันจอง'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _booking[id] = true);

    try {
      final token = await _needToken();
      final url = Uri.parse('${ApiConfig.payrollBaseUrl}/availabilities/$id/book');

      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'note': noteCtrl.text.trim(),
        }),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _snack('✅ จองสำเร็จ');
        // หลังจอง: refresh ทั้งสองแท็บ เพื่อให้ "จองแล้ว" โผล่ค้าง
        await _loadAll();
        // เด้งไปแท็บ "จองแล้ว" ให้เลย (UX ดีขึ้น)
        if (mounted) _tab.animateTo(1);
        return;
      }

      final m = await _decodeJsonSafe(resp.body);
      final msg = (m['message'] ?? m['error'] ?? resp.body).toString();
      throw Exception('จองไม่สำเร็จ: HTTP ${resp.statusCode} • $msg');
    } catch (e) {
      _snack('❌ $e');
    } finally {
      if (mounted) setState(() => _booking[id] = false);
    }
  }

  // ----------------------------
  // CLEAR (clinic)
  // ----------------------------
  Future<void> _clearAvailability(Availability a) async {
    final id = a.id.trim();
    if (id.isEmpty) {
      _snack('❌ รายการนี้ไม่มี id จากระบบ');
      return;
    }
    if (_clearing[id] == true) return;

    // ต้องเป็น booked ถึงจะ clear
    if (!_isBooked(a)) {
      _snack('รายการนี้ไม่ใช่สถานะ "จองแล้ว"');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เคลียร์รายการจองแล้ว?'),
        content: const Text(
          'การเคลียร์จะทำให้รายการนี้ "ไม่ค้างในจองแล้ว" อีกต่อไป (ใช้สำหรับปิดงาน/ปิดเคส)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.done_all),
            label: const Text('เคลียร์'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _clearing[id] = true);

    try {
      final token = await _needToken();
      final url = Uri.parse('${ApiConfig.payrollBaseUrl}/availabilities/$id/clear');

      final resp = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _snack('✅ เคลียร์แล้ว');
        await _loadAll();
        return;
      }

      final m = await _decodeJsonSafe(resp.body);
      final msg = (m['message'] ?? m['error'] ?? resp.body).toString();
      throw Exception('เคลียร์ไม่สำเร็จ: HTTP ${resp.statusCode} • $msg');
    } catch (e) {
      _snack('❌ $e');
    } finally {
      if (mounted) setState(() => _clearing[id] = false);
    }
  }

  // ----------------------------
  // UI builders
  // ----------------------------
  Widget _emptyList(String msg) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(
            msg,
            style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
          ),
        ),
      ],
    );
  }

  Widget _errorBox(String err, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'เกิดข้อผิดพลาด',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(err, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Availability a, {required bool showActionsOpen, required bool showActionsBooked}) {
    final cs = Theme.of(context).colorScheme;

    final id = a.id.trim();
    final isBooking = _booking[id] == true;
    final isClearing = _clearing[id] == true;

    final title = '${_s(a.date)} • ${_s(a.start)}-${_s(a.end)}';
    final subtitle = [
      _s(a.fullName),
      if (a.phone.trim().isNotEmpty) _s(a.phone),
    ].join(' • ');

    final roleLine = a.role.trim().isEmpty ? '' : _s(a.role);
    final noteLine = a.note.trim().isEmpty ? '' : 'หมายเหตุ: ${_s(a.note)}';

    // optional fields (ถ้ามีใน model)
    final bookedNote = (a.bookedNote ?? '').toString().trim();
    final shiftId = (a.shiftId ?? '').toString().trim();
    final rate = (a.bookedHourlyRate ?? 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: cs.primary.withOpacity(0.12),
            child: Icon(Icons.event_available, color: cs.primary),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(subtitle),

              if (roleLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(roleLine, style: TextStyle(color: cs.onSurface.withOpacity(0.75))),
              ],
              if (noteLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(noteLine, style: TextStyle(color: cs.onSurface.withOpacity(0.75))),
              ],

              // ✅ แสดงข้อมูลฝั่ง booking (เฉพาะแท็บจองแล้ว)
              if (showActionsBooked) ...[
                if (bookedNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('ข้อความตอนจอง: ${_s(bookedNote)}',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8))),
                ],
                if (rate is num && rate > 0) ...[
                  const SizedBox(height: 4),
                  Text('เรทที่จอง: $rate',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8))),
                ],
                if (shiftId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('สร้าง Shift แล้ว',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8))),
                ],
              ],

              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusBgColor(a),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(a),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _statusTextColor(a),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // ✅ Tab OPEN: ปุ่มจอง
                  if (showActionsOpen)
                    ElevatedButton.icon(
                      onPressed: isBooking ? null : () => _bookAvailability(a),
                      icon: isBooking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(isBooking ? 'กำลังจอง...' : 'จอง'),
                    ),

                  // ✅ Tab BOOKED: ปุ่มเคลียร์
                  if (showActionsBooked)
                    ElevatedButton.icon(
                      onPressed: isClearing ? null : () => _clearAvailability(a),
                      icon: isClearing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all),
                      label: Text(isClearing ? 'กำลังเคลียร์...' : 'เคลียร์'),
                    ),
                ],
              ),
            ],
          ),
          onTap: () {},
        ),
      ),
    );
  }

  Widget _buildOpenTab() {
    if (_openLoading) return const Center(child: CircularProgressIndicator());
    if (_openErr.isNotEmpty) return _errorBox(_openErr, _loadOpen);
    if (_openItems.isEmpty) return _emptyList('ยังไม่มีตารางว่างจากผู้ช่วย');

    return RefreshIndicator(
      onRefresh: _loadOpen,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _openItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _openItems[i];
          return _buildCard(a, showActionsOpen: true, showActionsBooked: false);
        },
      ),
    );
  }

  Widget _buildBookedTab() {
    if (_bookedLoading) return const Center(child: CircularProgressIndicator());
    if (_bookedErr.isNotEmpty) return _errorBox(_bookedErr, _loadBooked);
    if (_bookedItems.isEmpty) return _emptyList('ยังไม่มีรายการจองแล้ว');

    return RefreshIndicator(
      onRefresh: _loadBooked,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _bookedItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _bookedItems[i];
          return _buildCard(a, showActionsOpen: false, showActionsBooked: true);
        },
      ),
    );
  }

  // ----------------------------
  // UI
  // ----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตารางว่างผู้ช่วย'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.event_available), text: 'ว่าง'),
            Tab(icon: Icon(Icons.check_circle), text: 'จองแล้ว'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'รีเฟรชทั้งหมด',
            onPressed: (_openLoading || _bookedLoading) ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildOpenTab(),
          _buildBookedTab(),
        ],
      ),
    );
  }
}