import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class EmployeeUserLinkSearchScreen extends StatefulWidget {
  final String initialQuery;

  const EmployeeUserLinkSearchScreen({
    super.key,
    this.initialQuery = '',
  });

  @override
  State<EmployeeUserLinkSearchScreen> createState() =>
      _EmployeeUserLinkSearchScreenState();
}

class _EmployeeUserLinkSearchScreenState
    extends State<EmployeeUserLinkSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _debounce;

  bool _loading = false;
  String _err = '';
  String _lastQuery = '';

  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery.trim();

    if (_searchCtrl.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchNow(force: true);
      });
    }

    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Uri _authUserUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.authBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return qs == null ? uri : uri.replace(queryParameters: qs);
  }

  Future<String?> _getTokenAny() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty && t != 'null') return t;
    } catch (_) {}

    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ];

    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Future<http.Response> _tryGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Map<String, dynamic> _decodeBodyMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractApiMessage(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    return (decoded['message'] ??
            decoded['error'] ??
            decoded['msg'] ??
            decoded['detail'] ??
            '')
        .toString()
        .trim();
  }

  List<Map<String, dynamic>> _extractItems(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (decoded is Map) {
      dynamic source = decoded;

      if (decoded['items'] is List) {
        source = decoded['items'];
      } else if (decoded['data'] is List) {
        source = decoded['data'];
      } else if (decoded['results'] is List) {
        source = decoded['results'];
      } else if (decoded['users'] is List) {
        source = decoded['users'];
      }

      if (source is List) {
        return source
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }

    return <Map<String, dynamic>>[];
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _normalizeRole(Map<String, dynamic> item) {
    return _s(item['role']).toLowerCase();
  }

  bool _isAdminLike(Map<String, dynamic> item) {
    final role = _normalizeRole(item);
    return role == 'admin' || role == 'clinic_admin' || role == 'clinic';
  }

  String _displayName(Map<String, dynamic> item) {
    final fullName = _s(item['fullName']);
    if (fullName.isNotEmpty) return fullName;

    final name = _s(item['name']);
    if (name.isNotEmpty) return name;

    final firstName = _s(item['firstName']);
    final lastName = _s(item['lastName']);
    final combined = '$firstName $lastName'.trim();
    if (combined.isNotEmpty) return combined;

    final phone = _s(item['phone']);
    if (phone.isNotEmpty) return phone;

    final email = _s(item['email']);
    if (email.isNotEmpty) return email;

    final userId = _s(item['userId'].toString().isNotEmpty
        ? item['userId']
        : (item['_id'].toString().isNotEmpty ? item['_id'] : item['id']));
    return userId.isNotEmpty ? userId : 'ผู้ใช้';
  }

  String _subtitle(Map<String, dynamic> item) {
    final pieces = <String>[];

    final phone = _s(item['phone']);
    final email = _s(item['email']);
    final role = _s(item['role']);
    final userId = _s(
      _s(item['userId']).isNotEmpty ? item['userId'] : (_s(item['_id']).isNotEmpty ? item['_id'] : item['id']),
    );

    if (phone.isNotEmpty) pieces.add(phone);
    if (email.isNotEmpty) pieces.add(email);
    if (role.isNotEmpty) pieces.add('role: $role');
    if (userId.isNotEmpty) pieces.add('userId: $userId');

    return pieces.join(' • ');
  }

  Future<void> _searchNow({bool force = false}) async {
    final q = _searchCtrl.text.trim();

    if (q.isEmpty) {
      setState(() {
        _items = <Map<String, dynamic>>[];
        _err = '';
        _lastQuery = '';
        _loading = false;
      });
      return;
    }

    if (!force && q == _lastQuery && _items.isNotEmpty) {
      return;
    }

    final token = await _getTokenAny();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = <Map<String, dynamic>>[];
        _err = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
      _lastQuery = q;
    });

    try {
      final uri = _authUserUri(
        '/api/users/search-for-link',
        qs: {'q': q, 'limit': '20'},
      );

      final res = await _tryGet(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 401) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _items = <Map<String, dynamic>>[];
          _err = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
        });
        return;
      }

      if (res.statusCode != 200) {
        final apiMsg = _extractApiMessage(res);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _items = <Map<String, dynamic>>[];
          _err = apiMsg.isNotEmpty ? apiMsg : 'ค้นหาไม่สำเร็จ กรุณาลองใหม่';
        });
        return;
      }

      final decoded = jsonDecode(res.body);
      final items = _extractItems(decoded)
          .where((e) => !_isAdminLike(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items;
        _err = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = <Map<String, dynamic>>[];
        _err = 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่';
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _searchNow();
    });
  }

  void _pickItem(Map<String, dynamic> item) {
    final userId = _s(item['userId']);
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รายการนี้ไม่มี User ID')),
      );
      return;
    }

    Navigator.pop<Map<String, dynamic>>(context, item);
  }

  Widget _buildSearchBox() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          onSubmitted: (_) => _searchNow(force: true),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'ค้นหาผู้ใช้',
            hintText: 'ค้นหาด้วยชื่อ เบอร์โทร หรืออีเมล',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchCtrl.text.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'ล้างข้อความ',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _items = <Map<String, dynamic>>[];
                        _err = '';
                        _lastQuery = '';
                      });
                    },
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'ค้นหาบัญชีผู้ใช้จากชื่อ เบอร์โทร หรืออีเมล แล้วเลือกบัญชีที่ต้องการนำมาเชื่อมกับพนักงาน',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_err.trim().isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ค้นหาไม่สำเร็จ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _err,
                    style: TextStyle(color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _searchNow(force: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_searchCtrl.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'กรอกชื่อ เบอร์โทร หรืออีเมล เพื่อค้นหาผู้ใช้',
            style: TextStyle(color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _lastQuery.isEmpty
                ? 'ไม่พบข้อมูล'
                : 'ไม่พบผู้ใช้ที่ตรงกับ "$_lastQuery"',
            style: TextStyle(color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _items[index];
        final isUnsafe = _isAdminLike(item);

        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.person_outline),
            ),
            title: Text(
              _displayName(item),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_subtitle(item)),
                if (isUnsafe)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'บัญชีผู้ดูแล ไม่สามารถใช้ผูกเป็นพนักงานได้',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: isUnsafe ? null : () => _pickItem(item),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ค้นหาผู้ใช้เพื่อเชื่อมบัญชี'),
        actions: [
          IconButton(
            tooltip: 'ค้นหา',
            icon: const Icon(Icons.search),
            onPressed: () => _searchNow(force: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildSearchBox(),
                const SizedBox(height: 8),
                _buildInfoCard(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}