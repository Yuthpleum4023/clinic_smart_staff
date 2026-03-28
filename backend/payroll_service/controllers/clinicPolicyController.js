// backend/payroll_service/controllers/clinicPolicyController.js
const ClinicPolicy = require("../models/ClinicPolicy");

const ATTENDANCE_TIMEZONE = "Asia/Bangkok";
const ENFORCED_REQUIRE_LOCATION = true;
const ENFORCED_GEO_RADIUS_METERS = 200;

function normStr(v) {
  return String(v || "").trim();
}

function toNum(v, fallback) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function isHHmm(v) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(String(v || "").trim());
}

function normalizeStringArray(value, fallback = []) {
  if (Array.isArray(value)) {
    const arr = value.map((x) => normStr(x)).filter(Boolean);
    return arr.length ? arr : fallback;
  }

  if (typeof value === "string") {
    const one = normStr(value);
    return one ? [one] : fallback;
  }

  if (value && typeof value === "object") {
    const arr = Object.values(value)
      .map((x) => normStr(x))
      .filter(Boolean);
    return arr.length ? arr : fallback;
  }

  return fallback;
}

function normalizeApprovalRoles(value, fallback = ["clinic_admin"]) {
  const arr = normalizeStringArray(value, fallback)
    .map((x) => {
      const s = normStr(x).toLowerCase();
      if (!s) return "";
      if (s === "clinicadmin") return "clinic_admin";
      return s;
    })
    .filter(Boolean);

  return arr.length ? arr : fallback;
}

function normalizeOtRule(v) {
  const s = normStr(v).toUpperCase();
  const allowed = ["AFTER_DAILY_HOURS", "AFTER_SHIFT_END", "AFTER_CLOCK_TIME"];
  return allowed.includes(s) ? s : "AFTER_CLOCK_TIME";
}

function normalizeOtRounding(v) {
  const s = normStr(v).toUpperCase();
  const allowed = ["NONE", "15MIN", "30MIN", "HOUR"];
  return allowed.includes(s) ? s : "15MIN";
}

const ALLOWED_FEATURE_KEYS = [
  "manualAttendance",
  "fingerprintAttendance",
  "autoOtCalculation",
  "otApprovalWorkflow",
  "attendanceApproval",
  "payrollLock",
  "policyHumanReadable",
];

const WEEK_DAYS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
];

function sanitizeFeatures(value, fallback = {}) {
  const safe = {
    manualAttendance: true,
    fingerprintAttendance: true,
    autoOtCalculation: true,
    otApprovalWorkflow: true,
    attendanceApproval: true,
    payrollLock: true,
    policyHumanReadable: true,
    ...(fallback || {}),
  };

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return safe;
  }

  for (const key of Object.keys(value)) {
    if (!ALLOWED_FEATURE_KEYS.includes(key)) continue;
    safe[key] = !!value[key];
  }

  return safe;
}

function defaultDaySchedule(start = "09:00", end = "18:00", enabled = true) {
  return {
    enabled: !!enabled,
    start,
    end,
  };
}

function defaultWeeklySchedule() {
  return {
    monday: defaultDaySchedule("09:00", "18:00", true),
    tuesday: defaultDaySchedule("09:00", "18:00", true),
    wednesday: defaultDaySchedule("09:00", "18:00", true),
    thursday: defaultDaySchedule("09:00", "18:00", true),
    friday: defaultDaySchedule("09:00", "18:00", true),
    saturday: defaultDaySchedule("09:00", "13:00", false),
    sunday: defaultDaySchedule("09:00", "13:00", false),
  };
}

function normalizeDaySchedule(raw, fallback = defaultDaySchedule()) {
  const src = raw && typeof raw === "object" ? raw : {};
  const start = normStr(src.start || fallback.start || "09:00") || "09:00";
  const end = normStr(src.end || fallback.end || "18:00") || "18:00";

  return {
    enabled: src.enabled === undefined ? !!fallback.enabled : !!src.enabled,
    start,
    end,
  };
}

function normalizeWeeklySchedule(value, fallback = defaultWeeklySchedule()) {
  const src =
    value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const out = {};

  for (const day of WEEK_DAYS) {
    out[day] = normalizeDaySchedule(
      src[day],
      fallback[day] || defaultDaySchedule()
    );
  }

  return out;
}

