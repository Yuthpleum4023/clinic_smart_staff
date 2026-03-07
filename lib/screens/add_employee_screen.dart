import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController(text: 'Staff');

  final _salaryCtrl = TextEditingController();
  final _bonusCtrl = TextEditingController(text: '0');
  final _absentCtrl = TextEditingController(text: '0');

  final _hourlyWageCtrl = TextEditingController();

  String _employmentType = 'fulltime';

  static const String _ssoKey = 'settings_sso_percent';

  double _ssoPercent = 0.0;
  double _sso = 0.0;
  double _absentDeduct = 0.0;
  double _netFulltime = 0.0;

  double _previewParttimeWage = 0.0;

  final _moneyFmt = FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'));
  final _intFmt = FilteringTextInputFormatter.digitsOnly;

  bool _saving = false;

  double _toDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  int _toInt(String s) =>
      int.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadSsoPercentAndPreview();
  }

  Future<void> _loadSsoPercentAndPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final percent = prefs.getDouble(_ssoKey) ?? 5.0;

    if (!mounted) return;

    setState(() {
      _ssoPercent = percent;
    });

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

  void _calcPreview() {
    if (!mounted) return;

    if (_employmentType == 'fulltime') {
      final emp = EmployeeModel(
        id: 'tmp',
        staffId: 'tmp',
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        position: _positionCtrl.text.trim(),
        employmentType: 'fulltime',
        baseSalary: _toDouble(_salaryCtrl.text),
        bonus: _toDouble(_bonusCtrl.text),
        absentDays: _toInt(_absentCtrl.text),
      );

      setState(() {
        _sso = emp.socialSecurity(_ssoPercent);
        _absentDeduct = emp.absentDeduction();
        _netFulltime = emp.netSalary(_ssoPercent);
        _previewParttimeWage = 0;
      });
    } else {
      setState(() {
        _previewParttimeWage = _toDouble(_hourlyWageCtrl.text);
        _sso = 0;
        _absentDeduct = 0;
        _netFulltime = 0;
      });
    }
  }

  void _switchEmploymentType(String type) {
    if (!mounted) return;

    setState(() {
      _employmentType = type;
    });

    if (type == 'fulltime') {
      _hourlyWageCtrl.text = '';
    } else {
      _salaryCtrl.text = '';
      _absentCtrl.text = '0';
    }

    _calcPreview();
  }

  Future<void> _saveEmployee() async {
    if (_saving) return;

    if (_firstNameCtrl.text.trim().isEmpty) {
      _toast('กรุณากรอกชื่อ');
      return;
    }

    setState(() => _saving = true);

    try {

      // ✅ สร้าง id และ staffId อัตโนมัติ
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final staffId = "stf_$id";

      EmployeeModel emp;

      if (_employmentType == 'fulltime') {

        final salary = _toDouble(_salaryCtrl.text);

        if (salary <= 0) {
          _toast('เงินเดือนต้องมากกว่า 0');
          setState(() => _saving = false);
          return;
        }

        emp = EmployeeModel(
          id: id,
          staffId: staffId,
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
          _toast("กรุณากรอกบาท/ชั่วโมง");
          setState(() => _saving = false);
          return;
        }

        emp = EmployeeModel(
          id: id,
          staffId: staffId,
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

      Navigator.pop(context, emp);

    } catch (e) {

      if (mounted) {
        _toast('บันทึกไม่สำเร็จ: $e');
      }

    } finally {

      if (mounted) {
        setState(() => _saving = false);
      }

    }
  }

  void _toast(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool _isNumericType(TextInputType t) {
    return t == TextInputType.number ||
        t == const TextInputType.numberWithOptions(decimal: true);
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? fmts,
    VoidCallback? onChanged,
    String? hint,
  }) {
    final isNumeric = _isNumericType(type);

    final effectiveKeyboardType =
        isNumeric ? type : TextInputType.multiline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: effectiveKeyboardType,
        inputFormatters: fmts,
        onChanged: (_) => onChanged?.call(),
        minLines: 1,
        maxLines: isNumeric ? 1 : null,
        textInputAction:
            isNumeric ? TextInputAction.done : TextInputAction.newline,
        style: const TextStyle(fontSize: 16, height: 1.4),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  Widget _row(String l, String r, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(l)),
        const SizedBox(width: 12),
        Text(
          r,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    final isFulltime = _employmentType == 'fulltime';
    final isParttime = _employmentType == 'parttime';

    return Scaffold(
      appBar: AppBar(
        title: const Text('เพิ่มพนักงาน'),
      ),
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: kb),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafe + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                _field('ชื่อ', _firstNameCtrl, onChanged: _calcPreview),
                _field('นามสกุล', _lastNameCtrl, onChanged: _calcPreview),
                _field('ตำแหน่ง', _positionCtrl, onChanged: _calcPreview),

                const SizedBox(height: 12),

                ToggleButtons(
                  isSelected: [isFulltime, isParttime],
                  onPressed: (i) {
                    _switchEmploymentType(
                      i == 0 ? 'fulltime' : 'parttime',
                    );
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

                if (isFulltime) ...[

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
                    'วันลา/ขาด',
                    _absentCtrl,
                    type: TextInputType.number,
                    fmts: [_intFmt],
                    onChanged: _calcPreview,
                  ),

                  Card(
                    color: cs.primary.withOpacity(0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _row('หักประกันสังคม', _sso.toStringAsFixed(2)),
                          const SizedBox(height: 6),
                          _row('หักวันลา/ขาด', _absentDeduct.toStringAsFixed(2)),
                          const Divider(height: 18),
                          _row('สุทธิ', _netFulltime.toStringAsFixed(2), bold: true),
                        ],
                      ),
                    ),
                  ),
                ],

                if (isParttime) ...[

                  _field(
                    'ค่าจ้าง (บาท/ชั่วโมง)',
                    _hourlyWageCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                    fmts: [_moneyFmt],
                    onChanged: _calcPreview,
                  ),

                  Card(
                    color: cs.secondary.withOpacity(0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'พรีวิว (Part-time)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _row(
                            'อัตราค่าจ้าง',
                            '${_previewParttimeWage.toStringAsFixed(2)} บาท/ชม.',
                            bold: true,
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
                    icon: const Icon(Icons.save),
                    label: const Text('บันทึกพนักงาน'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}