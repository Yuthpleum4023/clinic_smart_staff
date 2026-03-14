// lib/screens/clinic/clinic_admin_settings_service.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/services/settings_service.dart';
import 'package:clinic_smart_staff/services/auth_service.dart';
import 'package:clinic_smart_staff/screens/location_settings_screen.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_ot_settings_screen.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

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
  final _clinicAddressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _savingProfile = false;

  double _ssoPercent = 5.0;
  bool _savingSso = false;

  bool _hasPin = false;
  bool _savingPin = false;

  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  bool _savingLocation = false;

  String _currentClinicId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clinicNameCtrl.dispose();
    _clinicAddressCtrl.dispose();
    _phoneCtrl.dispose();
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
      _clinicAddressCtrl.text = '';
      _phoneCtrl.text = '';
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
    final addr = await _readClinicScoped(clinicId, 'address');
    final phone = await _readClinicScoped(clinicId, 'phone');

    if (!mounted) return;

    setState(() {
      _clinicNameCtrl.text = name;
      _clinicAddressCtrl.text = addr;
      _phoneCtrl.text = phone;
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

      final name = (c['name'] ?? '').toString().trim();
      final phone = (c['phone'] ?? '').toString().trim();
      final addr = (c['address'] ?? '').toString().trim();

      if (!mounted) return;

      setState(() {
        _clinicNameCtrl.text = name;
        _clinicAddressCtrl.text = addr;
        _phoneCtrl.text = phone;
      });

      await _writeClinicScoped(clinicId, 'name', name);
      await _writeClinicScoped(clinicId, 'address', addr);
      await _writeClinicScoped(clinicId, 'phone', phone);
    } catch (_) {}
  }

  bool _isValidPhoneOrEmpty(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return true;
    return RegExp(r'^\d{9,10}$').hasMatch(p);
  }

  Future<void> _saveClinicProfile() async {
    if (_savingProfile) return;

    final clinicId = _currentClinicId.trim();
    if (clinicId.isEmpty) {
      _snack('ไม่พบ clinicId ของบัญชีนี้ กรุณาออกจากระบบแล้วเข้าใหม่');
      return;
    }

    final name = _clinicNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _clinicAddressCtrl.text.trim();

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
      await _writeClinicScoped(clinicId, 'address', address);
      await _writeClinicScoped(clinicId, 'phone', phone);

      final token = await _getTokenRobust();

      if (token.isEmpty) {
        _snack('บันทึกในเครื่องแล้ว');
        return;
      }

      final uri = Uri.parse('$_payrollBaseUrl/clinics/me/location');
      final body = {
        'clinicName': name,
        'clinicPhone': phone,
        'clinicAddress': address,
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
        _snack('อัปเดตข้อมูลคลินิกไม่สำเร็จ (${resp.statusCode})');
        return;
      }

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
      final loc = await SettingService.loadClinicLocation();
      final clinicId = await _getClinicId();

      if (!mounted) return;
      setState(() {
        _ssoPercent = sso;
        _hasPin = hasPin;
        _lat = loc?.lat;
        _lng = loc?.lng;
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

  Future<void> _openMapPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocationSettingsScreen()),
    );

    try {
      final loc = await SettingService.loadClinicLocation();
      if (!mounted) return;
      setState(() {
        _lat = loc?.lat;
        _lng = loc?.lng;
      });
    } catch (_) {}
  }

  Future<void> _useCurrentLocation() async {
    if (_savingLocation) return;

    try {
      setState(() => _savingLocation = true);

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack('กรุณาเปิด Location Services หรือ GPS');
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _snack('ยังไม่ได้รับสิทธิ์เข้าถึงตำแหน่ง');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _snack('ปิดสิทธิ์ถาวร กรุณาเปิดใน Settings');
        await Geolocator.openAppSettings();
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        _snack('ยังไม่สามารถอ่านตำแหน่งปัจจุบันได้');
        return;
      }

      await SettingService.saveClinicLocation(
        lat: pos.latitude,
        lng: pos.longitude,
      );

      if (!mounted) return;
      setState(() {
        _lat = pos!.latitude;
        _lng = pos.longitude;
      });

      _snack('บันทึกตำแหน่งคลินิกแล้ว');
    } catch (e) {
      _snack('อ่านตำแหน่งไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingLocation = false);
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
    final hasLocation = _lat != null && _lng != null;

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
                          'ตำแหน่งคลินิก',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          !hasLocation
                              ? 'ยังไม่ได้ตั้งค่า'
                              : 'Lat: ${_lat!.toStringAsFixed(6)}\nLng: ${_lng!.toStringAsFixed(6)}',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _savingLocation
                                    ? null
                                    : _useCurrentLocation,
                                icon: const Icon(Icons.my_location),
                                label: _savingLocation
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('ใช้ตำแหน่งปัจจุบัน'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    _savingLocation ? null : _openMapPicker,
                                icon: const Icon(Icons.map_outlined),
                                label: Text(
                                  hasLocation
                                      ? 'แก้ไขบนแผนที่'
                                      : 'ตั้งค่าบนแผนที่',
                                ),
                              ),
                            ),
                          ],
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