// ==============================
// NEW: location helpers
// ==============================

function sanitizeLat(v, fallback = null) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  if (n < -90 || n > 90) return fallback;
  if (n === 0) return fallback;
  return n;
}

function sanitizeLng(v, fallback = null) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  if (n < -180 || n > 180) return fallback;
  if (n === 0) return fallback;
  return n;
}

function normalizeLocationShape(raw = {}, fallback = {}) {
  const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const fb =
    fallback && typeof fallback === "object" && !Array.isArray(fallback)
      ? fallback
      : {};

  const lat = sanitizeLat(src.lat ?? src.latitude, sanitizeLat(fb.lat, null));
  const lng = sanitizeLng(src.lng ?? src.longitude, sanitizeLng(fb.lng, null));

  return {
    lat,
    lng,
    district: normStr(src.district || fb.district || ""),
    province: normStr(src.province || fb.province || ""),
    address: normStr(src.address || src.fullAddress || fb.address || ""),
    label: normStr(src.label || src.locationLabel || fb.label || ""),
  };
}

function hasUsableLocation(loc) {
  if (!loc || typeof loc !== "object") return false;
  return Number.isFinite(loc.lat) && Number.isFinite(loc.lng);
}

function defaultClinicLocation() {
  return {
    lat: null,
    lng: null,
    district: "",
    province: "",
    address: "",
    label: "",
  };
}

function buildReferenceLocationFields(raw = {}, fallback = {}) {
  const base = normalizeLocationShape(raw.location || raw.clinicLocation || raw, {
    ...(fallback.location || fallback.clinicLocation || {}),
    lat:
      fallback.clinicLat ??
      fallback.referenceLat ??
      fallback.location?.lat ??
      fallback.clinicLocation?.lat ??
      null,
    lng:
      fallback.clinicLng ??
      fallback.referenceLng ??
      fallback.location?.lng ??
      fallback.clinicLocation?.lng ??
      null,
  });

  const directLat = sanitizeLat(
    raw.clinicLat ?? raw.referenceLat,
    sanitizeLat(fallback.clinicLat ?? fallback.referenceLat, base.lat)
  );
  const directLng = sanitizeLng(
    raw.clinicLng ?? raw.referenceLng,
    sanitizeLng(fallback.clinicLng ?? fallback.referenceLng, base.lng)
  );

  const effectiveLat = Number.isFinite(directLat) ? directLat : base.lat;
  const effectiveLng = Number.isFinite(directLng) ? directLng : base.lng;

  const normalizedBase = {
    ...base,
    lat: Number.isFinite(effectiveLat) ? effectiveLat : null,
    lng: Number.isFinite(effectiveLng) ? effectiveLng : null,
  };

  return {
    clinicLat: normalizedBase.lat,
    clinicLng: normalizedBase.lng,
    referenceLat: normalizedBase.lat,
    referenceLng: normalizedBase.lng,
    location: { ...normalizedBase },
    clinicLocation: { ...normalizedBase },
  };
}

function validateLocationFields(p) {
  const clinicLat = sanitizeLat(p?.clinicLat, null);
  const clinicLng = sanitizeLng(p?.clinicLng, null);
  const referenceLat = sanitizeLat(p?.referenceLat, null);
  const referenceLng = sanitizeLng(p?.referenceLng, null);
  const locationLat = sanitizeLat(p?.location?.lat, null);
  const locationLng = sanitizeLng(p?.location?.lng, null);
  const clinicLocationLat = sanitizeLat(p?.clinicLocation?.lat, null);
  const clinicLocationLng = sanitizeLng(p?.clinicLocation?.lng, null);

  const pairs = [
    [clinicLat, clinicLng],
    [referenceLat, referenceLng],
    [locationLat, locationLng],
    [clinicLocationLat, clinicLocationLng],
  ];

  for (const [lat, lng] of pairs) {
    const hasLat = Number.isFinite(lat);
    const hasLng = Number.isFinite(lng);
    if (hasLat !== hasLng) {
      return "clinic reference location is incomplete";
    }
  }

  return null;
}

