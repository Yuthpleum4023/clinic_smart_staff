// lib/screens/clinic_shift_need_list_screen.dart
//
// ✅ ShiftNeed List (BACKEND)
// - โหลดจาก backend ผ่าน ClinicShiftNeedService
// - กด + เพื่อไปหน้า ClinicShiftNeedScreen (ฟอร์มประกาศงาน)
// - กดรายการเพื่อดูรายละเอียดแบบอ่านอย่างเดียว
//
// ✅ Actions (ตรง backend จริง)
// - ดูผู้สมัคร (GET /shift-needs/:id/applicants)
// - ยกเลิกประกาศงาน (PATCH /shift-needs/:id/cancel)
//

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/models/clinic_shift_need_model.dart';
import 'package:clinic_smart_staff/services/clinic_shift_need_service.dart';

import 'package:clinic_smart_staff/screens/clinic_shift_need_screen.dart';
import 'package:clinic_smart_staff/screens/clinic_shift_need_applicants_screen.dart';

class ClinicShiftNeedListScreen extends StatefulWidget {
  final String clinicId;
  const ClinicShiftNeedListScreen({super.key, required this.clinicId});

  @override
  State<ClinicShiftNeedListScreen> createState() =>
      _ClinicShiftNeedListScreenState();
}

class _ClinicShiftNeedListScreenState extends State<ClinicShiftNeedListScreen> {
  bool _loading = true;
  List<ClinicShiftNeed> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ClinicShiftNeedService.loadAll(widget.clinicId);
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      _snack('โหลดรายการไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(String s) {
    final v = s.trim().toLowerCase();
    if (v == 'open') return 'เปิดรับ';
    if (v == 'filled') return 'เต็มแล้ว';
    if (v == 'cancelled') return 'ยกเลิก';
    return s;
  }

  Future<void> _goCreate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicShiftNeedScreen(clinicId: widget.clinicId),
      ),
    );

    if (ok == true) {
      await _load();
    }
  }

  // ------------------------------------------------------------
  // Applicants
  // ------------------------------------------------------------
  Future<void> _openApplicants(ClinicShiftNeed need) async {
    if (need.id.trim().isEmpty) {
      _snack('needId ว่าง (เปิดรายชื่อผู้สมัครไม่ได้)');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicShiftNeedApplicantsScreen(
          needId: need.id,
          title: '${need.date} ${need.start}-${need.end} • ${need.role}',
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Detail / Actions
  // ------------------------------------------------------------
  Future<void> _openDetail(ClinicShiftNeed need) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Wrap(
              runSpacing: 10,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'รายละเอียดประกาศงาน',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                _kv(
                  'คลินิก',
                  need.clinicName.isEmpty
                      ? need.clinicId
                      : need.clinicName,
                ),
                _kv('ตำแหน่ง', need.role),
                _kv('วัน', need.date),
                _kv(
                  'เวลา',
                  '${need.start} - ${need.end} (${need.hours.toStringAsFixed(2)} ชม.)',
                ),
                _kv('จำนวนที่ต้องการ', '${need.requiredCount} คน'),
                _kv('สถานะ', _statusLabel(need.status)),
                if (need.note.trim().isNotEmpty)
                  _kv('หมายเหตุ', need.note),

                const SizedBox(height: 8),

                // ---------------- Applicants ----------------
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _openApplicants(need);
                    },
                    icon: const Icon(Icons.people_outline),
                    label: const Text('ดูผู้สมัคร'),
                  ),
                ),

                const SizedBox(height: 6),

                // ---------------- Cancel (NOT delete) ----------------
                if (need.status.toLowerCase() == 'open')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final ok = await _confirmCancel(need);
                        if (ok != true) return;

                        await ClinicShiftNeedService.removeById(
                          widget.clinicId,
                          need.id,
                        );

                        if (!mounted) return;
                        Navigator.pop(ctx);
                        await _load();
                        _snack('ยกเลิกประกาศงานแล้ว');
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('ยกเลิกประกาศงานนี้'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(v)),
      ],
    );
  }

  Future<bool?> _confirmCancel(ClinicShiftNeed need) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการยกเลิก'),
        content: Text(
          'ต้องการยกเลิกประกาศงานวันที่ ${need.date} '
          'เวลา ${need.start}-${need.end} ใช่ไหม?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('รายการประกาศงาน (ShiftNeed)'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _goCreate, icon: const Icon(Icons.add)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goCreate,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ยังไม่มีประกาศงาน'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _goCreate,
                        icon: const Icon(Icons.add),
                        label: const Text('สร้างประกาศงานแรก'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.campaign_outlined),
                          title: Text('${n.date} • ${n.start}-${n.end}'),
                          subtitle: Text(
                            '${n.role} • ${n.requiredCount} คน • ${_statusLabel(n.status)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openDetail(n),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemCount: _items.length,
                  ),
                ),
    );
  }
}
