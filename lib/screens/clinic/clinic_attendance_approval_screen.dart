import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ClinicAttendanceApprovalScreen extends StatefulWidget {
  const ClinicAttendanceApprovalScreen({super.key});

  @override
  State<ClinicAttendanceApprovalScreen> createState() =>
      _ClinicAttendanceApprovalScreenState();
}

class _ClinicAttendanceApprovalScreenState
    extends State<ClinicAttendanceApprovalScreen> {
  bool _loading = true;
  bool _submitting = false;
  String _err = '';

  String _approvalStatus = 'pending';
  String _workDate = '';

  List<Map<String, dynamic>> _items = [];

  void _log(String message, [Object? data]) {
    if (!kDebugMode) return;
    try {
      if (data == null) {
        debugPrint('[ATTENDANCE_APPROVAL] $message');
      } else if (data is String) {
        debugPrint('[ATTENDANCE_APPROVAL] $message: $data');
      } else {
        debugPrint('[ATTENDANCE_APPROVAL] $message: ${jsonEncode(data)}');
      }
    } catch (_) {
      debugPrint('[ATTENDANCE_APPROVAL] $message: $data');
    }
  }

  @override
  void initState() {
    super.initState();
    _workDate = _todayYmd();
    _load();
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

  Future<http.Response> _tryPost(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 20));
  }

  Map<String, dynamic> _decodeBodyMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractApiMessage(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    return (decoded['message'] ??
            decoded['error'] ??
            decoded['msg'] ??
            decoded['detail'] ??
            '')
        .toString()
        .trim();
  }

  List<Map<String, dynamic>> _extractItems(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['items'] is List) {
        return (decoded['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  String _fmtDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '-';
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  String _fmtDateTime(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '-';
    try {
      final dt = DateTime.parse(s).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    } catch (_) {
      return s;
    }
  }

  String _manualTypeLabel(String raw) {
    switch (raw.trim()) {
      case 'check_in':
        return 'เช็คอินย้อนหลัง / เช็คอินก่อนเวลา';
      case 'check_out':
        return 'เช็คเอาท์ย้อนหลัง';
      case 'edit_both':
        return 'แก้ทั้งเวลาเข้าและเวลาออก';
      case 'forgot_checkout':
        return 'ลืมเช็คเอาท์';
      default:
        return raw.trim().isEmpty ? '-' : raw.trim();
    }
  }

  String _statusLabel(String raw) {
    switch (raw.trim()) {
      case 'pending':
        return 'รออนุมัติ';
      case 'approved':
        return 'อนุมัติแล้ว';
      case 'rejected':
        return 'ไม่อนุมัติ';
      default:
        return raw.trim().isEmpty ? '-' : raw.trim();
    }
  }

  Color _statusColor(BuildContext context, String raw) {
    switch (raw.trim()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Theme.of(context).colorScheme.error;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  String _displayName(Map<String, dynamic> item) {
    final candidates = [
      item['employee'] is Map ? (item['employee'] as Map)['fullName'] : null,
      item['employeeName'],
      item['fullName'],
      item['userName'],
      item['staffName'],
      item['principalId'],
      item['staffId'],
      item['userId'],
    ];

    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return 'ไม่ระบุชื่อ';
  }

  void _showSnackNow(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _removeItemLocally(String id) {
    if (!mounted) return;
    setState(() {
      _items.removeWhere(
        (e) => ((e['_id'] ?? e['id'] ?? '').toString().trim()) == id,
      );
    });
  }

  Future<void> _pickWorkDate() async {
    final initial = DateTime.tryParse(_workDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');

    setState(() {
      _workDate = '$y-$m-$d';
    });

    await _load();
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

      if (!mounted) return;
      final headers = _authHeaders(token);

      final candidates = <String>[
        '/attendance/manual-request/clinic',
        '/api/attendance/manual-request/clinic',
      ];

      http.Response? lastRes;

      for (final p in candidates) {
        final uri = _payrollUri(
          p,
          qs: {
            'approvalStatus': _approvalStatus,
            'workDate': _workDate,
          },
        );

        _log('LOAD REQUEST', {
          'url': uri.toString(),
          'approvalStatus': _approvalStatus,
          'workDate': _workDate,
        });

        final res = await _tryGet(uri, headers: headers);

        _log('LOAD RESPONSE', {
          'url': uri.toString(),
          'statusCode': res.statusCode,
          'body': res.body,
        });

        lastRes = res;

        if (res.statusCode == 404) continue;

        if (res.statusCode == 200) {
          final items = _extractItems(res.body);
          if (!mounted) return;
          setState(() {
            _items = items;
            _loading = false;
            _err = '';
          });
          return;
        }

        if (res.statusCode == 401) {
          throw Exception('unauthorized');
        }
        if (res.statusCode == 403) {
          throw Exception('forbidden');
        }

        break;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = [];
        _err = lastRes == null
            ? 'เชื่อมต่อไม่สำเร็จ'
            : (_extractApiMessage(lastRes).isNotEmpty
                ? _extractApiMessage(lastRes)
                : 'โหลดรายการคำขอไม่สำเร็จ');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = [];
        final s = e.toString().toLowerCase();
        if (s.contains('unauthorized') || s.contains('401')) {
          _err = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
        } else if (s.contains('forbidden') || s.contains('403')) {
          _err = 'ไม่มีสิทธิ์เข้าหน้านี้';
        } else {
          _err = 'โหลดรายการคำขอไม่สำเร็จ';
        }
      });
    }
  }

  Future<String?> _showApproveDialog(Map<String, dynamic> item) async {
    final noteCtrl = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('อนุมัติคำขอ'),
          content: TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'หมายเหตุถึงพนักงาน (ถ้ามี)',
              border: OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              FocusScope.of(dialogContext).unfocus();
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(null);
              },
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final text = noteCtrl.text.trim();
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(text);
              },
              child: const Text('อนุมัติ'),
            ),
          ],
        );
      },
    );

    return result;
  }

  Future<String?> _showRejectDialog(Map<String, dynamic> item) async {
    final reasonCtrl = TextEditingController();
    String err = '';

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            return AlertDialog(
              title: const Text('ไม่อนุมัติคำขอ'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'เหตุผลที่ไม่อนุมัติ',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      FocusScope.of(dialogContext).unfocus();
                    },
                  ),
                  if (err.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      err,
                      style: TextStyle(
                        color: Theme.of(innerContext).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(dialogContext).unfocus();
                    Navigator.of(dialogContext).pop(null);
                  },
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: () {
                    final text = reasonCtrl.text.trim();
                    if (text.isEmpty) {
                      setInnerState(() {
                        err = 'กรุณาระบุเหตุผลที่ไม่อนุมัติ';
                      });
                      return;
                    }
                    FocusScope.of(dialogContext).unfocus();
                    Navigator.of(dialogContext).pop(text);
                  },
                  child: const Text('ยืนยันไม่อนุมัติ'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _approveItem(Map<String, dynamic> item) async {
    if (_submitting) return;

    final id = (item['_id'] ?? item['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      _showSnackNow('ไม่พบรหัสคำขอ');
      return;
    }

    final approvalNote = await _showApproveDialog(item);
    if (!mounted) return;
    if (approvalNote == null) return;

    setState(() {
      _submitting = true;
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        _showSnackNow('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      if (!mounted) return;
      final headers = _authHeaders(token);
      final body = jsonEncode({
        'action': 'approve',
        'approvalNote': approvalNote,
      });

      final candidates = <String>[
        '/attendance/manual-request/$id/approve',
        '/api/attendance/manual-request/$id/approve',
      ];

      http.Response? lastRes;

      for (final p in candidates) {
        final uri = _payrollUri(p);

        _log('APPROVE REQUEST', {
          'url': uri.toString(),
          'id': id,
          'body': jsonDecode(body),
        });

        final res = await _tryPost(
          uri,
          headers: headers,
          body: body,
        );

        _log('APPROVE RESPONSE', {
          'url': uri.toString(),
          'statusCode': res.statusCode,
          'body': res.body,
        });

        lastRes = res;

        if (res.statusCode == 404) continue;

        if (res.statusCode == 200 || res.statusCode == 201) {
          if (!mounted) return;

          _removeItemLocally(id);

          if (mounted) {
            setState(() {
              _submitting = false;
            });
          }

          _showSnackNow('อนุมัติคำขอแล้ว');
          return;
        }

        break;
      }

      if (!mounted) return;
      final msg = lastRes != null ? _extractApiMessage(lastRes) : '';
      _showSnackNow(msg.isNotEmpty ? msg : 'อนุมัติไม่สำเร็จ');
    } catch (e) {
      _log('APPROVE ERROR', e.toString());
      if (!mounted) return;
      _showSnackNow('เชื่อมต่อไม่สำเร็จ');
    } finally {
      if (mounted && _submitting) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _rejectItem(Map<String, dynamic> item) async {
    if (_submitting) return;

    final id = (item['_id'] ?? item['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      _showSnackNow('ไม่พบรหัสคำขอ');
      return;
    }

    final rejectReason = await _showRejectDialog(item);
    if (!mounted) return;
    if (rejectReason == null) return;

    setState(() {
      _submitting = true;
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        _showSnackNow('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      if (!mounted) return;
      final headers = _authHeaders(token);
      final body = jsonEncode({
        'action': 'reject',
        'rejectReason': rejectReason,
      });

      final candidates = <String>[
        '/attendance/manual-request/$id/reject',
        '/api/attendance/manual-request/$id/reject',
      ];

      http.Response? lastRes;

      for (final p in candidates) {
        final uri = _payrollUri(p);

        _log('REJECT REQUEST', {
          'url': uri.toString(),
          'id': id,
          'body': jsonDecode(body),
        });

        final res = await _tryPost(
          uri,
          headers: headers,
          body: body,
        );

        _log('REJECT RESPONSE', {
          'url': uri.toString(),
          'statusCode': res.statusCode,
          'body': res.body,
        });

        lastRes = res;

        if (res.statusCode == 404) continue;

        if (res.statusCode == 200 || res.statusCode == 201) {
          if (!mounted) return;

          _removeItemLocally(id);

          if (mounted) {
            setState(() {
              _submitting = false;
            });
          }

          _showSnackNow('บันทึกการไม่อนุมัติแล้ว');
          return;
        }

        break;
      }

      if (!mounted) return;
      final msg = lastRes != null ? _extractApiMessage(lastRes) : '';
      _showSnackNow(msg.isNotEmpty ? msg : 'ไม่สามารถปฏิเสธคำขอได้');
    } catch (e) {
      _log('REJECT ERROR', e.toString());
      if (!mounted) return;
      _showSnackNow('เชื่อมต่อไม่สำเร็จ');
    } finally {
      if (mounted && _submitting) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              k,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '-' : v,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> item) {
    final approvalStatus = (item['approvalStatus'] ?? '').toString().trim();
    final manualType = (item['manualRequestType'] ?? '').toString().trim();
    final requestedAt = item['requestedAt'];
    final requestedCheckInAt = item['requestedCheckInAt'];
    final requestedCheckOutAt = item['requestedCheckOutAt'];
    final workDate = (item['workDate'] ?? '').toString().trim();
    final reasonCode =
        (item['requestReasonCode'] ?? item['reasonCode'] ?? '')
            .toString()
            .trim();
    final reasonText = (item['requestReasonText'] ??
            item['reasonText'] ??
            item['manualReason'] ??
            item['note'] ??
            '')
        .toString()
        .trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _displayName(item),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        _statusColor(context, approvalStatus).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(approvalStatus),
                    style: TextStyle(
                      color: _statusColor(context, approvalStatus),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _kv('ประเภทคำขอ', _manualTypeLabel(manualType)),
            _kv('วันที่ทำงาน', workDate.isEmpty ? '-' : workDate),
            _kv('เวลาที่ขอเข้า', _fmtDateTime(requestedCheckInAt)),
            _kv('เวลาที่ขอออก', _fmtDateTime(requestedCheckOutAt)),
            _kv('ยื่นคำขอเมื่อ', _fmtDateTime(requestedAt)),
            _kv('รหัสเหตุผล', reasonCode.isEmpty ? '-' : reasonCode),
            _kv('รายละเอียด', reasonText.isEmpty ? '-' : reasonText),
            if ((item['approvalNote'] ?? '').toString().trim().isNotEmpty)
              _kv(
                'หมายเหตุอนุมัติ',
                (item['approvalNote'] ?? '').toString().trim(),
              ),
            if ((item['rejectReason'] ?? '').toString().trim().isNotEmpty)
              _kv(
                'เหตุผลที่ไม่อนุมัติ',
                (item['rejectReason'] ?? '').toString().trim(),
              ),
            if (_approvalStatus == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_submitting || _loading)
                          ? null
                          : () => _rejectItem(item),
                      icon: const Icon(Icons.close),
                      label: Text(_submitting ? 'กำลังทำรายการ...' : 'ไม่อนุมัติ'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_submitting || _loading)
                          ? null
                          : () => _approveItem(item),
                      icon: const Icon(Icons.check),
                      label: Text(_submitting ? 'กำลังทำรายการ...' : 'อนุมัติ'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_err.isNotEmpty) {
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
                    'ไม่พร้อมใช้งาน',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _err,
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
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ตัวกรอง',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _approvalStatus,
                    decoration: const InputDecoration(
                      labelText: 'สถานะคำขอ',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('รออนุมัติ'),
                      ),
                      DropdownMenuItem(
                        value: 'approved',
                        child: Text('อนุมัติแล้ว'),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Text('ไม่อนุมัติ'),
                      ),
                    ],
                    onChanged: (_loading || _submitting)
                        ? null
                        : (v) async {
                            if (v == null) return;
                            setState(() {
                              _approvalStatus = v;
                            });
                            await _load();
                          },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('วันที่ทำงาน'),
                    subtitle: Text(_fmtDate(_workDate)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: (_loading || _submitting) ? null : _pickWorkDate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: const [
                    Icon(Icons.inbox_outlined, size: 34),
                    SizedBox(height: 8),
                    Text(
                      'ไม่พบรายการคำขอ',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._items.map(_requestCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('อนุมัติคำขอ Attendance'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: (_loading || _submitting) ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }
}