function defaultPolicy(clinicId, updatedByUserId = "") {
  const weeklySchedule = defaultWeeklySchedule();
  const ref = buildReferenceLocationFields({}, {});

  return {
    clinicId,
    timezone: ATTENDANCE_TIMEZONE,

    requireBiometric: true,
    requireLocation: ENFORCED_REQUIRE_LOCATION,
    geoRadiusMeters: ENFORCED_GEO_RADIUS_METERS,

    // NEW: clinic reference location
    clinicLat: ref.clinicLat,
    clinicLng: ref.clinicLng,
    referenceLat: ref.referenceLat,
    referenceLng: ref.referenceLng,
    location: ref.location,
    clinicLocation: ref.clinicLocation,

    graceLateMinutes: 10,

    otRule: "AFTER_CLOCK_TIME",
    regularHoursPerDay: 8,

    otClockTime: "18:00",

    fullTimeOtClockTime: "18:00",
    partTimeOtClockTime: "18:00",

    otWindowStart: "18:00",
    otWindowEnd: "21:00",

    otStartAfterMinutes: 0,

    otRounding: "15MIN",
    otMultiplier: 1.5,
    holidayMultiplier: 2.0,
    weekendAllDayOT: false,

    employeeOnlyOt: true,
    requireOtApproval: true,
    realTimeAttendanceOnly: true,
    manualAttendanceRequireApproval: true,
    manualReasonRequired: true,
    lockAfterPayrollClose: true,

    attendanceApprovalRoles: ["clinic_admin"],
    otApprovalRoles: ["clinic_admin"],

    shiftStart: "09:00",
    shiftEnd: "18:00",
    cutoffTime: "03:00",
    minMinutesBeforeCheckout: 1,
    requireReasonForEarlyCheckIn: true,
    requireReasonForEarlyCheckOut: true,
    forgotCheckoutManualOnly: true,
    blockNewCheckInIfPreviousOpen: true,

    weeklySchedule,

    features: {
      manualAttendance: true,
      fingerprintAttendance: true,
      autoOtCalculation: true,
      otApprovalWorkflow: true,
      attendanceApproval: true,
      payrollLock: true,
      policyHumanReadable: true,
    },

    version: 1,
    updatedBy: updatedByUserId || "",
  };
}

function mergeFeatures(currentFeatures = {}, incomingFeatures = {}) {
  return sanitizeFeatures(incomingFeatures, {
    manualAttendance: true,
    fingerprintAttendance: true,
    autoOtCalculation: true,
    otApprovalWorkflow: true,
    attendanceApproval: true,
    payrollLock: true,
    policyHumanReadable: true,
    ...(currentFeatures || {}),
  });
}

