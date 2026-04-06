import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/services/settings_service.dart';
import 'package:clinic_smart_staff/services/auth_service.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_ot_settings_screen.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/api/clinic_logo_api.dart';
import 'package:clinic_smart_staff/widgets/clinic_logo_view.dart';

class ClinicAdminSettingsScreen extends StatefulWidget {
  const ClinicAdminSettingsScreen({super.key});

  @override
  State<ClinicAdminSettingsScreen> createState() =>
      _ClinicAdminSettingsScreenState();
}

class _ClinicAdminSettingsScreenState extends State<ClinicAdminSettingsScreen> {
  bool _loading = true;

  static const String _kClinicId = 'app_clinic_id';
  static const String _payrollBaseUrl =
      'https://payroll-service-808t.onrender.com';

  final _clinicNameCtrl = TextEditingController();
  final _clinicBranchNameCtrl = TextEditingController();
  final _clinicAddressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _clinicTaxIdCtrl = TextEditingController();

  bool _savingProfile = false;
  bool _uploadingLogo = false;
  bool _removingLogo = false;

  double _ssoPercent = 5.0;
  bool _savingSso = false;

  bool _hasPin = false;
  bool _savingPin = false;

  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  String _currentClinicId = '';
  String _logoUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clinicNameCtrl.dispose();
    _clinicBranchNameCtrl.dispose();
    _clinicAddressCtrl.dispose();
    _phoneCtrl.dispose();
    _clinicTaxIdCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _profileKey(String clinicId, String field) {
    return 'clinic_profile_${clinicId}_$field';
  }

