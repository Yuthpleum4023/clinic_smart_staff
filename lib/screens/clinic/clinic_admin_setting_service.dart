// lib/screens/clinic/clinic_admin_settings_service.dart
//
// ✅ FULL FILE (PURPLE THEME + CLINIC PROFILE EDIT + LOCATION SETTINGS + OT SETTINGS NAV)
// - ✅ เพิ่มการ์ด "ตั้งค่า OT" -> นำทางไปหน้า ClinicOtSettingsScreen
// - ✅ FIX: ไม่เช็ค clinicId แล้ว (เพราะ OT policy ใช้ /clinic-policy/me)
// - ✅ ไม่ลบ function เดิมออก
//
// Notes:
// - clinicId: SharedPreferences key = 'clinicId'
// - token: SharedPreferences key = 'auth_token' (ถ้าโปรเจกต์ท่านต่าง ให้แก้ _tokenKey บรรทัดเดียว)
// - Payroll base: Render URL ของท่าน
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/services/settings_service.dart';
import 'package:clinic_smart_staff/services/auth_service.dart';

// ✅ หน้าแผนที่ (ปรับ path/ชื่อ class ให้ตรงของท่าน)
import 'package:clinic_smart_staff/screens/location_settings_screen.dart';

// ✅ OT Settings Screen (ท่านสร้างไฟล์นี้ไว้แล้ว / ถ้าชื่อไฟล์ต่าง ให้แก้ import ให้ตรง)
import 'package:clinic_smart_staff/screens/clinic/clinic_ot_settings_screen.dart';

class ClinicAdminSettingsScreen extends StatefulWidget {
  const ClinicAdminSettingsScreen({super.key});

  @override
  State<ClinicAdminSettingsScreen> createState() =>
      _ClinicAdminSettingsScreenState();
}

class _ClinicAdminSettingsScreenState extends State<ClinicAdminSettingsScreen> {
  bool _loading = true;

  // =========================
  // ✅ BACKEND CONFIG
  // =========================
  static const String _tokenKey = 'auth_token';
  static const String _clinicIdKey = 'clinicId';

  // ✅ Payroll service base (Render)
  static const String _payrollBaseUrl =
      'https://payroll-service-808t.onrender.com';

  // =========================
  // ✅ CLINIC PROFILE (name/address/phone)
  // =========================
  static const String _kClinicContactPhone = 'clinic_contact_phone';
  static const String _kClinicName = 'clinic_name';
  static const String _kClinicAddress = 'clinic_address';

  final _clinicNameCtrl = TextEditingController();
  final _clinicAddressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _savingProfile = false;

  // SSO
  double _ssoPercent = 5.0;
  bool _savingSso = false;

  // PIN
  bool _hasPin = false;
  bool _savingPin = false;

  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  // LOCATION
  double? _lat;
  double? _lng;
  bool _savingLocation = false;

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