function normalizePolicyShape(raw, clinicId, updatedByUserId = "") {
  const defaults = defaultPolicy(clinicId, updatedByUserId);
  const src = raw && typeof raw === "object" ? raw : {};
  const ref = buildReferenceLocationFields(src, defaults);

  return {
    ...defaults,
    ...src,

    clinicId: normStr(src.clinicId || clinicId),
    timezone: ATTENDANCE_TIMEZONE,

    requireBiometric:
      src.requireBiometric === undefined
        ? defaults.requireBiometric
        : !!src.requireBiometric,

    requireLocation: ENFORCED_REQUIRE_LOCATION,

    geoRadiusMeters: ENFORCED_GEO_RADIUS_METERS,

    // NEW: normalized clinic reference location
    clinicLat: ref.clinicLat,
    clinicLng: ref.clinicLng,
    referenceLat: ref.referenceLat,
    referenceLng: ref.referenceLng,
    location: ref.location,
    clinicLocation: ref.clinicLocation,

    graceLateMinutes: toNum(src.graceLateMinutes, defaults.graceLateMinutes),

    otRule: normalizeOtRule(src.otRule || defaults.otRule),
    regularHoursPerDay: toNum(
      src.regularHoursPerDay,
      defaults.regularHoursPerDay
    ),

    otClockTime: normStr(src.otClockTime || defaults.otClockTime) || "18:00",

    fullTimeOtClockTime:
      normStr(
        src.fullTimeOtClockTime ||
          src.otClockTime ||
          defaults.fullTimeOtClockTime
      ) || "18:00",

    partTimeOtClockTime:
      normStr(
        src.partTimeOtClockTime ||
          src.otClockTime ||
          defaults.partTimeOtClockTime
      ) || "18:00",

    otWindowStart:
      normStr(src.otWindowStart || defaults.otWindowStart) || "18:00",

    otWindowEnd:
      normStr(src.otWindowEnd || defaults.otWindowEnd) || "21:00",

    otStartAfterMinutes: toNum(
      src.otStartAfterMinutes,
      defaults.otStartAfterMinutes
    ),

    otRounding: normalizeOtRounding(src.otRounding || defaults.otRounding),
    otMultiplier: toNum(src.otMultiplier, defaults.otMultiplier),
    holidayMultiplier: toNum(src.holidayMultiplier, defaults.holidayMultiplier),

    weekendAllDayOT:
      src.weekendAllDayOT === undefined
        ? defaults.weekendAllDayOT
        : !!src.weekendAllDayOT,

    employeeOnlyOt:
      src.employeeOnlyOt === undefined
        ? defaults.employeeOnlyOt
        : !!src.employeeOnlyOt,

    requireOtApproval:
      src.requireOtApproval === undefined
        ? defaults.requireOtApproval
        : !!src.requireOtApproval,

    realTimeAttendanceOnly:
      src.realTimeAttendanceOnly === undefined
        ? defaults.realTimeAttendanceOnly
        : !!src.realTimeAttendanceOnly,

    manualAttendanceRequireApproval:
      src.manualAttendanceRequireApproval === undefined
        ? defaults.manualAttendanceRequireApproval
        : !!src.manualAttendanceRequireApproval,

    manualReasonRequired:
      src.manualReasonRequired === undefined
        ? defaults.manualReasonRequired
        : !!src.manualReasonRequired,

    lockAfterPayrollClose:
      src.lockAfterPayrollClose === undefined
        ? defaults.lockAfterPayrollClose
        : !!src.lockAfterPayrollClose,

    attendanceApprovalRoles: normalizeApprovalRoles(
      src.attendanceApprovalRoles,
      defaults.attendanceApprovalRoles
    ),

    otApprovalRoles: normalizeApprovalRoles(
      src.otApprovalRoles,
      defaults.otApprovalRoles
    ),

    shiftStart: normStr(src.shiftStart || defaults.shiftStart) || "09:00",
    shiftEnd: normStr(src.shiftEnd || defaults.shiftEnd) || "18:00",
    cutoffTime: normStr(src.cutoffTime || defaults.cutoffTime) || "03:00",

    minMinutesBeforeCheckout: toNum(
      src.minMinutesBeforeCheckout,
      defaults.minMinutesBeforeCheckout
    ),

    requireReasonForEarlyCheckIn:
      src.requireReasonForEarlyCheckIn === undefined
        ? defaults.requireReasonForEarlyCheckIn
        : !!src.requireReasonForEarlyCheckIn,

    requireReasonForEarlyCheckOut:
      src.requireReasonForEarlyCheckOut === undefined
        ? defaults.requireReasonForEarlyCheckOut
        : !!src.requireReasonForEarlyCheckOut,

    forgotCheckoutManualOnly:
      src.forgotCheckoutManualOnly === undefined
        ? defaults.forgotCheckoutManualOnly
        : !!src.forgotCheckoutManualOnly,

    blockNewCheckInIfPreviousOpen:
      src.blockNewCheckInIfPreviousOpen === undefined
        ? defaults.blockNewCheckInIfPreviousOpen
        : !!src.blockNewCheckInIfPreviousOpen,

    weeklySchedule: normalizeWeeklySchedule(
      src.weeklySchedule,
      defaults.weeklySchedule
    ),

    features: mergeFeatures(defaults.features, src.features),

    version: Math.max(1, toNum(src.version, defaults.version)),
    updatedBy: normStr(src.updatedBy || updatedByUserId || ""),
  };
}

