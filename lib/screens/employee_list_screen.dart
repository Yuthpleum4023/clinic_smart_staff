import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

import 'package:clinic_smart_staff/screens/employee_detail_screen.dart';
import 'package:clinic_smart_staff/screens/add_employee_screen.dart';
import 'package:clinic_smart_staff/screens/edit_employee_screen.dart';

enum _EmployeeFilterType {
  all,
  fulltime,
  parttime,
}

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  bool _loading = true;
  List<EmployeeModel> _employees = [];

  final TextEditingController _searchCtrl = TextEditingController();
  _EmployeeFilterType _filter = _EmployeeFilterType.all;

  ApiClient get _staffClient => ApiClient(baseUrl: ApiConfig.staffBaseUrl);

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  double _toDouble(dynamic v) {
    final raw = _s(v).replaceAll(',', '');
    return double.tryParse(raw) ?? 0.0;
  }

  String _backendEmploymentTypeToLocal(String raw) {
    final t = raw.trim().toLowerCase();
    return t == 'parttime' ? 'parttime' : 'fulltime';
  }

  List<String> _splitFullName(String fullName) {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return ['', ''];
    if (parts.length == 1) return [parts.first, ''];
    return [parts.first, parts.sublist(1).join(' ')];
  }

  EmployeeModel _employeeFromBackend(
    Map<String, dynamic> raw, {
    EmployeeModel? local,
  }) {
    final staffId = _s(raw['staffId']).isNotEmpty ? _s(raw['staffId']) : _s(raw['_id']);
    final fullName = _s(raw['fullName']);
    final split = _splitFullName(fullName);

    final firstName = split[0].isNotEmpty
        ? split[0]
        : (local?.firstName ?? '');
    final lastName = split[1].isNotEmpty
        ? split[1]
        : (local?.lastName ?? '');

    final localEmployment = _backendEmploymentTypeToLocal(_s(raw['employmentType']));
    final isParttime = localEmployment == 'parttime';

    return EmployeeModel(
      id: staffId.isNotEmpty ? staffId : (local?.id ?? ''),
      staffId: staffId.isNotEmpty ? staffId : (local?.staffId ?? ''),
      linkedUserId: _s(raw['userId']).isNotEmpty
          ? _s(raw['userId'])
          : (local?.linkedUserId ?? ''),
      employeeCode: local?.employeeCode ?? '',
      firstName: firstName,
      lastName: lastName,
      position: (local?.position ?? '').trim().isNotEmpty
          ? local!.position
          : 'Staff',
      employmentType: localEmployment,
      baseSalary: isParttime
          ? 0.0
          : _toDouble(raw['monthlySalary']),
      bonus: local?.bonus ?? 0.0,
      absentDays: local?.absentDays ?? 0,
      hourlyWage: isParttime
          ? _toDouble(raw['hourlyRate'])
          : 0.0,
      otEntries: local?.otEntries ?? const [],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchEmployeesFromBackend() async {
    Object? lastError;

    final candidates = <String>[
      '/api/employees',
      '/employees',
    ];

    for (final path in candidates) {
      try {
        final res = await _staffClient.get(path, auth: true);
        final dynamic items = res['items'];

        if (items is List) {
          return items
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (res['employee'] is Map) {
          return [Map<String, dynamic>.from(res['employee'] as Map)];
        }

        if (res is Map<String, dynamic> && res['data'] is List) {
          return (res['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        return [];
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError?.toString() ?? 'LOAD_EMPLOYEES_FAILED');
  }

  Future<void> _persistMergedCache(List<EmployeeModel> merged) async {
    try {
      await StorageService.saveEmployees(merged);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final localList = await StorageService.loadEmployees();
      final localMap = <String, EmployeeModel>{};

      for (final e in localList) {
        final key = e.staffId.trim().isNotEmpty ? e.staffId.trim() : e.id.trim();
        if (key.isNotEmpty) {
          localMap[key] = e;
        }
      }

      final backendRows = await _fetchEmployeesFromBackend();
      final merged = backendRows.map((raw) {
        final key = _s(raw['staffId']).isNotEmpty ? _s(raw['staffId']) : _s(raw['_id']);
        final local = localMap[key];
        return _employeeFromBackend(raw, local: local);
      }).toList();

      await _persistMergedCache(merged);

      if (!mounted) return;
      setState(() {
        _employees = merged;
        _loading = false;
      });
    } catch (_) {
      final localList = await StorageService.loadEmployees();
      if (!mounted) return;
      setState(() {
        _employees = localList;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('โหลดจาก backend ไม่สำเร็จ ใช้ข้อมูลในเครื่องชั่วคราว'),
        ),
      );
    }
  }

  Future<void> _openAddEmployee() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEmployeeScreen()),
    );
    await _load();
  }

  Future<void> _openEmployeeDetail(EmployeeModel emp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeDetailScreen(employee: emp),
      ),
    );
    await _load();
  }

  Future<void> _openEditEmployee(EmployeeModel emp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditEmployeeScreen(employee: emp),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('อัปเดตข้อมูลพนักงานแล้ว')),
    );
    await _load();
  }

  Future<void> _deactivateOnBackend(EmployeeModel emp) async {
    final employeeId =
        emp.staffId.trim().isNotEmpty ? emp.staffId.trim() : emp.id.trim();

    if (employeeId.isEmpty) {
      throw Exception('ไม่พบ employee id สำหรับลบ');
    }

    Object? lastError;

    final candidates = <String>[
      '/api/employees/$employeeId',
      '/employees/$employeeId',
    ];

    for (final path in candidates) {
      try {
        await _staffClient.put(
          path,
          auth: true,
          body: {'active': false},
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError?.toString() ?? 'DEACTIVATE_EMPLOYEE_FAILED');
  }

  Future<void> _confirmDeleteEmployee(EmployeeModel emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ยืนยันการลบพนักงาน'),
        content: Text(
          'ต้องการลบ\n${emp.fullName}\nออกจากรายการพนักงานใช่หรือไม่?\n\n'
          'ระบบจะปิดการใช้งานใน backend และลบออกจาก cache ในเครื่อง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('ลบ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _deactivateOnBackend(emp);
      await StorageService.deleteEmployeeById(emp.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบพนักงานแล้ว: ${emp.fullName}')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบไม่สำเร็จ: $e')),
      );
    }
  }

  String _typeLabel(EmployeeModel e) {
    final t = e.employmentType.toLowerCase().trim();
    return t == 'parttime' ? 'Part-time' : 'Full-time';
  }

  bool _matchFilter(EmployeeModel e) {
    switch (_filter) {
      case _EmployeeFilterType.fulltime:
        return !e.isPartTime;
      case _EmployeeFilterType.parttime:
        return e.isPartTime;
      case _EmployeeFilterType.all:
        return true;
    }
  }

  bool _matchSearch(EmployeeModel e) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;

    final haystacks = <String>[
      e.fullName,
      e.firstName,
      e.lastName,
      e.position,
      e.employeeCode,
      e.staffId,
      e.linkedUserId,
      e.employmentType,
    ].map((s) => s.toLowerCase()).toList();

    return haystacks.any((s) => s.contains(q));
  }

  List<EmployeeModel> get _visibleEmployees {
    return _employees.where((e) {
      return _matchFilter(e) && _matchSearch(e);
    }).toList();
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEmployees;

    return Scaffold(
      appBar: AppBar(
        title: const Text('พนักงาน'),
        actions: [
          IconButton(
            tooltip: 'เพิ่มพนักงาน',
            icon: const Icon(Icons.person_add),
            onPressed: _openAddEmployee,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddEmployee,
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มพนักงาน'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'ค้นหาชื่อ / ตำแหน่ง / staffId / userId',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(
                              label: 'ทั้งหมด',
                              selected: _filter == _EmployeeFilterType.all,
                              onTap: () {
                                setState(() => _filter = _EmployeeFilterType.all);
                              },
                            ),
                            const SizedBox(width: 8),
                            _filterChip(
                              label: 'Full-time',
                              selected: _filter == _EmployeeFilterType.fulltime,
                              onTap: () {
                                setState(() => _filter = _EmployeeFilterType.fulltime);
                              },
                            ),
                            const SizedBox(width: 8),
                            _filterChip(
                              label: 'Part-time',
                              selected: _filter == _EmployeeFilterType.parttime,
                              onTap: () {
                                setState(() => _filter = _EmployeeFilterType.parttime);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _employees.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_outline, size: 48),
                                const SizedBox(height: 10),
                                const Text('ยังไม่มีพนักงาน'),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _openAddEmployee,
                                  icon: const Icon(Icons.add),
                                  label: const Text('เพิ่มพนักงานคนแรก'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : visible.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 120),
                                  Center(child: Text('ไม่พบข้อมูลที่ค้นหา')),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final emp = visible[i];
                                  final isParttime = emp.isPartTime;

                                  final salaryText = isParttime
                                      ? 'ชั่วโมงละ ${emp.hourlyWage.toStringAsFixed(0)}'
                                      : 'เงินเดือน ${emp.baseSalary.toStringAsFixed(0)}';

                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () => _openEmployeeDetail(emp),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        emp.fullName,
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${emp.position} • ${_typeLabel(emp)} • $salaryText',
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        'staffId: ${emp.staffId}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey.shade700,
                                                        ),
                                                      ),
                                                      if (emp.linkedUserId
                                                          .trim()
                                                          .isNotEmpty)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                          child: Text(
                                                            'userId: ${emp.linkedUserId}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey.shade700,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                onSelected: (v) async {
                                                  if (v == 'detail') {
                                                    await _openEmployeeDetail(emp);
                                                  } else if (v == 'edit') {
                                                    await _openEditEmployee(emp);
                                                  } else if (v == 'delete') {
                                                    await _confirmDeleteEmployee(emp);
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'detail',
                                                    child: Text('ดูรายละเอียด'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('แก้ไข'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('ลบ'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _openEmployeeDetail(emp),
                                                  icon: const Icon(Icons.visibility),
                                                  label: const Text('รายละเอียด'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _openEditEmployee(emp),
                                                  icon: const Icon(Icons.edit),
                                                  label: const Text('แก้ไข'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _confirmDeleteEmployee(emp),
                                                  icon: const Icon(Icons.delete_outline),
                                                  label: const Text('ลบ'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
    );
  }
}