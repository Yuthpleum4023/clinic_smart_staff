import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

import 'package:clinic_smart_staff/widgets/apply_success_dialog.dart';

class HelperOpenNeedsScreen extends StatefulWidget {
  const HelperOpenNeedsScreen({super.key});

  @override
  State<HelperOpenNeedsScreen> createState() => _HelperOpenNeedsScreenState();
}

class _HelperOpenNeedsScreenState extends State<HelperOpenNeedsScreen> {
  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _items = [];

  final TextEditingController _phoneCtrl = TextEditingController();

  String _actingId = '';

  bool _disposed = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  @override
  void dispose() {
    _disposed = true;
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^\d]'), '');

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _getToken() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString('token');

    return token;
  }

  Uri _u(String path) {
    final base = ApiConfig.payrollBaseUrl;
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      final token = await _getToken();

      if (token == null) throw Exception();

      final res = await http
          .get(_u('/shift-needs/open'), headers: _headers(token))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(res.body);

      final list = List<Map<String, dynamic>>.from(data['items'] ?? []);

      _safeSetState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _err = 'โหลดรายการงานไม่สำเร็จ';
        _loading = false;
      });
    }
  }

  Future<String?> _askPhone() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        bool loading = false;

        return StatefulBuilder(builder: (ctx, setSt) {
          Future<void> submit() async {
            final p = _digitsOnly(_phoneCtrl.text);

            if (p.length < 9) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('กรุณากรอกเบอร์โทร')),
              );
              return;
            }

            setSt(() => loading = true);

            Navigator.pop(ctx, p);
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ยืนยันเบอร์โทร',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'เบอร์โทร',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: loading ? null : submit,
                  child: const Text('ยืนยัน'),
                )
              ],
            ),
          );
        });
      },
    );

    _phoneCtrl.clear();

    return result;
  }

  Future<void> _apply(String needId) async {
    if (_actingId.isNotEmpty) return;

    try {
      _safeSetState(() => _actingId = needId);

      final token = await _getToken();

      if (token == null) throw Exception();

      final phone = await _askPhone();

      if (phone == null) {
        _safeSetState(() => _actingId = '');
        return;
      }

      final res = await http.post(
        _u('/shift-needs/$needId/apply'),
        headers: _headers(token),
        body: jsonEncode({'phone': phone}),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await showApplySuccessDialog(context);

        await _load();

        return;
      }

      if (res.statusCode == 409) {
        _snack('สมัครแล้ว');
        return;
      }

      throw Exception();
    } catch (e) {
      _snack('สมัครงานไม่สำเร็จ');
    } finally {
      _safeSetState(() => _actingId = '');
    }
  }

  Widget _jobCard(Map<String, dynamic> m) {
    final id = _s(m['_id']);
    final title = _s(m['title']);
    final role = _s(m['role']);

    final applied = m['_applied'] == true;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.isEmpty ? 'งานว่าง' : title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            Text(role),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: applied ? null : () => _apply(id),
                icon: Icon(applied ? Icons.check : Icons.send),
                label: Text(applied ? 'สมัครแล้ว' : 'สมัครงานนี้'),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _skeletonCard() {
    return const Card(
      margin: EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: SizedBox(height: 90),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('งานว่างจากคลินิก'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: [
                  _skeletonCard(),
                  _skeletonCard(),
                  _skeletonCard(),
                ],
              )
            : _err.isNotEmpty
                ? Center(child: Text(_err))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _jobCard(_items[i]),
                  ),
      ),
    );
  }
}