// lib/screens/add_helper_availability_screen.dart
import 'package:flutter/material.dart';

import '../services/helper_availability_service.dart';

class AddHelperAvailabilityScreen extends StatefulWidget {
  final String helperId;
  final String helperName;

  const AddHelperAvailabilityScreen({
    super.key,
    required this.helperId,
    required this.helperName,
  });

  @override
  State<AddHelperAvailabilityScreen> createState() =>
      _AddHelperAvailabilityScreenState();
}

class _AddHelperAvailabilityScreenState
    extends State<AddHelperAvailabilityScreen> {
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;

  final _roleCtrl = TextEditingController(text: 'ผู้ช่วยทันตแพทย์');
  final _noteCtrl = TextEditingController();

  bool _saving = false;

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  double _calcHours(DateTime date, TimeOfDay start, TimeOfDay end) {
    final s = DateTime(date.year, date.month, date.day, start.hour, start.minute);
    final e = DateTime(date.year, date.month, date.day, end.hour, end.minute);
    return e.difference(s).inMinutes / 60.0;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'เลือกวันที่ว่าง',
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _start ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'เวลาเริ่มว่าง',
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _end ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'เวลาสิ้นสุดว่าง',
    );
    if (picked != null) setState(() => _end = picked);
  }

  bool get _timeValid {
    if (_date == null || _start == null || _end == null) return true;
    final hours = _calcHours(_date!, _start!, _end!);
    return hours > 0;
  }

  double get _previewHours {
    if (_date == null || _start == null || _end == null) return 0;
    return _calcHours(_date!, _start!, _end!);
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_date == null || _start == null || _end == null) {
      _snack('กรุณาเลือก วันที่/เวลาเริ่ม/เวลาสิ้นสุด ให้ครบ');
      return;
    }

    if (!_timeValid) {
      _snack('เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม');
      return;
    }

    final role = _roleCtrl.text.trim();
    if (role.isEmpty) {
      _snack('กรุณากรอกบทบาท/ตำแหน่ง');
      return;
    }

    final hours = _calcHours(_date!, _start!, _end!);
    if (hours <= 0 || hours > 24) {
      _snack('ช่วงเวลาที่เลือกผิดปกติ (${hours.toStringAsFixed(2)} ชม.)');
      return;
    }

    setState(() => _saving = true);

    try {
      final created = await HelperAvailabilityService.addRemote(
        date: _fmtDate(_date!),
        start: _fmtTime(_start!),
        end: _fmtTime(_end!),
        role: role,
        note: _noteCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      final msg = e.toString().toLowerCase();

      if (msg.contains('overlap')) {
        _snack('เวลาซ้อนกับรายการเดิมแล้วครับท่าน');
      } else if (msg.contains('401') || msg.contains('unauthorized')) {
        _snack('session หมดอายุ กรุณา login ใหม่');
      } else if (msg.contains('socket') || msg.contains('network')) {
        _snack('เชื่อมต่อ server ไม่ได้');
      } else {
        _snack('บันทึกไม่สำเร็จ');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _roleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _previewHours;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ลงเวลาว่าง (ผู้ช่วย)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'ผู้ช่วย: ${widget.helperName}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _roleCtrl,
            decoration: const InputDecoration(
              labelText: 'บทบาท/ตำแหน่ง',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _pickDate,
                  child: Text(
                    _date == null ? 'เลือกวันที่' : _fmtDate(_date!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _pickStart,
                  child: Text(
                    _start == null ? 'เริ่ม' : _start!.format(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _pickEnd,
                  child: Text(
                    _end == null ? 'สิ้นสุด' : _end!.format(context),
                  ),
                ),
              ),
            ],
          ),

          if (hours > 0) ...[
            const SizedBox(height: 8),
            Text(
              'รวม ${hours.toStringAsFixed(2)} ชั่วโมง',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: hours <= 0 ? Colors.red : null,
              ),
            ),
          ],

          const SizedBox(height: 10),

          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'หมายเหตุ',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึก'),
            ),
          ),
        ],
      ),
    );
  }
}