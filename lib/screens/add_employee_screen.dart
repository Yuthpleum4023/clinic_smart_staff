import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/auth_user_lookup_api.dart';
import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';
import 'package:clinic_smart_staff/screens/employee_user_link_search_screen.dart';

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

  Map<String, dynamic>? _selectedAuthUser;

  ApiClient get _staffClient => ApiClient(baseUrl: ApiConfig.staffBaseUrl);

  double _toDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  int _toInt(String s) => int.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  String _cleanLinkedUserId(String s) => s.trim();

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _selectedUserFullName() => _s(_selectedAuthUser?['fullName']);

  String _selectedUserFirstName() => _s(_selectedAuthUser?['firstName']);

  String _selectedUserLastName() => _s(_selectedAuthUser?['lastName']);

  String _selectedUserPhone() => _s(_selectedAuthUser?['phone']);

  String _selectedUserRole() => _s(_selectedAuthUser?['role']);

  String _selectedUserId() {
    final m = _selectedAuthUser;
    if (m == null) return '';
    final userId = _s(m['userId']);
    if (userId.isNotEmpty) return userId;
    final id = _s(m['_id']);
    if (id.isNotEmpty) return id;
    return _s(m['id']);
  }

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

  bool _isAdminLikeRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'admin' || r == 'clinic_admin' || r == 'clinic';
  }

  bool _selectedUserLooksUnsafeForEmployeeLink() {
    final u = _selectedAuthUser;
    if (u == null) return false;

    final linkedUserId = _cleanLinkedUserId(_linkedUserIdCtrl.text);
    if (linkedUserId.isEmpty) return false;

    return _isAdminLikeRole(_selectedUserRole());
  }

  bool _hasLinkedUser() => _cleanLinkedUserId(_linkedUserIdCtrl.text).isNotEmpty;

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

      if (me != null && _s(me.userId).isNotEmpty) {
        final isAdminLike = _isAdminLikeRole(_s(me.role));

        setState(() {
          _selectedAuthUser = <String, dynamic>{
            'userId': _s(me.userId),
            'fullName': _s(me.fullName),
            'firstName': _s(me.firstName),
            'lastName': _s(me.lastName),
            'phone': _s(me.phone),
            'role': _s(me.role),
          };

          if (!isAdminLike) {
            _linkedUserIdCtrl.text = _s(me.userId);
          } else {
            _linkedUserIdCtrl.clear();
          }

          if (_firstNameCtrl.text.trim().isEmpty &&
              _s(me.firstName).isNotEmpty) {
            _firstNameCtrl.text = _s(me.firstName);
          }
          if (_lastNameCtrl.text.trim().isEmpty &&
              _s(me.lastName).isNotEmpty) {
            _lastNameCtrl.text = _s(me.lastName);
          }

          if (_firstNameCtrl.text.trim().isEmpty &&
              _lastNameCtrl.text.trim().isEmpty &&
              _s(me.fullName).isNotEmpty) {
            final parts = _s(me.fullName).split(RegExp(r'\s+'));
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
          if (isAdminLike) {
            _toast(
              'บัญชีที่ล็อกอินอยู่เป็นผู้ดูแล จึงยังไม่ผูก User ID ให้อัตโนมัติ',
            );
          } else {
            _toast('ดึงบัญชีผู้ใช้สำเร็จ');
          }
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

  Future<void> _openUserLinkSearch() async {
    if (_saving || _loadingLinkedUser) return;

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeUserLinkSearchScreen(
          initialQuery: _fullName(),
        ),
      ),
    );

    if (!mounted || result == null) return;

    final pickedUserId = _s(
      _s(result['userId']).isNotEmpty ? result['userId'] : result['_id'],
    );

    if (pickedUserId.isEmpty) {
      _toast('ไม่พบ User ID ของรายการที่เลือก');
      return;
    }

    final pickedRole = _s(result['role']);
    final pickedFullName = _s(result['fullName']);
    final pickedFirstName = _s(result['firstName']);
    final pickedLastName = _s(result['lastName']);
    final pickedPhone = _s(result['phone']);

    final isAdminLike = _isAdminLikeRole(pickedRole);

    setState(() {
      _selectedAuthUser = <String, dynamic>{
        'userId': pickedUserId,
        'fullName': pickedFullName,
        'firstName': pickedFirstName,
        'lastName': pickedLastName,
        'phone': pickedPhone,
        'role': pickedRole,
      };

      if (!isAdminLike) {
        _linkedUserIdCtrl.text = pickedUserId;
      } else {
        _linkedUserIdCtrl.clear();
      }

      if (_firstNameCtrl.text.trim().isEmpty && pickedFirstName.isNotEmpty) {
        _firstNameCtrl.text = pickedFirstName;
      }

      if (_lastNameCtrl.text.trim().isEmpty && pickedLastName.isNotEmpty) {
        _lastNameCtrl.text = pickedLastName;
      }

      if (_firstNameCtrl.text.trim().isEmpty &&
          _lastNameCtrl.text.trim().isEmpty &&
          pickedFullName.isNotEmpty) {
        final parts = pickedFullName.split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          _firstNameCtrl.text = parts.first;
          if (parts.length > 1) {
            _lastNameCtrl.text = parts.sublist(1).join(' ');
          }
        }
      }
    });

    _calcPreview();

    if (isAdminLike) {
      _toast('บัญชีที่เลือกเป็นผู้ดูแล จึงยังไม่ผูก User ID ให้');
    } else {
      _toast('เลือกบัญชีผู้ใช้เรียบร้อย');
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
    final res = await _staffClient.post(
      '/api/employees',
      auth: true,
      body: body,
    );
    return res;
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

    if (_selectedUserLooksUnsafeForEmployeeLink()) {
      _toast('ไม่สามารถใช้บัญชีผู้ดูแลมาผูกเป็นพนักงานได้');
      return;
    }

    if (userId.isEmpty) {
      _toast('กรุณาค้นหาและเลือกบัญชีผู้ใช้ก่อนบันทึกพนักงาน');
      return;
    }

    setState(() => _saving = true);

    try {
      final body = <String, dynamic>{
        'fullName': fullName,
        'employmentType': _backendEmploymentType(),
        'userId': userId,
      };

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

  void _clearLinkedUser() {
    _linkedUserIdCtrl.clear();
    _selectedAuthUser = null;
    _calcPreview();
    if (mounted) {
      setState(() {});
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
    bool readOnly = false,
    Widget? suffixIcon,
  }) {
    final isNumeric = _isNumericType(type);
    final effectiveKeyboardType =
        readOnly ? TextInputType.none : (isNumeric ? type : TextInputType.multiline);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        readOnly: readOnly,
        keyboardType: effectiveKeyboardType,
        inputFormatters: readOnly ? null : fmts,
        onChanged: readOnly ? null : (_) => onChanged?.call(),
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
          suffixIcon: suffixIcon,
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
    final isUnsafe = _selectedUserLooksUnsafeForEmployeeLink();

    final fullName = _selectedUserFullName();
    final phone = _selectedUserPhone();
    final role = _selectedUserRole();

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
            if (fullName.isNotEmpty || phone.isNotEmpty || role.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (fullName.isNotEmpty) Text('ชื่อบัญชี: $fullName'),
              if (phone.isNotEmpty) Text('โทรศัพท์: $phone'),
              if (role.isNotEmpty) Text('บทบาท: $role'),
            ],
            if (isUnsafe) ...[
              const SizedBox(height: 10),
              const Text(
                'บัญชีที่เลือกเป็นผู้ดูแล จึงไม่สามารถผูกเป็นพนักงานได้',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_saving || _loadingLinkedUser)
                        ? null
                        : _openUserLinkSearch,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('ค้นหาผู้ใช้'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'ล้างค่า',
                  onPressed: _loadingLinkedUser ? null : _clearLinkedUser,
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
                _field(
                  'ตำแหน่ง (แสดงในแอป)',
                  _positionCtrl,
                  onChanged: _calcPreview,
                ),
                _field(
                  'User ID',
                  _linkedUserIdCtrl,
                  onChanged: _calcPreview,
                  hint: 'เลือกจากปุ่มค้นหาผู้ใช้',
                  readOnly: true,
                  suffixIcon: _hasLinkedUser()
                      ? IconButton(
                          tooltip: 'ล้างค่า',
                          onPressed: _clearLinkedUser,
                          icon: const Icon(Icons.clear),
                        )
                      : null,
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