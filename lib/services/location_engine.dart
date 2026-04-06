import 'dart:math';

import 'package:clinic_smart_staff/services/settings_service.dart';

class LocationEngine {
  static String _s(dynamic v) => (v ?? '').toString().trim();

  static double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  // --------------------------------------------------
  // Safety validation
  // --------------------------------------------------

  static bool _validLat(double? v) {
    if (v == null) return false;
    if (!v.isFinite) return false;
    if (v < -90 || v > 90) return false;
    if (v == 0) return false;
    return true;
  }

  static bool _validLng(double? v) {
    if (v == null) return false;
    if (!v.isFinite) return false;
    if (v < -180 || v > 180) return false;
    if (v == 0) return false;
    return true;
  }

  static bool hasUsableLocation(AppLocation? loc) {
    if (loc == null) return false;
    return _validLat(loc.lat) && _validLng(loc.lng);
  }

  // --------------------------------------------------
  // Helper location label
  // --------------------------------------------------

  static String resolveLocationLabelForItem(Map<String, dynamic> item) {
    final explicit = _s(
      item['locationLabel'] ??
          item['helperLocationLabel'] ??
          item['profileLocationLabel'],
    );

    if (explicit.isNotEmpty) return explicit;

    final district = _s(item['district'] ?? item['helperDistrict']);
    final province = _s(item['province'] ?? item['helperProvince']);
    final address = _s(item['address'] ?? item['helperAddress']);

    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }

    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;

