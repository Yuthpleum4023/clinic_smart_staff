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
    return value
      .map((x) => normStr(x))
      .filter(Boolean);
  }
  if (typeof value === "string") {
    const one = normStr(value);
    return one ? [one] : fallback;
  }
  return fallback;
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

  const allowedOtRules = ["AFTER_DAILY_HOURS", "AFTER_SHIFT_END", "AFTER_CLOCK_TIME"];
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
    if (!Number.isFinite(h) || h <= 0 || h > 24) return "regularHoursPerDay must be 1..24";
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

  const attendanceRoles = normalizeStringArray(p.attendanceApprovalRoles, []);
  const otRoles = normalizeStringArray(p.otApprovalRoles, []);

  if (!attendanceRoles.length) {
    return "attendanceApprovalRoles must contain at least 1 role";
  }

  if (!otRoles.length) {
    return "otApprovalRoles must contain at least 1 role";
  }

  const featureKeys = [
    "manualAttendance",
    "fingerprintAttendance",
    "autoOtCalculation",
    "otApprovalWorkflow",
    "attendanceApproval",
    "payrollLock",
    "policyHumanReadable",
  ];

  if (p.features && typeof p.features !== "object") {
    return "features must be an object";
  }

  if (p.features && typeof p.features === "object") {
    for (const key of Object.keys(p.features)) {
      if (!featureKeys.includes(key)) {
        return `Invalid feature key: ${key}`;
      }
    }
  }

  return null;
}

function mergeFeatures(currentFeatures = {}, incomingFeatures = {}) {
  const base = {
    manualAttendance: true,
    fingerprintAttendance: true,
    autoOtCalculation: true,
    otApprovalWorkflow: true,
    attendanceApproval: true,
    payrollLock: true,
    policyHumanReadable: true,
  };

  return {
    ...base,
    ...(currentFeatures || {}),
    ...(incomingFeatures || {}),
  };
}

// GET /clinic-policy/me
async function getMyClinicPolicy(req, res) {
  try {
    const clinicId = normStr(req.user?.clinicId);
    if (!clinicId) return res.status(401).json({ message: "Missing clinicId in token" });

    let policy = await ClinicPolicy.findOne({ clinicId }).lean();
    if (!policy) {
      const created = await ClinicPolicy.create(
        defaultPolicy(clinicId, normStr(req.user?.userId))
      );
      policy = created.toObject();
    }

    // ✅ ensure defaults exist even for old records
    policy = {
      ...defaultPolicy(clinicId, normStr(req.user?.userId)),
      ...policy,
      features: mergeFeatures(
        defaultPolicy(clinicId, normStr(req.user?.userId)).features,
        policy.features || {}
      ),
      attendanceApprovalRoles: normalizeStringArray(
        policy.attendanceApprovalRoles,
        ["clinic_admin"]
      ),
      otApprovalRoles: normalizeStringArray(policy.otApprovalRoles, ["clinic_admin"]),
    };

    return res.json({ ok: true, policy });
  } catch (e) {
    return res.status(500).json({ message: "get policy failed", error: e.message });
  }
}

// PUT /clinic-policy/me
async function updateMyClinicPolicy(req, res) {
  try {
    const clinicId = normStr(req.user?.clinicId);
    if (!clinicId) return res.status(401).json({ message: "Missing clinicId in token" });

    let policy = await ClinicPolicy.findOne({ clinicId });
    if (!policy) {
      policy = await ClinicPolicy.create(
        defaultPolicy(clinicId, normStr(req.user?.userId))
      );
    }

    const body = req.body || {};

    const next = {
      timezone: body.timezone ?? policy.timezone,

      requireBiometric: body.requireBiometric ?? policy.requireBiometric,
      requireLocation: body.requireLocation ?? policy.requireLocation,
      geoRadiusMeters: body.geoRadiusMeters ?? policy.geoRadiusMeters,

      graceLateMinutes: body.graceLateMinutes ?? policy.graceLateMinutes,

      otRule: body.otRule ?? policy.otRule,
      regularHoursPerDay: body.regularHoursPerDay ?? policy.regularHoursPerDay,

      // legacy
      otClockTime: body.otClockTime ?? policy.otClockTime,

      // separated clock time
      fullTimeOtClockTime:
        body.fullTimeOtClockTime ?? policy.fullTimeOtClockTime ?? policy.otClockTime,
      partTimeOtClockTime:
        body.partTimeOtClockTime ?? policy.partTimeOtClockTime ?? policy.otClockTime,

      // ✅ NEW: OT window
      otWindowStart: body.otWindowStart ?? policy.otWindowStart ?? "18:00",
      otWindowEnd: body.otWindowEnd ?? policy.otWindowEnd ?? "21:00",

      otStartAfterMinutes: body.otStartAfterMinutes ?? policy.otStartAfterMinutes,

      otRounding: body.otRounding ?? policy.otRounding,
      otMultiplier: body.otMultiplier ?? policy.otMultiplier,
      holidayMultiplier: body.holidayMultiplier ?? policy.holidayMultiplier,
      weekendAllDayOT: body.weekendAllDayOT ?? policy.weekendAllDayOT,

      // ✅ NEW: core policy
      employeeOnlyOt: body.employeeOnlyOt ?? policy.employeeOnlyOt ?? true,
      requireOtApproval: body.requireOtApproval ?? policy.requireOtApproval ?? true,
      realTimeAttendanceOnly:
        body.realTimeAttendanceOnly ?? policy.realTimeAttendanceOnly ?? true,
      manualAttendanceRequireApproval:
        body.manualAttendanceRequireApproval ??
        policy.manualAttendanceRequireApproval ??
        true,
      manualReasonRequired:
        body.manualReasonRequired ?? policy.manualReasonRequired ?? true,
      lockAfterPayrollClose:
        body.lockAfterPayrollClose ?? policy.lockAfterPayrollClose ?? true,

      // ✅ NEW: approval roles
      attendanceApprovalRoles: normalizeStringArray(
        body.attendanceApprovalRoles ?? policy.attendanceApprovalRoles,
        ["clinic_admin"]
      ),
      otApprovalRoles: normalizeStringArray(
        body.otApprovalRoles ?? policy.otApprovalRoles,
        ["clinic_admin"]
      ),

      // ✅ NEW: feature flags
      features: mergeFeatures(policy.features || {}, body.features || {}),
    };

    const err = validatePolicy(next);
    if (err) return res.status(400).json({ message: err });

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
    policy.otApprovalRoles = normalizeStringArray(next.otApprovalRoles, ["clinic_admin"]);

    // ✅ NEW: features
    policy.features = mergeFeatures(policy.features || {}, next.features || {});

    policy.version = Number(policy.version || 1) + 1;
    policy.updatedBy = normStr(req.user?.userId);

    await policy.save();

    return res.json({ ok: true, policy: policy.toObject() });
  } catch (e) {
    return res.status(500).json({ message: "update policy failed", error: e.message });
  }
}

module.exports = { getMyClinicPolicy, updateMyClinicPolicy };