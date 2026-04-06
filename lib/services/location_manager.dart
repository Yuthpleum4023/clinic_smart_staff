import 'dart:convert';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationManager {
  static bool hasUsableLocation(AppLocation? loc) {
    if (loc == null) return false;
    if (!loc.lat.isFinite || !loc.lng.isFinite) return false;
    if (loc.lat == 0 || loc.lng == 0) return false;
    if (loc.lat < -90 || loc.lat > 90) return false;
    if (loc.lng < -180 || loc.lng > 180) return false;
    return true;
  }

  static String _pickFirstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _buildLabel({
    required String district,
    required String province,
    required String address,
  }) {
    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;
    return '';
  }

  static double? _toNum(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static double? _sanitizeLat(double? v) {
    if (v == null) return null;
    if (!v.isFinite) return null;
    if (v < -90 || v > 90) return null;
    if (v == 0) return null;
    return v;
  }

  static double? _sanitizeLng(double? v) {
    if (v == null) return null;
    if (!v.isFinite) return null;
    if (v < -180 || v > 180) return null;
    if (v == 0) return null;
    return v;
  }

  static AppLocation _normalizeRemoteLocation(dynamic json) {
    final root =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};

    final policy = root['policy'] is Map
        ? Map<String, dynamic>.from(root['policy'])
        : root['data'] is Map
            ? Map<String, dynamic>.from(root['data'])
            : <String, dynamic>{};

    final user = root['user'] is Map
        ? Map<String, dynamic>.from(root['user'])
        : root['data'] is Map
            ? Map<String, dynamic>.from(root['data'])
            : root;

    final location = policy['location'] is Map
        ? Map<String, dynamic>.from(policy['location'])
        : policy['clinicLocation'] is Map
            ? Map<String, dynamic>.from(policy['clinicLocation'])
            : user['location'] is Map
                ? Map<String, dynamic>.from(user['location'])
                : root['location'] is Map
                    ? Map<String, dynamic>.from(root['location'])
                    : <String, dynamic>{};

    final lat = _sanitizeLat(
      _toNum(policy['clinicLat']) ??
          _toNum(policy['referenceLat']) ??
          _toNum(location['lat']) ??
          _toNum(location['latitude']) ??
          _toNum(user['lat']) ??
          _toNum(user['latitude']),
    );

    final lng = _sanitizeLng(
      _toNum(policy['clinicLng']) ??
          _toNum(policy['referenceLng']) ??
          _toNum(location['lng']) ??
          _toNum(location['longitude']) ??
          _toNum(user['lng']) ??
          _toNum(user['longitude']),
    );

    final district = _pickFirstNonEmpty([
      location['district'],
      location['amphoe'],
      policy['district'],
      policy['amphoe'],
      user['district'],
      user['amphoe'],
    ]);

    final province = _pickFirstNonEmpty([
      location['province'],
      location['changwat'],
      policy['province'],
      policy['changwat'],
      user['province'],
      user['changwat'],
    ]);

    final address = _pickFirstNonEmpty([
      location['address'],
      location['fullAddress'],
      policy['address'],
      policy['fullAddress'],
      user['address'],
      user['fullAddress'],
    ]);

    final label = _pickFirstNonEmpty([
      location['label'],
      location['locationLabel'],
      policy['label'],
      policy['locationLabel'],
      user['locationLabel'],
    ]);

    return AppLocation(
      lat: lat ?? 0,
      lng: lng ?? 0,
      district: district,
      province: province,
      address: address,
      label: label.isNotEmpty
          ? label
          : _buildLabel(
              district: district,
              province: province,
              address: address,
            ),
    );
  }

  static Future<AppLocation?> _fetchClinicBackendLocation() async {
    try {
      final token = await AuthStorage.getToken();
      if (token == null || token.trim().isEmpty) {
        print('[LocationManager] clinic backend location: missing token');
        return null;
      }

      final headers = {
        'Authorization': 'Bearer ${token.trim()}',
        'Accept': 'application/json',
      };

      final candidates = <String>[
        '${ApiConfig.payrollBaseUrl}/clinic-policy/me',
        '${ApiConfig.authBaseUrl}/users/me',
        '${ApiConfig.authBaseUrl}/users/me/location',
      ];

      for (final rawUrl in candidates) {
        try {
          print('[LocationManager] GET clinic source $rawUrl');
          final uri = Uri.parse(rawUrl);
          final res = await http.get(uri, headers: headers).timeout(
                const Duration(seconds: 12),
              );

          print(
            '[LocationManager] <- ${res.statusCode} GET clinic source '
            '$rawUrl body=${res.body}',
          );

          if (res.statusCode < 200 || res.statusCode >= 300) {
            continue;
          }

          final decoded = jsonDecode(res.body);
          final loc = _normalizeRemoteLocation(decoded);

          print(
            '[LocationManager] normalized clinic remote '
            'lat=${loc.lat} lng=${loc.lng} '
            'district=${loc.district} province=${loc.province} '
            'label=${loc.label}',
          );

          if (hasUsableLocation(loc)) {
            return loc;
          }

          print(
            '[LocationManager] clinic remote location unusable, continue next candidate',
          );
        } catch (e) {
          print(
            '[LocationManager] clinic backend candidate failed: '
            '$rawUrl error=$e',
          );
        }
      }
    } catch (e) {
      print('[LocationManager] _fetchClinicBackendLocation failed: $e');
    }

    return null;
  }

  static Future<AppLocation?> _fetchGeneralBackendLocation() async {
    try {
      final token = await AuthStorage.getToken();
      if (token == null || token.trim().isEmpty) {
        print('[LocationManager] backend location: missing token');
        return null;
      }

      final headers = {
        'Authorization': 'Bearer ${token.trim()}',
        'Accept': 'application/json',
      };

      final candidates = <String>[
        '${ApiConfig.authBaseUrl}/users/me',
        '${ApiConfig.authBaseUrl}/users/me/location',
      ];

      for (final rawUrl in candidates) {
        try {
          print('[LocationManager] GET $rawUrl');
          final uri = Uri.parse(rawUrl);
          final res = await http.get(uri, headers: headers).timeout(
                const Duration(seconds: 12),
              );

          print(
            '[LocationManager] <- ${res.statusCode} GET $rawUrl body=${res.body}',
          );

          if (res.statusCode < 200 || res.statusCode >= 300) {
            continue;
          }

          final decoded = jsonDecode(res.body);
          final loc = _normalizeRemoteLocation(decoded);

          print(
            '[LocationManager] normalized remote lat=${loc.lat} lng=${loc.lng} '
            'district=${loc.district} province=${loc.province} '
            'label=${loc.label}',
          );

          if (hasUsableLocation(loc)) {
            return loc;
          }

          print(
            '[LocationManager] remote location unusable, continue next candidate',
          );
        } catch (e) {
          print('[LocationManager] backend candidate failed: $rawUrl error=$e');
        }
      }
    } catch (e) {
      print('[LocationManager] _fetchGeneralBackendLocation failed: $e');
    }

    return null;
  }

  // --------------------------------------------------
  // Clinic location
  // --------------------------------------------------

  static Future<AppLocation?> loadClinicLocationSmart({
    bool allowGpsFallback = true,
  }) async {
    final local = await SettingService.loadClinicLocation();
    print(
      '[LocationManager] clinic local lat=${local?.lat} lng=${local?.lng} '
      'district=${local?.district} province=${local?.province}',
    );

    if (hasUsableLocation(local)) {
      print('[LocationManager] using clinic local');
      return local;
    }

    final remote = await _fetchClinicBackendLocation();
    print(
      '[LocationManager] clinic remote lat=${remote?.lat} lng=${remote?.lng} '
      'district=${remote?.district} province=${remote?.province}',
    );

    if (hasUsableLocation(remote)) {
      await SettingService.saveClinicLocation(
        lat: remote!.lat,
        lng: remote.lng,
        district: remote.district,
        province: remote.province,
        address: remote.address,
        label: remote.label,
      );
      print('[LocationManager] using clinic remote');
      return remote;
    }

    if (!allowGpsFallback) {
      print('[LocationManager] clinic location not found, gps fallback disabled');
      return null;
    }

    final gps = await _getGpsLocation();
    print('[LocationManager] clinic gps lat=${gps?.lat} lng=${gps?.lng}');
    return gps;
  }

  // --------------------------------------------------
  // Helper location
  // --------------------------------------------------

  static Future<AppLocation?> loadHelperLocationSmart({
    bool allowGpsFallback = true,
  }) async {
    final local = await SettingService.loadHelperLocation();
    print(
      '[LocationManager] helper local lat=${local?.lat} lng=${local?.lng} '
      'district=${local?.district} province=${local?.province}',
    );

    if (hasUsableLocation(local)) {
      print('[LocationManager] using helper local');
      return local;
    }

    final remote = await _fetchGeneralBackendLocation();
    print(
      '[LocationManager] helper remote lat=${remote?.lat} lng=${remote?.lng} '
      'district=${remote?.district} province=${remote?.province}',
    );

    if (hasUsableLocation(remote)) {
      await SettingService.saveHelperLocation(
        lat: remote!.lat,
        lng: remote.lng,
        district: remote.district,
        province: remote.province,
        address: remote.address,
        label: remote.label,
      );
      print('[LocationManager] using helper remote');
      return remote;
    }

    if (!allowGpsFallback) {
      print('[LocationManager] helper location not found, gps fallback disabled');
      return null;
    }

    final gps = await _getGpsLocation();
    print('[LocationManager] helper gps lat=${gps?.lat} lng=${gps?.lng}');
    return gps;
  }

  // --------------------------------------------------
  // Load any location (helper first, then clinic)
  // --------------------------------------------------

  static Future<AppLocation?> loadAnyLocation({
    bool allowGpsFallback = false,
  }) async {
    final helper = await loadHelperLocationSmart(
      allowGpsFallback: false,
    );
    if (hasUsableLocation(helper)) return helper;

    final clinic = await loadClinicLocationSmart(
      allowGpsFallback: false,
    );
    if (hasUsableLocation(clinic)) return clinic;

    if (!allowGpsFallback) return null;

    final gps = await _getGpsLocation();
    print('[LocationManager] any gps lat=${gps?.lat} lng=${gps?.lng}');
    return gps;
  }

  // --------------------------------------------------
  // Save clinic location
  // --------------------------------------------------

  static Future<void> saveClinicLocationSmart(
    AppLocation location,
  ) async {
    if (!hasUsableLocation(location)) {
      print(
        '[LocationManager] saveClinicLocationSmart skipped: unusable location',
      );
      return;
    }

    await SettingService.saveClinicLocation(
      lat: location.lat,
      lng: location.lng,
      district: location.district,
      province: location.province,
      address: location.address,
      label: location.label,
    );
  }

  // --------------------------------------------------
  // Save helper location
  // --------------------------------------------------

  static Future<void> saveHelperLocationSmart(
    AppLocation location,
  ) async {
    if (!hasUsableLocation(location)) {
      print(
        '[LocationManager] saveHelperLocationSmart skipped: unusable location',
      );
      return;
    }

    await SettingService.saveHelperLocation(
      lat: location.lat,
      lng: location.lng,
      district: location.district,
      province: location.province,
      address: location.address,
      label: location.label,
    );
  }

  // --------------------------------------------------
  // GPS
  // --------------------------------------------------

  static Future<AppLocation?> _getGpsLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        print('[LocationManager] GPS disabled');
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print('[LocationManager] GPS permission denied');
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final lat = _sanitizeLat(pos.latitude);
      final lng = _sanitizeLng(pos.longitude);

      print(
        '[LocationManager] GPS current raw lat=${pos.latitude} lng=${pos.longitude}',
      );

      if (lat == null || lng == null) {
        print('[LocationManager] GPS unusable after sanitize');
        return null;
      }

      return AppLocation(
        lat: lat,
        lng: lng,
      );
    } catch (e) {
      print('[LocationManager] _getGpsLocation failed: $e');
      return null;
    }
  }
}