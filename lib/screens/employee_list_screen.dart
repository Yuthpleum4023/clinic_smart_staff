// lib/screens/employee_list_screen.dart
import 'package:flutter/material.dart';

import 'package:clinic_payroll/models/employee_model.dart';
import 'package:clinic_payroll/services/storage_service.dart';

import 'package:clinic_payroll/screens/employee_detail_screen.dart';
import 'package:clinic_payroll/screens/add_employee_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  bool _loading = true;
  List<EmployeeModel> _employees = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await StorageService.loadEmployees();
    if (!mounted) return;
    setState(() {
      _employees = list;
      _loading = false;
    });
  }

  Future<void> _openAddEmployee() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEmployeeScreen()),
    );
    await _load();
  }

  String _typeLabel(EmployeeModel e) {
    final t = e.employmentType.toLowerCase().trim();
    return t == 'parttime' ? 'Part-time' : 'Full-time';
  }

  @override
  Widget build(BuildContext context) {
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _employees.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final emp = _employees[i];

                      final isParttime =
                          emp.employmentType.toLowerCase().trim() == 'parttime';

                      final salaryText = isParttime
                          ? 'ชั่วโมงละ ${emp.hourlyWage.toStringAsFixed(0)}'
                          : 'เงินเดือน ${emp.baseSalary.toStringAsFixed(0)}';

                      return ListTile(
                        title: Text(emp.fullName),
                        subtitle: Text(
                          '${emp.position} • ${_typeLabel(emp)} • $salaryText',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          // ✅ เปิดหน้ารายละเอียด (มี OT/WorkEntry/เลือกเดือน/SSO)
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmployeeDetailScreen(employee: emp),
                            ),
                          );

                          // ✅ กลับมาแล้ว reload เสมอ (เพราะ detail บันทึกลง storage อยู่แล้ว)
                          await _load();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