    return '';
  }

  // --------------------------------------------------
  // Clinic location label
  // --------------------------------------------------

  static String resolveClinicLocationLabel(Map<String, dynamic> item) {
    final clinic = item['clinic'];
    final clinicLocation = item['clinicLocation'];
    final clinicLocation2 = item['clinic_location'];

    final explicit = _s(
      item['clinicLocationLabel'] ??
          item['locationLabel'] ??
          (clinic is Map ? clinic['locationLabel'] : null) ??
          (clinic is Map ? clinic['clinicLocationLabel'] : null) ??
          (clinicLocation is Map ? clinicLocation['label'] : null) ??
          (clinicLocation2 is Map ? clinicLocation2['label'] : null),
    );

    if (explicit.isNotEmpty) return explicit;

    final district = _s(
      item['clinicDistrict'] ??
          (clinic is Map ? clinic['district'] : null) ??
          (clinicLocation is Map ? clinicLocation['district'] : null) ??
          (clinicLocation2 is Map ? clinicLocation2['district'] : null),
    );

    final province = _s(
      item['clinicProvince'] ??
          (clinic is Map ? clinic['province'] : null) ??
          (clinicLocation is Map ? clinicLocation['province'] : null) ??
          (clinicLocation2 is Map ? clinicLocation2['province'] : null),
    );

    final address = _s(
      item['clinicAddress'] ??
          item['clinic_address'] ??
          (clinic is Map ? clinic['address'] : null),
    );

    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }

    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;

    return '';
  }

  // --------------------------------------------------
  // Extract helper location
  // --------------------------------------------------

  static AppLocation? extractHelperLocation(Map<String, dynamic> item) {
    final lat = _toNum(
      item['lat'] ??
          item['latitude'] ??
          item['helperLat'] ??
          item['helperLatitude'],
    );

    final lng = _toNum(
      item['lng'] ??
          item['longitude'] ??
          item['helperLng'] ??
          item['helperLongitude'],
    );

    if (!_validLat(lat) || !_validLng(lng)) return null;

    return AppLocation(
      lat: lat!,
      lng: lng!,
      district: _s(item['district'] ?? item['helperDistrict']),
      province: _s(item['province'] ?? item['helperProvince']),
      address: _s(item['address'] ?? item['helperAddress']),
      label: resolveLocationLabelForItem(item),
    );
  }

  static AppLocation? extractLocationFromItem(Map<String, dynamic> item) {
    return extractHelperLocation(item);
  }

  // --------------------------------------------------
  // Extract clinic location
  // --------------------------------------------------

  static AppLocation? extractClinicLocation(Map<String, dynamic> item) {
    final clinic = item['clinic'];
    final clinicLocation = item['clinicLocation'];
    final clinicLocation2 = item['clinic_location'];

    final lat = _toNum(
      item['clinicLat'] ??
          item['clinic_lat'] ??
          (clinic is Map ? clinic['lat'] : null) ??
          (clinic is Map ? clinic['clinicLat'] : null) ??
          (clinicLocation is Map ? clinicLocation['lat'] : null) ??
          (clinicLocation2 is Map ? clinicLocation2['lat'] : null) ??
          (clinic is Map && clinic['location'] is Map
              ? clinic['location']['lat']
              : null),
    );

    final lng = _toNum(
      item['clinicLng'] ??
          item['clinic_lng'] ??
          (clinic is Map ? clinic['lng'] : null) ??
          (clinic is Map ? clinic['clinicLng'] : null) ??
          (clinicLocation is Map ? clinicLocation['lng'] : null) ??
          (clinicLocation2 is Map ? clinicLocation2['lng'] : null) ??
          (clinic is Map && clinic['location'] is Map
              ? clinic['location']['lng']
              : null),
    );

    if (!_validLat(lat) || !_validLng(lng)) return null;

    return AppLocation(
      lat: lat!,
      lng: lng!,
      district: _s(
        item['clinicDistrict'] ??
            (clinic is Map ? clinic['district'] : null),
      ),
      province: _s(
        item['clinicProvince'] ??
            (clinic is Map ? clinic['province'] : null),
      ),
      address: _s(
        item['clinicAddress'] ??
            item['clinic_address'] ??
            (clinic is Map ? clinic['address'] : null),
      ),
      label: resolveClinicLocationLabel(item),
    );
  }

  // --------------------------------------------------
  // Distance calculation (Haversine)
  // --------------------------------------------------

  static double? distanceKmBetween(
    AppLocation? a,
    AppLocation? b,
  ) {
    if (!hasUsableLocation(a) || !hasUsableLocation(b)) return null;

    const r = 6371.0;

    final dLat = _degToRad(b!.lat - a!.lat);
    final dLng = _degToRad(b.lng - a.lng);

    final lat1 = _degToRad(a.lat);
    final lat2 = _degToRad(b.lat);

    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);

    final c = 2 * atan2(sqrt(x), sqrt(1 - x));

    final dist = r * c;

    if (!dist.isFinite) return null;

    // กันค่าหลอน
    if (dist > 1500) return null;

    return dist;
  }

  static double _degToRad(double v) => v * pi / 180;

  // --------------------------------------------------
  // Format distance
  // --------------------------------------------------

  static String formatDistanceKm(double? km) {
    if (km == null) return '';

    if (km < 0.2) {
      return '${(km * 1000).round()} เมตร';
    }

    if (km < 10) {
      return '${km.toStringAsFixed(1)} กม.';
    }

    return '${km.round()} กม.';
  }

  // --------------------------------------------------
  // Nearby label
  // --------------------------------------------------

  static String nearbyLabelFromDistance(double? km) {
    if (km == null) return '';

    if (km <= 10) return 'ใกล้คุณ';

    return '';
  }

  // --------------------------------------------------
  // Helper marketplace distance
  // --------------------------------------------------

  static double? resolveMarketplaceDistanceKm(
    Map<String, dynamic> item,
    AppLocation? clinicLocation,
  ) {
    final helperLoc = extractHelperLocation(item);
    return distanceKmBetween(clinicLocation, helperLoc);
  }

  static String resolveMarketplaceDistanceText(
    Map<String, dynamic> item,
    AppLocation? clinicLocation,
  ) {
    final explicit = _s(item['distanceText'] ?? item['distance_text']);
    if (explicit.isNotEmpty) return explicit;

    return formatDistanceKm(
      resolveMarketplaceDistanceKm(item, clinicLocation),
    );
  }

  static String resolveMarketplaceNearbyLabel(
    Map<String, dynamic> item,
    AppLocation? clinicLocation,
  ) {
    return nearbyLabelFromDistance(
      resolveMarketplaceDistanceKm(item, clinicLocation),
    );
  }

  // --------------------------------------------------
  // Clinic / shift distance
  // --------------------------------------------------

  static double? resolveDistanceKmForItem(
    Map<String, dynamic> item,
    AppLocation? helperLocation,
  ) {
    final clinicLoc = extractClinicLocation(item);
    return distanceKmBetween(helperLocation, clinicLoc);
  }

  static String resolveDistanceTextForItem(
    Map<String, dynamic> item,
    AppLocation? helperLocation,
  ) {
    final explicit = _s(item['distanceText'] ?? item['distance_text']);
    if (explicit.isNotEmpty) return explicit;

    final km = resolveDistanceKmForItem(item, helperLocation);
    return formatDistanceKm(km);
  }

  static String resolveNearbyLabelForItem(
    Map<String, dynamic> item,
    AppLocation? helperLocation,
  ) {
    final km = resolveDistanceKmForItem(item, helperLocation);
    return nearbyLabelFromDistance(km);
  }

  // --------------------------------------------------
  // Marketplace sorting
  // --------------------------------------------------

  static int compareMarketplaceItems(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    AppLocation? clinicLocation,
  ) {
    final aDist = resolveMarketplaceDistanceKm(a, clinicLocation);
    final bDist = resolveMarketplaceDistanceKm(b, clinicLocation);

    if (aDist != null && bDist != null) {
      final byDistance = aDist.compareTo(bDist);
      if (byDistance != 0) return byDistance;
    } else if (aDist != null && bDist == null) {
      return -1;
    } else if (aDist == null && bDist != null) {
      return 1;
    }

    final aScore = _toNum(a['trustScore']) ?? 0;
    final bScore = _toNum(b['trustScore']) ?? 0;

    return bScore.compareTo(aScore);
  }
}