function applyPolicyToDoc(doc, normalized, updatedByUserId = "") {
  doc.clinicId = normStr(normalized.clinicId);
  doc.timezone = ATTENDANCE_TIMEZONE;

  doc.requireBiometric = !!normalized.requireBiometric;
  doc.requireLocation = ENFORCED_REQUIRE_LOCATION;
  doc.geoRadiusMeters = ENFORCED_GEO_RADIUS_METERS;

  // NEW: clinic reference location
  const ref = buildReferenceLocationFields(normalized, normalized);
  doc.clinicLat = ref.clinicLat;
  doc.clinicLng = ref.clinicLng;
  doc.referenceLat = ref.referenceLat;
  doc.referenceLng = ref.referenceLng;
  doc.location = ref.location;
  doc.clinicLocation = ref.clinicLocation;

  doc.graceLateMinutes = Number(normalized.graceLateMinutes);

  doc.otRule = normalizeOtRule(normalized.otRule);
  doc.regularHoursPerDay = Number(normalized.regularHoursPerDay);

  doc.otClockTime = normStr(normalized.otClockTime);
  doc.fullTimeOtClockTime = normStr(normalized.fullTimeOtClockTime);
  doc.partTimeOtClockTime = normStr(normalized.partTimeOtClockTime);

  doc.otWindowStart = normStr(normalized.otWindowStart);
  doc.otWindowEnd = normStr(normalized.otWindowEnd);

  doc.otStartAfterMinutes = Number(normalized.otStartAfterMinutes);

  doc.otRounding = normalizeOtRounding(normalized.otRounding);
  doc.otMultiplier = Number(normalized.otMultiplier);
  doc.holidayMultiplier = Number(normalized.holidayMultiplier);
  doc.weekendAllDayOT = !!normalized.weekendAllDayOT;

  doc.employeeOnlyOt = !!normalized.employeeOnlyOt;
  doc.requireOtApproval = !!normalized.requireOtApproval;
  doc.realTimeAttendanceOnly = !!normalized.realTimeAttendanceOnly;
  doc.manualAttendanceRequireApproval =
    !!normalized.manualAttendanceRequireApproval;
  doc.manualReasonRequired = !!normalized.manualReasonRequired;
  doc.lockAfterPayrollClose = !!normalized.lockAfterPayrollClose;

  doc.attendanceApprovalRoles = normalizeApprovalRoles(
    normalized.attendanceApprovalRoles,
    ["clinic_admin"]
  );
  doc.otApprovalRoles = normalizeApprovalRoles(
    normalized.otApprovalRoles,
    ["clinic_admin"]
  );

  doc.shiftStart = normStr(normalized.shiftStart) || "09:00";
  doc.shiftEnd = normStr(normalized.shiftEnd) || "18:00";
  doc.cutoffTime = normStr(normalized.cutoffTime) || "03:00";
  doc.minMinutesBeforeCheckout = Number(normalized.minMinutesBeforeCheckout);
  doc.requireReasonForEarlyCheckIn = !!normalized.requireReasonForEarlyCheckIn;
  doc.requireReasonForEarlyCheckOut = !!normalized.requireReasonForEarlyCheckOut;
  doc.forgotCheckoutManualOnly = !!normalized.forgotCheckoutManualOnly;
  doc.blockNewCheckInIfPreviousOpen =
    !!normalized.blockNewCheckInIfPreviousOpen;

  doc.weeklySchedule = normalizeWeeklySchedule(
    normalized.weeklySchedule,
    defaultWeeklySchedule()
  );

  doc.features = mergeFeatures(doc.features || {}, normalized.features || {});
  doc.updatedBy = normStr(updatedByUserId || normalized.updatedBy || "");
}

function validateDaySchedule(dayName, day) {
  if (!day || typeof day !== "object" || Array.isArray(day)) {
    return `${dayName} must be an object`;
  }

  if (day.start && !isHHmm(day.start)) {
    return `${dayName}.start must be HH:mm`;
  }

  if (day.end && !isHHmm(day.end)) {
    return `${dayName}.end must be HH:mm`;
  }

  if (day.enabled && day.start && day.end && day.start === day.end) {
    return `${dayName}.start and ${dayName}.end must not be the same`;
  }

  return null;
}