  // =========================
  // ✅ PREFS helpers
  // =========================
  Future<String> _prefGet(String k) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(k) ?? '').trim();
  }

  Future<void> _prefSet(String k, String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(k, v.trim());
  }

  Future<void> _loadProfileFromPrefs() async {
    final name = await _prefGet(_kClinicName);
    final addr = await _prefGet(_kClinicAddress);
    final phone = await _prefGet(_kClinicContactPhone);

    if (!mounted) return;
    // เติมเฉพาะที่ว่าง เพื่อไม่ชนกับค่าจาก backend
    if (_clinicNameCtrl.text.trim().isEmpty && name.isNotEmpty) {
      _clinicNameCtrl.text = name;
    }
    if (_clinicAddressCtrl.text.trim().isEmpty && addr.isNotEmpty) {
      _clinicAddressCtrl.text = addr;
    }
    if (_phoneCtrl.text.trim().isEmpty && phone.isNotEmpty) {
      _phoneCtrl.text = phone;
    }
  }

  // =========================
  // ✅ BACKEND: load clinic profile
  // =========================
  Future<void> _loadClinicProfileFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString(_tokenKey) ?? '').trim();
    final clinicId = (prefs.getString(_clinicIdKey) ?? '').trim();

    if (token.isEmpty || clinicId.isEmpty) return;

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
        if (name.isNotEmpty) _clinicNameCtrl.text = name;
        if (addr.isNotEmpty) _clinicAddressCtrl.text = addr;
        if (phone.isNotEmpty) _phoneCtrl.text = phone;
      });

      // ✅ sync to prefs as fallback
      if (name.isNotEmpty) await _prefSet(_kClinicName, name);
      if (addr.isNotEmpty) await _prefSet(_kClinicAddress, addr);
      if (phone.isNotEmpty) await _prefSet(_kClinicContactPhone, phone);
    } catch (_) {
      // เงียบไว้: UI ยังใช้งานได้ด้วย prefs
    }
  }

  // =========================
  // ✅ BACKEND: save clinic profile (name/address/phone)
  // PATCH /clinics/me/location
  // body: { clinicName, clinicPhone, clinicAddress }  (ไม่ต้องส่ง lat/lng)
  // =========================
  bool _isValidPhoneOrEmpty(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return true;
    return RegExp(r'^\d{9,10}$').hasMatch(p);
  }

  Future<void> _saveClinicProfile() async {
    if (_savingProfile) return;

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
      // ✅ Save to prefs first (offline-safe)
      await _prefSet(_kClinicName, name);
      await _prefSet(_kClinicAddress, address);
      await _prefSet(_kClinicContactPhone, phone);

      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString(_tokenKey) ?? '').trim();

      // ไม่มี token ก็ไม่พัง: แค่ยังไม่ sync ขึ้น backend
      if (token.isEmpty) {
        _snack('บันทึกในเครื่องแล้ว ✅ (ยังไม่ sync เพราะไม่มี token)');
        return;
      }

      final uri = Uri.parse('$_payrollBaseUrl/clinics/me/location');
      final body = {
        'clinicName': name,
        'clinicPhone': phone,
        'clinicAddress': address,
        // ไม่ส่ง clinicLat/clinicLng เพื่อเน้น “แก้โปรไฟล์อย่างเดียว”
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
        _snack('อัปเดตชื่อคลินิกไม่สำเร็จ (${resp.statusCode})');
        return;
      }

      _snack('อัปเดตข้อมูลคลินิกแล้ว ✅');
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

      if (!mounted) return;
      setState(() {
        _ssoPercent = sso;
        _hasPin = hasPin;
        _lat = loc?.lat;
        _lng = loc?.lng;
      });

      // ✅ Profile: load prefs -> then backend (ถ้ามี token/clinicId)
      await _loadProfileFromPrefs();
      await _loadClinicProfileFromBackend();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('โหลดตั้งค่าไม่สำเร็จ: $e');
    }
  }

  // =========================
  // ✅ OPEN MAP SCREEN
  // =========================
  Future<void> _openMapPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocationSettingsScreen()),
    );

    // กลับมาแล้ว reload location เพื่ออัปเดต UI
    try {
      final loc = await SettingService.loadClinicLocation();
      if (!mounted) return;
      setState(() {
        _lat = loc?.lat;
        _lng = loc?.lng;
      });
    } catch (_) {}
  }

  // =========================
  // ✅ LOCATION (CURRENT GPS)
  // =========================
  Future<void> _useCurrentLocation() async {
    if (_savingLocation) return;

    try {
      setState(() => _savingLocation = true);

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack('กรุณาเปิด Location Services / GPS');
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _snack('ผู้ใช้ปฏิเสธ permission location');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _snack('ปิดสิทธิ์ถาวร กรุณาเปิดใน Settings');
        await Geolocator.openAppSettings();
        return;
      }

      // ✅ กันค้าง: ใส่ timeLimit + fallback lastKnown
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
        _snack(
          'ยังอ่านตำแหน่งไม่ได้\n'
          '- ถ้าเป็น iOS Simulator: Features > Location เลือก Apple/Custom\n'
          '- ถ้าเป็นเครื่องจริง: เปิด Location + ให้สิทธิ์ While in use',
        );
        return;
      }

      await SettingService.saveClinicLocation(
        lat: pos.latitude,
        lng: pos.longitude,
      );

      if (!mounted) return;
      setState(() {
        _lat = pos!.latitude;
        _lng = pos!.longitude;
      });

      _snack('บันทึกตำแหน่งคลินิกแล้ว ✅');
    } catch (e) {
      _snack('อ่านตำแหน่งไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingLocation = false);
    }
  }

  // =========================
  // ✅ OPEN OT SETTINGS (FIXED)
  // - ไม่ต้องใช้ clinicId แล้ว เพราะ backend ใช้ /clinic-policy/me
  // =========================
  Future<void> _openOtSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString(_tokenKey) ?? '').trim();

      if (token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClinicOtSettingsScreen()),
      );
    } catch (_) {
      _snack('ไม่สามารถเปิดหน้า OT ได้');
    }
  }

  // =========================
  // SSO
  // =========================
  Future<void> _saveSso() async {
    if (_savingSso) return;
    setState(() => _savingSso = true);

    try {
      await SettingService.saveSsoPercent(_ssoPercent);
      _snack('บันทึก SSO เรียบร้อยแล้ว ✅');
    } catch (e) {
      _snack('บันทึก SSO ไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingSso = false);
    }
  }

  // =========================
  // PIN
  // =========================
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
      _snack('PIN ต้อง 4–6 หลัก');
      return;
    }

    try {
      setState(() => _savingPin = true);
      await AuthService.setPin(newPin);
      _clearPinFields();
      _snack('บันทึก PIN แล้ว ✅');

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
        title: const Text('Clinic Admin Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // =========================
                // ✅ CLINIC PROFILE (NEW)
                // =========================
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

                        // Clinic Name
                        TextField(
                          controller: _clinicNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อคลินิก',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Clinic Address
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

                        // Clinic Phone
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
                                        strokeWidth: 2),
                                  )
                                : const Text('บันทึกข้อมูลคลินิก'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // ✅ OT SETTINGS NAV
                // =========================
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text(
                      'ตั้งค่า OT',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'กำหนดเวลาเริ่มงาน/เลิกงาน และตัวคูณ OT ของคลินิก',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openOtSettings,
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // ✅ LOCATION
                // =========================
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
                                            strokeWidth: 2),
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
                                label: Text(hasLocation
                                    ? 'แก้ไขบนแผนที่'
                                    : 'ตั้งบนแผนที่'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // ✅ SSO
                // =========================
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
                                        strokeWidth: 2),
                                  )
                                : const Text('บันทึก SSO'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // ✅ PIN
                // =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasPin ? 'ตั้ง/เปลี่ยน PIN' : 'ตั้ง PIN (ยังไม่มี)',
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
                                        strokeWidth: 2),
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