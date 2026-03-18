// score_service/utils/locationEngine.js

function s(v) {
  return String(v || "").trim();
}

function numOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return n;
}

// --------------------------------------------------
// Validation
// --------------------------------------------------

function isValidLat(lat) {
  return typeof lat === "number" && Number.isFinite(lat) && lat >= -90 && lat <= 90;
}

function isValidLng(lng) {
  return typeof lng === "number" && Number.isFinite(lng) && lng >= -180 && lng <= 180;
}

function isValidLatLng(lat, lng) {
  return isValidLat(lat) && isValidLng(lng);
}

// --------------------------------------------------
// Math
// --------------------------------------------------

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

function haversineKm(lat1, lng1, lat2, lng2) {

  if (!isValidLatLng(lat1, lng1) || !isValidLatLng(lat2, lng2)) {
    return null;
  }

  const R = 6371;

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

  // กันค่าหลอน (เช่น coordinate ผิดประเทศ)
  if (dist > 2000) return null;

  return dist;
}

// --------------------------------------------------
// Normalize distance
// --------------------------------------------------

function normalizeDistanceKm(distanceKm) {

  const km = numOrNull(distanceKm);

  if (km === null) return null;

  if (km < 10) {
    return Number(km.toFixed(1));
  }

  return Number(km.toFixed(0));
}

// --------------------------------------------------
// Format distance
// --------------------------------------------------

function formatDistanceText(distanceKm) {

  const km = numOrNull(distanceKm);

  if (km === null) return "";

  if (km < 0.2) {
    return `${Math.round(km * 1000)} เมตร`;
  }

  if (km < 10) {
    return `${km.toFixed(1)} กม.`;
  }

  return `${Math.round(km)} กม.`;
}

// --------------------------------------------------
// Nearby label
// --------------------------------------------------

function isNearby(distanceKm, thresholdKm = 10) {

  const km = numOrNull(distanceKm);

  if (km === null) return false;

  return km <= thresholdKm;
}

// --------------------------------------------------
// Distance payload
// --------------------------------------------------

function buildDistancePayload(helperLocation, clinicLocation) {

  const helperLat = numOrNull(helperLocation?.lat);
  const helperLng = numOrNull(helperLocation?.lng);

  const clinicLat = numOrNull(clinicLocation?.lat);
  const clinicLng = numOrNull(clinicLocation?.lng);

  if (!isValidLatLng(helperLat, helperLng) || !isValidLatLng(clinicLat, clinicLng)) {
    return {
      distanceKm: null,
      distanceText: "",
      nearClinic: false,
    };
  }

  const rawKm = haversineKm(helperLat, helperLng, clinicLat, clinicLng);

  const distanceKm = normalizeDistanceKm(rawKm);

  const distanceText = formatDistanceText(rawKm);

  return {
    distanceKm,
    distanceText,
    nearClinic: isNearby(distanceKm),
  };
}

// --------------------------------------------------
// Marketplace sorting
// --------------------------------------------------

function compareByDistanceAndScore(a, b) {

  const aDist = numOrNull(a.distanceKm);
  const bDist = numOrNull(b.distanceKm);

  if (aDist !== null && bDist !== null) {
    if (aDist !== bDist) return aDist - bDist;
  }

  if (aDist !== null && bDist === null) return -1;
  if (aDist === null && bDist !== null) return 1;

  const aScore = numOrNull(a.trustScore) || 0;
  const bScore = numOrNull(b.trustScore) || 0;

  return bScore - aScore;
}

// --------------------------------------------------

module.exports = {
  s,
  numOrNull,

  isValidLat,
  isValidLng,
  isValidLatLng,

  haversineKm,
  normalizeDistanceKm,
  formatDistanceText,

  isNearby,
  buildDistancePayload,

  compareByDistanceAndScore,
};