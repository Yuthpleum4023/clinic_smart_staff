// lib/screens/add_helper_availability_screen.dart
import 'package:flutter/material.dart';
import '../models/helper_availability_model.dart';
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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
      setState(() =>
          _date = DateTime(picked.year, picked.month, picked.day));
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

  Future<void> _save() async {
    if (_date == null || _start == null || _end == null) {
      _snack('กรุณาเลือก วันที่/เวลาเริ่ม/เวลาสิ้นสุด ให้ครบ');
      return;
    }

    final role = _roleCtrl.text.trim();
    if (role.isEmpty) {
      _snack('กรุณากรอกบทบาท/ตำแหน่ง');
      return;
    }

    final item = HelperAvailability(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      helperId: widget.helperId,
      helperName: widget.helperName,
      role: role,
      date: _fmtDate(_date!),
      start: _fmtTime(_start!),
      end: _fmtTime(_end!),
      status: 'open',
      note: _noteCtrl.text.trim(),
    );

    if (item.hours <= 0 || item.hours > 24) {
      _snack('ช่วงเวลาที่เลือกผิดปกติ (${item.hours.toStringAsFixed(2)} ชม.)');
      return;
    }

    await HelperAvailabilityService.add(item);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _roleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ลงเวลาว่าง (ผู้ช่วย)'),
        // ✅ ไม่กำหนดสี → ใช้ Theme ม่วง
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
                  onPressed: _pickDate,
                  child: Text(
                    _date == null
                        ? 'เลือกวันที่'
                        : 'วันที่: ${_fmtDate(_date!)}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickStart,
                  child: Text(
                    _start == null
                        ? 'เวลาเริ่ม'
                        : 'เริ่ม: ${_start!.format(context)}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickEnd,
                  child: Text(
                    _end == null
                        ? 'เวลาจบ'
                        : 'จบ: ${_end!.format(context)}',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'หมายเหตุ (ไม่บังคับ)',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('บันทึกเวลาว่าง'),
            ),
          ),
        ],
      ),
    );
  }
}
