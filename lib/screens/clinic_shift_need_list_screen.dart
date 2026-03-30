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
// ✅ FIX (สำคัญ): ส่ง needStatus ไปหน้า applicants (OPTION #2)
// - ClinicShiftNeedApplicantsScreen ต้องการ required needStatus
//
// ✅ NEW UX
// - ซ่อนประกาศที่ผ่านมาได้
// - filter: ทั้งหมด / ซ่อนที่ผ่านมา / เฉพาะเปิดรับ
// - ไม่ลบจริงจาก backend เพื่อความปลอดภัย
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

  _NeedListViewMode _viewMode = _NeedListViewMode.hidePast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  String _viewModeLabel(_NeedListViewMode mode) {
    switch (mode) {
      case _NeedListViewMode.all:
        return 'ทั้งหมด';
      case _NeedListViewMode.hidePast:
        return 'ซ่อนประกาศที่ผ่านมา';
      case _NeedListViewMode.openOnly:
        return 'เฉพาะที่ยังเปิดรับ';
    }
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

  DateTime? _parseNeedEndDateTime(ClinicShiftNeed need) {
    try {
      final date = need.date.trim(); // yyyy-MM-dd
      final end = need.end.trim(); // HH:mm
      if (date.isEmpty || end.isEmpty) return null;

      final parts = end.split(':');
      if (parts.length < 2) return null;

      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;

      final d = DateTime.parse(date);
      return DateTime(d.year, d.month, d.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  bool _isPastNeed(ClinicShiftNeed need) {
    final endAt = _parseNeedEndDateTime(need);
    if (endAt == null) return false;
    return endAt.isBefore(DateTime.now());
  }

  bool _isOpenNeed(ClinicShiftNeed need) {
    return need.status.trim().toLowerCase() == 'open';
  }

  List<ClinicShiftNeed> _sortedItems(List<ClinicShiftNeed> source) {
    final list = List<ClinicShiftNeed>.from(source);
    list.sort((a, b) {
      final aPast = _isPastNeed(a);
      final bPast = _isPastNeed(b);

      if (aPast != bPast) {
        return aPast ? 1 : -1;
      }

      final aKey = '${a.date} ${a.start}';
      final bKey = '${b.date} ${b.start}';
      return aKey.compareTo(bKey);
    });
    return list;
  }

  List<ClinicShiftNeed> _visibleItems() {
    final base = _sortedItems(_items);

    switch (_viewMode) {
      case _NeedListViewMode.all:
        return base;
      case _NeedListViewMode.hidePast:
        return base.where((e) => !_isPastNeed(e)).toList();
      case _NeedListViewMode.openOnly:
        return base
            .where((e) => !_isPastNeed(e) && _isOpenNeed(e))
            .toList();
    }
  }

  int _pastCount() {
    return _items.where(_isPastNeed).length;
  }

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
          needStatus: need.status,
        ),
      ),
    );
  }

  Future<void> _openDetail(ClinicShiftNeed need) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final isPast = _isPastNeed(need);

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
                  need.clinicName.isEmpty ? need.clinicId : need.clinicName,
                ),
                _kv('ตำแหน่ง', need.role),
                _kv('วัน', need.date),
                _kv(
                  'เวลา',
                  '${need.start} - ${need.end} (${need.hours.toStringAsFixed(2)} ชม.)',
                ),
                _kv('จำนวนที่ต้องการ', '${need.requiredCount} คน'),
                _kv('สถานะ', _statusLabel(need.status)),
                _kv('ช่วงเวลา', isPast ? 'ผ่านไปแล้ว' : 'ยังไม่ผ่านเวลา'),
                if (need.note.trim().isNotEmpty) _kv('หมายเหตุ', need.note),
                const SizedBox(height: 8),
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
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseViewMode() async {
    final picked = await showModalBottomSheet<_NeedListViewMode>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                title: const Text(
                  'ตัวกรองรายการประกาศงาน',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ),
              RadioListTile<_NeedListViewMode>(
                value: _NeedListViewMode.all,
                groupValue: _viewMode,
                title: const Text('แสดงทั้งหมด'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
              RadioListTile<_NeedListViewMode>(
                value: _NeedListViewMode.hidePast,
                groupValue: _viewMode,
                title: const Text('ซ่อนประกาศที่ผ่านมา'),
                subtitle: const Text('เหมาะกับการดูงานที่ยังเกี่ยวข้องตอนนี้'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
              RadioListTile<_NeedListViewMode>(
                value: _NeedListViewMode.openOnly,
                groupValue: _viewMode,
                title: const Text('เฉพาะที่ยังเปิดรับ'),
                subtitle: const Text('ซ่อนทั้งงานที่ผ่านมาและงานที่เต็ม/ยกเลิกแล้ว'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _viewMode = picked);
    }
  }

  Widget _buildModeBanner() {
    final hiddenPast = _pastCount();

    if (_viewMode != _NeedListViewMode.hidePast || hiddenPast <= 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        color: Colors.amber.shade50,
        child: ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: Text('ซ่อนประกาศที่ผ่านมาอยู่ $hiddenPast รายการ'),
          subtitle: const Text('กดเพื่อแสดงทั้งหมดหรือเปลี่ยนตัวกรอง'),
          trailing: TextButton(
            onPressed: () {
              setState(() => _viewMode = _NeedListViewMode.all);
            },
            child: const Text('ดูทั้งหมด'),
          ),
        ),
      ),
    );
  }

  Widget _buildCountHeader(List<ClinicShiftNeed> visible) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'โหมด: ${_viewModeLabel(_viewMode)}',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${visible.length} รายการ',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _items.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isFiltered ? 'ไม่พบรายการตามตัวกรองที่เลือก' : 'ยังไม่มีประกาศงาน',
          ),
          const SizedBox(height: 12),
          if (isFiltered)
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _viewMode = _NeedListViewMode.all);
              },
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('แสดงทั้งหมด'),
            ),
          if (!isFiltered)
            ElevatedButton.icon(
              onPressed: _goCreate,
              icon: const Icon(Icons.add),
              label: const Text('สร้างประกาศงานแรก'),
            ),
        ],
      ),
    );
  }

  Widget _buildListTile(ClinicShiftNeed n) {
    final isPast = _isPastNeed(n);
    final status = _statusLabel(n.status);

    return Card(
      child: ListTile(
        leading: Icon(
          isPast ? Icons.history_toggle_off : Icons.campaign_outlined,
          color: isPast ? Colors.grey : null,
        ),
        title: Text('${n.date} • ${n.start}-${n.end}'),
        subtitle: Text(
          '${n.role} • ${n.requiredCount} คน • $status${isPast ? ' • ผ่านเวลาแล้ว' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openDetail(n),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายการประกาศงาน'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'ตัวกรอง',
            onPressed: _chooseViewMode,
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            tooltip: 'เพิ่มประกาศงาน',
            onPressed: _goCreate,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goCreate,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildModeBanner(),
                _buildCountHeader(visibleItems),
                Expanded(
                  child: visibleItems.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            itemBuilder: (_, i) {
                              final n = visibleItems[i];
                              return _buildListTile(n);
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemCount: visibleItems.length,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

enum _NeedListViewMode {
  all,
  hidePast,
  openOnly,
}