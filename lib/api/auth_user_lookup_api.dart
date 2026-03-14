// lib/api/auth_user_lookup_api.dart
//
// ✅ FULL FILE (COPY-PASTE READY)
// ✅ PURPOSE:
// - lookup / search user จาก auth_user_service
// - ใช้ ApiClient + ApiConfig.authBaseUrl
// - รองรับหลาย endpoint candidate เพื่อให้ใช้ได้แม้ backend mount path ไม่เหมือนกัน
//
// ✅ INCLUDED:
// - getMe()
// - searchUsers()
// - searchHelpers()
// - searchStaff()
// - getUserById()
//
// ✅ ROBUST:
// - parse response ได้หลายรูปแบบ: rows / items / users / data / list
// - map field name ให้ยืดหยุ่น: id / userId / _id / firstName / lastName / name / fullName
// - ถ้า endpoint แรกไม่เจอ จะลอง endpoint ถัดไปอัตโนมัติ
//
// ✅ UPDATED:
// - searchStaff() ใช้ role=employee ให้ตรงกับ backend auth จริง
// - fallback ยังรองรับ role=staff เผื่อ legacy data
//
// NOTE:
// - ไฟล์นี้ “อ่านข้อมูล” อย่างเดียว
// - เหมาะกับใช้ใน AddEmployeeScreen / EditEmployeeScreen
//

import 'api_client.dart';
import 'api_config.dart';

class AuthLookupUser {
  final String userId;
  final String firstName;
  final String lastName;
  final String fullName;
  final String role;
  final String phone;
  final String email;
  final Map<String, dynamic> raw;

  const AuthLookupUser({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.role,
    required this.phone,
    required this.email,
    required this.raw,
  });

  bool get isValid => userId.trim().isNotEmpty;

