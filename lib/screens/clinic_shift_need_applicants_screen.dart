// lib/screens/clinic_shift_need_applicants_screen.dart
//
// ✅ FULL FILE (OPTION #2: รับ needStatus จากหน้า list แล้ว “ปิดรับ” ตั้งแต่เปิดหน้าได้ทันที)
// - เพิ่ม widget.needStatus (ส่งมาจาก ClinicShiftNeedListScreen)
// - initState: ถ้า needStatus != open => ปิดปุ่ม “รับเข้าทำงาน” ทั้งหน้า + แสดง banner
// - ยังมี safety ชั้นสอง: ถ้า approve แล้ว backend ตอบ need is not open -> ปิดรับทันที
// - ปุ่ม event (completed/late/no_show/cancelled_early) โชว์เฉพาะ applicant ที่ approved
//
// ✅ Event ตรง model AttendanceEvent:
// - status: completed | late | no_show | cancelled_early
// - minutesLate: number (เฉพาะ late)
// - occurredAt: DateTime.now()
// - clinicId, staffId, shiftId
//
// IMPORTANT:
// - endpoint approve: POST /shift-needs/:id/approve body { staffId }
// - endpoint attendance event: ปรับ path ใน ScoreService ให้ตรง backend ของท่าน (ค่า default ด้านล่าง)
//

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/services/clinic_shift_need_service.dart';
import 'package:clinic_smart_staff/services/score_service.dart';

class ClinicShiftNeedApplicantsScreen extends StatefulWidget {
  final String needId;
  final String title;

  /// ✅ OPTION #2: รับสถานะ need มาจากหน้า list
  /// ค่าที่คาดหวัง: open / filled / cancelled
  final String needStatus;

  const ClinicShiftNeedApplicantsScreen({
    super.key,
    required this.needId,
    required this.title,
    required this.needStatus,
  });

  @override
  State<ClinicShiftNeedApplicantsScreen> createState() =>
      _ClinicShiftNeedApplicantsScreenState();
}

