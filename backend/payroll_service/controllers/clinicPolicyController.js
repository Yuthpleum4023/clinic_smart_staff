// backend/payroll_service/controllers/clinicPolicyController.js
const ClinicPolicy = require("../models/ClinicPolicy");

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
    const arr = value
      .map((x) => normStr(x))
      .filter(Boolean);
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

const ALLOWED_FEATURE_KEYS = [
  "manualAttendance",
  "fingerprintAttendance",
  "autoOtCalculation",
  "otApprovalWorkflow",
  "attendanceApproval",
  "payrollLock",
  "policyHumanReadable",
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

function defaultPolicy(clinicId, updatedByUserId = "") {
  return {
    clinicId,
    timezone: "Asia/Bangkok",

    requireBiometric: true,
    requireLocation: false,
    geoRadiusMeters: 200,

    graceLateMinutes: 10,

    // ✅ DEFAULT CHANGED
    otRule: "AFTER_CLOCK_TIME",
    regularHoursPerDay: 8,

    // legacy fallback
    otClockTime: "18:00",

    // ✅ separated employee/helper clock time (legacy support)
    fullTimeOtClockTime: "18:00",
    partTimeOtClockTime: "18:00",

    // ✅ NEW: OT window (ใช้กับ employee เท่านั้น)
    otWindowStart: "18:00",
    otWindowEnd: "21:00",

    otStartAfterMinutes: 0,

    otRounding: "15MIN",
    otMultiplier: 1.5,
    holidayMultiplier: 2.0,
    weekendAllDayOT: false,

    // ✅ NEW: core policy
    employeeOnlyOt: true,
    requireOtApproval: true,
    realTimeAttendanceOnly: true,
    manualAttendanceRequireApproval: true,
    manualReasonRequired: true,
    lockAfterPayrollClose: true,

    // ✅ NEW: approval roles
    attendanceApprovalRoles: ["clinic_admin"],
    otApprovalRoles: ["clinic_admin"],

    // ✅ NEW: feature flags
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

function validatePolicy(p) {
  const otRule = normStr(p.otRule);

  const allowedOtRules = [
    "AFTER_DAILY_HOURS",
    "AFTER_SHIFT_END",
    "AFTER_CLOCK_TIME",
  ];
  if (otRule && !allowedOtRules.includes(otRule)) return "Invalid otRule";

  const allowedRounding = ["NONE", "15MIN", "30MIN", "HOUR"];
  if (p.otRounding && !allowedRounding.includes(normStr(p.otRounding))) {
    return "Invalid otRounding";
  }

  const grace = toNum(p.graceLateMinutes, NaN);
  if (!Number.isFinite(grace) || grace < 0 || grace > 180) {
    return "graceLateMinutes must be 0..180";
  }

  const radius = toNum(p.geoRadiusMeters, NaN);
  if (!Number.isFinite(radius) || radius < 0 || radius > 5000) {
    return "geoRadiusMeters must be 0..5000";
  }

  const otStartAfter = toNum(p.otStartAfterMinutes, NaN);
  if (!Number.isFinite(otStartAfter) || otStartAfter < 0 || otStartAfter > 180) {
    return "otStartAfterMinutes must be 0..180";
  }

  const otM = toNum(p.otMultiplier, NaN);
  if (!Number.isFinite(otM) || otM <= 0) return "otMultiplier must be > 0";

  const holM = toNum(p.holidayMultiplier, NaN);
  if (!Number.isFinite(holM) || holM <= 0) return "holidayMultiplier must be > 0";

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

  // ✅ NEW: validate OT window
  if (p.otWindowStart && !isHHmm(p.otWindowStart)) {
    return "otWindowStart must be HH:mm";
  }

  if (p.otWindowEnd && !isHHmm(p.otWindowEnd)) {
    return "otWindowEnd must be HH:mm";
  }

  const attendanceRoles = normalizeStringArray(
    p.attendanceApprovalRoles,
    ["clinic_admin"]
  );
  const otRoles = normalizeStringArray(
    p.otApprovalRoles,
    ["clinic_admin"]
  );

  if (!attendanceRoles.length) {
    return "attendanceApprovalRoles must contain at least 1 role";
  }

  if (!otRoles.length) {
    return "otApprovalRoles must contain at least 1 role";
  }

  if (p.features && (typeof p.features !== "object" || Array.isArray(p.features))) {
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

// GET /clinic-policy/me
async function getMyClinicPolicy(req, res) {
  try {
    const clinicId = normStr(req.user?.clinicId);
    if (!clinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    let policy = await ClinicPolicy.findOne({ clinicId }).lean();

    if (!policy) {
      const created = await ClinicPolicy.create(
        defaultPolicy(clinicId, normStr(req.user?.userId))
      );
      policy = created.toObject();
    }

    const defaults = defaultPolicy(clinicId, normStr(req.user?.userId));

    policy = {
      ...defaults,
      ...policy,
      features: mergeFeatures(defaults.features, policy.features || {}),
      attendanceApprovalRoles: normalizeStringArray(
        policy.attendanceApprovalRoles,
        ["clinic_admin"]
      ),
      otApprovalRoles: normalizeStringArray(
        policy.otApprovalRoles,
        ["clinic_admin"]
      ),
    };

    return res.json({ ok: true, policy });
  } catch (e) {
    return res.status(500).json({
      message: "get policy failed",
      error: e.message,
    });
  }
}

// PUT /clinic-policy/me
async function updateMyClinicPolicy(req, res) {
  try {
    const clinicId = normStr(req.user?.clinicId);
    if (!clinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    let policy = await ClinicPolicy.findOne({ clinicId });
    if (!policy) {
      policy = await ClinicPolicy.create(
        defaultPolicy(clinicId, normStr(req.user?.userId))
      );
    }

    const defaults = defaultPolicy(clinicId, normStr(req.user?.userId));
    const body = req.body || {};

    const next = {
      timezone: body.timezone ?? policy.timezone ?? defaults.timezone,

      requireBiometric:
        body.requireBiometric ?? policy.requireBiometric ?? defaults.requireBiometric,
      requireLocation:
        body.requireLocation ?? policy.requireLocation ?? defaults.requireLocation,
      geoRadiusMeters:
        body.geoRadiusMeters ?? policy.geoRadiusMeters ?? defaults.geoRadiusMeters,

      graceLateMinutes:
        body.graceLateMinutes ?? policy.graceLateMinutes ?? defaults.graceLateMinutes,

      otRule: body.otRule ?? policy.otRule ?? defaults.otRule,
      regularHoursPerDay:
        body.regularHoursPerDay ??
        policy.regularHoursPerDay ??
        defaults.regularHoursPerDay,

      // legacy
      otClockTime: body.otClockTime ?? policy.otClockTime ?? defaults.otClockTime,

      // separated clock time
      fullTimeOtClockTime:
        body.fullTimeOtClockTime ??
        policy.fullTimeOtClockTime ??
        policy.otClockTime ??
        defaults.fullTimeOtClockTime,

      partTimeOtClockTime:
        body.partTimeOtClockTime ??
        policy.partTimeOtClockTime ??
        policy.otClockTime ??
        defaults.partTimeOtClockTime,

      // ✅ NEW: OT window
      otWindowStart:
        body.otWindowStart ?? policy.otWindowStart ?? defaults.otWindowStart,
      otWindowEnd:
        body.otWindowEnd ?? policy.otWindowEnd ?? defaults.otWindowEnd,

      otStartAfterMinutes:
        body.otStartAfterMinutes ??
        policy.otStartAfterMinutes ??
        defaults.otStartAfterMinutes,

      otRounding: body.otRounding ?? policy.otRounding ?? defaults.otRounding,
      otMultiplier: body.otMultiplier ?? policy.otMultiplier ?? defaults.otMultiplier,
      holidayMultiplier:
        body.holidayMultiplier ??
        policy.holidayMultiplier ??
        defaults.holidayMultiplier,
      weekendAllDayOT:
        body.weekendAllDayOT ?? policy.weekendAllDayOT ?? defaults.weekendAllDayOT,

      // ✅ NEW: core policy
      employeeOnlyOt:
        body.employeeOnlyOt ?? policy.employeeOnlyOt ?? defaults.employeeOnlyOt,
      requireOtApproval:
        body.requireOtApproval ??
        policy.requireOtApproval ??
        defaults.requireOtApproval,
      realTimeAttendanceOnly:
        body.realTimeAttendanceOnly ??
        policy.realTimeAttendanceOnly ??
        defaults.realTimeAttendanceOnly,
      manualAttendanceRequireApproval:
        body.manualAttendanceRequireApproval ??
        policy.manualAttendanceRequireApproval ??
        defaults.manualAttendanceRequireApproval,
      manualReasonRequired:
        body.manualReasonRequired ??
        policy.manualReasonRequired ??
        defaults.manualReasonRequired,
      lockAfterPayrollClose:
        body.lockAfterPayrollClose ??
        policy.lockAfterPayrollClose ??
        defaults.lockAfterPayrollClose,

      // ✅ NEW: approval roles
      attendanceApprovalRoles: normalizeStringArray(
        body.attendanceApprovalRoles ||
          policy.attendanceApprovalRoles ||
          defaults.attendanceApprovalRoles,
        ["clinic_admin"]
      ),

      otApprovalRoles: normalizeStringArray(
        body.otApprovalRoles ||
          policy.otApprovalRoles ||
          defaults.otApprovalRoles,
        ["clinic_admin"]
      ),

      // ✅ NEW: feature flags
      features: mergeFeatures(policy.features || defaults.features, body.features || {}),
    };

    const err = validatePolicy(next);
    if (err) {
      return res.status(400).json({
        message: err,
        debug: {
          attendanceApprovalRoles: next.attendanceApprovalRoles,
          otApprovalRoles: next.otApprovalRoles,
          otWindowStart: next.otWindowStart,
          otWindowEnd: next.otWindowEnd,
        },
      });
    }

    policy.timezone = normStr(next.timezone) || "Asia/Bangkok";

    policy.requireBiometric = !!next.requireBiometric;
    policy.requireLocation = !!next.requireLocation;
    policy.geoRadiusMeters = Number(next.geoRadiusMeters);

    policy.graceLateMinutes = Number(next.graceLateMinutes);

    policy.otRule = normStr(next.otRule);
    policy.regularHoursPerDay = Number(next.regularHoursPerDay);

    policy.otClockTime = normStr(next.otClockTime);
    policy.fullTimeOtClockTime = normStr(next.fullTimeOtClockTime);
    policy.partTimeOtClockTime = normStr(next.partTimeOtClockTime);

    policy.otWindowStart = normStr(next.otWindowStart);
    policy.otWindowEnd = normStr(next.otWindowEnd);

    policy.otStartAfterMinutes = Number(next.otStartAfterMinutes);

    policy.otRounding = normStr(next.otRounding);
    policy.otMultiplier = Number(next.otMultiplier);
    policy.holidayMultiplier = Number(next.holidayMultiplier);
    policy.weekendAllDayOT = !!next.weekendAllDayOT;

    // ✅ NEW: core policy
    policy.employeeOnlyOt = !!next.employeeOnlyOt;
    policy.requireOtApproval = !!next.requireOtApproval;
    policy.realTimeAttendanceOnly = !!next.realTimeAttendanceOnly;
    policy.manualAttendanceRequireApproval = !!next.manualAttendanceRequireApproval;
    policy.manualReasonRequired = !!next.manualReasonRequired;
    policy.lockAfterPayrollClose = !!next.lockAfterPayrollClose;

    // ✅ NEW: approval roles
    policy.attendanceApprovalRoles = normalizeStringArray(
      next.attendanceApprovalRoles,
      ["clinic_admin"]
    );
    policy.otApprovalRoles = normalizeStringArray(
      next.otApprovalRoles,
      ["clinic_admin"]
    );

    // ✅ NEW: features
    policy.features = mergeFeatures(policy.features || {}, next.features || {});

    policy.version = Number(policy.version || 1) + 1;
    policy.updatedBy = normStr(req.user?.userId);

    await policy.save();

    return res.json({ ok: true, policy: policy.toObject() });
  } catch (e) {
    return res.status(500).json({
      message: "update policy failed",
      error: e.message,
    });
  }
}

module.exports = { getMyClinicPolicy, updateMyClinicPolicy };