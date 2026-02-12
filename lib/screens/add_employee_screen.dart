// lib/screens/add_employee_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_payroll/models/employee_model.dart';
import 'package:clinic_payroll/services/storage_service.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  // ---------------- Controllers ----------------
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController(text: 'Staff');

  // Full-time
  final _salaryCtrl = TextEditingController();
  final _bonusCtrl = TextEditingController(text: '0');
  final _absentCtrl = TextEditingController(text: '0');

  // Part-time
  final _hourlyWageCtrl = TextEditingController();

  // ---------------- State ----------------
  String _employmentType = 'fulltime'; // fulltime | parttime

  // ✅ โหลดจาก settings (ไม่ import SettingService)
  static const String _ssoKey = 'settings_sso_percent';
  double _ssoPercent = 0.0;

  double _sso = 0.0;
  double _absentDeduct = 0.0;
  double _netFulltime = 0.0;

  double _previewParttime = 0.0;

  final _moneyFmt = FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'));
  final _intFmt = FilteringTextInputFormatter.digitsOnly;

  bool _saving = false;

  // ---------------- Utils ----------------
  double _toDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  int _toInt(String s) => int.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadSsoPercentAndPreview();
  }

  Future<void> _loadSsoPercentAndPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final percent = prefs.getDouble(_ssoKey) ?? 5.0; // fallback ถ้ายังไม่เคยตั้งค่า

    if (!mounted) return;
    setState(() => _ssoPercent = percent);

    _calcPreview();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _positionCtrl.dispose();
    _salaryCtrl.dispose();
    _bonusCtrl.dispose();
    _absentCtrl.dispose();
    _hourlyWageCtrl.dispose();
    super.dispose();
  }

  // ---------------- Calculate Preview ----------------
  void _calcPreview() {
    if (_employmentType == 'fulltime') {
      final emp = EmployeeModel(
        id: 'tmp',
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        position: _positionCtrl.text.trim(),
        employmentType: 'fulltime',
        baseSalary: _toDouble(_salaryCtrl.text),
        bonus: _toDouble(_bonusCtrl.text),
        absentDays: _toInt(_absentCtrl.text),
      );

      if (!mounted) return;
      setState(() {
        _sso = emp.socialSecurity(_ssoPercent);
        _absentDeduct = emp.absentDeduction();
        _netFulltime = emp.netSalary(_ssoPercent);

        _previewParttime = 0.0;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _previewParttime = _toDouble(_hourlyWageCtrl.text);

        _sso = 0.0;
        _absentDeduct = 0.0;
        _netFulltime = 0.0;
      });
    }
  }

  // ---------------- Save ----------------
  Future<void> _saveEmployee() async {
    if (_saving) return;

    if (_firstNameCtrl.text.trim().isEmpty) {
      _toast('กรุณากรอกชื่อ');
      return;
    }

    setState(() => _saving = true);

    try {
      EmployeeModel emp;
      final id = DateTime.now().millisecondsSinceEpoch.toString();

      if (_employmentType == 'fulltime') {
        final salary = _toDouble(_salaryCtrl.text);
        if (salary <= 0) {
          _toast('เงินเดือนต้องมากกว่า 0');
          setState(() => _saving = false);
          return;
        }

        emp = EmployeeModel(
          id: id,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          position: _positionCtrl.text.trim(),
          employmentType: 'fulltime',
          baseSalary: salary,
          bonus: _toDouble(_bonusCtrl.text),
          absentDays: _toInt(_absentCtrl.text),
        );
      } else {
        final wage = _toDouble(_hourlyWageCtrl.text);
        if (wage <= 0) {
          _toast('กรุณากรอกบาท/ชั่วโมง');
          setState(() => _saving = false);
          return;
        }

        emp = EmployeeModel(
          id: id,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          position: _positionCtrl.text.trim(),
          employmentType: 'parttime',
          hourlyWage: wage,
        );
      }

      final list = await StorageService.loadEmployees();
      list.add(emp);
      await StorageService.saveEmployees(list);

      if (!mounted) return;

      _toast('บันทึกพนักงานเรียบร้อย');

      // ✅ สำคัญ: กลับไปหน้าก่อนหน้า (EmployeeListScreen) เพื่อให้มัน _load() ต่อเอง
      Navigator.pop(context, emp);
    } catch (e) {
      if (mounted) _toast('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------------- UI ----------------
  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? fmts,
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: type,
        inputFormatters: fmts,
        onChanged: (_) => onChanged?.call(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ).copyWith(labelText: label),
      ),
    );
  }

  Widget _row(String l, String r, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l),
          Text(
            r,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เพิ่มพนักงาน'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('ชื่อ', _firstNameCtrl, onChanged: _calcPreview),
          _field('นามสกุล', _lastNameCtrl, onChanged: _calcPreview),
          _field('ตำแหน่ง', _positionCtrl, onChanged: _calcPreview),

          const SizedBox(height: 8),
          const Text(
            'ประเภทพนักงาน',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),

          ToggleButtons(
            isSelected: [
              _employmentType == 'fulltime',
              _employmentType == 'parttime',
            ],
            onPressed: (i) {
              setState(() {
                _employmentType = i == 0 ? 'fulltime' : 'parttime';
              });
              _calcPreview();
            },
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Full-time'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Part-time'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ================= Full-time =================
          if (_employmentType == 'fulltime') ...[
            _field(
              'เงินเดือนพื้นฐาน',
              _salaryCtrl,
              type: TextInputType.number,
              fmts: [_moneyFmt],
              onChanged: _calcPreview,
            ),
            _field(
              'โบนัส',
              _bonusCtrl,
              type: TextInputType.number,
              fmts: [_moneyFmt],
              onChanged: _calcPreview,
            ),
            _field(
              'วันลา/ขาด (วัน)',
              _absentCtrl,
              type: TextInputType.number,
              fmts: [_intFmt],
              onChanged: _calcPreview,
            ),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _row('อัตราประกันสังคม', '${_ssoPercent.toStringAsFixed(2)}%'),
                    const Divider(),
                    _row('หักประกันสังคม', '- ${_sso.toStringAsFixed(2)}'),
                    _row('หักวันลา', '- ${_absentDeduct.toStringAsFixed(2)}'),
                    const Divider(),
                    _row('สุทธิ', _netFulltime.toStringAsFixed(2), bold: true),
                  ],
                ),
              ),
            ),
          ],

          // ================= Part-time =================
          if (_employmentType == 'parttime') ...[
            _field(
              'ค่าจ้าง (บาท/ชั่วโมง)',
              _hourlyWageCtrl,
              type: TextInputType.number,
              fmts: [_moneyFmt],
              onChanged: _calcPreview,
            ),
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เงื่อนไข Part-time'),
                    const SizedBox(height: 6),
                    const Text('• ไม่หักประกันสังคม'),
                    const Text('• ไม่สน absentDays'),
                    const Divider(),
                    Text(
                      'อัตรา: ${_previewParttime.toStringAsFixed(2)} บาท/ชม.',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveEmployee,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึกพนักงาน'),
            ),
          ),
        ],
      ),
    );
  }
}
