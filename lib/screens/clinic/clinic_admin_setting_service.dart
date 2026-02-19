// lib/screens/clinic/clinic_admin_settings_screen.dart
//
// ✅ FULL FILE (PURPLE THEME + LOCATION SETTINGS ADDED) — clinic_smart_staff package
// - ✅ ไม่ hardcode สีฟ้า (ให้ Theme ใน main.dart คุมโทนม่วงทั้งระบบ)
// - ✅ เพิ่มการ์ด "ตำแหน่งคลินิก" + 2 ปุ่ม: GPS + Map picker
// - ✅ มี CONTACT PHONE + SSO + PIN
//
// ✅ FIX "แดง clinic contact phone":
// - ไม่เรียก SettingService.loadClinicContactPhone/saveClinicContactPhone (เพราะของท่านยังไม่มี)
// - ใช้ SharedPreferences key: clinic_contact_phone แทน (อยู่ในไฟล์นี้เลย)
//
// NOTE:
// - ถ้า import LocationSettingsScreen path ไม่ตรง ให้ปรับ 1 บรรทัดนั้น
//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/services/settings_service.dart';
import 'package:clinic_smart_staff/services/auth_service.dart';

// ✅ หน้าแผนที่ (ปรับ path/ชื่อ class ให้ตรงของท่าน)
import 'package:clinic_smart_staff/screens/location_settings_screen.dart';

class ClinicAdminSettingsScreen extends StatefulWidget {
  const ClinicAdminSettingsScreen({super.key});

  @override
  State<ClinicAdminSettingsScreen> createState() =>
      _ClinicAdminSettingsScreenState();
}

class _ClinicAdminSettingsScreenState extends State<ClinicAdminSettingsScreen> {
  bool _loading = true;

  // SSO
  double _ssoPercent = 5.0;
  bool _savingSso = false;

  // PIN
  bool _hasPin = false;
  bool _savingPin = false;

  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  // ✅ CONTACT PHONE
  static const String _kClinicContactPhone = 'clinic_contact_phone';
  final _phoneCtrl = TextEditingController();
  bool _savingPhone = false;

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
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =========================
  // ✅ CONTACT PHONE (PREFS)
  // =========================
  Future<String> _loadClinicContactPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kClinicContactPhone) ?? '').trim();
  }

  Future<void> _saveClinicContactPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClinicContactPhone, phone.trim());
  }

  Future<void> _load() async {
    try {
      final sso = await SettingService.loadSsoPercent();
      final hasPin = await AuthService.hasPin();
      final loc = await SettingService.loadClinicLocation();

      // ✅ phone from prefs (กันแดง)
      final phone = await _loadClinicContactPhone();

      if (!mounted) return;
      setState(() {
        _ssoPercent = sso;
        _hasPin = hasPin;

        _lat = loc?.lat;
        _lng = loc?.lng;

        _phoneCtrl.text = phone;

        _loading = false;
      });
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
  // ✅ CONTACT PHONE (SAVE)
  // =========================
  Future<void> _savePhone() async {
    if (_savingPhone) return;

    final phone = _phoneCtrl.text.trim();

    if (phone.isEmpty) {
      _snack('กรุณากรอกเบอร์ติดต่อ');
      return;
    }

    if (!RegExp(r'^\d{9,10}$').hasMatch(phone)) {
      _snack('เบอร์โทรไม่ถูกต้อง');
      return;
    }

    try {
      setState(() => _savingPhone = true);

      // ✅ save to prefs (กันแดง)
      await _saveClinicContactPhone(phone);

      _snack('บันทึกเบอร์ติดต่อแล้ว ✅');
    } catch (e) {
      _snack('บันทึกเบอร์ไม่สำเร็จ: $e');
    } finally {
      if (!mounted) return;
      setState(() => _savingPhone = false);
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
        // ✅ ไม่ hardcode สีฟ้า ให้ Theme คุม
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                                  hasLocation ? 'แก้ไขบนแผนที่' : 'ตั้งบนแผนที่',
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

                // =========================
                // ✅ CONTACT PHONE
                // =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'เบอร์ติดต่อคลินิก',
                          style: TextStyle(fontWeight: FontWeight.w900),
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
                            hintText: 'เช่น 0801234567',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savingPhone ? null : _savePhone,
                            child: _savingPhone
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('บันทึกเบอร์'),
                          ),
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