function validatePolicy(p) {
  const otRule = normalizeOtRule(p.otRule);

  const allowedOtRules = [
    "AFTER_DAILY_HOURS",
    "AFTER_SHIFT_END",
    "AFTER_CLOCK_TIME",
  ];
  if (otRule && !allowedOtRules.includes(otRule)) return "Invalid otRule";

  const otRounding = normalizeOtRounding(p.otRounding);
  const allowedRounding = ["NONE", "15MIN", "30MIN", "HOUR"];
  if (otRounding && !allowedRounding.includes(otRounding)) {
    return "Invalid otRounding";
  }

  if (p.requireLocation !== ENFORCED_REQUIRE_LOCATION) {
    return `requireLocation must be ${String(ENFORCED_REQUIRE_LOCATION)}`;
  }

  const radius = toNum(p.geoRadiusMeters, NaN);
  if (!Number.isFinite(radius) || radius !== ENFORCED_GEO_RADIUS_METERS) {
    return `geoRadiusMeters must be ${ENFORCED_GEO_RADIUS_METERS}`;
  }

  const locErr = validateLocationFields(p);
  if (locErr) return locErr;

  const grace = toNum(p.graceLateMinutes, NaN);
  if (!Number.isFinite(grace) || grace < 0 || grace > 180) {
    return "graceLateMinutes must be 0..180";
  }

  const otStartAfter = toNum(p.otStartAfterMinutes, NaN);
  if (!Number.isFinite(otStartAfter) || otStartAfter < 0 || otStartAfter > 180) {
    return "otStartAfterMinutes must be 0..180";
  }

  const otM = toNum(p.otMultiplier, NaN);
  if (!Number.isFinite(otM) || otM <= 0) return "otMultiplier must be > 0";

  const holM = toNum(p.holidayMultiplier, NaN);
  if (!Number.isFinite(holM) || holM <= 0) {
    return "holidayMultiplier must be > 0";
  }

  if (otRule === "AFTER_DAILY_HOURS") {
    const h = toNum(p.regularHoursPerDay, NaN);
    if (!Number.isFinite(h) || h <= 0 || h > 24) {
      return "regularHoursPerDay must be 1..24";
    }
  }

  if (otRule === "AFTER_CLOCK_TIME") {
    if (p.fullTimeOtClockTime && !isHHmm(p.fullTimeOtClockTime)) {
      return "fullTimeOtClockTime must be HH:mm";
    }

    if (p.partTimeOtClockTime && !isHHmm(p.partTimeOtClockTime)) {
      return "partTimeOtClockTime must be HH:mm";
    }

    if (!p.fullTimeOtClockTime && !p.partTimeOtClockTime) {
      if (!isHHmm(p.otClockTime)) return "otClockTime must be HH:mm";
    }
  }

  if (p.otWindowStart && !isHHmm(p.otWindowStart)) {
    return "otWindowStart must be HH:mm";
  }

  if (p.otWindowEnd && !isHHmm(p.otWindowEnd)) {
    return "otWindowEnd must be HH:mm";
  }

  if (p.shiftStart && !isHHmm(p.shiftStart)) {
    return "shiftStart must be HH:mm";
  }

  if (p.shiftEnd && !isHHmm(p.shiftEnd)) {
    return "shiftEnd must be HH:mm";
  }

  if (p.cutoffTime && !isHHmm(p.cutoffTime)) {
    return "cutoffTime must be HH:mm";
  }

  const minCheckout = toNum(p.minMinutesBeforeCheckout, NaN);
  if (!Number.isFinite(minCheckout) || minCheckout < 1 || minCheckout > 1440) {
    return "minMinutesBeforeCheckout must be 1..1440";
  }

  if (
    p.weeklySchedule !== undefined &&
    (typeof p.weeklySchedule !== "object" || Array.isArray(p.weeklySchedule))
  ) {
    return "weeklySchedule must be an object";
  }

  const normalizedWeekly = normalizeWeeklySchedule(
    p.weeklySchedule,
    defaultWeeklySchedule()
  );

  for (const day of WEEK_DAYS) {
    const err = validateDaySchedule(day, normalizedWeekly[day]);
    if (err) return err;
  }

  const attendanceRoles = normalizeApprovalRoles(
    p.attendanceApprovalRoles,
    ["clinic_admin"]
  );
  const otRoles = normalizeApprovalRoles(p.otApprovalRoles, ["clinic_admin"]);

  if (!attendanceRoles.length) {
    return "attendanceApprovalRoles must contain at least 1 role";
  }

  if (!otRoles.length) {
    return "otApprovalRoles must contain at least 1 role";
  }

  if (
    p.features &&
    (typeof p.features !== "object" || Array.isArray(p.features))
  ) {
    return "features must be an object";
  }

  if (p.features && typeof p.features === "object") {
    for (const key of Object.keys(p.features)) {
      if (!ALLOWED_FEATURE_KEYS.includes(key)) {
        return `Invalid feature key: ${key}`;
      }
    }
  }

  return null;
}

