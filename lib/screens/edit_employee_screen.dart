// lib/screens/edit_employee_screen.dart
//
// ✅ FULL FILE (COPY-PASTE READY)
// ✅ BACKEND-READY (HYBRID SAFE)
// - อัปเดต staff_service สำหรับ field ที่ backend รองรับจริง
// - cache local ต่อสำหรับ field legacy ที่แอปยังใช้
// - ไม่ลบ otEntries เดิม
// - ไม่แตะ manual OT backend records
//
// ✅ BACKEND FIELDS:
// - userId
// - fullName
// - employmentType => fullTime / partTime
// - monthlySalary
// - hourlyRate
//
// ✅ LOCAL LEGACY FIELDS (ยังเก็บต่อใน EmployeeModel/StorageService):
// - position
// - bonus
// - absentDays
// - otEntries
//
// ✅ IMPORTANT:
// - staffId จริง = employee record id จาก backend (Mongo _id / backend staffId)
// - ใช้ PUT/PATCH ไป staff_service ด้วย employee id
//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

class EditEmployeeScreen extends StatefulWidget {
  final EmployeeModel employee;

  const EditEmployeeScreen({super.key, required this.employee});

  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  late TextEditingController firstNameCtrl;
  late TextEditingController lastNameCtrl;
  late TextEditingController positionCtrl;
  late TextEditingController linkedUserIdCtrl;

  // Full-time fields
  late TextEditingController baseSalaryCtrl;
  late TextEditingController absentDaysCtrl;

  // Shared
  late TextEditingController bonusCtrl;

  // Part-time fields
  late TextEditingController hourlyWageCtrl;

  bool _isSaving = false;
  bool _dirty = false;
  bool _isPopping = false;

  late String employmentType; // 'fulltime' | 'parttime'

  ApiClient get _staffClient => ApiClient(baseUrl: ApiConfig.staffBaseUrl);

  @override
  void initState() {
    super.initState();
    final e = widget.employee;

    final t = e.employmentType.toLowerCase().trim();
    employmentType = (t == 'parttime') ? 'parttime' : 'fulltime';

    firstNameCtrl = TextEditingController(text: e.firstName);
    lastNameCtrl = TextEditingController(text: e.lastName);
    positionCtrl = TextEditingController(text: e.position);
    linkedUserIdCtrl = TextEditingController(text: e.linkedUserId);

    baseSalaryCtrl =
        TextEditingController(text: e.baseSalary.toStringAsFixed(0));
    bonusCtrl = TextEditingController(text: e.bonus.toStringAsFixed(0));
    absentDaysCtrl = TextEditingController(text: e.absentDays.toString());

    hourlyWageCtrl =
        TextEditingController(text: e.hourlyWage.toStringAsFixed(0));

    void markDirty() {
      if (!_dirty && mounted) setState(() => _dirty = true);
    }

    for (final c in [
      firstNameCtrl,
      lastNameCtrl,
      positionCtrl,
      linkedUserIdCtrl,
      baseSalaryCtrl,
      bonusCtrl,
      absentDaysCtrl,
      hourlyWageCtrl,
    ]) {
      c.addListener(markDirty);
    }
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    positionCtrl.dispose();
    linkedUserIdCtrl.dispose();
    baseSalaryCtrl.dispose();
    bonusCtrl.dispose();
    absentDaysCtrl.dispose();
    hourlyWageCtrl.dispose();
    super.dispose();
  }