  Future<String> _readClinicScoped(String clinicId, String field) async {
    if (clinicId.trim().isEmpty) return '';
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_profileKey(clinicId, field)) ?? '').trim();
  }

  Future<void> _writeClinicScoped(
    String clinicId,
    String field,
    String value,
  ) async {
    if (clinicId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey(clinicId, field), value.trim());
  }

  Future<void> _clearForm() async {
    if (!mounted) return;
    setState(() {
      _clinicNameCtrl.text = '';
      _clinicBranchNameCtrl.text = '';
      _clinicAddressCtrl.text = '';
      _phoneCtrl.text = '';
      _clinicTaxIdCtrl.text = '';
      _logoUrl = '';
    });
  }

  Future<String> _getClinicId() async {
    final prefs = await SharedPreferences.getInstance();
    final cid = (prefs.getString(_kClinicId) ?? '').trim();
    return cid;
  }

  Future<String> _getTokenRobust() async {
    final t = await AuthStorage.getToken();
    if (t != null && t.trim().isNotEmpty) return t.trim();

    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'auth_token',
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ];

    for (final k in keys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty) return v;
    }

    return '';
  }

  Future<void> _loadProfileFromPrefs(String clinicId) async {
    if (clinicId.trim().isEmpty) {
      await _clearForm();
      return;
    }

    final name = await _readClinicScoped(clinicId, 'name');
    final branchName = await _readClinicScoped(clinicId, 'branchName');
    final addr = await _readClinicScoped(clinicId, 'address');
    final phone = await _readClinicScoped(clinicId, 'phone');
    final taxId = await _readClinicScoped(clinicId, 'taxId');
    final logoUrl = await _readClinicScoped(clinicId, 'logoUrl');

    if (!mounted) return;

    setState(() {
      _clinicNameCtrl.text = name;
      _clinicBranchNameCtrl.text = branchName;
      _clinicAddressCtrl.text = addr;
      _phoneCtrl.text = phone;
      _clinicTaxIdCtrl.text = taxId;
      _logoUrl = logoUrl;
    });
  }

  Future<void> _loadClinicProfileFromBackend(String clinicId) async {
    final token = await _getTokenRobust();

    if (token.isEmpty || clinicId.trim().isEmpty) return;

    try {
      final uri = Uri.parse('$_payrollBaseUrl/clinics/$clinicId');
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode >= 400) return;

      final decoded = json.decode(resp.body);
      if (decoded is! Map) return;

      final c = (decoded['clinic'] is Map) ? decoded['clinic'] as Map : decoded;

      final name = (c['name'] ?? c['clinicName'] ?? '').toString().trim();
      final branchName =
          (c['branchName'] ?? c['clinicBranchName'] ?? '').toString().trim();
      final phone = (c['phone'] ?? c['clinicPhone'] ?? '').toString().trim();
      final addr = (c['address'] ?? c['clinicAddress'] ?? '').toString().trim();
      final taxId = (c['taxId'] ?? c['clinicTaxId'] ?? '').toString().trim();
      final logoUrl =
          (c['logoUrl'] ?? c['clinicLogoUrl'] ?? '').toString().trim();

      if (!mounted) return;

      setState(() {
        _clinicNameCtrl.text = name;
        _clinicBranchNameCtrl.text = branchName;
        _clinicAddressCtrl.text = addr;
        _phoneCtrl.text = phone;
        _clinicTaxIdCtrl.text = taxId;
        _logoUrl = logoUrl;
      });

      await _writeClinicScoped(clinicId, 'name', name);
      await _writeClinicScoped(clinicId, 'branchName', branchName);
      await _writeClinicScoped(clinicId, 'address', addr);
      await _writeClinicScoped(clinicId, 'phone', phone);
      await _writeClinicScoped(clinicId, 'taxId', taxId);
      await _writeClinicScoped(clinicId, 'logoUrl', logoUrl);
    } catch (_) {}
  }

  bool _isValidPhoneOrEmpty(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return true;
    return RegExp(r'^\d{9,10}$').hasMatch(p);
  }

  bool get _logoBusy => _uploadingLogo || _removingLogo;

  Future<void> _pickAndUploadLogo() async {
    if (_logoBusy) return;

    final clinicId = _currentClinicId.trim();
    if (clinicId.isEmpty) {
      _snack('ไม่พบ clinicId ของบัญชีนี้ กรุณาออกจากระบบแล้วเข้าใหม่');
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );

      if (picked == null) return;

      setState(() => _uploadingLogo = true);

      final result = await ClinicLogoApi.uploadLogo(
        clinicId: clinicId,
        file: File(picked.path),
      );

      final clinic = (result['clinic'] is Map<String, dynamic>)
          ? result['clinic'] as Map<String, dynamic>
          : <String, dynamic>{};

      final logoUrl = (clinic['logoUrl'] ?? '').toString().trim();
      final clinicName = (clinic['name'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _logoUrl = logoUrl;
        if (clinicName.isNotEmpty) {
          _clinicNameCtrl.text = clinicName;
        }
      });

      await _writeClinicScoped(clinicId, 'logoUrl', logoUrl);

      _snack('อัปโหลดโลโก้สำเร็จ');
    } catch (e) {
      _snack('อัปโหลดโลโก้ไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    if (_logoBusy || _logoUrl.trim().isEmpty) return;

    final clinicId = _currentClinicId.trim();
    if (clinicId.isEmpty) {
      _snack('ไม่พบ clinicId ของบัญชีนี้ กรุณาออกจากระบบแล้วเข้าใหม่');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('ลบโลโก้คลินิก'),
              content: const Text('ยืนยันการลบโลโก้ใช่หรือไม่'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('ลบโลโก้'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      setState(() => _removingLogo = true);

      final result = await ClinicLogoApi.removeLogo(clinicId: clinicId);

      final clinic = (result['clinic'] is Map<String, dynamic>)
          ? result['clinic'] as Map<String, dynamic>
          : <String, dynamic>{};

      final clinicName = (clinic['name'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _logoUrl = '';
        if (clinicName.isNotEmpty) {
          _clinicNameCtrl.text = clinicName;
        }
      });

      await _writeClinicScoped(clinicId, 'logoUrl', '');

      _snack('ลบโลโก้สำเร็จ');
    } catch (e) {
      _snack('ลบโลโก้ไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _removingLogo = false);
    }
  }

  Widget _buildLogoSection() {
    final clinicName = _clinicNameCtrl.text.trim();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ClinicLogoView(
            logoUrl: _logoUrl,
            clinicName: clinicName.isNotEmpty ? clinicName : 'คลินิก',
            size: 92,
          ),
          const SizedBox(height: 12),
          Text(
            _logoUrl.trim().isNotEmpty
                ? 'โลโก้นี้จะถูกใช้กับเอกสารและ PDF ที่สร้างใหม่'
                : 'ยังไม่มีโลโก้ ระบบจะแสดง fallback อัตโนมัติ',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _logoBusy ? null : _pickAndUploadLogo,
                  icon: _uploadingLogo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: Text(
                    _uploadingLogo ? 'กำลังอัปโหลด...' : 'อัปโหลดโลโก้',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _logoBusy || _logoUrl.trim().isEmpty ? null : _removeLogo,
                  icon: _removingLogo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _removingLogo ? 'กำลังลบ...' : 'ลบโลโก้',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveClinicProfile() async {
    if (_savingProfile) return;

    final clinicId = _currentClinicId.trim();
    if (clinicId.isEmpty) {
      _snack('ไม่พบ clinicId ของบัญชีนี้ กรุณาออกจากระบบแล้วเข้าใหม่');
      return;
    }

    final name = _clinicNameCtrl.text.trim();
    final branchName = _clinicBranchNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _clinicAddressCtrl.text.trim();
    final taxId = _clinicTaxIdCtrl.text.trim();
    final logoUrl = _logoUrl.trim();

    if (name.isEmpty) {
      _snack('กรุณากรอกชื่อคลินิก');
      return;
    }
    if (!_isValidPhoneOrEmpty(phone)) {
      _snack('เบอร์โทรไม่ถูกต้อง (ต้องเป็นตัวเลข 9–10 หลัก)');
      return;
    }

    setState(() => _savingProfile = true);

    try {
      await _writeClinicScoped(clinicId, 'name', name);
      await _writeClinicScoped(clinicId, 'branchName', branchName);
      await _writeClinicScoped(clinicId, 'address', address);
      await _writeClinicScoped(clinicId, 'phone', phone);
      await _writeClinicScoped(clinicId, 'taxId', taxId);
      await _writeClinicScoped(clinicId, 'logoUrl', logoUrl);

      final token = await _getTokenRobust();

      if (token.isEmpty) {
        _snack('บันทึกในเครื่องแล้ว');
        return;
      }

      final uri = Uri.parse('$_payrollBaseUrl/clinics/me/profile');
      final body = {
        'clinicName': name,
        'branchName': branchName,
        'clinicPhone': phone,
        'clinicAddress': address,
        'taxId': taxId,
        'logoUrl': logoUrl,
      };

      final resp = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (resp.statusCode >= 400) {
        String msg = 'อัปเดตข้อมูลคลินิกไม่สำเร็จ (${resp.statusCode})';
        try {
          final decoded = json.decode(resp.body);
          if (decoded is Map &&
              (decoded['message'] ?? '').toString().trim().isNotEmpty) {
            msg = (decoded['message']).toString();
          }
        } catch (_) {}
        _snack(msg);
        return;
      }

      await _loadClinicProfileFromBackend(clinicId);
      _snack('อัปเดตข้อมูลคลินิกแล้ว');
    } catch (e) {
      _snack('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingProfile = false);
    }
  }

  Future<void> _load() async {
    try {
      final sso = await SettingService.loadSsoPercent();
      final hasPin = await AuthService.hasPin();
      final clinicId = await _getClinicId();

      if (!mounted) return;
      setState(() {
        _ssoPercent = sso;
        _hasPin = hasPin;
        _currentClinicId = clinicId;
      });

      if (clinicId.isEmpty) {
        await _clearForm();
      } else {
        await _loadProfileFromPrefs(clinicId);
        await _loadClinicProfileFromBackend(clinicId);
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('โหลดตั้งค่าไม่สำเร็จ: $e');
    }
  }

  Future<void> _openOtSettings() async {
    try {
      final token = await _getTokenRobust();

      if (token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClinicOtSettingsScreen()),
      );
    } catch (_) {
      _snack('ไม่สามารถเปิดหน้าตั้งค่า OT ได้');
    }
  }

  Future<void> _saveSso() async {
    if (_savingSso) return;
    setState(() => _savingSso = true);

    try {
      await SettingService.saveSsoPercent(_ssoPercent);
      _snack('บันทึก SSO เรียบร้อยแล้ว');
    } catch (e) {
      _snack('บันทึก SSO ไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingSso = false);
    }
  }

  bool _isValidPin(String pin) {
    final p = pin.trim();
    if (p.length < 4 || p.length > 6) return false;
    return RegExp(r'^\d{4,6}$').hasMatch(p);
  }

  void _clearPinFields() {
    _newPinCtrl.clear();
    _confirmPinCtrl.clear();
  }

  Future<void> _setOrResetPin() async {
    if (_savingPin) return;

    final newPin = _newPinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();

    if (newPin != confirm) {
      _snack('PIN ไม่ตรงกัน');
      return;
    }

    if (!_isValidPin(newPin)) {
      _snack('PIN ต้องมี 4–6 หลัก');
      return;
    }

    try {
      setState(() => _savingPin = true);
      await AuthService.setPin(newPin);
      _clearPinFields();
      _snack('บันทึก PIN แล้ว');

      final hasPin = await AuthService.hasPin();
      if (!mounted) return;
      setState(() => _hasPin = hasPin);
    } catch (e) {
      _snack('บันทึก PIN ไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingPin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าผู้ดูแลคลินิก'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ข้อมูลคลินิก',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _clinicNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อคลินิก',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _clinicBranchNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'สาขา',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _clinicAddressCtrl,
                          textInputAction: TextInputAction.next,
                          minLines: 1,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ที่อยู่คลินิก',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'เบอร์ติดต่อคลินิก',
                            hintText: 'เช่น 0801234567',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _clinicTaxIdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'เลขผู้เสียภาษีคลินิก',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        _buildLogoSection(),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                _savingProfile ? null : _saveClinicProfile,
                            child: _savingProfile
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('บันทึกข้อมูลคลินิก'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text(
                      'ตั้งค่า OT',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'กำหนดเวลาเริ่มงาน เวลาเลิกงาน และตัวคูณ OT',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openOtSettings,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SSO (%)',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_ssoPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 18),
                        ),
                        Slider(
                          value: _ssoPercent,
                          min: 0,
                          max: 20,
                          divisions: 40,
                          onChanged: (v) => setState(() => _ssoPercent = v),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savingSso ? null : _saveSso,
                            child: _savingSso
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('บันทึก SSO'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasPin ? 'ตั้งหรือเปลี่ยน PIN' : 'ตั้ง PIN',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _newPinCtrl,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'PIN ใหม่ (4–6 หลัก)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _confirmPinCtrl,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'ยืนยัน PIN',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savingPin ? null : _setOrResetPin,
                            child: _savingPin
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('บันทึก PIN'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}