  factory AuthLookupUser.fromMap(Map<String, dynamic> map) {
    String s(dynamic v) => (v ?? '').toString().trim();

    String pickFirstNonEmpty(List<dynamic> values) {
      for (final v in values) {
        final t = s(v);
        if (t.isNotEmpty) return t;
      }
      return '';
    }

    final firstName = pickFirstNonEmpty([
      map['firstName'],
      map['first_name'],
      map['givenName'],
      map['given_name'],
    ]);

    final lastName = pickFirstNonEmpty([
      map['lastName'],
      map['last_name'],
      map['familyName'],
      map['family_name'],
    ]);

    final fullNameRaw = pickFirstNonEmpty([
      map['fullName'],
      map['full_name'],
      map['name'],
      map['displayName'],
      map['display_name'],
    ]);

    final computedFullName = [
      firstName,
      lastName,
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    return AuthLookupUser(
      userId: pickFirstNonEmpty([
        map['userId'],
        map['userID'],
        map['user_id'],
        map['id'],
        map['_id'],
      ]),
      firstName: firstName,
      lastName: lastName,
      fullName: fullNameRaw.isNotEmpty ? fullNameRaw : computedFullName,
      role: pickFirstNonEmpty([
        map['role'],
        map['activeRole'],
        map['userRole'],
      ]),
      phone: pickFirstNonEmpty([
        map['phone'],
        map['phoneNumber'],
        map['mobile'],
      ]),
      email: pickFirstNonEmpty([
        map['email'],
        map['mail'],
      ]),
      raw: Map<String, dynamic>.from(map),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'role': role,
      'phone': phone,
      'email': email,
      'raw': raw,
    };
  }
}

class AuthUserLookupApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.authBaseUrl);

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static bool _is404Like(Object e) {
    final msg = e.toString();
    return msg.contains('API 404') ||
        msg.contains('404') ||
        msg.contains('NOT_FOUND');
  }

  static bool _isSoftRetryError(Object e) {
    final msg = e.toString();
    return _is404Like(e) ||
        msg.contains('API 400') ||
        msg.contains('API 405');
  }

  static List<Map<String, dynamic>> _extractMapList(dynamic decoded) {
    dynamic data = decoded;

    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] != null) data = decoded['data'];
    }

    List rawList = [];

    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      if (data['rows'] is List) {
        rawList = data['rows'];
      } else if (data['items'] is List) {
        rawList = data['items'];
      } else if (data['users'] is List) {
        rawList = data['users'];
      } else if (data['list'] is List) {
        rawList = data['list'];
      } else if (data['results'] is List) {
        rawList = data['results'];
      } else if (data['employees'] is List) {
        rawList = data['employees'];
      } else if (data['helpers'] is List) {
        rawList = data['helpers'];
      } else if (data['staff'] is List) {
        rawList = data['staff'];
      } else if (data['data'] is List) {
        rawList = data['data'];
      }
    } else if (decoded is Map) {
      if (decoded['rows'] is List) {
        rawList = decoded['rows'];
      } else if (decoded['items'] is List) {
        rawList = decoded['items'];
      } else if (decoded['users'] is List) {
        rawList = decoded['users'];
      } else if (decoded['list'] is List) {
        rawList = decoded['list'];
      } else if (decoded['results'] is List) {
        rawList = decoded['results'];
      } else if (decoded['employees'] is List) {
        rawList = decoded['employees'];
      } else if (decoded['helpers'] is List) {
        rawList = decoded['helpers'];
      } else if (decoded['staff'] is List) {
        rawList = decoded['staff'];
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(
          item.map((k, v) => MapEntry(k.toString(), v)),
        ));
      }
    }
    return out;
  }

  static List<AuthLookupUser> _parseUsers(dynamic decoded) {
    final rows = _extractMapList(decoded);
    return rows
        .map(AuthLookupUser.fromMap)
        .where((e) => e.userId.trim().isNotEmpty)
        .toList();
  }

  static AuthLookupUser? _parseSingleUser(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded['user'] is Map) {
        return AuthLookupUser.fromMap(
          Map<String, dynamic>.from(decoded['user']),
        );
      }
      if (decoded['data'] is Map) {
        return AuthLookupUser.fromMap(
          Map<String, dynamic>.from(decoded['data']),
        );
      }

      final maybeDirect = AuthLookupUser.fromMap(decoded);
      if (maybeDirect.userId.isNotEmpty) return maybeDirect;
    }

    if (decoded is Map) {
      final direct = Map<String, dynamic>.from(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
      final maybeDirect = AuthLookupUser.fromMap(direct);
      if (maybeDirect.userId.isNotEmpty) return maybeDirect;
    }

    final list = _parseUsers(decoded);
    return list.isNotEmpty ? list.first : null;
  }

  static Future<Map<String, dynamic>> _tryGetMany(
    List<String> candidates, {
    Map<String, String>? query,
  }) async {
    Object? lastError;

    for (final path in candidates) {
      try {
        return await _client.get(path, auth: true, query: query);
      } catch (e) {
        lastError = e;
        if (!_isSoftRetryError(e)) {
          rethrow;
        }
      }
    }

    throw Exception(lastError?.toString() ?? 'GET_LOOKUP_FAILED');
  }

  static Future<Map<String, dynamic>> _tryPostMany(
    List<String> candidates, {
    Map<String, dynamic>? body,
  }) async {
    Object? lastError;

    for (final path in candidates) {
      try {
        return await _client.post(path, auth: true, body: body ?? {});
      } catch (e) {
        lastError = e;
        if (!_isSoftRetryError(e)) {
          rethrow;
        }
      }
    }

    throw Exception(lastError?.toString() ?? 'POST_LOOKUP_FAILED');
  }

  /// ✅ ดึง user ปัจจุบันจาก token
  static Future<AuthLookupUser?> getMe() async {
    final res = await _tryGetMany([
      '/me',
      '/api/me',
      '/users/me',
      '/api/users/me',
      '/auth/me',
      '/api/auth/me',
    ]);

    return _parseSingleUser(res);
  }

  /// ✅ ดึง user ตาม userId
  static Future<AuthLookupUser?> getUserById(String userId) async {
    final uid = _s(userId);
    if (uid.isEmpty) return null;

    final res = await _tryGetMany([
      '/users/$uid',
      '/api/users/$uid',
      '/user/$uid',
      '/api/user/$uid',
    ]);

    return _parseSingleUser(res);
  }

  /// ✅ search user ทั่วไป
  static Future<List<AuthLookupUser>> searchUsers({
    String query = '',
    int limit = 20,
    String role = '',
  }) async {
    final q = _s(query);
    final r = _s(role);
    final lim = limit <= 0 ? 20 : limit;

    final getQueries = <Map<String, String>>[
      {
        if (q.isNotEmpty) 'q': q,
        'limit': '$lim',
        if (r.isNotEmpty) 'role': r,
      },
      {
        if (q.isNotEmpty) 'search': q,
        'limit': '$lim',
        if (r.isNotEmpty) 'role': r,
      },
      {
        if (q.isNotEmpty) 'keyword': q,
        'limit': '$lim',
        if (r.isNotEmpty) 'role': r,
      },
    ];

    final getCandidates = <String>[
      '/users/search',
      '/api/users/search',
      '/users',
      '/api/users',
      '/auth/users/search',
      '/api/auth/users/search',
    ];

    Object? lastErr;

    for (final qMap in getQueries) {
      try {
        final res = await _tryGetMany(getCandidates, query: qMap);
        final users = _parseUsers(res);
        if (users.isNotEmpty || q.isEmpty) {
          return users;
        }
      } catch (e) {
        lastErr = e;
      }
    }

    try {
      final res = await _tryPostMany(
        [
          '/users/search',
          '/api/users/search',
          '/auth/users/search',
          '/api/auth/users/search',
        ],
        body: {
          if (q.isNotEmpty) 'q': q,
          if (q.isNotEmpty) 'search': q,
          'limit': lim,
          if (r.isNotEmpty) 'role': r,
        },
      );
      return _parseUsers(res);
    } catch (e) {
      lastErr = e;
    }

    if (lastErr != null) {
      throw Exception(lastErr.toString());
    }

    return [];
  }

  /// ✅ search helper โดยบังคับ role helper
  static Future<List<AuthLookupUser>> searchHelpers({
    String query = '',
    int limit = 20,
  }) async {
    final users = await searchUsers(
      query: query,
      limit: limit,
      role: 'helper',
    );

    if (users.isNotEmpty) return users;

    final fallback = await searchUsers(query: query, limit: limit);
    return fallback
        .where((u) => u.role.toLowerCase().trim() == 'helper')
        .toList();
  }

  /// ✅ search staff / employee
  /// backend auth จริงใช้ role = employee
  static Future<List<AuthLookupUser>> searchStaff({
    String query = '',
    int limit = 20,
  }) async {
    final users = await searchUsers(
      query: query,
      limit: limit,
      role: 'employee',
    );

    if (users.isNotEmpty) return users;

    final fallback = await searchUsers(query: query, limit: limit);
    return fallback.where((u) {
      final role = u.role.toLowerCase().trim();
      return role == 'employee' || role == 'staff';
    }).toList();
  }
}