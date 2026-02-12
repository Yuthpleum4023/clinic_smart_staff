// lib/screens/clinic/clinic_admin_settings_screen.dart
//
// ✅ FULL FILE (UPDATED)
// - ✅ SSO ยังใช้ SettingService เหมือนเดิม
// - ✅ PIN เปลี่ยนมาใช้ AuthService ชุดเดียว (ไม่ใช้ SettingService แล้ว)
// - ✅ บังคับตั้ง PIN ครั้งแรก: ถ้ายังไม่เคยตั้ง -> ไม่ต้องกรอก PIN เดิม
// - ✅ ถ้าเคยตั้งแล้ว -> ต้องกรอก PIN เดิมให้ถูกก่อนเปลี่ยน
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:clinic_payroll/services/settings_service.dart';
import 'package:clinic_payroll/services/auth_service.dart';

class ClinicAdminSettingsScreen extends StatefulWidget {
  const ClinicAdminSettingsScreen({super.key});

  @override
  State<ClinicAdminSettingsScreen> createState() =>
      _ClinicAdminSettingsScreenState();
}

class _ClinicAdminSettingsScreenState
    extends State<ClinicAdminSettingsScreen> {
  bool _loading = true;

  // SSO
  double _ssoPercent = 5.0;

  // PIN
  bool _hasPin = false; // ✅ เช็คว่าตั้ง PIN แล้วหรือยัง
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =========================
  // Load settings
  // =========================
  Future<void> _load() async {
    final sso = await SettingService.loadSsoPercent();
    final hasPin = await AuthService.hasPin();

    if (!mounted) return;
    setState(() {
      _ssoPercent = sso;
      _hasPin = hasPin;
      _loading = false;
    });
  }

  // =========================
  // Save SSO
  // =========================
  Future<void> _saveSso() async {
    await SettingService.saveSsoPercent(_ssoPercent);
    _snack('บันทึก SSO เรียบร้อยแล้ว');
  }

  // =========================
  // Change / Set PIN (AuthService)
  // =========================
  Future<void> _changePin() async {
    final oldPin = _oldPinCtrl.text.trim();
    final newPin = _newPinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();

    // ต้องกรอก PIN ใหม่ + ยืนยัน
    if (newPin.isEmpty || confirm.isEmpty) {
      _snack('กรอก PIN ใหม่และยืนยัน PIN ให้ครบ');
      return;
    }

    if (newPin != confirm) {
      _snack('PIN ใหม่ไม่ตรงกัน');
      return;
    }

    // ถ้ามี PIN เดิมแล้ว ต้อง verify ก่อน
    final hasPinNow = await AuthService.hasPin();
    if (hasPinNow) {
      if (oldPin.isEmpty) {
        _snack('กรุณากรอก PIN เดิม');
        return;
      }
      final ok = await AuthService.verifyPin(oldPin);
      if (!ok) {
        _snack('PIN เดิมไม่ถูกต้อง');
        return;
      }
    }

    // บันทึก PIN ใหม่
    final saved = await AuthService.setPin(newPin);
    if (!saved) {
      _snack('PIN ต้องเป็นตัวเลข 4–6 หลัก');
      return;
    }

    _oldPinCtrl.clear();
    _newPinCtrl.clear();
    _confirmPinCtrl.clear();

    if (!mounted) return;
    setState(() => _hasPin = true);

    _snack(hasPinNow ? 'เปลี่ยน PIN เรียบร้อยแล้ว' : 'ตั้ง PIN เรียบร้อยแล้ว');
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
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
                // SSO
                // =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SSO (%)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'เปอร์เซ็นต์หักประกันสังคม',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _ssoPercent,
                                min: 0,
                                max: 20,
                                divisions: 40,
                                label: _ssoPercent.toStringAsFixed(1),
                                onChanged: (v) {
                                  setState(() => _ssoPercent = v);
                                },
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                '${_ssoPercent.toStringAsFixed(1)}%',
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saveSso,
                            child: const Text('บันทึก SSO'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // PIN
                // =========================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasPin ? 'เปลี่ยน PIN คลินิก' : 'ตั้ง PIN คลินิก (ครั้งแรก)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _hasPin
                              ? 'ต้องกรอก PIN เดิมก่อนเพื่อเปลี่ยน'
                              : 'ยังไม่เคยตั้ง PIN — ตั้งใหม่ได้เลย',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 10),

                        // PIN เดิม: แสดงเฉพาะเมื่อเคยตั้งแล้ว
                        if (_hasPin) ...[
                          TextField(
                            controller: _oldPinCtrl,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                              labelText: 'PIN เดิม',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        TextField(
                          controller: _newPinCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'PIN ใหม่ (4–6 หลัก)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _confirmPinCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'ยืนยัน PIN ใหม่',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _changePin,
                            child: Text(_hasPin ? 'เปลี่ยน PIN' : 'ตั้ง PIN'),
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
