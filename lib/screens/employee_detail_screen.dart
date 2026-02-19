// lib/screens/employee_detail_screen.dart
//
// ✅ FULL FILE (COPY-PASTE READY) — NO FUNCTION CUT
// - ✅ OT: สวิตช์ (เห็นแน่นอน + ไม่ล้น)  เปิด=×2.0 / ปิด=×1.5
// - ✅ FIX SCROLL (ชัวร์บน iOS): ListView + controller + primary:false + physics
// - ✅ FIX เห็นไม่เต็ม/โดนตัดล่าง: AnimatedPadding ตาม viewInsets + padding.bottom เผื่อ home indicator
// - ✅ FIX PIN จอแดง (_dependents.isEmpty + used-after-dispose):
//      - ✅ ไม่ dispose pinCtrl (iOS dialog ปิดแล้วยังมี 1-2 frame rebuild)
//      - ✅ rootNavigator pop + unfocus + กัน submit ซ้ำ
//      - ✅ setState หลัง dialog ด้วย microtask
// - ✅ ไม่ตัด function ใดๆ ทั้งหมดอยู่ครบ

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

import 'package:clinic_smart_staff/screens/payroll/payroll_after_tax_preview_screen.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_home_screen.dart';

/// ✅ Part-time work hours entry (ตามแนวทางใหม่ของคุณ: {date, hours})
class WorkHourEntry {
  final String date; // yyyy-MM-dd
  final double hours;

  const WorkHourEntry({required this.date, required this.hours});

  Map<String, dynamic> toMap() => {'date': date, 'hours': hours};

  factory WorkHourEntry.fromMap(Map<String, dynamic> map) {
    return WorkHourEntry(
      date: (map['date'] ?? '').toString(),
      hours: (map['hours'] as num? ?? 0).toDouble(),
    );
  }

  bool isInMonth(int year, int month) {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    return d.year == year && d.month == month;
  }
}

class EmployeeDetailScreen extends StatefulWidget {
  final String clinicId; // อาจว่างได้
  final EmployeeModel employee;

