import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String token;
  final String role;
  final String clinicId;
  final String staffId;

  const AttendanceHistoryScreen({
    super.key,
    required this.token,
    required this.role,
    required this.clinicId,
    required this.staffId,
  });

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _all = [];

  int _quickDays = 30;
  DateTime? _from;
  DateTime? _to;

  Uri _payrollUri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Map<String, String> _headers() => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  DateTime? _parseDateAny(dynamic v) {
    if (v == null) return null;

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (dateOnly.hasMatch(s)) {
      final parts = s.split('-');
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    try {
      final dt = DateTime.parse(s);

      final hasUtcZ = s.toUpperCase().endsWith('Z');
      final hasTzOffset = RegExp(r'([+-]\d{2}:\d{2})$').hasMatch(s);

      if (hasUtcZ || hasTzOffset || dt.isUtc) {
        return dt.toLocal();
      }
      return dt;
    } catch (_) {
      if (s.length >= 10) {
        final head = s.substring(0, 10);
        if (dateOnly.hasMatch(head)) {
          final parts = head.split('-');
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y == null || m == null || d == null) return null;
          return DateTime(y, m, d);
        }
      }
      return null;
    }
  }

  String _fmtHM(dynamic v) {
    final dt = _parseDateAny(v);
    if (dt == null) return '-';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _hasIn(Map<String, dynamic> s) {
    final v = s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime'];
    return v != null && v.toString().trim().isNotEmpty;
  }

  bool _hasOut(Map<String, dynamic> s) {
    final v = s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime'];
    return v != null && v.toString().trim().isNotEmpty;
  }

  double _calcHours(Map<String, dynamic> s) {
    final ci =
        _parseDateAny(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']);
    final co =
        _parseDateAny(s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime']);
    if (ci == null || co == null) return 0;
    final diff = co.difference(ci).inMinutes;
    if (diff <= 0) return 0;
    return diff / 60.0;
  }

  String _workDateText(Map<String, dynamic> s) {
    final workDate = s['workDate'] ?? s['date'] ?? s['day'];
    final d = _parseDateAny(workDate) ??
        _parseDateAny(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']) ??
        _parseDateAny(s['createdAt']);
    if (d == null) return '-';
    return _ymd(d);
  }

  bool _isTodayText(String ymd) {
    final now = DateTime.now();
    final today = _ymd(DateTime(now.year, now.month, now.day));
    return ymd == today;
  }

  bool _isStaleOpen(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);
    final dateText = _workDateText(s);
    return hasIn && !hasOut && !_isTodayText(dateText);
  }

  bool _isTodayOpen(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);
    final dateText = _workDateText(s);
    return hasIn && !hasOut && _isTodayText(dateText);
  }

  bool _shouldShowItem(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (hasIn && hasOut) return true;
    if (hasIn && !hasOut) return true;

    return false;
  }

  String _mainValueText(Map<String, dynamic> s) {
    final hasOut = _hasOut(s);
    final hasIn = _hasIn(s);
    final hours = _calcHours(s);

    if (hasIn && hasOut) {
      if (hours > 0) return '${hours.toStringAsFixed(2)} ชม.';
      return 'เสร็จสิ้น';
    }

    if (hasIn && !hasOut) {
      return 'ยังไม่เช็คเอาท์';
    }

    return '-';
  }

  String _statusLabel(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (hasIn && hasOut) return 'เสร็จสิ้น';
    if (hasIn && !hasOut) {
      return _isStaleOpen(s) ? 'ค้างเก่า' : 'กำลังทำงาน';
    }
    return 'ไม่สมบูรณ์';
  }

  Color _statusColor(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (hasIn && hasOut) return Colors.green.shade700;
    if (hasIn && !hasOut) {
      return _isStaleOpen(s) ? Colors.red.shade700 : Colors.orange.shade700;
    }
    return Colors.red.shade700;
  }

  Color _badgeBgColor(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (hasIn && hasOut) return Colors.green.shade50;
    if (hasIn && !hasOut) {
      return _isStaleOpen(s) ? Colors.red.shade50 : Colors.orange.shade50;
    }
    return Colors.grey.shade100;
  }

  Color _cardBorderColor(Map<String, dynamic> s) {
    if (_isTodayOpen(s)) return Colors.orange.shade200;
    if (_isStaleOpen(s)) return Colors.red.shade100;
    return Colors.purple.shade100;
  }

  Color _cardBgColor(Map<String, dynamic> s) {
    if (_isTodayOpen(s)) return const Color(0xFFFFFBF5);
    if (_isStaleOpen(s)) return const Color(0xFFFFFBFB);
    return Colors.white;
  }

  DateTimeRange _effectiveRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _quickDays - 1));
    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange _rangeOrQuick() {
    if (_from == null && _to == null) return _effectiveRange();
    final now = DateTime.now();
    final from = _from ??
        DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
    final to = _to ?? now;
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }

  bool _isInRange(Map<String, dynamic> s, DateTimeRange r) {
    final d = _parseDateAny(s['workDate'] ?? s['date'] ?? s['day']) ??
        _parseDateAny(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']) ??
        _parseDateAny(s['createdAt']);
    if (d == null) return false;
    return !d.isBefore(r.start) && !d.isAfter(r.end);
  }

  List<Map<String, dynamic>> _filtered() {
    final r = _rangeOrQuick();
    final list = _all
        .where((s) => _shouldShowItem(s))
        .where((s) => _isInRange(s, r))
        .toList();

    list.sort((a, b) {
      final da = _parseDateAny(a['workDate'] ?? a['date'] ?? a['day']) ??
          _parseDateAny(a['checkInAt'] ?? a['checkinAt'] ?? a['checkInTime']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = _parseDateAny(b['workDate'] ?? b['date'] ?? b['day']) ??
          _parseDateAny(b['checkInAt'] ?? b['checkinAt'] ?? b['checkInTime']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<http.Response> _tryGet(Uri uri) async {
    return http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
      _all = [];
    });

    try {
      final candidates = <String>[
        '/attendance/me',
        '/api/attendance/me',
      ];

      http.Response? last;

      for (final p in candidates) {
        final u = _payrollUri(p);
        final res = await _tryGet(u);
        last = res;

        if (res.statusCode == 404) continue;
        if (res.statusCode == 401) throw Exception('no token');
        if (res.statusCode == 403) throw Exception('forbidden');
        if (res.statusCode != 200) break;

        final decoded = jsonDecode(res.body);

        List<Map<String, dynamic>> list = [];

        if (decoded is Map) {
          final dataAny = decoded['data'];
          if (dataAny is List) {
            list = dataAny
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded['items'] is List) {
            list = (decoded['items'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded['results'] is List) {
            list = (decoded['results'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else if (decoded is List) {
          list = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (!mounted) return;
        setState(() {
          _loading = false;
          _err = '';
          _all = list;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = (last == null)
            ? 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่'
            : 'โหลดข้อมูลไม่สำเร็จ กรุณาลองใหม่';
        _all = [];
      });
    } catch (e) {
      if (!mounted) return;
      final s = e.toString().toLowerCase();
      setState(() {
        _loading = false;
        _err = s.contains('forbidden')
            ? 'ไม่มีสิทธิ์ใช้งานเมนูนี้'
            : 'เซสชันหมดอายุ/โหลดข้อมูลไม่สำเร็จ กรุณาเข้าสู่ระบบใหม่';
        _all = [];
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final initial = _from ?? now.subtract(Duration(days: _quickDays));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
    });
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final initial = _to ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _to = picked;
    });
  }

  void _setQuick(int days) {
    setState(() {
      _quickDays = days;
      _from = null;
      _to = null;
    });
  }

  Widget _chip(String label, bool on, VoidCallback tap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => tap(),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _statusBadge(Map<String, dynamic> s) {
    final text = _statusLabel(s);
    final fg = _statusColor(s);
    final bg = _badgeBgColor(s);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rangeOrQuick();
    final list = _filtered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการเช็คอินย้อนหลัง'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ไม่พร้อมใช้งาน',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _err,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
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
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ช่วงเวลา',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _chip(
                                      '7 วัน',
                                      _from == null &&
                                          _to == null &&
                                          _quickDays == 7,
                                      () => _setQuick(7),
                                    ),
                                    _chip(
                                      '30 วัน',
                                      _from == null &&
                                          _to == null &&
                                          _quickDays == 30,
                                      () => _setQuick(30),
                                    ),
                                    _chip(
                                      '90 วัน',
                                      _from == null &&
                                          _to == null &&
                                          _quickDays == 90,
                                      () => _setQuick(90),
                                    ),
                                    _chip(
                                      'เลือกเอง',
                                      _from != null || _to != null,
                                      () {
                                        if (_from == null && _to == null) {
                                          setState(() {
                                            _from = DateTime.now().subtract(
                                              const Duration(days: 29),
                                            );
                                            _to = DateTime.now();
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        if (_from == null && _to == null) {
                                          setState(() {
                                            _from = DateTime.now().subtract(
                                              const Duration(days: 29),
                                            );
                                            _to = DateTime.now();
                                          });
                                        }
                                        await _pickFrom();
                                      },
                                      icon: const Icon(Icons.date_range),
                                      label: Text(
                                        'เริ่ม: ${_from == null ? _ymd(r.start) : _ymd(_from!)}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        if (_from == null && _to == null) {
                                          setState(() {
                                            _from = DateTime.now().subtract(
                                              const Duration(days: 29),
                                            );
                                            _to = DateTime.now();
                                          });
                                        }
                                        await _pickTo();
                                      },
                                      icon: const Icon(Icons.event),
                                      label: Text(
                                        'ถึง: ${_to == null ? _ymd(r.end) : _ymd(_to!)}',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'แสดง: ${_ymd(r.start)} ถึง ${_ymd(r.end)} • ทั้งหมด ${list.length} รายการ',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Text(
                                'ไม่พบรายการในช่วงเวลานี้',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final s = list[i];

                                final dateText = _workDateText(s);
                                final ci = _fmtHM(
                                  s['checkInAt'] ??
                                      s['checkinAt'] ??
                                      s['checkInTime'],
                                );
                                final co = _fmtHM(
                                  s['checkOutAt'] ??
                                      s['checkoutAt'] ??
                                      s['checkOutTime'],
                                );

                                final mainValue = _mainValueText(s);

                                return Card(
                                  elevation: 0.6,
                                  color: _cardBgColor(s),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: BorderSide(
                                      color: _cardBorderColor(s),
                                      width: 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.purple.shade50,
                                      child: Text(
                                        dateText.length >= 10
                                            ? dateText.substring(8, 10)
                                            : '--',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      dateText,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'เข้า $ci • ออก $co',
                                            style: TextStyle(
                                              color: Colors.grey.shade800,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _statusBadge(s),
                                        ],
                                      ),
                                    ),
                                    trailing: SizedBox(
                                      width: 110,
                                      child: Text(
                                        mainValue,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: _isStaleOpen(s)
                                              ? Colors.red.shade700
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    onTap: () async {
                                      final statusText = _statusLabel(s);
                                      final mainValue = _mainValueText(s);

                                      await showModalBottomSheet(
                                        context: context,
                                        showDragHandle: true,
                                        builder: (ctx) {
                                          return SafeArea(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(14),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'รายละเอียด $dateText',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  _kv('เวลาเช็คอิน', ci),
                                                  _kv('เวลาเช็คเอาท์', co),
                                                  _kv('สถานะ', statusText),
                                                  _kv('ผลลัพธ์', mainValue),
                                                  if (_isStaleOpen(s)) ...[
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      width: double.infinity,
                                                      padding:
                                                          const EdgeInsets.all(
                                                        10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.red.shade50,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        border: Border.all(
                                                          color: Colors
                                                              .red.shade100,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'รายการนี้เป็น session ค้างเก่าที่ยังไม่มีเวลาเช็คเอาท์',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .red.shade700,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  if (_isTodayOpen(s)) ...[
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      width: double.infinity,
                                                      padding:
                                                          const EdgeInsets.all(
                                                        10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .orange.shade50,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        border: Border.all(
                                                          color: Colors.orange
                                                              .shade100,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'รายการนี้เป็น session ที่กำลังทำงานอยู่ของวันนี้',
                                                        style: TextStyle(
                                                          color: Colors.orange
                                                              .shade800,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 10),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: OutlinedButton.icon(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx),
                                                      icon:
                                                          const Icon(Icons.close),
                                                      label: const Text('ปิด'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}