// lib/screens/clinic_shift_need_applicants_screen.dart
//
// ✅ FULL FILE (POLISHED THAI COPY + CLEAN UI)
// - ซ่อน staffId ออกจาก UI
// - ถ้าไม่มี location -> ใช้ข้อความ “ยังไม่มีพิกัดผู้ช่วย”
// - ปรับคำ “ใกล้” -> “ใกล้คลินิก”
// - ยังรักษา logic เดิมเรื่อง approve / auto match / attendance event ครบ
//
// ✅ PATCH NEW
// - แปล error approve ชนกะเป็นภาษาไทย
// - รองรับ backend response ที่ส่ง conflictShift / conflictText / code กลับมา
// - แสดง dialog ชัดเจนว่า “ผู้ช่วยคนนี้มีงานกะอื่นอยู่แล้ว”
// - ถ้า service ยังส่ง error แบบดิบ ก็พยายาม parse จากข้อความให้มากที่สุด
//

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/services/clinic_shift_need_service.dart';
import 'package:clinic_smart_staff/services/score_service.dart';

class ClinicShiftNeedApplicantsScreen extends StatefulWidget {
  final String needId;
  final String title;

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

  final Map<String, String> _shiftIdByStaff = {};

  bool _needClosed = false;
  String _needClosedMsg = '';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _s(dynamic v) => (v ?? '').toString();
  String _norm(String s) => s.trim().toLowerCase();

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    final s = _norm('$v');
    return s == 'true' || s == '1' || s == 'yes';
  }

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v);
    }
    return <String, dynamic>{};
  }

  String _needStatusLabel(String s) {
    final v = _norm(s);
    if (v == 'open') return 'เปิดรับ';
    if (v == 'filled') return 'เต็มแล้ว';
    if (v == 'cancelled') return 'ยกเลิก';
    return s;
  }

  // =========================
  // Error helpers
  // =========================
  Map<String, dynamic> _tryJsonFromAny(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    final text = raw?.toString() ?? '';
    if (text.trim().isEmpty) return <String, dynamic>{};

    try {
      final direct = jsonDecode(text);
      if (direct is Map) {
        return Map<String, dynamic>.from(direct);
      }
    } catch (_) {}

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final jsonText = text.substring(start, end + 1);
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return <String, dynamic>{};
  }

  String _buildConflictShiftLine(Map<String, dynamic> body) {
    final shift = _map(body['conflictShift']);

    final clinicName = _s(
      shift['clinicName'] ?? shift['clinicTitle'] ?? shift['clinicId'],
    ).trim();

    final date = _s(shift['date'] ?? shift['workDate']).trim();
    final start = _s(shift['start'] ?? shift['startTime']).trim();
    final end = _s(shift['end'] ?? shift['endTime']).trim();

    final parts = <String>[];
    if (clinicName.isNotEmpty) parts.add('คลินิก $clinicName');
    if (date.isNotEmpty) parts.add('วันที่ $date');
    if (start.isNotEmpty || end.isNotEmpty) {
      parts.add(
        'เวลา ${start.isEmpty ? "--:--" : start}-${end.isEmpty ? "--:--" : end}',
      );
    }

    return parts.join(' • ');
  }

  String _friendlyApproveError(dynamic error) {
    final body = _tryJsonFromAny(error);

    final code = _norm(_s(body['code']));
    final msg = _s(body['message']).trim();
    final err = _s(body['error']).trim();
    final detail = _s(body['detail']).trim();
    final conflictText = _s(body['conflictText']).trim();
    final conflictLine = _buildConflictShiftLine(body);

    if (code == 'shift_overlap' ||
        _norm(err) == 'applicant already has overlapping shift' ||
        _norm(msg).contains('overlapping shift') ||
        _norm(detail).contains('overlapping shift') ||
        _norm(conflictText).contains('ชน') ||
        _norm(error.toString()).contains('applicant already has overlapping shift')) {
      if (conflictLine.isNotEmpty) {
        return 'ผู้ช่วยคนนี้มีงานกะอื่นอยู่แล้ว\n$conflictLine';
      }
      if (conflictText.isNotEmpty) {
        return 'ผู้ช่วยคนนี้มีงานกะอื่นอยู่แล้ว\n$conflictText';
      }
      return 'ผู้ช่วยคนนี้มีงานกะอื่นเวลา 09:00-17:00 อยู่แล้ว';
    }

    if (code == 'shift_already_created' ||
        _norm(err).contains('shift already created')) {
      if (conflictLine.isNotEmpty) {
        return 'ผู้สมัครคนนี้ถูกอนุมัติและสร้างกะงานไปแล้ว\n$conflictLine';
      }
      return 'ผู้สมัครคนนี้ถูกอนุมัติและสร้างกะงานไปแล้ว';
    }

    if (_norm(msg).contains('need is not open') || _norm(err).contains('need is not open')) {
      return 'งานนี้ปิดรับแล้ว กรุณากลับไปดูสถานะล่าสุดที่หน้ารายการประกาศงาน';
    }

    if (conflictLine.isNotEmpty && msg.isNotEmpty) {
      return '$msg\n$conflictLine';
    }

    if (conflictText.isNotEmpty && msg.isNotEmpty) {
      return '$msg\n$conflictText';
    }

    if (msg.isNotEmpty && msg != 'approveApplicant failed') {
      return msg;
    }

    if (err.isNotEmpty && err != 'approveApplicant failed') {
      return err;
    }

    if (detail.isNotEmpty) {
      return detail;
    }

    return 'รับเข้าทำงานไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  Future<void> _showApproveErrorDialog(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ไม่สามารถรับเข้าทำงานได้'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  // =========================
  // Location helpers
  // =========================
  Map<String, dynamic> _extractLocation(Map<String, dynamic> m) {
    final loc = _map(m['location']);
    final geo = _map(m['geo']);

    final lat = _toDouble(
      m['lat'] ??
          m['helperLat'] ??
          m['assistantLat'] ??
          m['userLat'] ??
          loc['lat'] ??
          loc['latitude'] ??
          geo['lat'] ??
          geo['latitude'],
    );

    final lng = _toDouble(
      m['lng'] ??
          m['lon'] ??
          m['long'] ??
          m['longitude'] ??
          m['helperLng'] ??
          m['assistantLng'] ??
          m['userLng'] ??
          loc['lng'] ??
          loc['longitude'] ??
          geo['lng'] ??
          geo['longitude'],
    );

    final district = _s(
      m['district'] ??
          m['helperDistrict'] ??
          m['assistantDistrict'] ??
          m['amphoe'] ??
          loc['district'] ??
          loc['amphoe'],
    ).trim();

    final province = _s(
      m['province'] ??
          m['helperProvince'] ??
          m['assistantProvince'] ??
          m['changwat'] ??
          loc['province'] ??
          loc['changwat'],
    ).trim();

    final address = _s(
      m['address'] ??
          m['fullAddress'] ??
          m['helperAddress'] ??
          m['assistantAddress'] ??
          loc['address'] ??
          loc['fullAddress'],
    ).trim();

    final label = _s(
      m['locationLabel'] ??
          m['label'] ??
          m['helperLocationLabel'] ??
          m['assistantLocationLabel'] ??
          loc['label'] ??
          loc['locationLabel'],
    ).trim();

    final distanceKm = _toDouble(
      m['distanceKm'] ??
          m['distance'] ??
          m['helperDistanceKm'] ??
          m['assistantDistanceKm'],
    );

    return {
      'lat': lat,
      'lng': lng,
      'district': district,
      'province': province,
      'address': address,
      'label': label,
      'distanceKm': distanceKm,
      'hasCoords': lat != null && lng != null,
    };
  }

  String _locationHeadline(Map<String, dynamic> m) {
    final district = _s(m['district']).trim();
    final province = _s(m['province']).trim();
    final label = _s(m['label']).trim();

    final districtProvince = [district, province]
        .where((e) => e.trim().isNotEmpty)
        .join(', ');

    if (districtProvince.isNotEmpty) return districtProvince;
    if (label.isNotEmpty) return label;
    return 'ยังไม่มีพิกัดผู้ช่วย';
  }

  String _distanceText(double km) {
    if (km < 1) {
      final meters = (km * 1000).round();
      return '$meters เมตร';
    }
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} กม.';
  }

  // =========================
  // Auto match helpers
  // =========================
  bool _isRecommended(Map<String, dynamic> m) {
    return _toBool(m['recommended']);
  }

  int? _rank(Map<String, dynamic> m) {
    return _toInt(m['rank']);
  }

  String _recommendReason(Map<String, dynamic> m) {
    return _s(m['recommendReason']).trim();
  }

  String _matchTier(Map<String, dynamic> m) {
    return _norm(_s(m['matchTier']));
  }

  String _recommendScoreText(Map<String, dynamic> m) {
    final score = _toDouble(m['recommendScore']);
    if (score == null) return '';
    if (score == score.roundToDouble()) {
      return score.toStringAsFixed(0);
    }
    return score.toStringAsFixed(1);
  }

  Color _tierColor(ColorScheme cs, String tier) {
    switch (tier) {
      case 'near':
        return Colors.green.shade700;
      case 'medium':
        return Colors.orange.shade700;
      case 'far':
        return Colors.blueGrey.shade700;
      default:
        return cs.primary;
    }
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'near':
        return 'ใกล้คลินิก';
      case 'medium':
        return 'ระยะกลาง';
      case 'far':
        return 'ค่อนข้างไกล';
      default:
        return 'ยังไม่ทราบ';
    }
  }

  Widget _infoRow({
    required IconData icon,
    required String text,
    Color? color,
    FontWeight? weight,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: weight,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required String text,
    required Color bg,
    required Color fg,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoMatchSection(Map<String, dynamic> item, ColorScheme cs) {
    final recommended = _isRecommended(item);
    final rank = _rank(item);
    final reason = _recommendReason(item);
    final tier = _matchTier(item);
    final scoreText = _recommendScoreText(item);

    final hasAnyData = recommended ||
        rank != null ||
        reason.isNotEmpty ||
        tier.isNotEmpty ||
        scoreText.isNotEmpty;

    if (!hasAnyData) return const SizedBox.shrink();

    final tierColor = _tierColor(cs, tier);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: recommended
            ? Colors.amber.withOpacity(0.12)
            : cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: recommended
              ? Colors.amber.withOpacity(0.45)
              : cs.primary.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (recommended)
                _buildBadge(
                  text: 'แนะนำอัตโนมัติ',
                  bg: Colors.amber.shade100,
                  fg: Colors.amber.shade900,
                  icon: Icons.auto_awesome,
                ),
              if (rank != null)
                _buildBadge(
                  text: 'อันดับ #$rank',
                  bg: cs.primary.withOpacity(0.12),
                  fg: cs.primary,
                  icon: Icons.leaderboard_outlined,
                ),
              if (tier.isNotEmpty)
                _buildBadge(
                  text: _tierLabel(tier),
                  bg: tierColor.withOpacity(0.12),
                  fg: tierColor,
                  icon: Icons.route,
                ),
              if (scoreText.isNotEmpty)
                _buildBadge(
                  text: 'คะแนน $scoreText',
                  bg: Colors.teal.withOpacity(0.12),
                  fg: Colors.teal.shade800,
                  icon: Icons.insights_outlined,
                ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              icon: recommended ? Icons.star : Icons.info_outline,
              text: reason,
              color: recommended ? Colors.amber.shade900 : cs.primary,
              weight: FontWeight.w700,
            ),
          ],
        ],
      ),
    );
  }

  Widget _locationSection(Map<String, dynamic> item, ColorScheme cs) {
    final loc = _extractLocation(item);

    final headline = _locationHeadline(loc);
    final address = _s(loc['address']).trim();
    final label = _s(loc['label']).trim();
    final hasCoords = loc['hasCoords'] == true;
    final distanceKm =
        loc['distanceKm'] is double ? loc['distanceKm'] as double : null;

    final district = _s(loc['district']).trim();
    final province = _s(loc['province']).trim();

    final showPlaceholder = !hasCoords &&
        district.isEmpty &&
        province.isEmpty &&
        address.isEmpty &&
        label.isEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ตำแหน่งผู้ช่วย',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          if (showPlaceholder)
            _infoRow(
              icon: Icons.location_off,
              text: 'ยังไม่มีพิกัดผู้ช่วย',
              color: cs.onSurface.withOpacity(0.7),
              weight: FontWeight.w700,
            )
          else ...[
            _infoRow(
              icon: Icons.place,
              text: headline,
              weight: FontWeight.w800,
            ),
            if (label.isNotEmpty && label != headline)
              _infoRow(
                icon: Icons.pin_drop_outlined,
                text: label,
              ),
            if (address.isNotEmpty)
              _infoRow(
                icon: Icons.home_work_outlined,
                text: address,
              ),
            if (distanceKm != null)
              _infoRow(
                icon: Icons.route,
                text: 'ห่างจากคลินิก ${_distanceText(distanceKm)}',
                color: cs.primary,
                weight: FontWeight.w700,
              ),
            if (distanceKm == null && hasCoords)
              _infoRow(
                icon: Icons.my_location_outlined,
                text: 'มีพิกัดผู้ช่วยแล้ว',
                color: cs.primary,
                weight: FontWeight.w700,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
      _items = [];
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

  Future<void> _approveApplicant(String staffId) async {
    if (_approving) return;

    if (_needClosed) {
      _snack(_needClosedMsg.isNotEmpty ? _needClosedMsg : 'งานนี้ปิดรับแล้ว');
      return;
    }

    final sid = staffId.trim();
    if (sid.isEmpty) {
      _snack('ไม่พบข้อมูลผู้สมัคร');
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('รับผู้สมัครเข้าทำงาน?'),
            content: const Text(
              'ต้องการรับผู้สมัครคนนี้เข้าทำงานใช่ไหม?\n\nระบบจะสร้าง Shift ให้ผู้ช่วยโดยอัตโนมัติ',
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
        pathBuilder: (id) => '/shift-needs/$id/approve',
      );

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

      setState(() {
        for (var i = 0; i < _items.length; i++) {
          final m = _items[i];
          final staffInRow =
              _s(m['staffId'] ?? m['assistantId'] ?? m['userId']).trim();
          if (staffInRow == sid) {
            final newMap = Map<String, dynamic>.from(m);
            newMap['status'] = 'approved';
            _items[i] = newMap;
          }
        }
      });

      _snack('✅ รับเข้าทำงานแล้ว');
      await _load();
    } catch (e) {
      final raw = e.toString().toLowerCase();

      if (raw.contains('need is not open') || raw.contains('not open')) {
        setState(() {
          _needClosed = true;
          _needClosedMsg =
              'งานนี้ปิดรับแล้ว กรุณากลับไปดูสถานะล่าสุดที่หน้ารายการประกาศงาน';
        });
      }

      final friendly = _friendlyApproveError(e);
      await _showApproveErrorDialog(friendly);
      _snack(friendly.replaceAll('\n', ' • '));
    } finally {
      if (!mounted) return;
      setState(() => _approving = false);
    }
  }

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
    required String status,
    int minutesLate = 0,
  }) async {
    if (_posting) return;

    final sid = staffId.trim();
    if (sid.isEmpty) {
      _snack('ไม่พบข้อมูลผู้สมัคร');
      return;
    }

    setState(() => _posting = true);

    try {
      final shiftId = (_shiftIdByStaff[sid] ?? '').trim();

      await ScoreService.postAttendanceEvent(
        staffId: sid,
        shiftId: shiftId,
        status: status,
        minutesLate: minutesLate,
        occurredAt: DateTime.now(),
      );

      _snack('บันทึกเหตุการณ์แล้ว ✅');
      await _load();
    } catch (e) {
      _snack('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _posting = false);
    }
  }

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

    final st = _norm(widget.needStatus);
    if (st.isNotEmpty && st != 'open') {
      _needClosed = true;
      _needClosedMsg =
          'งานนี้ปิดรับแล้ว (สถานะ: ${_needStatusLabel(widget.needStatus)})';
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
                                    : 'งานนี้ปิดรับแล้ว',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ...List.generate(_items.length, (i) {
                            final m = _items[i];

                            final name = _s(
                              m['fullName'] ?? m['name'] ?? m['helperName'],
                            ).trim();

                            final staffId = _s(
                              m['staffId'] ?? m['assistantId'] ?? m['userId'],
                            ).trim();

                            final phone = _s(m['phone'] ?? m['tel']).trim();
                            final note = _s(m['note']).trim();
                            final status = _s(m['status']);

                            final approved = _isApproved(m);
                            final pending = _isPending(m);
                            final rejected = _isRejected(m);

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
                                            child: Text(
                                              name.isEmpty ? 'ผู้ช่วย' : name,
                                            ),
                                          ),
                                          _statusChip(status),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'โทร: ${phone.isEmpty ? '-' : phone}'
                                          '${note.isEmpty ? '' : '\nหมายเหตุ: $note'}',
                                        ),
                                      ),
                                    ),
                                    _autoMatchSection(m, cs),
                                    _locationSection(m, cs),
                                    const SizedBox(height: 10),
                                    if (staffId.isNotEmpty &&
                                        pending &&
                                        !approved &&
                                        !rejected)
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
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(Icons.check_circle),
                                          label: Text(
                                            _needClosed ? 'ปิดรับแล้ว' : 'รับเข้าทำงาน',
                                          ),
                                        ),
                                      ),
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
                                      const Row(
                                        children: [
                                          SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
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