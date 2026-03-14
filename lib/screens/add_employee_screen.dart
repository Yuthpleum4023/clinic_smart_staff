import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/auth_user_lookup_api.dart';
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

  final _linkedUserIdCtrl = TextEditingController();

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
  bool _loadingLinkedUser = false;

  AuthLookupUser? _selectedAuthUser;

  ApiClient get _staffClient => ApiClient(baseUrl: ApiConfig.staffBaseUrl);

  double _toDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  int _toInt(String s) => int.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  String _cleanLinkedUserId(String s) => s.trim();

  String _fullName() {
    final parts = [
      _firstNameCtrl.text.trim(),
      _lastNameCtrl.text.trim(),
    ].where((e) => e.isNotEmpty).toList();

    return parts.join(' ').trim();
  }

  String _backendEmploymentType() {
    return _employmentType == 'parttime' ? 'partTime' : 'fullTime';
  }

  @override
  void initState() {
    super.initState();
    _loadSsoPercentAndPreview();
    _tryAutoFillLinkedUserId();
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
    _linkedUserIdCtrl.dispose();
    _salaryCtrl.dispose();
    _bonusCtrl.dispose();
    _absentCtrl.dispose();
    _hourlyWageCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryAutoFillLinkedUserId({bool showSnack = false}) async {
    if (_loadingLinkedUser) return;

    if (!mounted) return;
    setState(() => _loadingLinkedUser = true);

    try {
      final me = await AuthUserLookupApi.getMe();

      if (!mounted) return;

      if (me != null && me.userId.trim().isNotEmpty) {
        setState(() {
          _selectedAuthUser = me;
          _linkedUserIdCtrl.text = me.userId.trim();

          if (_firstNameCtrl.text.trim().isEmpty && me.firstName.trim().isNotEmpty) {
            _firstNameCtrl.text = me.firstName.trim();
          }
          if (_lastNameCtrl.text.trim().isEmpty && me.lastName.trim().isNotEmpty) {
            _lastNameCtrl.text = me.lastName.trim();
          }

          if (_firstNameCtrl.text.trim().isEmpty &&
              _lastNameCtrl.text.trim().isEmpty &&
              me.fullName.trim().isNotEmpty) {
            final parts = me.fullName.trim().split(RegExp(r'\s+'));
            if (parts.isNotEmpty) {
              _firstNameCtrl.text = parts.first;
              if (parts.length > 1) {
                _lastNameCtrl.text = parts.sublist(1).join(' ');
              }
            }
          }
        });

        _calcPreview();

        if (showSnack) {
          _toast('ดึงบัญชีผู้ใช้สำเร็จ');
        }
      } else {
        if (showSnack) {
          _toast('ดึง User ID อัตโนมัติไม่สำเร็จ');
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (showSnack) {
        _toast('ดึงบัญชีผู้ใช้ไม่สำเร็จ: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingLinkedUser = false);
      }
    }
  }

  void _calcPreview() {
    if (!mounted) return;

    if (_employmentType == 'fulltime') {
      final emp = EmployeeModel(
        id: 'tmp',
        staffId: 'tmp',
        linkedUserId: _cleanLinkedUserId(_linkedUserIdCtrl.text),
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

  Map<String, dynamic> _extractEmployeeFromResponse(Map<String, dynamic> res) {
    final dynamic employee = res['employee'];
    if (employee is Map<String, dynamic>) return employee;
    if (employee is Map) return Map<String, dynamic>.from(employee);

    final dynamic data = res['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    return res;
  }

  Future<Map<String, dynamic>> _createEmployeeOnBackend(
    Map<String, dynamic> body,
  ) async {
    Object? lastError;

    final candidates = <String>[
      '/api/employees',
      '/employees',
    ];

    for (final path in candidates) {
      try {
        final res = await _staffClient.post(
          path,
          auth: true,
          body: body,
        );
        return res;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError?.toString() ?? 'CREATE_EMPLOYEE_FAILED');
  }

  EmployeeModel _buildLocalEmployeeFromBackend(Map<String, dynamic> raw) {
    String s(dynamic v) => (v ?? '').toString().trim();
    double d(dynamic v) => double.tryParse(s(v).replaceAll(',', '')) ?? 0;

    final backendFullName = s(raw['fullName']);
    final backendStaffId =
        s(raw['staffId']).isNotEmpty ? s(raw['staffId']) : s(raw['_id']);

    String firstName = _firstNameCtrl.text.trim();
    String lastName = _lastNameCtrl.text.trim();

    if (firstName.isEmpty && lastName.isEmpty && backendFullName.isNotEmpty) {
      final parts = backendFullName.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }
    }

    final linkedUserId = s(raw['userId']).isNotEmpty
        ? s(raw['userId'])
        : _cleanLinkedUserId(_linkedUserIdCtrl.text);

    final isParttime = s(raw['employmentType']).toLowerCase() == 'parttime';

    return EmployeeModel(
      id: backendStaffId.isNotEmpty
          ? backendStaffId
          : DateTime.now().millisecondsSinceEpoch.toString(),
      staffId: backendStaffId,
      linkedUserId: linkedUserId,
      firstName: firstName,
      lastName: lastName,
      position: _positionCtrl.text.trim(),
      employmentType: isParttime ? 'parttime' : 'fulltime',
      baseSalary: isParttime ? 0 : d(raw['monthlySalary']),
      hourlyWage: isParttime ? d(raw['hourlyRate']) : 0,
      bonus: _toDouble(_bonusCtrl.text),
      absentDays: _toInt(_absentCtrl.text),
    );
  }

  Future<void> _saveEmployee() async {
    if (_saving) return;

    final firstName = _firstNameCtrl.text.trim();
    final fullName = _fullName();
    final userId = _cleanLinkedUserId(_linkedUserIdCtrl.text);

    if (firstName.isEmpty) {
      _toast('กรุณากรอกชื่อ');
      return;
    }

    if (fullName.isEmpty) {
      _toast('กรุณากรอกชื่อพนักงาน');
      return;
    }

    setState(() => _saving = true);

    try {
      final body = <String, dynamic>{
        'fullName': fullName,
        'employmentType': _backendEmploymentType(),
      };

      if (userId.isNotEmpty) {
        body['userId'] = userId;
      }

      if (_employmentType == 'fulltime') {
        final salary = _toDouble(_salaryCtrl.text);

        if (salary <= 0) {
          _toast('เงินเดือนต้องมากกว่า 0');
          setState(() => _saving = false);
          return;
        }

        body['monthlySalary'] = salary;
      } else {
        final wage = _toDouble(_hourlyWageCtrl.text);

        if (wage <= 0) {
          _toast('กรุณากรอกบาท/ชั่วโมง');
          setState(() => _saving = false);
          return;
        }

        body['hourlyRate'] = wage;
      }

      final createdRes = await _createEmployeeOnBackend(body);
      final createdEmployeeRaw = _extractEmployeeFromResponse(createdRes);
      final localEmp = _buildLocalEmployeeFromBackend(createdEmployeeRaw);

      try {
        final list = await StorageService.loadEmployees();
        final idx = list.indexWhere(
          (e) => e.staffId.trim() == localEmp.staffId.trim(),
        );

        if (idx >= 0) {
          list[idx] = localEmp;
        } else {
          list.add(localEmp);
        }

        await StorageService.saveEmployees(list);
      } catch (_) {}

      if (!mounted) return;

      _toast('บันทึกพนักงานเรียบร้อย');
      Navigator.pop(context, localEmp);
    } catch (e) {
      if (!mounted) return;
      _toast('บันทึกไม่สำเร็จ: $e');
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
    final effectiveKeyboardType = isNumeric ? type : TextInputType.multiline;

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

  Widget _linkedUserCard() {
    final linked = _cleanLinkedUserId(_linkedUserIdCtrl.text);
    final u = _selectedAuthUser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'การเชื่อมบัญชีผู้ใช้',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              linked.isEmpty
                  ? 'ตอนนี้ยังไม่ได้ผูกบัญชีผู้ใช้'
                  : 'User ID ปัจจุบัน: $linked',
            ),
            if (u != null &&
                (u.fullName.trim().isNotEmpty ||
                    u.phone.trim().isNotEmpty ||
                    u.role.trim().isNotEmpty)) ...[
              const SizedBox(height: 8),
              if (u.fullName.trim().isNotEmpty) Text('ชื่อบัญชี: ${u.fullName}'),
              if (u.phone.trim().isNotEmpty) Text('โทรศัพท์: ${u.phone}'),
              if (u.role.trim().isNotEmpty) Text('บทบาท: ${u.role}'),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingLinkedUser
                        ? null
                        : () => _tryAutoFillLinkedUserId(showSnack: true),
                    icon: _loadingLinkedUser
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_search),
                    label: Text(
                      _loadingLinkedUser ? 'กำลังดึง...' : 'ใช้บัญชีที่ล็อกอินอยู่',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'ล้างค่า',
                  onPressed: _loadingLinkedUser
                      ? null
                      : () {
                          _linkedUserIdCtrl.clear();
                          _selectedAuthUser = null;
                          _calcPreview();
                          setState(() {});
                        },
                  icon: const Icon(Icons.clear),
                ),
              ],
            ),
          ],
        ),
      ),
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
                _field('ตำแหน่ง (แสดงในแอป)', _positionCtrl, onChanged: _calcPreview),

                _field(
                  'User ID (ถ้ามี)',
                  _linkedUserIdCtrl,
                  onChanged: _calcPreview,
                  hint: 'เช่น usr_xxxxx',
                ),

                _linkedUserCard(),

                const SizedBox(height: 12),

                ToggleButtons(
                  isSelected: [isFulltime, isParttime],
                  onPressed: (i) {
                    _switchEmploymentType(i == 0 ? 'fulltime' : 'parttime');
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
                    'โบนัส (พรีวิวในแอป)',
                    _bonusCtrl,
                    type: TextInputType.number,
                    fmts: [_moneyFmt],
                    onChanged: _calcPreview,
                  ),
                  _field(
                    'วันลา/ขาด (พรีวิวในแอป)',
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
                          _row(
                            'สุทธิ',
                            _netFulltime.toStringAsFixed(2),
                            bold: true,
                          ),
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
                    label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึกพนักงาน'),
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