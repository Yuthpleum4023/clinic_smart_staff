// lib/screens/edit_employee_screen.dart
//
// PRODUCTION — Employee Edit Screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

class EditEmployeeScreen extends StatefulWidget {
  final EmployeeModel employee;

  const EditEmployeeScreen({
    super.key,
    required this.employee,
  });

  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  late final TextEditingController firstNameCtrl;
  late final TextEditingController lastNameCtrl;
  late final TextEditingController positionCtrl;
  late final TextEditingController linkedUserIdCtrl;

  late final TextEditingController baseSalaryCtrl;
  late final TextEditingController absentDaysCtrl;
  late final TextEditingController bonusCtrl;
  late final TextEditingController hourlyWageCtrl;

  bool _isSaving = false;
  bool _dirty = false;
  bool _isPopping = false;

  late String employmentType; // fulltime | parttime

  ApiClient get _staffClient => ApiClient(baseUrl: ApiConfig.staffBaseUrl);

  final TextInputFormatter _moneyFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'));
  final TextInputFormatter _intFormatter =
      FilteringTextInputFormatter.digitsOnly;

  @override
  void initState() {
    super.initState();

    final e = widget.employee;

    final t = e.employmentType.toLowerCase().trim();
    employmentType = t == 'parttime' || t == 'part_time' || t == 'part-time'
        ? 'parttime'
        : 'fulltime';

    firstNameCtrl = TextEditingController(text: e.firstName);
    lastNameCtrl = TextEditingController(text: e.lastName);
    positionCtrl = TextEditingController(text: e.position);
    linkedUserIdCtrl = TextEditingController(text: e.linkedUserId);

    baseSalaryCtrl =
        TextEditingController(text: e.baseSalary.toStringAsFixed(0));
    absentDaysCtrl = TextEditingController(text: e.absentDays.toString());
    bonusCtrl = TextEditingController(text: e.bonus.toStringAsFixed(0));
    hourlyWageCtrl =
        TextEditingController(text: e.hourlyWage.toStringAsFixed(0));

    for (final c in [
      firstNameCtrl,
      lastNameCtrl,
      positionCtrl,
      linkedUserIdCtrl,
      baseSalaryCtrl,
      absentDaysCtrl,
      bonusCtrl,
      hourlyWageCtrl,
    ]) {
      c.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    positionCtrl.dispose();
    linkedUserIdCtrl.dispose();
    baseSalaryCtrl.dispose();
    absentDaysCtrl.dispose();
    bonusCtrl.dispose();
    hourlyWageCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!mounted || _dirty) return;
    setState(() => _dirty = true);
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  double _toDouble(String s) {
    final cleaned = s.trim().replaceAll(',', '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _toInt(String s) {
    final cleaned = s.trim().replaceAll(',', '');
    return int.tryParse(cleaned) ?? 0;
  }

  double _readDouble(dynamic v) {
    if (v is num) return v.toDouble();

    final cleaned = _s(v).replaceAll(',', '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _readInt(dynamic v) {
    if (v is num) return v.toInt();

    final cleaned = _s(v).replaceAll(',', '');
    return int.tryParse(cleaned) ?? 0;
  }

  double _firstPositiveNum(List<dynamic> values) {
    for (final v in values) {
      final n = _readDouble(v);
      if (n > 0) return n;
    }
    return 0.0;
  }

  String _cleanLinkedUserId(String s) => s.trim();

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

  String _localEmploymentTypeFromBackend(dynamic raw) {
    final t = _s(raw).toLowerCase();

    if (t == 'parttime' ||
        t == 'part-time' ||
        t == 'part_time' ||
        t == 'part time' ||
        t == 'hourly') {
      return 'parttime';
    }

    return 'fulltime';
  }

  void _safePop<T extends Object?>([T? result]) {
    if (!mounted || _isPopping) return;

    _isPopping = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateSync() {
    final fn = firstNameCtrl.text.trim();
    final ln = lastNameCtrl.text.trim();
    final pos = positionCtrl.text.trim();

    if (fn.isEmpty) return 'กรุณากรอกชื่อพนักงาน';
    if (ln.isEmpty) return 'กรุณากรอกนามสกุลพนักงาน';
    if (pos.isEmpty) return 'กรุณากรอกตำแหน่ง';

    final bonus = _toDouble(bonusCtrl.text);
    if (bonus < 0) return 'โบนัสหรือค่าคอมมิชชั่นต้องไม่ติดลบ';

    if (employmentType == 'fulltime') {
      final base = _toDouble(baseSalaryCtrl.text);
      final absent = _toInt(absentDaysCtrl.text);

      if (base <= 0) return 'กรุณากรอกเงินเดือนพื้นฐานให้ถูกต้อง';
      if (absent < 0) return 'จำนวนวันลา/ขาดต้องไม่ติดลบ';
      if (absent > 31) return 'จำนวนวันลา/ขาดเกิน 31 วัน กรุณาตรวจสอบอีกครั้ง';
    } else {
      final wage = _toDouble(hourlyWageCtrl.text);
      if (wage <= 0) return 'กรุณากรอกค่าจ้างต่อชั่วโมงให้ถูกต้อง';
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
        return 'รหัสผู้ใช้นี้ถูกผูกกับพนักงานคนอื่นแล้ว';
      }
    }

    return null;
  }

  String _employeeIdForBackend() {
    final staffId = widget.employee.staffId.trim();
    if (staffId.isNotEmpty) return staffId;

    final id = widget.employee.id.trim();
    if (id.isNotEmpty) return id;

    return '';
  }

  Map<String, dynamic> _buildBackendBody({
    required bool includePayrollExtras,
  }) {
    final fullName = _fullName();
    final userId = _cleanLinkedUserId(linkedUserIdCtrl.text);

    final monthlySalary = _toDouble(baseSalaryCtrl.text);
    final hourlyRate = _toDouble(hourlyWageCtrl.text);
    final bonus = _toDouble(bonusCtrl.text);
    final absentDays =
        employmentType == 'fulltime' ? _toInt(absentDaysCtrl.text) : 0;

    final body = <String, dynamic>{
      'fullName': fullName,
      'employmentType': _backendEmploymentType(),
      'userId': userId,
    };

    if (employmentType == 'fulltime') {
      body['monthlySalary'] = monthlySalary;
    } else {
      body['hourlyRate'] = hourlyRate;
    }

    if (includePayrollExtras) {
      body['position'] = positionCtrl.text.trim();

      if (employmentType == 'fulltime') {
        body['baseSalary'] = monthlySalary;
        body['salary'] = monthlySalary;
      } else {
        body['hourlyWage'] = hourlyRate;
      }

      body['bonus'] = bonus;
      body['absentDays'] = absentDays;
    }

    return body;
  }

  Future<Map<String, dynamic>> _updateEmployeeOnBackend(
    String employeeId,
    Map<String, dynamic> body,
  ) async {
    Object? lastError;

    final candidates = <String>[
      '/api/employees/$employeeId',
      '/employees/$employeeId',
      '/api/staff/$employeeId',
      '/staff/$employeeId',
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

  Future<Map<String, dynamic>> _updateEmployeeProductionSafe(
    String employeeId,
  ) async {
    final fullBody = _buildBackendBody(includePayrollExtras: true);
    final coreBody = _buildBackendBody(includePayrollExtras: false);

    try {
      return await _updateEmployeeOnBackend(employeeId, fullBody);
    } catch (_) {
      return _updateEmployeeOnBackend(employeeId, coreBody);
    }
  }

  Map<String, dynamic> _extractEmployeeFromResponse(Map<String, dynamic> res) {
    final dynamic employee = res['employee'];
    if (employee is Map<String, dynamic>) return employee;
    if (employee is Map) return Map<String, dynamic>.from(employee);

    final dynamic data = res['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    final dynamic row = res['row'];
    if (row is Map<String, dynamic>) return row;
    if (row is Map) return Map<String, dynamic>.from(row);

    return res;
  }

  EmployeeModel _mergeUpdatedModel(Map<String, dynamic> raw) {
    final backendStaffId = _s(raw['staffId']).isNotEmpty
        ? _s(raw['staffId'])
        : _s(raw['_id']).isNotEmpty
            ? _s(raw['_id'])
            : _s(raw['id']);

    final backendUserId = _s(raw['userId']).isNotEmpty
        ? _s(raw['userId'])
        : _s(raw['linkedUserId']).isNotEmpty
            ? _s(raw['linkedUserId'])
            : _cleanLinkedUserId(linkedUserIdCtrl.text);

    final localType = _localEmploymentTypeFromBackend(
      _s(raw['employmentType']).isNotEmpty
          ? raw['employmentType']
          : _backendEmploymentType(),
    );

    final isParttime = localType == 'parttime';

    final monthlySalary = _firstPositiveNum([
      raw['monthlySalary'],
      raw['baseSalary'],
      raw['salary'],
      raw['grossBase'],
      raw['grossMonthly'],
      baseSalaryCtrl.text,
    ]);

    final hourlyRate = _firstPositiveNum([
      raw['hourlyRate'],
      raw['hourlyWage'],
      raw['wagePerHour'],
      raw['ratePerHour'],
      hourlyWageCtrl.text,
    ]);

    final backendPosition = _s(raw['position']);
    final backendBonus = _readDouble(raw['bonus']);
    final backendAbsentDays = _readInt(raw['absentDays']);

    return widget.employee.copyWith(
      id: backendStaffId.isNotEmpty ? backendStaffId : widget.employee.id,
      staffId:
          backendStaffId.isNotEmpty ? backendStaffId : widget.employee.staffId,
      linkedUserId: backendUserId,
      firstName: firstNameCtrl.text.trim(),
      lastName: lastNameCtrl.text.trim(),
      position:
          backendPosition.isNotEmpty ? backendPosition : positionCtrl.text.trim(),
      employmentType: isParttime ? 'parttime' : 'fulltime',
      baseSalary: isParttime ? 0.0 : monthlySalary,
      hourlyWage: isParttime ? hourlyRate : 0.0,
      bonus: backendBonus > 0 ? backendBonus : _toDouble(bonusCtrl.text),
      absentDays: isParttime
          ? 0
          : backendAbsentDays > 0
              ? backendAbsentDays
              : _toInt(absentDaysCtrl.text),
      otEntries: widget.employee.otEntries,
    );
  }

  Future<void> _safeUpdateLocalById(String id, EmployeeModel model) async {
    final key = id.trim();
    if (key.isEmpty) return;

    try {
      await StorageService.updateEmployeeById(key, model);
    } catch (_) {}
  }

  Future<void> _persistUpdatedEmployeeLocal(EmployeeModel updated) async {
    final keys = <String>{
      widget.employee.id.trim(),
      widget.employee.staffId.trim(),
      updated.id.trim(),
      updated.staffId.trim(),
    }.where((x) => x.isNotEmpty).toSet();

    for (final key in keys) {
      await _safeUpdateLocalById(key, updated);
    }
  }

  String _friendlySaveError(Object e) {
    final msg = e.toString();

    if (msg.contains('401')) {
      return 'สิทธิ์หมดอายุ กรุณาออกจากระบบแล้วเข้าใหม่';
    }

    if (msg.contains('403')) {
      return 'ไม่มีสิทธิ์แก้ไขข้อมูลพนักงาน';
    }

    if (msg.contains('404')) {
      return 'ไม่พบข้อมูลพนักงาน กรุณารีเฟรชแล้วลองใหม่';
    }

    if (msg.contains('timeout') || msg.contains('SocketException')) {
      return 'เชื่อมต่อระบบไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ต';
    }

    return 'บันทึกข้อมูลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  Future<void> _save() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);

    try {
      final err = await _validateAsync();

      if (err != null) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack(err);
        return;
      }

      final employeeId = _employeeIdForBackend();

      if (employeeId.isEmpty) {
        throw Exception('MISSING_EMPLOYEE_ID');
      }

      final updatedRes = await _updateEmployeeProductionSafe(employeeId);
      final updatedRaw = _extractEmployeeFromResponse(updatedRes);
      final updated = _mergeUpdatedModel(updatedRaw);

      await _persistUpdatedEmployeeLocal(updated);

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _dirty = false;
      });

      _showSnack('บันทึกข้อมูลพนักงานแล้ว');
      _safePop<EmployeeModel>(updated);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSaving = false);
      _showSnack(_friendlySaveError(e));
    }
  }

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
    String? helperText,
  }) {
    final isNumeric = _isNumericType(type);
    final effectiveKeyboardType = isNumeric ? type : TextInputType.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: enabled && !_isSaving,
        keyboardType: effectiveKeyboardType,
        inputFormatters: formatters,
        minLines: 1,
        maxLines: 1,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 16, height: 1.4),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
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
          'มีข้อมูลที่แก้ไขแล้วยังไม่ได้บันทึก ต้องการออกจากหน้านี้หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('อยู่ต่อ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ออกจากหน้า'),
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
        if (absentDaysCtrl.text.trim().isEmpty) {
          absentDaysCtrl.text = '0';
        }
      } else {
        absentDaysCtrl.text = '0';
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
              ButtonSegment(
                value: 'fulltime',
                label: Text('Full-time'),
              ),
              ButtonSegment(
                value: 'parttime',
                label: Text('Part-time'),
              ),
            ],
            selected: {employmentType},
            onSelectionChanged: _isSaving
                ? null
                : (set) {
                    if (set.isEmpty) return;
                    _onChangeType(set.first);
                  },
          ),
          const SizedBox(height: 6),
          Text(
            employmentType == 'parttime'
                ? 'พนักงานรายชั่วโมงจะคิดค่าจ้างตามเวลาทำงาน และไม่หักประกันสังคมในงวดเงินเดือน'
                : 'พนักงานประจำใช้เงินเดือนพื้นฐาน วันลา/ขาด และค่าประกันสังคมตามนโยบายคลินิก',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payrollHintCard() {
    return Card(
      elevation: 0,
      color: Colors.deepPurple.withOpacity(0.07),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Colors.deepPurple.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ข้อมูลนี้ใช้สำหรับอัปเดตโปรไฟล์พนักงาน และเป็นข้อมูลประกอบการคำนวณเงินเดือนโดยระบบหลังบ้าน',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.deepPurple.shade900,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    'ชื่อ',
                    firstNameCtrl,
                    hint: 'เช่น สมชาย',
                  ),
                  _field(
                    'นามสกุล',
                    lastNameCtrl,
                    hint: 'เช่น ใจดี',
                  ),
                  _field(
                    'ตำแหน่ง',
                    positionCtrl,
                    hint: 'เช่น ผู้ช่วยทันตแพทย์',
                  ),
                  _field(
                    'รหัสผู้ใช้ที่ผูกบัญชี (ถ้ามี)',
                    linkedUserIdCtrl,
                    hint: 'เช่น usr_xxxxx',
                    helperText:
                        'ใช้เมื่อพนักงานมีบัญชีสำหรับเข้าใช้งานแอปหรือสแกนเวลา',
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
                      'ค่าจ้างต่อชั่วโมง (บาท/ชม.)',
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
                  const SizedBox(height: 4),
                  _payrollHintCard(),
                  const SizedBox(height: 12),
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
                      label: Text(
                        _isSaving ? 'กำลังบันทึก...' : 'บันทึกการแก้ไข',
                      ),
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