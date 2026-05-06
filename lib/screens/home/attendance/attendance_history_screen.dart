import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String token;
  final String role;
  final String clinicId;
  final String staffId;

  final String initialShiftId;
  final String initialShiftLabel;

  const AttendanceHistoryScreen({
    super.key,
    required this.token,
    required this.role,
    required this.clinicId,
    required this.staffId,
    this.initialShiftId = '',
    this.initialShiftLabel = '',
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

  late final String _initialShiftId;
  late final String _initialShiftLabel;

  // Production behavior:
  // - Do not silently lock 30-day history to one shift.
  // - Admin/helper can explicitly switch to selected shift when needed.
  bool _showSelectedShiftOnly = false;

  final Map<String, String> _clinicNameCache = <String, String>{};

  bool get _isHelper => widget.role.trim().toLowerCase() == 'helper';

  String get _activeShiftId => _showSelectedShiftOnly ? _initialShiftId : '';

  String get _activeShiftLabel =>
      _initialShiftLabel.trim().isNotEmpty ? _initialShiftLabel.trim() : 'กะที่เลือก';

  Uri _payrollUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return qs == null ? uri : uri.replace(queryParameters: qs);
  }

  Uri _authUri(String path) {
    final base = ApiConfig.authBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Map<String, String> _headers() => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  String _s(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((k, val) => MapEntry(k.toString(), val)),
      );
    }
    return <String, dynamic>{};
  }

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

  (int, int)? _parseHHmm(dynamic v) {
    final s = _s(v);
    if (s.isEmpty) return null;

    final parts = s.split(':');
    if (parts.length < 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);

    if (h == null || m == null) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;

    return (h, m);
  }

  String _fmtHM(dynamic v) {
    final hhmm = _parseHHmm(v);
    if (hhmm != null) {
      final h = hhmm.$1.toString().padLeft(2, '0');
      final m = hhmm.$2.toString().padLeft(2, '0');
      return '$h:$m';
    }

    final dt = _parseDateAny(v);
    if (dt == null) return '-';

    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  dynamic _checkInValue(Map<String, dynamic> s) {
    return s['checkInAt'] ??
        s['checkinAt'] ??
        s['checkedInAt'] ??
        s['clockInAt'] ??
        s['inAt'] ??
        s['startAt'] ??
        s['startTime'] ??
        s['checkInTime'] ??
        s['clockInTime'] ??
        s['timeIn'] ??
        _asMap(s['checkIn'])['at'] ??
        _asMap(s['clockIn'])['at'];
  }

  dynamic _checkOutValue(Map<String, dynamic> s) {
    return s['checkOutAt'] ??
        s['checkoutAt'] ??
        s['checkedOutAt'] ??
        s['clockOutAt'] ??
        s['outAt'] ??
        s['endAt'] ??
        s['endTime'] ??
        s['checkOutTime'] ??
        s['clockOutTime'] ??
        s['timeOut'] ??
        _asMap(s['checkOut'])['at'] ??
        _asMap(s['clockOut'])['at'];
  }

  bool _hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  bool _hasIn(Map<String, dynamic> s) => _hasValue(_checkInValue(s));

  bool _hasOut(Map<String, dynamic> s) => _hasValue(_checkOutValue(s));

  String _statusCode(Map<String, dynamic> s) {
    return _s(s['status'] ?? s['attendanceStatus'] ?? s['state']).toLowerCase();
  }

  String _approvalStatus(Map<String, dynamic> s) {
    return _s(s['approvalStatus'] ?? s['approval'] ?? s['requestStatus'])
        .toLowerCase();
  }

  bool _isPendingManual(Map<String, dynamic> s) {
    final status = _statusCode(s);
    final approval = _approvalStatus(s);

    return status == 'pending_manual' ||
        status == 'manual_pending' ||
        approval == 'pending' ||
        approval == 'waiting';
  }

  bool _isRejectedManual(Map<String, dynamic> s) {
    final approval = _approvalStatus(s);
    return approval == 'rejected';
  }

  bool _isApprovedManual(Map<String, dynamic> s) {
    final approval = _approvalStatus(s);
    return approval == 'approved';
  }

  double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0.0;
  }

  int _firstPositiveMinutes(Map<String, dynamic> s) {
    final minuteKeys = [
      'regularWorkMinutes',
      'normalWorkMinutes',
      'workMinutes',
      'totalWorkMinutes',
      'totalMinutes',
      'workedMinutes',
      'durationMinutes',
      'minutes',
    ];

    for (final k in minuteKeys) {
      final n = _readNum(s[k]).floor();
      if (n > 0) return n;
    }

    final hourKeys = [
      'regularWorkHours',
      'normalWorkHours',
      'workHours',
      'totalWorkHours',
      'totalHours',
      'workedHours',
      'durationHours',
      'hours',
    ];

    for (final k in hourKeys) {
      final n = _readNum(s[k]);
      if (n > 0) return (n * 60).floor();
    }

    return 0;
  }

  double _calcHours(Map<String, dynamic> s) {
    final precomputedMinutes = _firstPositiveMinutes(s);
    if (precomputedMinutes > 0) return precomputedMinutes / 60.0;

    final ciRaw = _checkInValue(s);
    final coRaw = _checkOutValue(s);

    final ci = _parseDateAny(ciRaw);
    final co = _parseDateAny(coRaw);

    if (ci != null && co != null) {
      final diff = co.difference(ci).inMinutes;
      if (diff > 0 && diff <= 24 * 60) return diff / 60.0;
    }

    final inHHmm = _parseHHmm(ciRaw);
    final outHHmm = _parseHHmm(coRaw);

    if (inHHmm != null && outHHmm != null) {
      final startMin = inHHmm.$1 * 60 + inHHmm.$2;
      var endMin = outHHmm.$1 * 60 + outHHmm.$2;

      if (endMin < startMin) endMin += 24 * 60;

      final diff = endMin - startMin;
      if (diff > 0 && diff <= 24 * 60) return diff / 60.0;
    }

    return 0;
  }

  String _workDateText(Map<String, dynamic> s) {
    final workDate = s['workDate'] ??
        s['date'] ??
        s['day'] ??
        s['attendanceDate'] ??
        s['workDay'];

    final d = _parseDateAny(workDate) ??
        _parseDateAny(_checkInValue(s)) ??
        _parseDateAny(s['createdAt']) ??
        _parseDateAny(s['updatedAt']);

    if (d == null) return '-';
    return _ymd(d);
  }

  DateTime? _workDateForFilter(Map<String, dynamic> s) {
    return _parseDateAny(
          s['workDate'] ??
              s['date'] ??
              s['day'] ??
              s['attendanceDate'] ??
              s['workDay'],
        ) ??
        _parseDateAny(_checkInValue(s)) ??
        _parseDateAny(s['createdAt']) ??
        _parseDateAny(s['updatedAt']);
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
    if (_isPendingManual(s)) return true;
    if (_isRejectedManual(s)) return true;
    if (_isApprovedManual(s) && !hasIn && !hasOut) return true;

    final status = _statusCode(s);
    if ([
      'completed',
      'complete',
      'checked_out',
      'checkout',
      'checkedout',
      'finished',
      'done',
      'closed',
      'success',
    ].contains(status)) {
      return true;
    }

    return false;
  }

  String _mainValueText(Map<String, dynamic> s) {
    final hasOut = _hasOut(s);
    final hasIn = _hasIn(s);
    final hours = _calcHours(s);

    if (_isPendingManual(s)) return 'รออนุมัติ';
    if (_isRejectedManual(s)) return 'ไม่อนุมัติ';
    if (_isApprovedManual(s) && !hasIn && !hasOut) return 'อนุมัติแล้ว';

    if (hasIn && hasOut) {
      if (hours > 0) return '${hours.toStringAsFixed(2)} ชม.';
      return 'เสร็จสิ้น';
    }

    if (hasIn && !hasOut) return 'ยังไม่เช็กเอาท์';

    if (hours > 0) return '${hours.toStringAsFixed(2)} ชม.';

    return '-';
  }

  String _statusLabel(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (_isPendingManual(s)) return 'รออนุมัติ';
    if (_isRejectedManual(s)) return 'ไม่อนุมัติ';
    if (_isApprovedManual(s) && !hasIn && !hasOut) return 'อนุมัติแล้ว';

    if (hasIn && hasOut) return 'เสร็จสิ้น';
    if (hasIn && !hasOut) {
      return _isStaleOpen(s) ? 'ค้างเก่า' : 'กำลังทำงาน';
    }

    final status = _statusCode(s);
    if (status == 'completed' || status == 'complete') return 'เสร็จสิ้น';

    return 'ไม่สมบูรณ์';
  }

  Color _statusColor(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (_isPendingManual(s)) return Colors.deepPurple.shade700;
    if (_isRejectedManual(s)) return Colors.red.shade700;
    if (_isApprovedManual(s) && !hasIn && !hasOut) {
      return Colors.blue.shade700;
    }

    if (hasIn && hasOut) return Colors.green.shade700;
    if (hasIn && !hasOut) {
      return _isStaleOpen(s) ? Colors.red.shade700 : Colors.orange.shade700;
    }

    final status = _statusCode(s);
    if (status == 'completed' || status == 'complete') {
      return Colors.green.shade700;
    }

    return Colors.red.shade700;
  }

  Color _badgeBgColor(Map<String, dynamic> s) {
    final hasIn = _hasIn(s);
    final hasOut = _hasOut(s);

    if (_isPendingManual(s)) return Colors.deepPurple.shade50;
    if (_isRejectedManual(s)) return Colors.red.shade50;
    if (_isApprovedManual(s) && !hasIn && !hasOut) {
      return Colors.blue.shade50;
    }

    if (hasIn && hasOut) return Colors.green.shade50;
    if (hasIn && !hasOut) {
      return _isStaleOpen(s) ? Colors.red.shade50 : Colors.orange.shade50;
    }

    final status = _statusCode(s);
    if (status == 'completed' || status == 'complete') {
      return Colors.green.shade50;
    }

    return Colors.grey.shade100;
  }

  Color _cardBorderColor(Map<String, dynamic> s) {
    if (_isPendingManual(s)) return Colors.deepPurple.shade100;
    if (_isRejectedManual(s)) return Colors.red.shade100;
    if (_isApprovedManual(s) && !_hasIn(s) && !_hasOut(s)) {
      return Colors.blue.shade100;
    }
    if (_isTodayOpen(s)) return Colors.orange.shade200;
    if (_isStaleOpen(s)) return Colors.red.shade100;
    return Colors.purple.shade100;
  }

  Color _cardBgColor(Map<String, dynamic> s) {
    if (_isPendingManual(s)) return const Color(0xFFF8F4FF);
    if (_isRejectedManual(s)) return const Color(0xFFFFFBFB);
    if (_isApprovedManual(s) && !_hasIn(s) && !_hasOut(s)) {
      return const Color(0xFFF7FBFF);
    }
    if (_isTodayOpen(s)) return const Color(0xFFFFFBF5);
    if (_isStaleOpen(s)) return const Color(0xFFFFFBFB);
    return Colors.white;
  }

  DateTimeRange _effectiveRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final start = DateTime(now.year, now.month, now.day).subtract(
      Duration(days: (_quickDays <= 0 ? 30 : _quickDays) - 1),
    );

    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange _rangeOrQuick() {
    if (_from == null && _to == null) return _effectiveRange();

    final now = DateTime.now();
    final from = _from ??
        DateTime(now.year, now.month, now.day).subtract(
          const Duration(days: 29),
        );
    final to = _to ?? now;

    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);

    return DateTimeRange(start: start, end: end);
  }

  bool _isInRange(Map<String, dynamic> s, DateTimeRange r) {
    final d = _workDateForFilter(s);
    if (d == null) return false;
    return !d.isBefore(r.start) && !d.isAfter(r.end);
  }

  String _sessionShiftId(Map<String, dynamic> s) {
    final shift = _asMap(s['shift']);
    return _s(
      s['shiftId'] ??
          s['clinicShiftNeedId'] ??
          s['shiftNeedId'] ??
          s['workAssignmentId'] ??
          shift['_id'] ??
          shift['id'] ??
          shift['shiftId'],
    );
  }

  bool _matchesShiftFilter(Map<String, dynamic> s) {
    if (!_isHelper) return true;
    if (_activeShiftId.isEmpty) return true;
    return _sessionShiftId(s) == _activeShiftId;
  }

  List<Map<String, dynamic>> _filtered() {
    final r = _rangeOrQuick();
    final list = _all
        .where((s) => _shouldShowItem(s))
        .where((s) => _matchesShiftFilter(s))
        .where((s) => _isInRange(s, r))
        .toList();

    list.sort((a, b) {
      final da = _workDateForFilter(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = _workDateForFilter(b) ?? DateTime.fromMillisecondsSinceEpoch(0);

      final cmpDate = db.compareTo(da);
      if (cmpDate != 0) return cmpDate;

      final ca = _parseDateAny(_checkInValue(a)) ??
          _parseDateAny(a['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final cb = _parseDateAny(_checkInValue(b)) ??
          _parseDateAny(b['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return cb.compareTo(ca);
    });

    return list;
  }

  String _manualReasonText(Map<String, dynamic> s) {
    return _s(
      s['manualReason'] ??
          s['reasonText'] ??
          s['approvalNote'] ??
          s['rejectReason'] ??
          s['note'] ??
          s['message'],
    );
  }

  String _displayShiftText(Map<String, dynamic> s) {
    final shift = _asMap(s['shift']);
    final label = _s(
      shift['label'] ??
          shift['name'] ??
          shift['title'] ??
          shift['shiftLabel'] ??
          s['shiftLabel'] ??
          s['shiftName'] ??
          s['shiftTitle'],
    );

    if (label.isNotEmpty) return label;

    final shiftId = _sessionShiftId(s);
    if (_isHelper &&
        _initialShiftLabel.trim().isNotEmpty &&
        shiftId == _initialShiftId) {
      return _initialShiftLabel.trim();
    }

    if (shiftId.isEmpty) return '-';
    if (shiftId.length <= 16) return shiftId;

    return '${shiftId.substring(0, 8)}...${shiftId.substring(shiftId.length - 6)}';
  }

  String _extractClinicNameFromAny(Map<String, dynamic> s) {
    final shift = _asMap(s['shift']);
    final shiftClinic = _asMap(shift['clinic']);
    final clinic = _asMap(s['clinic']);

    final fromShift = _s(
      shift['clinicName'] ??
          shiftClinic['name'] ??
          shiftClinic['clinicName'] ??
          shiftClinic['title'] ??
          shift['locationName'] ??
          shift['workplaceName'],
    );

    if (fromShift.isNotEmpty) return fromShift;

    return _s(
      s['clinicName'] ??
          clinic['name'] ??
          clinic['clinicName'] ??
          clinic['title'] ??
          s['clinicTitle'] ??
          s['clinicDisplayName'] ??
          s['locationName'] ??
          s['workplaceName'] ??
          s['hospitalName'] ??
          s['branchName'],
    );
  }

  String _extractClinicId(Map<String, dynamic> s) {
    final clinic = _asMap(s['clinic']);

    return _s(
      s['clinicId'] ??
          clinic['_id'] ??
          clinic['id'] ??
          clinic['clinicId'] ??
          s['clinic_id'],
    );
  }

  String _displayClinicText(Map<String, dynamic> s) {
    final directName = _extractClinicNameFromAny(s);
    if (directName.isNotEmpty) return directName;

    final clinicId = _extractClinicId(s);
    if (clinicId.isEmpty) return '-';

    final cached = _clinicNameCache[clinicId];
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }

    if (clinicId.length <= 16) return clinicId;
    return '${clinicId.substring(0, 8)}...${clinicId.substring(clinicId.length - 6)}';
  }

  String _shortText(String v, {int max = 80}) {
    final text = v.trim();
    if (text.isEmpty) return '-';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  @override
  void initState() {
    super.initState();

    _initialShiftId = widget.initialShiftId.trim();
    _initialShiftLabel = widget.initialShiftLabel.trim();

    // Do not apply hidden shift filter by default.
    _showSelectedShiftOnly = false;

    _load();
  }

  Future<http.Response> _tryGet(Uri uri) async {
    return http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 15));
  }

  Future<String> _fetchClinicNameById(String clinicId) async {
    if (clinicId.isEmpty) return '';

    final candidates = <Uri>[
      _authUri('/clinics/$clinicId'),
      _authUri('/api/clinics/$clinicId'),
      _authUri('/users/clinic/$clinicId'),
      _authUri('/api/users/clinic/$clinicId'),
    ];

    for (final uri in candidates) {
      try {
        final res = await _tryGet(uri);
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        Map<String, dynamic> map = <String, dynamic>{};

        if (decoded is Map) {
          map = _asMap(decoded);

          if (map['data'] is Map) {
            map = _asMap(map['data']);
          } else if (map['item'] is Map) {
            map = _asMap(map['item']);
          } else if (map['clinic'] is Map) {
            map = _asMap(map['clinic']);
          }
        }

        final name = _s(
          map['name'] ??
              map['clinicName'] ??
              map['title'] ??
              map['clinicTitle'] ??
              map['displayName'],
        );

        if (name.isNotEmpty) return name;
      } catch (_) {}
    }

    return '';
  }

  Future<void> _hydrateClinicNames(List<Map<String, dynamic>> list) async {
    if (!_isHelper) return;

    final missingIds = <String>{};

    for (final item in list) {
      final directName = _extractClinicNameFromAny(item);
      final clinicId = _extractClinicId(item);

      if (directName.isNotEmpty && clinicId.isNotEmpty) {
        _clinicNameCache[clinicId] = directName;
        continue;
      }

      if (clinicId.isNotEmpty &&
          !_clinicNameCache.containsKey(clinicId) &&
          directName.isEmpty) {
        missingIds.add(clinicId);
      }
    }

    if (missingIds.isEmpty) return;

    bool changed = false;

    for (final clinicId in missingIds) {
      final name = await _fetchClinicNameById(clinicId);
      if (name.isNotEmpty) {
        _clinicNameCache[clinicId] = name;
        changed = true;
      }
    }

    if (changed && mounted) setState(() {});
  }

  void _addMapsFromList(dynamic raw, List<Map<String, dynamic>> out) {
    if (raw is! List) return;

    for (final item in raw) {
      if (item is Map) {
        out.add(_asMap(item));
      }
    }
  }

  List<Map<String, dynamic>> _extractAttendanceRows(dynamic decoded) {
    final out = <Map<String, dynamic>>[];

    if (decoded is List) {
      _addMapsFromList(decoded, out);
      return out;
    }

    if (decoded is! Map) return out;

    final root = _asMap(decoded);

    final rootListKeys = [
      'data',
      'items',
      'results',
      'rows',
      'sessions',
      'attendanceSessions',
      'histories',
      'history',
      'records',
    ];

    for (final key in rootListKeys) {
      _addMapsFromList(root[key], out);
    }

    final nestedCandidates = <Map<String, dynamic>>[];

    for (final key in [
      'data',
      'attendance',
      'result',
      'payload',
      'response',
      'item',
    ]) {
      if (root[key] is Map) nestedCandidates.add(_asMap(root[key]));
    }

    for (final nested in nestedCandidates) {
      for (final key in rootListKeys) {
        _addMapsFromList(nested[key], out);
      }

      final attendance = _asMap(nested['attendance']);
      if (attendance.isNotEmpty) {
        for (final key in rootListKeys) {
          _addMapsFromList(attendance[key], out);
        }
      }
    }

    // Single current/open session fallback.
    // This is intentionally last so it never replaces the full list.
    final singleKeys = [
      'session',
      'todaySession',
      'currentSession',
      'openSession',
      'pendingManualSession',
      'latestSession',
      'lastSession',
    ];

    for (final key in singleKeys) {
      if (root[key] is Map) out.add(_asMap(root[key]));
    }

    final attendance = _asMap(root['attendance']);
    if (attendance.isNotEmpty) {
      for (final key in singleKeys) {
        if (attendance[key] is Map) out.add(_asMap(attendance[key]));
      }
    }

    return out;
  }

  String _rowKey(Map<String, dynamic> row) {
    final id = _s(row['_id'] ?? row['id'] ?? row['sessionId']);
    if (id.isNotEmpty) return 'id:$id';

    return [
      _workDateText(row),
      _s(_checkInValue(row)),
      _s(_checkOutValue(row)),
      _statusCode(row),
      _approvalStatus(row),
      _sessionShiftId(row),
      _extractClinicId(row),
      _manualReasonText(row),
    ].join('|');
  }

  List<Map<String, dynamic>> _mergeUniqueRows(List<Map<String, dynamic>> rows) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final row in rows) {
      final key = _rowKey(row);
      if (key.trim().isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(row);
    }

    return out;
  }

  Map<String, String> _buildQuery(DateTimeRange range) {
    final days = range.duration.inDays.abs() + 1;
    final qs = <String, String>{
      'dateFrom': _ymd(range.start),
      'dateTo': _ymd(range.end),

      // Compatibility aliases for different controller versions.
      'from': _ymd(range.start),
      'to': _ymd(range.end),
      'startDate': _ymd(range.start),
      'endDate': _ymd(range.end),
      'days': days.toString(),
      'limit': '500',
      'includeAll': 'true',
    };

    final staffId = widget.staffId.trim();
    if (staffId.isNotEmpty) {
      qs['staffId'] = staffId;
      qs['employeeId'] = staffId;
      qs['principalId'] = staffId;
    }

    final clinicId = widget.clinicId.trim();
    if (clinicId.isNotEmpty) {
      qs['clinicId'] = clinicId;
    }

    if (_isHelper && _activeShiftId.isNotEmpty) {
      qs['shiftId'] = _activeShiftId;
      qs['clinicShiftNeedId'] = _activeShiftId;
      qs['shiftNeedId'] = _activeShiftId;
    }

    return qs;
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _err = '';
      _all = [];
    });

    try {
      final range = _rangeOrQuick();
      final qs = _buildQuery(range);

      final candidates = <String>[
        '/attendance/my-sessions',
        '/api/attendance/my-sessions',
        '/attendance/me/history',
        '/api/attendance/me/history',
        '/attendance/history',
        '/api/attendance/history',
        '/attendance/sessions/my',
        '/api/attendance/sessions/my',
        '/attendance/me',
        '/api/attendance/me',
      ];

      http.Response? last;
      final collected = <Map<String, dynamic>>[];
      bool gotAnyOk = false;

      for (final p in candidates) {
        final u = _payrollUri(p, qs: qs);

        http.Response res;
        try {
          res = await _tryGet(u);
        } catch (_) {
          continue;
        }

        last = res;

        if (res.statusCode == 404) continue;
        if (res.statusCode == 401) throw Exception('no token');
        if (res.statusCode == 403) throw Exception('forbidden');

        if (res.statusCode != 200) {
          continue;
        }

        gotAnyOk = true;

        dynamic decoded;
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {
          continue;
        }

        final rows = _extractAttendanceRows(decoded);
        if (rows.isNotEmpty) {
          collected.addAll(rows);
        }
      }

      final merged = _mergeUniqueRows(collected);

      if (!mounted) return;

      if (gotAnyOk) {
        setState(() {
          _loading = false;
          _err = '';
          _all = merged;
        });

        await _hydrateClinicNames(merged);
        return;
      }

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
            : 'เซสชันหมดอายุหรือโหลดข้อมูลไม่สำเร็จ กรุณาเข้าสู่ระบบใหม่';
        _all = [];
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final initial = _from ?? now.subtract(Duration(days: _quickDays - 1));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _from = picked;
    });

    await _load();
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
    if (!mounted) return;

    setState(() {
      _to = picked;
    });

    await _load();
  }

  void _setQuick(int days) {
    setState(() {
      _quickDays = days;
      _from = null;
      _to = null;

      // Quick history should show the whole period, not only one selected shift.
      if (days >= 30) {
        _showSelectedShiftOnly = false;
      }
    });

    _load();
  }

  void _showAllShifts() {
    setState(() {
      _showSelectedShiftOnly = false;
    });

    _load();
  }

  void _showOnlyInitialShift() {
    if (_initialShiftId.isEmpty) return;

    setState(() {
      _showSelectedShiftOnly = true;
    });

    _load();
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

  Widget _detailRow({
    required String label,
    required String value,
    Color? valueColor,
    FontWeight valueWeight = FontWeight.w800,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueWeight,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
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
        border: Border.all(color: fg.withValues(alpha: 0.15)),
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

  Future<void> _showDetailSheet(Map<String, dynamic> s) async {
    final dateText = _workDateText(s);
    final ci = _fmtHM(_checkInValue(s));
    final co = _fmtHM(_checkOutValue(s));
    final statusText = _statusLabel(s);
    final mainValue = _mainValueText(s);
    final manualReason = _manualReasonText(s);
    final shiftId = _sessionShiftId(s);
    final displayShift = _displayShiftText(s);
    final clinicText = _displayClinicText(s);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'รายละเอียด $dateText',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusBadge(s),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          mainValue,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(label: 'เวลาเช็กอิน', value: ci),
                          _detailRow(label: 'เวลาเช็กเอาท์', value: co),
                          _detailRow(
                            label: 'สถานะ',
                            value: statusText,
                            valueColor: _statusColor(s),
                          ),
                          _detailRow(label: 'ผลลัพธ์', value: mainValue),
                          if (_isHelper)
                            _detailRow(label: 'คลินิก', value: clinicText),
                          if (_isHelper)
                            _detailRow(label: 'กะงาน', value: displayShift),
                          if (_isHelper && shiftId.isNotEmpty)
                            _detailRow(
                              label: 'รหัสกะงาน',
                              value: shiftId,
                              valueWeight: FontWeight.w700,
                            ),
                          if (manualReason.isNotEmpty)
                            _detailRow(
                              label: 'เหตุผล / หมายเหตุ',
                              value: manualReason,
                            ),
                          if (_isPendingManual(s)) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.deepPurple.shade100,
                                ),
                              ),
                              child: Text(
                                'รายการนี้เป็นคำขอแก้ไขเวลาที่กำลังรอการอนุมัติ',
                                style: TextStyle(
                                  color: Colors.deepPurple.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (_isRejectedManual(s)) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.red.shade100,
                                ),
                              ),
                              child: Text(
                                'รายการนี้เป็นคำขอแก้ไขเวลาที่ไม่ผ่านการอนุมัติ',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (_isStaleOpen(s)) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.red.shade100,
                                ),
                              ),
                              child: Text(
                                'รายการนี้ยังไม่มีเวลาเช็กเอาท์ และไม่ใช่รายการของวันนี้',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (_isTodayOpen(s)) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.orange.shade100,
                                ),
                              ),
                              child: Text(
                                'รายการนี้เป็นรายการที่กำลังทำงานอยู่ของวันนี้',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      label: const Text('ปิด'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shiftFilterCard() {
    if (!_isHelper || _initialShiftId.isEmpty) {
      return const SizedBox.shrink();
    }

    final showingShift = _showSelectedShiftOnly;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: showingShift ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showingShift ? Colors.green.shade100 : Colors.blue.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showingShift
                ? 'กำลังแสดงเฉพาะกะ: $_activeShiftLabel'
                : 'กำลังแสดงประวัติทุกกะในช่วงเวลานี้',
            style: TextStyle(
              color: showingShift ? Colors.green.shade800 : Colors.blue.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: showingShift ? _showAllShifts : null,
                icon: const Icon(Icons.view_list),
                label: const Text('แสดงทุกกะ'),
              ),
              OutlinedButton.icon(
                onPressed: showingShift ? null : _showOnlyInitialShift,
                icon: const Icon(Icons.filter_alt),
                label: const Text('ดูกะที่เลือก'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rangeOrQuick();
    final list = _filtered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการเช็กอินย้อนหลัง'),
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
                              _shiftFilterCard(),
                              if (_isHelper && _initialShiftId.isNotEmpty)
                                const SizedBox(height: 10),
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
                                            _showSelectedShiftOnly = false;
                                          });
                                          _load();
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
                                      onPressed: _pickFrom,
                                      icon: const Icon(Icons.date_range),
                                      label: Text(
                                        'เริ่ม: ${_from == null ? _ymd(r.start) : _ymd(_from!)}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickTo,
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
                                'แสดง: ${_ymd(r.start)} ถึง ${_ymd(r.end)} • พบ ${list.length} รายการ',
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
                                _isHelper && _showSelectedShiftOnly
                                    ? 'ไม่พบรายการของกะที่เลือกในช่วงเวลานี้'
                                    : 'ไม่พบรายการในช่วงเวลานี้',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final s = list[i];

                                final dateText = _workDateText(s);
                                final ci = _fmtHM(_checkInValue(s));
                                final co = _fmtHM(_checkOutValue(s));

                                final mainValue = _mainValueText(s);
                                final shiftText = _displayShiftText(s);
                                final clinicText = _displayClinicText(s);
                                final manualReason = _manualReasonText(s);

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
                                          if (_isHelper) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'คลินิก: $clinicText',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'กะงาน: $shiftText',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                          if (manualReason.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _shortText(manualReason, max: 90),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          _statusBadge(s),
                                        ],
                                      ),
                                    ),
                                    trailing: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 96),
                                      child: Text(
                                        mainValue,
                                        textAlign: TextAlign.end,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: _isPendingManual(s)
                                              ? Colors.deepPurple.shade700
                                              : _isRejectedManual(s)
                                                  ? Colors.red.shade700
                                                  : _isStaleOpen(s)
                                                      ? Colors.red.shade700
                                                      : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    onTap: () => _showDetailSheet(s),
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