// GET /clinic-policy/me
async function getMyClinicPolicy(req, res) {
  try {
    const clinicId = normStr(req.user?.clinicId);
    const userId = normStr(req.user?.userId);

    if (!clinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    let policyDoc = await ClinicPolicy.findOne({ clinicId });

    if (!policyDoc) {
      policyDoc = await ClinicPolicy.create(defaultPolicy(clinicId, userId));
    } else {
      const normalized = normalizePolicyShape(
        policyDoc.toObject(),
        clinicId,
        userId
      );
      const err = validatePolicy(normalized);

      if (!err) {
        applyPolicyToDoc(policyDoc, normalized, userId);
        await policyDoc.save();
      }
    }

    const normalizedPolicy = normalizePolicyShape(
      policyDoc.toObject(),
      clinicId,
      userId
    );

    return res.json({ ok: true, policy: normalizedPolicy });
  } catch (e) {
    return res.status(500).json({
      message: "get policy failed",
      error: e.message,
    });
  }
}

// PUT/PATCH /clinic-policy/me
async function updateMyClinicPolicy(req, res) {
  try {
    const clinicId = normStr(req.user?.clinicId);
    const userId = normStr(req.user?.userId);

    if (!clinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    let policyDoc = await ClinicPolicy.findOne({ clinicId });
    if (!policyDoc) {
      policyDoc = await ClinicPolicy.create(defaultPolicy(clinicId, userId));
    }

    const base = normalizePolicyShape(policyDoc.toObject(), clinicId, userId);
    const body = req.body || {};

    const next = normalizePolicyShape(
      {
        ...base,
        ...body,
        requireLocation: ENFORCED_REQUIRE_LOCATION,
        geoRadiusMeters: ENFORCED_GEO_RADIUS_METERS,
        timezone: ATTENDANCE_TIMEZONE,
        features: mergeFeatures(base.features, body.features || {}),
        attendanceApprovalRoles:
          body.attendanceApprovalRoles ?? base.attendanceApprovalRoles,
        otApprovalRoles: body.otApprovalRoles ?? base.otApprovalRoles,
        weeklySchedule: body.weeklySchedule ?? base.weeklySchedule,
        location: body.location ?? body.clinicLocation ?? base.location,
        clinicLocation:
          body.clinicLocation ?? body.location ?? base.clinicLocation,
        clinicLat:
          body.clinicLat ??
          body.referenceLat ??
          body.location?.lat ??
          body.clinicLocation?.lat ??
          base.clinicLat,
        clinicLng:
          body.clinicLng ??
          body.referenceLng ??
          body.location?.lng ??
          body.clinicLocation?.lng ??
          base.clinicLng,
        referenceLat:
          body.referenceLat ??
          body.clinicLat ??
          body.location?.lat ??
          body.clinicLocation?.lat ??
          base.referenceLat,
        referenceLng:
          body.referenceLng ??
          body.clinicLng ??
          body.location?.lng ??
          body.clinicLocation?.lng ??
          base.referenceLng,
      },
      clinicId,
      userId
    );

    const err = validatePolicy(next);
    if (err) {
      return res.status(400).json({ message: err });
    }

    applyPolicyToDoc(policyDoc, next, userId);
    policyDoc.version = Number(policyDoc.version || 1) + 1;

    await policyDoc.save();

    const normalizedPolicy = normalizePolicyShape(
      policyDoc.toObject(),
      clinicId,
      userId
    );

    return res.json({ ok: true, policy: normalizedPolicy });
  } catch (e) {
    return res.status(500).json({
      message: "update policy failed",
      error: e.message,
    });
  }
}

module.exports = { getMyClinicPolicy, updateMyClinicPolicy };