class _ClinicShiftNeedApplicantsScreenState
    extends State<ClinicShiftNeedApplicantsScreen> {
  bool _loading = true;
  bool _approving = false;
  bool _posting = false;

  String _err = '';
  List<Map<String, dynamic>> _items = [];

  /// ✅ เก็บ shiftId ที่ได้จากตอน approve เพื่อใช้ยิง event ให้ถูก shift จริง
  final Map<String, String> _shiftIdByStaff = {};

  /// ✅ ปิดการ “รับเข้าทำงาน” ทั้งหน้า ถ้า need ไม่ open
  bool _needClosed = false;
  String _needClosedMsg = '';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _s(dynamic v) => (v ?? '').toString();
  String _norm(String s) => s.trim().toLowerCase();

  String _needStatusLabel(String s) {
    final v = _norm(s);
    if (v == 'open') return 'เปิดรับ';
    if (v == 'filled') return 'เต็มแล้ว';
    if (v == 'cancelled') return 'ยกเลิก';
    return s;
  }

  // =========================
  // LOAD applicants (ผ่าน service เดิม)
  // =========================
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
      _items = [];
      // ❌ ไม่รีเซ็ต _needClosed ที่นี่ เพื่อกันกดซ้ำหลังรู้ว่า need ปิดแล้ว
    });

    try {
      final raw = await ClinicShiftNeedService.loadApplicants(widget.needId);

      final items = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it is Map) items.add(Map<String, dynamic>.from(it));
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
      _snack('โหลดผู้สมัครไม่สำเร็จ: $e');
    }
  }

  // =========================
  // Helpers (status)
  // =========================
  bool _isApproved(Map<String, dynamic> m) {
    final s = _s(m['status']).trim().toLowerCase();
    return s == 'approved';
  }

  bool _isPending(Map<String, dynamic> m) {
    final s = _s(m['status']).trim().toLowerCase();
    return s.isEmpty || s == 'pending' || s == 'waiting';
  }

  bool _isRejected(Map<String, dynamic> m) {
    final s = _s(m['status']).trim().toLowerCase();
    return s == 'rejected';
  }

  // =========================
  // APPROVE (รับเข้าทำงาน)
  // POST /shift-needs/:id/approve  { staffId }
  // =========================
  Future<void> _approveApplicant(String staffId) async {
    if (_approving) return;

    if (_needClosed) {
      _snack(_needClosedMsg.isNotEmpty
          ? _needClosedMsg
          : 'งานนี้ปิดรับแล้ว (need is not open)');
      return;
    }

    final sid = staffId.trim();
    if (sid.isEmpty) {
      _snack('staffId ว่าง (backend ส่งมาไม่ครบ)');
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('รับผู้สมัครเข้าทำงาน?'),
            content: Text(
              'ต้องการ “รับเข้าทำงาน” staffId: $sid ใช่ไหม?\n\n'
              'ระบบจะสร้าง Shift ให้ผู้ช่วย (แล้วจะไปโผล่ที่หน้า “งานของฉัน”)',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('รับเข้าทำงาน'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    setState(() => _approving = true);

    try {
      final decoded = await ClinicShiftNeedService.approveApplicant(
        needId: widget.needId,
        staffId: sid,
        // ถ้า route ท่านไม่ใช่นี้ค่อย override ใน service ได้
        pathBuilder: (id) => '/shift-needs/$id/approve',
      );

      // backend ตามที่ท่านแปะ: { ok:true, shift:{...} }
      String shiftId = '';
      if (decoded is Map) {
        final shift = decoded['shift'];
        if (shift is Map) {
          shiftId = (shift['_id'] ?? shift['id'] ?? '').toString().trim();
        }
      }
      if (shiftId.isNotEmpty) {
        _shiftIdByStaff[sid] = shiftId;
      }

      // ✅ mark approved ใน UI ทันที
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          final m = _items[i];
          final staffInRow =
              _s(m['staffId'] ?? m['assistantId'] ?? m['userId']).trim();
          if (staffInRow == sid) {
            final newMap = Map<String, dynamic>.from(m);
            newMap['status'] = 'approved';
            _items[i] = newMap;
          } else {
            // backend ของท่านจะ reject คนอื่นอัตโนมัติ
            // ถ้าท่านอยาก reflect เลย ก็เปิดบรรทัดนี้ได้:
            // final newMap = Map<String, dynamic>.from(m);
            // newMap['status'] = 'rejected';
            // _items[i] = newMap;
          }
        }
      });

      _snack('✅ รับเข้าทำงานแล้ว (สร้าง Shift แล้ว)');
      await _load();
    } catch (e) {
      final msg = e.toString().toLowerCase();

      // ✅ safety ชั้นสอง: ถ้า backend บอก need ปิดแล้ว -> ปิดการรับทั้งหมดในหน้านี้ทันที
      if (msg.contains('need is not open') || msg.contains('not open')) {
        setState(() {
          _needClosed = true;
          _needClosedMsg =
              'งานนี้ปิดรับแล้ว (need is not open) — กรุณากลับไปหน้า “รายการประกาศงาน” เพื่อดูสถานะล่าสุด';
        });
      }

      _snack('รับเข้าทำงานไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _approving = false);
    }
  }

  // =========================
  // Attendance Event actions (ตรง model)
  // =========================
  Future<int?> _askMinutesLate() async {
    final ctrl = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('มาสายกี่นาที?'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'เช่น 10',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('บันทึก'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return null;

    final n = int.tryParse(ctrl.text.trim());
    if (n == null || n < 0) return 0;
    return n;
  }

  Future<void> _postEvent({
    required String staffId,
    required String status, // completed | late | no_show | cancelled_early
    int minutesLate = 0,
  }) async {
    if (_posting) return;

    final sid = staffId.trim();
    if (sid.isEmpty) {
      _snack('staffId ว่าง (backend ส่งมาไม่ครบ)');
      return;
    }

    setState(() => _posting = true);

    try {
      // ✅ ใช้ shiftId จริงถ้ามี (จากตอน approve)
      final shiftId = (_shiftIdByStaff[sid] ?? '').trim();

      await ScoreService.postAttendanceEvent(
        staffId: sid,
        shiftId: shiftId, // ถ้าว่าง backend จะรับเป็น "" ได้ (ตาม model default)
        status: status,
        minutesLate: minutesLate,
        occurredAt: DateTime.now(),
      );

      _snack('บันทึกเหตุการณ์แล้ว ✅ ($status)');
      await _load();
    } catch (e) {
      _snack('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _posting = false);
    }
  }

  // =========================
  // UI helpers
  // =========================
  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final s = status.trim().toLowerCase();
    String text;
    if (s == 'approved') {
      text = 'รับแล้ว';
    } else if (s == 'rejected') {
      text = 'ปฏิเสธ';
    } else {
      text = 'รออนุมัติ';
    }
    return Chip(label: Text(text), visualDensity: VisualDensity.compact);
  }

  @override
  void initState() {
    super.initState();

    // ✅ OPTION #2: ปิดรับตั้งแต่เปิดหน้า ถ้า needStatus != open
    final st = _norm(widget.needStatus);
    if (st.isNotEmpty && st != 'open') {
      _needClosed = true;
      _needClosedMsg =
          'งานนี้ปิดรับแล้ว (status: ${_needStatusLabel(widget.needStatus)}) — ปุ่ม “รับเข้าทำงาน” ถูกปิดอัตโนมัติ';
    }

    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('ผู้สมัคร: ${widget.title}'),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: (_approving || _posting) ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'โหลดผู้สมัครไม่สำเร็จ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Text(_err, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('ลองใหม่'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'ยังไม่มีผู้สมัคร',
                          style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          // ✅ Banner ถ้างานปิดรับแล้ว
                          if (_needClosed)
                            Container(
                              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.primary.withOpacity(0.25),
                                ),
                              ),
                              child: Text(
                                _needClosedMsg.isNotEmpty
                                    ? _needClosedMsg
                                    : 'งานนี้ปิดรับแล้ว — ปุ่ม “รับเข้าทำงาน” ถูกปิดอัตโนมัติ',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),

                          ...List.generate(_items.length, (i) {
                            final m = _items[i];

                            final name = _s(
                              m['fullName'] ?? m['name'] ?? m['helperName'],
                            );

                            final staffId = _s(
                              m['staffId'] ?? m['assistantId'] ?? m['userId'],
                            ).trim();

                            final phone = _s(m['phone'] ?? m['tel']);
                            final note = _s(m['note']);
                            final status = _s(m['status']); // pending/approved/rejected

                            final approved = _isApproved(m);
                            final pending = _isPending(m);
                            final rejected = _isRejected(m);

                            // ✅ รับได้เฉพาะ pending + งานยังไม่ปิด
                            final canApprove =
                                staffId.isNotEmpty && pending && !_needClosed;

                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        backgroundColor: cs.primary.withOpacity(0.12),
                                        child: Icon(Icons.person, color: cs.primary),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(name.isEmpty ? 'ผู้ช่วย' : name),
                                          ),
                                          _statusChip(status),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'staffId: ${staffId.isEmpty ? '-' : staffId}\n'
                                          'โทร: ${phone.isEmpty ? '-' : phone}'
                                          '${note.trim().isEmpty ? '' : '\nหมายเหตุ: $note'}',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // ✅ ปุ่ม “รับเข้าทำงาน” (เฉพาะ pending)
                                    if (staffId.isNotEmpty && pending && !approved && !rejected)
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: (!canApprove || _approving)
                                              ? null
                                              : () => _approveApplicant(staffId),
                                          icon: _approving
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.check_circle),
                                          label: Text(_needClosed ? 'ปิดรับแล้ว' : 'รับเข้าทำงาน'),
                                        ),
                                      ),

                                    // ✅ ปุ่ม event (โชว์เมื่อ approved เท่านั้น) — ตรง model AttendanceEvent
                                    if (staffId.isNotEmpty && approved) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          _actionButton(
                                            label: 'เสร็จงาน',
                                            icon: Icons.check_circle,
                                            onPressed: _posting
                                                ? null
                                                : () => _postEvent(
                                                      staffId: staffId,
                                                      status: 'completed',
                                                    ),
                                          ),
                                          const SizedBox(width: 8),
                                          _actionButton(
                                            label: 'มาสาย',
                                            icon: Icons.schedule,
                                            onPressed: _posting
                                                ? null
                                                : () async {
                                                    final mins = await _askMinutesLate();
                                                    if (mins == null) return;
                                                    await _postEvent(
                                                      staffId: staffId,
                                                      status: 'late',
                                                      minutesLate: mins,
                                                    );
                                                  },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          _actionButton(
                                            label: 'ไม่มา',
                                            icon: Icons.person_off,
                                            onPressed: _posting
                                                ? null
                                                : () => _postEvent(
                                                      staffId: staffId,
                                                      status: 'no_show',
                                                    ),
                                          ),
                                          const SizedBox(width: 8),
                                          _actionButton(
                                            label: 'ยกเลิกก่อนเวลา',
                                            icon: Icons.cancel,
                                            onPressed: _posting
                                                ? null
                                                : () => _postEvent(
                                                      staffId: staffId,
                                                      status: 'cancelled_early',
                                                    ),
                                          ),
                                        ],
                                      ),
                                    ],

                                    if (_posting) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: const [
                                          SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text('กำลังบันทึกเหตุการณ์...'),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
      ),
    );
  }
}