  double _toDouble(String s) {
    final cleaned = s.trim().replaceAll(',', '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _toInt(String s) {
    final cleaned = s.trim().replaceAll(',', '');
    return int.tryParse(cleaned) ?? 0;
  }

  String _cleanLinkedUserId(String s) {
    return s.trim();
  }

  String _fullName() {
    final parts = [
      firstNameCtrl.text.trim(),
      lastNameCtrl.text.trim(),
    ].where((e) => e.isNotEmpty).toList();

    return parts.join(' ').trim();
  }

  String _backendEmploymentType() {
    return employmentType == 'parttime' ? 'partTime' : 'fullTime';
  }

  void _safePop<T extends Object?>([T? result]) {
    if (!mounted) return;
    if (_isPopping) return;
    _isPopping = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  String? _validateSync() {
    final fn = firstNameCtrl.text.trim();
    final ln = lastNameCtrl.text.trim();
    final pos = positionCtrl.text.trim();

    if (fn.isEmpty) return 'กรุณากรอก “ชื่อ”';
    if (ln.isEmpty) return 'กรุณากรอก “นามสกุล”';
    if (pos.isEmpty) return 'กรุณากรอก “ตำแหน่ง”';

    final bonus = _toDouble(bonusCtrl.text);
    if (bonus < 0) return 'โบนัสต้องไม่ติดลบ';

    if (employmentType == 'fulltime') {
      final base = _toDouble(baseSalaryCtrl.text);
      final absent = _toInt(absentDaysCtrl.text);

      if (base <= 0) return 'เงินเดือนพื้นฐานต้องมากกว่า 0';
      if (absent < 0) return 'วันลา/ขาด ต้องไม่ติดลบ';
      if (absent > 31) return 'วันลา/ขาด เกิน 31 วัน (ตรวจสอบอีกครั้ง)';
    } else {
      final wage = _toDouble(hourlyWageCtrl.text);
      if (wage <= 0) return 'กรุณากรอก “ค่าจ้าง/ชั่วโมง” ให้ถูกต้อง';
    }

    return null;
  }

  Future<String?> _validateAsync() async {
    final syncErr = _validateSync();
    if (syncErr != null) return syncErr;

    final linkedUserId = _cleanLinkedUserId(linkedUserIdCtrl.text);
    if (linkedUserId.isNotEmpty) {
      final duplicated = await StorageService.existsLinkedUserId(
        linkedUserId,
        exceptEmployeeId: widget.employee.id,
      );
      if (duplicated) {
        return 'User ID นี้ถูกผูกกับพนักงานคนอื่นแล้ว';
      }
    }

    return null;
  }

  Future<Map<String, dynamic>> _updateEmployeeOnBackend(
    String employeeId,
    Map<String, dynamic> body,
  ) async {
    Object? lastError;

    final candidates = <String>[
      '/api/employees/$employeeId',
      '/employees/$employeeId',
    ];

    for (final path in candidates) {
      try {
        return await _staffClient.put(
          path,
          auth: true,
          body: body,
        );
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError?.toString() ?? 'UPDATE_EMPLOYEE_FAILED');
  }

  Map<String, dynamic> _extractEmployeeFromResponse(Map<String, dynamic> res) {
    final dynamic employee = res['employee'];
    if (employee is Map<String, dynamic>) return employee;
    if (employee is Map) return Map<String, dynamic>.from(employee);

    final dynamic data = res['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    return res;
  }

  EmployeeModel _mergeUpdatedModel(Map<String, dynamic> raw) {
    String s(dynamic v) => (v ?? '').toString().trim();
    double d(dynamic v) => double.tryParse(s(v).replaceAll(',', '')) ?? 0;

    final backendStaffId =
        s(raw['staffId']).isNotEmpty ? s(raw['staffId']) : s(raw['_id']);

    final backendUserId =
        s(raw['userId']).isNotEmpty ? s(raw['userId']) : _cleanLinkedUserId(linkedUserIdCtrl.text);

    final isParttime = s(raw['employmentType']).toLowerCase() == 'parttime';

    return widget.employee.copyWith(
      id: backendStaffId.isNotEmpty ? backendStaffId : widget.employee.id,
      staffId: backendStaffId.isNotEmpty ? backendStaffId : widget.employee.staffId,
      linkedUserId: backendUserId,
      firstName: firstNameCtrl.text.trim(),
      lastName: lastNameCtrl.text.trim(),
      position: positionCtrl.text.trim(),
      employmentType: isParttime ? 'parttime' : 'fulltime',
      baseSalary: isParttime ? 0.0 : d(raw['monthlySalary']),
      hourlyWage: isParttime ? d(raw['hourlyRate']) : 0.0,
      bonus: _toDouble(bonusCtrl.text),
      absentDays: employmentType == 'fulltime' ? _toInt(absentDaysCtrl.text) : 0,
      otEntries: widget.employee.otEntries,
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      final err = await _validateAsync();
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        setState(() => _isSaving = false);
        return;
      }

      final fullName = _fullName();
      final userId = _cleanLinkedUserId(linkedUserIdCtrl.text);
      final employeeId = widget.employee.staffId.trim().isNotEmpty
          ? widget.employee.staffId.trim()
          : widget.employee.id.trim();

      if (employeeId.isEmpty) {
        throw Exception('ไม่พบ employee id สำหรับอัปเดต backend');
      }

      final body = <String, dynamic>{
        'fullName': fullName,
        'employmentType': _backendEmploymentType(),
        'userId': userId,
      };

      if (employmentType == 'fulltime') {
        body['monthlySalary'] = _toDouble(baseSalaryCtrl.text);
      } else {
        body['hourlyRate'] = _toDouble(hourlyWageCtrl.text);
      }

      final updatedRes = await _updateEmployeeOnBackend(employeeId, body);
      final updatedRaw = _extractEmployeeFromResponse(updatedRes);
      final updated = _mergeUpdatedModel(updatedRaw);

      await StorageService.updateEmployeeById(updated.id, updated);

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _dirty = false;
      });

      _safePop<EmployeeModel>(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
      );
    }
  }

  final _moneyFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'));
  final _intFormatter = FilteringTextInputFormatter.digitsOnly;

  bool _isNumericType(TextInputType t) {
    return t == TextInputType.number ||
        t == const TextInputType.numberWithOptions(decimal: true);
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? formatters,
    String? hint,
    bool enabled = true,
  }) {
    final isNumeric = _isNumericType(type);
    final effectiveKeyboardType = isNumeric ? type : TextInputType.multiline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: enabled,
        keyboardType: effectiveKeyboardType,
        inputFormatters: formatters,
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

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยังไม่ได้บันทึก'),
        content: const Text(
          'คุณแก้ไขข้อมูลแล้ว แต่ยังไม่ได้กดบันทึก ต้องการออกเลยไหม?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('อยู่ต่อ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ออกเลย'),
          ),
        ],
      ),
    );

    return ok == true;
  }

  void _onChangeType(String nextType) {
    if (!mounted) return;
    setState(() {
      employmentType = nextType;
      _dirty = true;

      if (employmentType == 'fulltime') {
        if (absentDaysCtrl.text.trim().isEmpty) absentDaysCtrl.text = '0';
      }
    });
  }

  Widget _typeSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ประเภทพนักงาน',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fulltime', label: Text('Full-time')),
              ButtonSegment(value: 'parttime', label: Text('Part-time')),
            ],
            selected: {employmentType},
            onSelectionChanged: (set) => _onChangeType(set.first),
          ),
          const SizedBox(height: 6),
          Text(
            employmentType == 'parttime'
                ? 'หมายเหตุ: Part-time ไม่หักประกันสังคม และไม่สน absentDays'
                : 'หมายเหตุ: Full-time คิดประกันสังคม/หักขาด-ลา ตามระบบ',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isParttime = employmentType == 'parttime';
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return WillPopScope(
      onWillPop: _confirmDiscardIfDirty,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('แก้ไขข้อมูลพนักงาน'),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final ok = await _confirmDiscardIfDirty();
              if (!ok) return;
              if (!mounted) return;
              _safePop();
            },
          ),
        ),
        body: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: kb),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafe + 24),
              child: Column(
                children: [
                  _field('ชื่อ', firstNameCtrl),
                  _field('นามสกุล', lastNameCtrl),
                  _field('ตำแหน่ง', positionCtrl),
                  _field(
                    'User ID (ถ้ามี)',
                    linkedUserIdCtrl,
                    hint: 'เช่น usr_xxxxx',
                  ),
                  _typeSelector(),
                  if (!isParttime) ...[
                    _field(
                      'เงินเดือนพื้นฐาน',
                      baseSalaryCtrl,
                      type: TextInputType.number,
                      formatters: [_moneyFormatter],
                      hint: 'เช่น 30000 หรือ 30,000',
                    ),
                    _field(
                      'วันลา/ขาด (วัน)',
                      absentDaysCtrl,
                      type: TextInputType.number,
                      formatters: [_intFormatter],
                      hint: 'เช่น 0',
                    ),
                  ],
                  if (isParttime) ...[
                    _field(
                      'ค่าจ้าง/ชั่วโมง (บาท/ชม.)',
                      hourlyWageCtrl,
                      type: const TextInputType.numberWithOptions(decimal: true),
                      formatters: [_moneyFormatter],
                      hint: 'เช่น 120',
                    ),
                  ],
                  _field(
                    'โบนัส/ค่าคอมมิชชั่น',
                    bonusCtrl,
                    type: TextInputType.number,
                    formatters: [_moneyFormatter],
                    hint: 'เช่น 0 หรือ 1500',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'กำลังบันทึก...' : 'บันทึกการแก้ไข'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}