  const EmployeeDetailScreen({
    super.key,
    this.clinicId = '',
    required this.employee,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late EmployeeModel emp;

  // ---------------- UI state ----------------
  bool _isEditUnlocked = false;
  bool _disposed = false;

  // ✅ FIX SCROLL: controller ของเราเอง + primary:false
  final ScrollController _scrollCtrl = ScrollController();

  // month selected
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // SSO percent (fulltime)
  late final TextEditingController ssoPercentCtrl;
  final TextInputFormatter _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'));

  // Part-time work hours (prefs)
  bool _workEntriesLoaded = false;
  List<WorkHourEntry> _allWorkEntries = [];
  DateTime? workDate;
  late final TextEditingController workHoursCtrl;

  // OT pickers
  DateTime? otDate;
  TimeOfDay? otStart;
  TimeOfDay? otEnd;

  /// ✅ OT multiplier toggle
  bool isHolidayX2 = false;

  static const double _otNormalMultiplier = 1.5;
  static const double _otHolidayMultiplier = 2.0;

  @override
  void initState() {
    super.initState();

    // ✅ init controllers ใน initState
    ssoPercentCtrl = TextEditingController();
    workHoursCtrl = TextEditingController(text: '');

    emp = widget.employee;
    selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

    _initSsoPercentFromPrefs();
    _loadWorkEntriesIfNeeded();
  }

  @override
  void dispose() {
    // ✅ iOS: บางเคสมี rebuild หลัง pop -> controller ถูกเรียกต่อแม้ dispose แล้ว
    // ดังนั้นเรา "ไม่ dispose controller" เพื่อกัน used-after-dispose
    _disposed = true;

    // ถ้าอยาก dispose ภายหลังค่อยเปิดใช้ได้
    // _scrollCtrl.dispose();

    super.dispose();
  }

  // =========================================================
  // SAFE BACK NAV
  // =========================================================
  Future<void> _safePopOrGoClinicHome() async {
    if (!mounted) return;

    final nav = Navigator.of(context);

    if (nav.canPop()) {
      nav.pop();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ClinicHomeScreen()),
        (route) => false,
      );
    });
  }

  // =========================================================
  // SNACK
  // =========================================================
  void _snack(String msg) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =========================================================
  // FORMATTERS
  // =========================================================
  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String _fmtMonth(DateTime d) => '${d.year}-${_two(d.month)}';
  String _fmtCloseMonth(DateTime d) => _fmtMonth(d);
  String _fmtTOD(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  // =========================================================
  // PICK MONTH
  // =========================================================
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'เลือกเดือน (เลือกวันใดก็ได้ในเดือนนั้น)',
    );
    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() {
      selectedMonth = DateTime(picked.year, picked.month, 1);
    });

    await _loadWorkEntriesIfNeeded();

    // ✅ หลังเปลี่ยนเดือน เลื่อนขึ้นบนให้เห็นสรุปเสมอ
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  // =========================================================
  // EDIT UNLOCK (PIN)
  // =========================================================
  Future<void> _toggleEditLock() async {
    if (_isEditUnlocked) {
      if (!mounted || _disposed) return;
      // ✅ ปลอดภัย: ทำใน microtask กันชนเฟรม/สโคป
      Future.microtask(() {
        if (!mounted || _disposed) return;
        setState(() => _isEditUnlocked = false);
        _snack('ล็อกโหมดแก้ไขแล้ว');
      });
      return;
    }

    final ok = await _promptForPin();
    if (!mounted || _disposed) return;

    // ✅ แก้จอแดง iOS: ห้าม setState ทันทีหลัง dialog ปิด
    Future.microtask(() {
      if (!mounted || _disposed) return;
      if (ok) {
        setState(() => _isEditUnlocked = true);
        _snack('ปลดล็อกโหมดแก้ไขแล้ว');
      } else {
        _snack('รหัสไม่ถูกต้อง');
      }
    });
  }

  /// ✅ FIX PIN (iOS จอแดง):
  /// - ไม่ dispose pinCtrl (dialog ปิดแล้วยัง rebuild ระหว่าง animation)
  /// - rootNavigator pop + unfocus + กัน submit ซ้ำ
  Future<bool> _promptForPin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = (prefs.getString('app_edit_pin') ?? '1234').trim();

    // ✅ สำคัญ: ห้าม dispose (ดูเหตุผลด้านบน)
    final TextEditingController pinCtrl = TextEditingController();
    bool submitted = false;

    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        void closeWith(bool v) {
          if (submitted) return;
          submitted = true;

          // ปิดคีย์บอร์ดก่อน กัน build scope เพี้ยน
          FocusScope.of(ctx).unfocus();

          // pop ผ่าน rootNavigator กันชน PopScope/route อื่น
          Navigator.of(ctx, rootNavigator: true).pop(v);
        }

        void submit() {
          final pass = pinCtrl.text.trim() == savedPin;
          closeWith(pass);
        }

        return AlertDialog(
          title: const Text('ใส่รหัสเพื่อปลดล็อก'),
          content: TextField(
            controller: pinCtrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => closeWith(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: submit,
              child: const Text('ยืนยัน'),
            ),
          ],
        );
      },
    );

    return ok == true;
  }

  // =========================================================
  // SSO PERCENT STORAGE
  // =========================================================
  Future<void> _initSsoPercentFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getDouble('settings_sso_percent') ?? 5.0;
    if (!mounted || _disposed) return;
    ssoPercentCtrl.text = p.toStringAsFixed(2);
  }

  double _getSsoPercent() {
    final v = double.tryParse(ssoPercentCtrl.text.trim());
    return (v == null || v <= 0) ? 5.0 : v;
  }

  Future<void> _saveSsoPercentFromUI() async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    final v = double.tryParse(ssoPercentCtrl.text.trim());
    if (v == null || v <= 0 || v > 20) {
      _snack('กรุณาใส่ % ให้ถูกต้อง (เช่น 5.00)');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('settings_sso_percent', v);

    if (!mounted || _disposed) return;
    setState(() {});
    _snack('บันทึก SSO% = ${v.toStringAsFixed(2)} แล้ว');
  }

  // =========================================================
  // RESOLVE CLINIC ID
  // =========================================================
  Future<String?> _resolveClinicId() async {
    final fromWidget = widget.clinicId.trim();
    if (fromWidget.isNotEmpty) return fromWidget;

    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = (prefs.getString('app_clinic_id') ?? '').trim();
    if (fromPrefs.isNotEmpty) return fromPrefs;

    try {
      final dynamic store = StorageService();
      final dynamic got = await store.getClinicId();
      final String? v = got?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}

    return null;
  }

  // =========================================================
  // PART-TIME WORK HOURS (PREFS)
  // =========================================================
  String get _workEntriesKey => 'work_entries_${emp.id}';

  Future<void> _loadWorkEntriesIfNeeded() async {
    if (!emp.isPartTime) return;

    if (!mounted || _disposed) return;
    setState(() => _workEntriesLoaded = false);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workEntriesKey);

    List<WorkHourEntry> list = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final it in decoded) {
            if (it is Map) {
              final m = it.map((k, v) => MapEntry(k.toString(), v));
              list.add(WorkHourEntry.fromMap(Map<String, dynamic>.from(m)));
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted || _disposed) return;
    setState(() {
      _allWorkEntries = list;
      _workEntriesLoaded = true;
    });
  }

  Future<void> _persistWorkEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(_allWorkEntries.map((e) => e.toMap()).toList());
    await prefs.setString(_workEntriesKey, payload);
  }

  List<WorkHourEntry> _monthWorkEntries(DateTime month) {
    return _allWorkEntries.where((e) => e.isInMonth(month.year, month.month)).toList();
  }

  double _sumWorkHours(List<WorkHourEntry> list) {
    double total = 0;
    for (final e in list) {
      total += e.hours;
    }
    return total;
  }

  Future<void> _pickWorkDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: workDate ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'เลือกวันที่ทำงาน',
    );
    if (picked == null) return;
    if (!mounted || _disposed) return;
    setState(() => workDate = picked);
  }

  Future<void> _addWorkEntry() async {
    if (!emp.isPartTime) return;

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (workDate == null) {
      _snack('กรุณาเลือกวันที่');
      return;
    }

    final hours = double.tryParse(workHoursCtrl.text.trim());
    if (hours == null || hours <= 0 || hours > 24) {
      _snack('กรุณาใส่ชั่วโมงให้ถูกต้อง (เช่น 8.00)');
      return;
    }

    final entry = WorkHourEntry(date: _fmtDate(workDate!), hours: hours);

    if (!mounted || _disposed) return;
    setState(() {
      _allWorkEntries.add(entry);
      workDate = null;
      workHoursCtrl.text = '';
    });

    await _persistWorkEntries();
    await _loadWorkEntriesIfNeeded();
    _snack('บันทึกชั่วโมงทำงานแล้ว (${hours.toStringAsFixed(2)} ชม.)');
  }

  Future<void> _deleteWorkEntry(int indexInMonth, List<WorkHourEntry> monthList) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (indexInMonth < 0 || indexInMonth >= monthList.length) return;
    final target = monthList[indexInMonth];

    if (!mounted || _disposed) return;
    setState(() {
      _allWorkEntries.removeWhere((e) => e.date == target.date && e.hours == target.hours);
    });

    await _persistWorkEntries();
    await _loadWorkEntriesIfNeeded();
    _snack('ลบรายการชั่วโมงทำงานแล้ว');
  }

  // =========================================================
  // OT helpers
  // =========================================================
  Future<void> _pickOtDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: otDate ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'เลือกวันที่ทำ OT',
    );
    if (picked == null) return;
    if (!mounted || _disposed) return;
    setState(() => otDate = picked);
  }

  Future<void> _pickTimeStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: otStart ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'เวลาเริ่ม OT',
    );
    if (picked == null) return;
    if (!mounted || _disposed) return;
    setState(() => otStart = picked);
  }

  Future<void> _pickTimeEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: otEnd ?? const TimeOfDay(hour: 20, minute: 0),
      helpText: 'เวลาจบ OT',
    );
    if (picked == null) return;
    if (!mounted || _disposed) return;
    setState(() => otEnd = picked);
  }

  Future<void> _addOtEntry() async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (otDate == null || otStart == null || otEnd == null) {
      _snack('กรุณาเลือก วันที่/เวลา OT ให้ครบ');
      return;
    }

    final entry = OTEntry(
      date: _fmtDate(otDate!),
      start: _fmtTOD(otStart!),
      end: _fmtTOD(otEnd!),
      multiplier: isHolidayX2 ? _otHolidayMultiplier : _otNormalMultiplier,
    );

    if (!mounted || _disposed) return;
    setState(() {
      emp = emp.addOtEntry(entry);
      otDate = null;
      otStart = null;
      otEnd = null;
      isHolidayX2 = false;
    });

    await _saveEmployeeLocal();
    _snack('บันทึก OT แล้ว (${entry.hours.toStringAsFixed(2)} ชม.)');
  }

  Future<void> _deleteOtEntryByMonthIndex(int indexInMonth, List<OTEntry> monthList) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }
    if (indexInMonth < 0 || indexInMonth >= monthList.length) return;

    final target = monthList[indexInMonth];

    final realIndex = emp.otEntries.indexWhere((e) =>
        e.date == target.date &&
        e.start == target.start &&
        e.end == target.end &&
        e.multiplier == target.multiplier);

    if (realIndex < 0) return;

    if (!mounted || _disposed) return;
    setState(() {
      emp = emp.removeOtEntryAt(realIndex);
    });

    await _saveEmployeeLocal();
    _snack('ลบ OT แล้ว');
  }

  Future<void> _saveEmployeeLocal() async {
    try {
      final dynamic store = StorageService();
      await store.updateEmployee(emp);
    } catch (_) {}
  }

  // =========================================================
  // UI helper: triple buttons with Wrap (กัน overflow)
  // =========================================================
  Widget _triplePickButtons({
    required String label1,
    required VoidCallback on1,
    required String label2,
    required VoidCallback on2,
    required String label3,
    required VoidCallback on3,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(onPressed: on1, child: Text(label1)),
        OutlinedButton(onPressed: on2, child: Text(label2)),
        OutlinedButton(onPressed: on3, child: Text(label3)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isParttime = emp.isPartTime;

    final monthWorkEntries = _monthWorkEntries(selectedMonth);
    final totalWorkHours = _sumWorkHours(monthWorkEntries);

    final totalOtHours = emp.totalOtHoursOfMonth(selectedMonth.year, selectedMonth.month);
    final totalOtAmount = emp.totalOtAmountOfMonth(selectedMonth.year, selectedMonth.month);

    final ssoPercent = _getSsoPercent();
    final ssoAmount = isParttime ? 0.0 : emp.socialSecurity(ssoPercent);
    final absentDeduction = isParttime ? 0.0 : emp.absentDeduction();

    final hourlyWage = emp.hourlyWage;
    final normalPay = isParttime ? (totalWorkHours * hourlyWage) : 0.0;
    final otPay = totalOtAmount;

    final netNoOtFulltime = isParttime ? 0.0 : emp.netSalary(ssoPercent);
    final totalMonthPayFulltime = isParttime ? 0.0 : (netNoOtFulltime + otPay);
    final totalMonthPayParttime = isParttime ? (normalPay + otPay + emp.bonus) : 0.0;

    final grossMonthlyForTax =
        isParttime ? (normalPay + emp.bonus) : (emp.baseSalary + emp.bonus);
    final ssoForTax = ssoAmount;

    final monthOtEntries = emp.otEntries
        .where((e) => e.isInMonth(selectedMonth.year, selectedMonth.month))
        .toList();

    // ✅ bottom safe space แบบชัวร์บน iPhone:
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom; // home indicator
    final keyboard = MediaQuery.of(context).viewInsets.bottom; // keyboard

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _safePopOrGoClinicHome();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text('รายละเอียด: ${emp.fullName}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _safePopOrGoClinicHome,
          ),
          actions: [
            IconButton(
              tooltip: _isEditUnlocked ? 'ล็อกโหมดแก้ไข' : 'ปลดล็อกโหมดแก้ไข',
              onPressed: _toggleEditLock,
              icon: Icon(_isEditUnlocked ? Icons.lock_open : Icons.lock),
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboard),
            child: ListView(
              controller: _scrollCtrl,
              primary: false,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(14, 14, 14, bottomSafe + 80),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(_isEditUnlocked ? Icons.lock_open : Icons.lock, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isEditUnlocked
                                ? 'โหมดแก้ไข: ปลดล็อกแล้ว'
                                : 'โหมดแก้ไข: ล็อกอยู่ (กดรูปกุญแจเพื่อใส่รหัส)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'เดือนที่เลือก: ${_fmtMonth(selectedMonth)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickMonth,
                      child: const Text('เปลี่ยนเดือน'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สรุปเดือน ${_fmtMonth(selectedMonth)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),

                        if (!isParttime) ...[
                          const Text('ประเภท: Full-time'),
                          const SizedBox(height: 6),
                          const Text('อัตราประกันสังคม (%)'),
                          const SizedBox(height: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: ssoPercentCtrl,
                                enabled: _isEditUnlocked,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_decimalFormatter],
                                decoration: const InputDecoration(
                                  labelText: 'เช่น 5.00',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _saveSsoPercentFromUI,
                                child: const Text('บันทึก'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('หักประกันสังคม: -${ssoAmount.toStringAsFixed(2)} บาท'),
                          Text('หักวันลา/ขาด: -${absentDeduction.toStringAsFixed(2)} บาท'),
                          const Divider(height: 18),
                          Text('ชั่วโมง OT รวม: ${totalOtHours.toStringAsFixed(2)} ชม.'),
                          Text('ค่า OT รวม: ${otPay.toStringAsFixed(2)} บาท'),
                          const SizedBox(height: 10),
                          Text('สุทธิเดิม (ไม่รวม OT): ${netNoOtFulltime.toStringAsFixed(2)} บาท'),
                          Text(
                            'สุทธิรวม OT (ทั้งเดือน): ${totalMonthPayFulltime.toStringAsFixed(2)} บาท',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ] else ...[
                          const Text('ประเภท: Part-time'),
                          const SizedBox(height: 6),
                          Text('อัตราค่าจ้าง: ${hourlyWage.toStringAsFixed(2)} บาท/ชม.'),
                          Text('ชั่วโมงทำงานปกติรวม: ${totalWorkHours.toStringAsFixed(2)} ชม.'),
                          Text('ค่าแรงปกติรวม: ${normalPay.toStringAsFixed(2)} บาท'),
                          const SizedBox(height: 6),
                          Text('ชั่วโมง OT รวม: ${totalOtHours.toStringAsFixed(2)} ชม.'),
                          Text('ค่า OT รวม: ${otPay.toStringAsFixed(2)} บาท'),
                          const Divider(height: 18),
                          Text(
                            'รวมทั้งเดือน: ${totalMonthPayParttime.toStringAsFixed(2)} บาท',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],

                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('ดูหลังหักภาษี (คำนวณจาก Backend)'),
                            onPressed: () async {
                              final clinicId = await _resolveClinicId();
                              if (!mounted) return;

                              if (clinicId == null || clinicId.trim().isEmpty) {
                                _snack('ไม่พบ clinicId อัตโนมัติ (ลองออก/เข้าใหม่)');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PayrollAfterTaxPreviewScreen(
                                    grossMonthly: grossMonthlyForTax,
                                    year: selectedMonth.year,
                                    ssoEmployeeMonthly: ssoForTax,
                                    clinicId: clinicId,
                                    employeeId: emp.id,
                                    otPay: otPay,
                                    bonus: emp.bonus,
                                    otherAllowance: 0,
                                    otherDeduction: isParttime ? 0 : absentDeduction,
                                    pvdEmployeeMonthly: 0,
                                    closeMonth: _fmtCloseMonth(selectedMonth),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (isParttime) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'บันทึกชั่วโมงทำงานปกติ (Part-time)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton(
                                onPressed: _pickWorkDate,
                                child: Text(
                                  workDate == null ? 'เลือกวันที่' : 'วันที่: ${_fmtDate(workDate!)}',
                                ),
                              ),
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  controller: workHoursCtrl,
                                  enabled: _isEditUnlocked,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [_decimalFormatter],
                                  decoration: const InputDecoration(
                                    labelText: 'ชั่วโมง (เช่น 8.00)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _addWorkEntry,
                              icon: const Icon(Icons.save),
                              label: const Text('บันทึกชั่วโมงทำงาน'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (!_workEntriesLoaded)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (monthWorkEntries.isEmpty)
                    const Text('ยังไม่มีชั่วโมงทำงานในเดือนนี้')
                  else
                    ...List.generate(monthWorkEntries.length, (i) {
                      final w = monthWorkEntries[i];
                      final pay = w.hours * hourlyWage;
                      return Card(
                        child: ListTile(
                          title: Text(w.date),
                          subtitle: Text(
                            'ชั่วโมง: ${w.hours.toStringAsFixed(2)} ชม. • ค่าแรง: ${pay.toStringAsFixed(2)} บาท',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey),
                            onPressed: () => _deleteWorkEntry(i, monthWorkEntries),
                          ),
                        ),
                      );
                    }),
                ],

                const SizedBox(height: 12),

                // ========================= OT CARD =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'เพิ่ม OT รายวัน',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        _triplePickButtons(
                          label1: otDate == null ? 'เลือกวันที่' : 'วันที่: ${_fmtDate(otDate!)}',
                          on1: _pickOtDate,
                          label2: otStart == null ? 'เวลาเริ่ม' : 'เริ่ม: ${otStart!.format(context)}',
                          on2: _pickTimeStart,
                          label3: otEnd == null ? 'เวลาจบ' : 'จบ: ${otEnd!.format(context)}',
                          on3: _pickTimeEnd,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SwitchListTile.adaptive(
                            value: isHolidayX2,
                            onChanged: (v) {
                              if (!_isEditUnlocked) {
                                _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
                                return;
                              }
                              if (!mounted) return;
                              setState(() => isHolidayX2 = v);
                            },
                            secondary: Icon(
                              Icons.flash_on,
                              color: isHolidayX2 ? Colors.red : Colors.grey,
                            ),
                            title: const Text('OT วันหยุด / นักขัตฤกษ์'),
                            subtitle: Text(
                              isHolidayX2
                                  ? 'ตัวคูณ ×${_otHolidayMultiplier.toStringAsFixed(1)}'
                                  : 'ตัวคูณ ×${_otNormalMultiplier.toStringAsFixed(1)}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _addOtEntry,
                            icon: const Icon(Icons.save),
                            label: const Text('บันทึก OT ของวันนี้'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'รายการ OT เดือน ${_fmtMonth(selectedMonth)} (${monthOtEntries.length} รายการ)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                if (monthOtEntries.isEmpty)
                  const Text('ยังไม่มี OT ในเดือนนี้')
                else
                  ...List.generate(monthOtEntries.length, (i) {
                    final e = monthOtEntries[i];
                    return Card(
                      child: ListTile(
                        title: Text('${e.date}  ${e.start} - ${e.end}'),
                        subtitle: Text(
                          'ชั่วโมง: ${e.hours.toStringAsFixed(2)} ชม. • ตัวคูณ: ${e.multiplier.toStringAsFixed(1)}x',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () => _deleteOtEntryByMonthIndex(i, monthOtEntries),
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
