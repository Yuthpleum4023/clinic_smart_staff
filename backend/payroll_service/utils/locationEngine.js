// payroll_service/utils/locationEngine.js

function s(v) {
  return (v ?? "").toString().trim();
}

function numOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return n;
}

function isValidLat(lat) {
  return typeof lat === "number" && Number.isFinite(lat) && lat >= -90 && lat <= 90;
}

function isValidLng(lng) {
  return typeof lng === "number" && Number.isFinite(lng) && lng >= -180 && lng <= 180;
}

function isValidLatLng(lat, lng) {
  return isValidLat(lat) && isValidLng(lng);
}

function haversineKm(lat1, lng1, lat2, lng2) {
  if (!isValidLatLng(lat1, lng1) || !isValidLatLng(lat2, lng2)) return null;

  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371; // km

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const dist = R * c;

  if (!Number.isFinite(dist)) return null;

  // กันค่าหลอนในบริบทใช้งานในไทย
  if (dist > 2000) return null;

  return dist;
}

function formatDistanceText(distanceKm) {
  const km = numOrNull(distanceKm);
  if (km === null || !Number.isFinite(km) || km <= 0) return "";

  if (km < 0.2) {
    return `${Math.round(km * 1000)} เมตร`;
  }

  if (km < 10) {
    return `${km.toFixed(1)} กม.`;
  }

  return `${Math.round(km)} กม.`;
}

function normalizeDistanceKm(distanceKm) {
  const km = numOrNull(distanceKm);
  if (km === null || !Number.isFinite(km) || km <= 0) return null;

  if (km < 10) return Number(km.toFixed(1));
  return Number(km.toFixed(0));
}

function buildDistancePayload(helperLocation, clinicLocation) {
  const helperLat = numOrNull(helperLocation?.lat);
  const helperLng = numOrNull(helperLocation?.lng);
  const clinicLat = numOrNull(clinicLocation?.lat);
  const clinicLng = numOrNull(clinicLocation?.lng);

  if (!isValidLatLng(helperLat, helperLng) || !isValidLatLng(clinicLat, clinicLng)) {
    return {
      distanceKm: null,
      distance_km: null,
      distanceText: "",
      distance_text: "",
    };
  }

  const rawKm = haversineKm(helperLat, helperLng, clinicLat, clinicLng);
  const distanceKm = normalizeDistanceKm(rawKm);
  const distanceText = formatDistanceText(rawKm);

  return {
    distanceKm,
    distance_km: distanceKm,
    distanceText,
    distance_text: distanceText,
  };
}

function pickBestDistanceFromRow(row = {}) {
  const distanceKm =
    numOrNull(row.distanceKm) ??
    numOrNull(row.distance_km) ??
    null;

  const distanceText =
    s(row.distanceText) ||
    s(row.distance_text) ||
    formatDistanceText(distanceKm);

  return {
    distanceKm,
    distance_km: distanceKm,
    distanceText,
    distance_text: distanceText,
  };
}

module.exports = {
  s,
  numOrNull,
  isValidLat,
  isValidLng,
  isValidLatLng,
  haversineKm,
  formatDistanceText,
  normalizeDistanceKm,
  buildDistancePayload,
  pickBestDistanceFromRow,
};