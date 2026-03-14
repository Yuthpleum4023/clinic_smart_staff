const mongoose = require("mongoose");
const AttendanceSession = require("../models/AttendanceSession");
const Shift = require("../models/Shift");
const ClinicPolicy = require("../models/ClinicPolicy");
const Overtime = require("../models/Overtime");
const {
  getEmployeeByUserId,
  getEmployeeByStaffId,
} = require("../utils/staffClient");

// ======================================================
// TRUST SCORE EVENT CLIENT
// ======================================================
function getScoreServiceBaseUrl() {
  return s(process.env.SCORE_SERVICE_URL).replace(/\/+$/, "");
}

function getScoreServiceInternalKey() {
  return (
    s(process.env.SCORE_SERVICE_INTERNAL_KEY) ||
    s(process.env.INTERNAL_SERVICE_KEY)
  );
}

async function postTrustScoreEvent(payload) {
  try {
    const base = getScoreServiceBaseUrl();
    if (!base) {
      console.log("⚠️ Missing SCORE_SERVICE_URL");
      return;
    }

    const internalKey = getScoreServiceInternalKey();
    if (!internalKey) {
      console.log("⚠️ Missing SCORE_SERVICE_INTERNAL_KEY / INTERNAL_SERVICE_KEY");
      return;
    }

    const url = `${base}/events/attendance`;

    const r = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-internal-key": internalKey,
      },
      body: JSON.stringify(payload),
    });

    if (!r.ok) {
      const txt = await r.text().catch(() => "");
      console.log("⚠️ score_service error:", txt || `HTTP ${r.status}`);
    }
  } catch (e) {
    console.log("⚠️ score_service call failed:", e.message);
  }
}

async function buildTrustScorePayloadFromSession(session) {
  if (!session) return null;

  const clinicId = s(session.clinicId);
  const staffId = s(session.staffId);

  // score_service schema ตอนนี้ยัง require staffId
  if (!clinicId || !staffId) return null;

  const ownerUserId = s(session.userId) || "";
  let emp = null;

  if (ownerUserId) {
    try {
      emp = await getEmployeeByUserId(ownerUserId);
    } catch (_) {
      emp = null;
    }
  }

  let status = "completed";

  // ออกก่อนเวลาให้แรงกว่า late
  if (Number(session.lateMinutes || 0) > 0) {
    status = "late";
  }

  if (Number(session.leftEarlyMinutes || 0) > 0) {
    status = "cancelled_early";
  }

  return {
    clinicId,
    staffId,
    userId: ownerUserId,
    principalId: s(session.principalId),
    fullName: s(emp?.fullName || emp?.name || ""),
    name: s(emp?.name || emp?.fullName || ""),
    phone: s(emp?.phone || ""),
    role: s(session.staffId) ? "employee" : "helper",
    status,
    minutesLate: Number(session.lateMinutes || 0),
    occurredAt: new Date().toISOString(),
  };
}

async function maybePostTrustScoreFromSession(session) {
  try {
    const payload = await buildTrustScorePayloadFromSession(session);
    if (!payload) return;
    await postTrustScoreEvent(payload);
  } catch (e) {
    console.log("⚠️ trust score event failed:", e.message);
  }
}

// ======================================================
// basic helpers
// ======================================================
function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = null) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function isHHmm(v) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(String(v || "").trim());
}

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "").trim());
}

function clampMinutes(m) {
  const x = Math.max(0, Math.floor(Number(m || 0)));
  return Number.isFinite(x) ? x : 0;
}

function clampRisk(v) {
  const x = Math.max(0, Math.floor(Number(v || 0)));
  return Math.min(100, Number.isFinite(x) ? x : 0);
}

function monthKeyFromYmd(workDate) {
  const d = s(workDate);
  return isYmd(d) ? d.slice(0, 7) : "";
}

// Thailand fixed offset
function makeLocalDateTime(dateYmd, timeHHmm) {
  return new Date(`${dateYmd}T${timeHHmm}:00+07:00`);
}

function minutesDiff(a, b) {
  return Math.floor((b.getTime() - a.getTime()) / 60000);
}

function floorToStepMinutes(minutes, step) {
  if (!step || step <= 0) return minutes;
  return Math.floor(minutes / step) * step;
}

function roundOtMinutes(minutes, rounding) {
  const m = clampMinutes(minutes);
  const r = s(rounding);

  if (r === "NONE") return m;
  if (r === "15MIN") return floorToStepMinutes(m, 15);
  if (r === "30MIN") return floorToStepMinutes(m, 30);
  if (r === "HOUR") return floorToStepMinutes(m, 60);
  return floorToStepMinutes(m, 15);
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function normalizeStringArray(value, fallback = []) {
  if (Array.isArray(value)) {
    return value.map((x) => s(x)).filter(Boolean);
  }
  if (typeof value === "string") {
    const one = s(value);
    return one ? [one] : fallback;
  }
  return fallback;
}

function parseDateOrNull(v) {
  if (!v) return null;
  const d = new Date(v);
  return Number.isFinite(d.getTime()) ? d : null;
}

function firstValidDate(...values) {
  for (const v of values) {
    const d = parseDateOrNull(v);
    if (d) return d;
  }
  return null;
}

function normalizeManualRequestType(v) {
  const t = s(v);
  if (["check_in", "check_out", "edit_both", "forgot_checkout"].includes(t)) {
    return t;
  }
  return "";
}

function normalizeApprovalFilter(v) {
  const t = s(v).toLowerCase();
  if (["pending", "approved", "rejected", "history"].includes(t)) return t;
  return "";
}

function buildCodeResponse(status, code, message, extra = {}) {
  return {
    status,
    body: {
      ok: false,
      code,
      message,
      ...extra,
    },
  };
}

// ======================================================
// security helpers
// ======================================================
function truthyBool(v) {
  if (v === true) return true;
  const t = s(v).toLowerCase();
  return t === "true" || t === "1" || t === "yes";
}

function getLocationSource(req, prefix = "in") {
  return (
    s(req.body?.[`${prefix}LocationSource`]) ||
    s(req.body?.locationSource) ||
    s(req.body?.gpsProvider) ||
    ""
  );
}

function isMockLocation(req, prefix = "in") {
  return (
    truthyBool(req.body?.[`${prefix}Mocked`]) ||
    truthyBool(req.body?.isMocked) ||
    truthyBool(req.body?.mockLocation) ||
    truthyBool(req.body?.isMockLocation)
  );
}

function ensureSecurityFields(session) {
  if (!Array.isArray(session.suspiciousFlags)) {
    session.suspiciousFlags = [];
  }
  if (!session.securityMeta || typeof session.securityMeta !== "object") {
    session.securityMeta = {
      inDistanceMeters: null,
      outDistanceMeters: null,
      inLocationSource: "",
      outLocationSource: "",
      inMocked: false,
      outMocked: false,
    };
  }
  if (!Number.isFinite(Number(session.riskScore))) {
    session.riskScore = 0;
  }
}

function addSuspiciousFlag(session, flag, risk = 0) {
  ensureSecurityFields(session);
  const f = s(flag);
  if (!f) return;

  if (!session.suspiciousFlags.includes(f)) {
    session.suspiciousFlags.push(f);
  }
  session.riskScore = clampRisk(Number(session.riskScore || 0) + clampRisk(risk));
}

function setLocationSecurityMeta({
  session,
  phase, // "in" | "out"
  distanceMeters = null,
  locationSource = "",
  mocked = false,
}) {
  ensureSecurityFields(session);

  if (phase === "in") {
    session.securityMeta.inDistanceMeters = Number.isFinite(distanceMeters)
      ? Math.round(distanceMeters)
      : null;
    session.securityMeta.inLocationSource = s(locationSource);
    session.securityMeta.inMocked = !!mocked;
  } else {
    session.securityMeta.outDistanceMeters = Number.isFinite(distanceMeters)
      ? Math.round(distanceMeters)
      : null;
    session.securityMeta.outLocationSource = s(locationSource);
    session.securityMeta.outMocked = !!mocked;
  }
}

function maybeFlagDistanceRisk(session, distanceMeters, allowedRadius) {
  if (!Number.isFinite(distanceMeters) || !Number.isFinite(allowedRadius)) return;

  const ratio = distanceMeters / Math.max(1, allowedRadius);

  if (ratio >= 0.9 && ratio <= 1) {
    addSuspiciousFlag(session, "NEAR_GEOFENCE_EDGE", 5);
  }

  if (distanceMeters > allowedRadius) {
    addSuspiciousFlag(session, "OUTSIDE_ALLOWED_RADIUS", 40);
  }
}

function detectCheckoutRiskFlags({
  session,
  policy,
  shift,
  checkOutAt,
  role,
  workDate,
}) {
  const flags = [];
  const rules = attendanceRuleDefaults(policy);
  const worked = clampMinutes(computeWorkedMinutes(session.checkInAt, checkOutAt));

  if (worked > 0 && worked < Math.max(10, rules.minMinutesBeforeCheckout)) {
    flags.push({ code: "VERY_SHORT_SESSION", risk: 25 });
  }

  const earlyMinutes = detectLeftEarlyMinutes({
    shift,
    checkOutAt,
    toleranceMinutes:
      clampMinutes(session.leaveEarlyToleranceMinutes) ||
      clampMinutes(policy.leaveEarlyToleranceMinutes || 0),
    role,
    policy,
    workDate,
  });

  if (earlyMinutes >= 30) {
    flags.push({ code: "SUSPICIOUS_EARLY_CHECKOUT", risk: 20 });
  }

  if (clampMinutes(session.otMinutes) >= 300) {
    flags.push({ code: "UNUSUAL_HIGH_OT", risk: 15 });
  }

  return flags;
}

// ======================================================
// feature / policy helpers
// ======================================================
function withFeatureDefaults(features) {
  return {
    manualAttendance: true,
    fingerprintAttendance: true,
    autoOtCalculation: true,
    otApprovalWorkflow: true,
    attendanceApproval: true,
    payrollLock: true,
    policyHumanReadable: true,
    ...(features || {}),
  };
}

function attendanceRuleDefaults(policy) {
  return {
    cutoffTime: isHHmm(policy?.cutoffTime) ? s(policy.cutoffTime) : "03:00",
    minMinutesBeforeCheckout: clampMinutes(
      policy?.minMinutesBeforeCheckout || 1
    ),
    blockNewCheckInIfPreviousOpen:
      policy?.blockNewCheckInIfPreviousOpen === undefined
        ? true
        : !!policy.blockNewCheckInIfPreviousOpen,
    forgotCheckoutManualOnly:
      policy?.forgotCheckoutManualOnly === undefined
        ? true
        : !!policy.forgotCheckoutManualOnly,
    requireReasonForEarlyCheckIn:
      policy?.requireReasonForEarlyCheckIn === undefined
        ? true
        : !!policy.requireReasonForEarlyCheckIn,
    requireReasonForEarlyCheckOut:
      policy?.requireReasonForEarlyCheckOut === undefined
        ? true
        : !!policy.requireReasonForEarlyCheckOut,
  };
}

function buildHumanReadablePolicy(policy) {
  const lines = [];

  if (policy?.realTimeAttendanceOnly) {
    lines.push("การลงเวลางานต้องเป็นแบบเรียลไทม์");
  }

  if (policy?.manualAttendanceRequireApproval) {
    lines.push("หากลืมลงเวลา ต้องส่งคำขอแก้ไขเวลาและรอผู้ดูแลอนุมัติ");
  }

  if (policy?.manualReasonRequired) {
    lines.push("การแก้ไขเวลาทำงานต้องระบุเหตุผล");
  }

  if (policy?.employeeOnlyOt) {
    lines.push("ระบบ OT ใช้กับพนักงานประจำเท่านั้น");
  }

  if (isHHmm(policy?.otWindowStart) && isHHmm(policy?.otWindowEnd)) {
    lines.push(`OT จะคิดเฉพาะช่วง ${policy.otWindowStart} - ${policy.otWindowEnd}`);
    lines.push("เวลานอกช่วงดังกล่าวจะไม่ถูกนำมาคิดเป็น OT");
  }

  if (policy?.requireOtApproval) {
    lines.push("OT ต้องได้รับการอนุมัติก่อนจึงจะถูกนำไปคิดเงิน");
  }

  if (policy?.lockAfterPayrollClose) {
    lines.push("เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาทำงานย้อนหลังได้");
  }

  return lines;
}

function getWeekdayKey(dateYmd) {
  const d = new Date(`${dateYmd}T00:00:00+07:00`);
  const map = [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ];
  return map[d.getDay()];
}

function getWeeklyDaySchedule(policy, workDate) {
  const dayKey = getWeekdayKey(workDate);
  return policy?.weeklySchedule?.[dayKey] || null;
}

function isClinicOpenDay(policy, workDate) {
  const day = getWeeklyDaySchedule(policy, workDate);
  if (!day) return true;
  return day.enabled !== false;
}

function pickClinicOpenTime(policy, workDate) {
  const day = getWeeklyDaySchedule(policy, workDate);
  if (day?.enabled && isHHmm(day?.start)) {
    return s(day.start);
  }

  const candidates = [
    policy?.shiftStart,
    policy?.openTime,
    policy?.clinicOpenTime,
    policy?.workingDayStart,
    policy?.businessOpenTime,
    policy?.startTime,
  ]
    .map((v) => s(v))
    .filter((v) => isHHmm(v));

  return candidates[0] || "09:00";
}

function pickClinicCloseTime(policy, workDate) {
  const day = getWeeklyDaySchedule(policy, workDate);
  if (day?.enabled && isHHmm(day?.end)) {
    return s(day.end);
  }

  const candidates = [
    policy?.shiftEnd,
    policy?.closeTime,
    policy?.clinicCloseTime,
    policy?.workingDayEnd,
    policy?.businessCloseTime,
    policy?.endTime,
  ]
    .map((v) => s(v))
    .filter((v) => isHHmm(v));

  return candidates[0] || "18:00";
}

function getClinicOpenDateTime(workDate, policy) {
  return makeLocalDateTime(workDate, pickClinicOpenTime(policy, workDate));
}

function getClinicCloseDateTime(workDate, policy) {
  const startAt = getClinicOpenDateTime(workDate, policy);
  let endAt = makeLocalDateTime(workDate, pickClinicCloseTime(policy, workDate));

  if (endAt.getTime() <= startAt.getTime()) {
    endAt = new Date(endAt.getTime() + 24 * 60 * 60000);
  }
  return endAt;
}

function buildPublicPolicy(policy, workDate = "") {
  const features = withFeatureDefaults(policy?.features || {});
  const rules = attendanceRuleDefaults(policy);

  const wd = isYmd(workDate) ? workDate : null;
  const openTime = wd
    ? pickClinicOpenTime(policy, wd)
    : s(policy?.shiftStart || policy?.openTime || "09:00");
  const closeTime = wd
    ? pickClinicCloseTime(policy, wd)
    : s(policy?.shiftEnd || policy?.closeTime || "18:00");

  return {
    otRule: s(policy?.otRule),
    otRounding: s(policy?.otRounding),
    otMultiplier: Number(policy?.otMultiplier || 1.5),
    version: Number(policy?.version || 1),

    fullTimeOtClockTime: s(policy?.fullTimeOtClockTime),
    partTimeOtClockTime: s(policy?.partTimeOtClockTime),
    otClockTime: s(policy?.otClockTime),

    otWindowStart: s(policy?.otWindowStart),
    otWindowEnd: s(policy?.otWindowEnd),

    openTime,
    closeTime,
    clinicOpenDay: wd ? isClinicOpenDay(policy, wd) : true,

    employeeOnlyOt: !!policy?.employeeOnlyOt,
    requireOtApproval: !!policy?.requireOtApproval,
    realTimeAttendanceOnly: !!policy?.realTimeAttendanceOnly,
    manualAttendanceRequireApproval: !!policy?.manualAttendanceRequireApproval,
    manualReasonRequired: !!policy?.manualReasonRequired,
    lockAfterPayrollClose: !!policy?.lockAfterPayrollClose,

    cutoffTime: rules.cutoffTime,
    minMinutesBeforeCheckout: rules.minMinutesBeforeCheckout,
    blockNewCheckInIfPreviousOpen: rules.blockNewCheckInIfPreviousOpen,
    forgotCheckoutManualOnly: rules.forgotCheckoutManualOnly,
    requireReasonForEarlyCheckIn: rules.requireReasonForEarlyCheckIn,
    requireReasonForEarlyCheckOut: rules.requireReasonForEarlyCheckOut,

    attendanceApprovalRoles: normalizeStringArray(
      policy?.attendanceApprovalRoles,
      ["clinic_admin"]
    ),
    otApprovalRoles: normalizeStringArray(policy?.otApprovalRoles, [
      "clinic_admin",
    ]),

    features,
    humanReadable: features.policyHumanReadable
      ? buildHumanReadablePolicy(policy)
      : [],
  };
}

// ======================================================
// principal / auth helpers
// ======================================================
function getPrincipal(req) {
  const clinicId = s(req.user?.clinicId);
  const role = s(req.user?.role);
  const userId = s(req.user?.userId);
  const staffId = s(req.user?.staffId);

  const principalId = staffId || userId;
  const principalType = staffId ? "staff" : "user";

  return { clinicId, role, userId, staffId, principalId, principalType };
}

function pickEmployeeClinicId(emp) {
  return s(
    emp?.clinicId ||
      emp?.clinic?._id ||
      emp?.clinic?.id ||
      emp?.clinic?.clinicId ||
      ""
  );
}

async function resolveEmployeeClinicIdFromStaff(req, fallbackClinicId = "") {
  const staffId = s(req.user?.staffId);
  if (!staffId) return s(fallbackClinicId);

  try {
    const emp = await getEmployeeByStaffId(
      staffId,
      s(req.headers?.authorization)
    );
    const clinicId = pickEmployeeClinicId(emp);
    return clinicId || s(fallbackClinicId);
  } catch (_) {
    return s(fallbackClinicId);
  }
}

// ======================================================
// db / loader helpers
// ======================================================
async function getOrCreatePolicy(clinicId, userId) {
  let p = await ClinicPolicy.findOne({ clinicId });
  if (!p) {
    p = await ClinicPolicy.create({
      clinicId,
      timezone: "Asia/Bangkok",
      requireBiometric: true,
      requireLocation: false,
      geoRadiusMeters: 200,
      graceLateMinutes: 10,

      cutoffTime: "03:00",
      minMinutesBeforeCheckout: 1,
      blockNewCheckInIfPreviousOpen: true,
      forgotCheckoutManualOnly: true,
      requireReasonForEarlyCheckIn: true,
      requireReasonForEarlyCheckOut: true,
      leaveEarlyToleranceMinutes: 0,

      shiftStart: "09:00",
      shiftEnd: "18:00",

      weeklySchedule: {
        monday: { enabled: true, start: "09:00", end: "18:00" },
        tuesday: { enabled: true, start: "09:00", end: "18:00" },
        wednesday: { enabled: true, start: "09:00", end: "18:00" },
        thursday: { enabled: true, start: "09:00", end: "18:00" },
        friday: { enabled: true, start: "09:00", end: "18:00" },
        saturday: { enabled: false, start: "09:00", end: "13:00" },
        sunday: { enabled: false, start: "09:00", end: "13:00" },
      },

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
      updatedBy: s(userId),
    });
  }
  return p;
}

async function loadShiftForSession({
  clinicId,
  staffId,
  userId,
  workDate,
  shiftId,
}) {
  if (shiftId && mongoose.Types.ObjectId.isValid(String(shiftId))) {
    const sh = await Shift.findById(shiftId).lean();
    return sh || null;
  }

  const cid = s(clinicId);
  const date = s(workDate);
  const sid = s(staffId);
  const uid = s(userId);

  if (sid) {
    const q = { staffId: sid, date };
    if (cid) q.clinicId = cid;
    const sh = await Shift.findOne(q).sort({ createdAt: -1 }).lean();
    return sh || null;
  }

  if (uid) {
    const q = { helperUserId: uid, date };
    if (cid) q.clinicId = cid;
    const sh = await Shift.findOne(q).sort({ createdAt: -1 }).lean();
    return sh || null;
  }

  return null;
}

async function findPreviousOpenSession({ clinicId, principalId, workDate }) {
  return AttendanceSession.findOne({
    clinicId,
    principalId,
    status: "open",
    workDate: { $lt: workDate },
  })
    .sort({ workDate: -1, checkInAt: -1 })
    .lean();
}

// ======================================================
// time / business-rule helpers
// ======================================================
function getShiftStartDateTime(shift) {
  if (!shift || !isYmd(shift.date) || !isHHmm(shift.start)) return null;
  return makeLocalDateTime(shift.date, shift.start);
}

function getShiftEndDateTime(shift) {
  if (!shift || !isYmd(shift.date) || !isHHmm(shift.end)) return null;

  const startAt = isHHmm(shift.start)
    ? makeLocalDateTime(shift.date, shift.start)
    : null;
  let endAt = makeLocalDateTime(shift.date, shift.end);

  if (startAt && endAt.getTime() <= startAt.getTime()) {
    endAt = new Date(endAt.getTime() + 24 * 60 * 60000);
  }

  return endAt;
}

function getCutoffDateTime(workDate, cutoffTime) {
  const cutoff = isHHmm(cutoffTime) ? cutoffTime : "03:00";
  const base = makeLocalDateTime(workDate, cutoff);
  return new Date(base.getTime() + 24 * 60 * 60000);
}

function computeLateMinutes(policy, shift, checkInAt) {
  if (!shift) return 0;
  if (!isYmd(shift.date) || !isHHmm(shift.start)) return 0;

  const shiftStart = makeLocalDateTime(shift.date, shift.start);
  const diff = minutesDiff(shiftStart, checkInAt);
  const late = Math.max(0, diff - clampMinutes(policy.graceLateMinutes));
  return clampMinutes(late);
}

function computeWorkedMinutes(checkInAt, checkOutAt) {
  if (!checkInAt || !checkOutAt) return 0;
  const m = minutesDiff(checkInAt, checkOutAt);
  return clampMinutes(m);
}

function computeWindowOverlapMinutes(
  windowStartAt,
  windowEndAt,
  actualStartAt,
  actualEndAt
) {
  if (!windowStartAt || !windowEndAt || !actualStartAt || !actualEndAt) {
    return 0;
  }

  const startAt = new Date(
    Math.max(windowStartAt.getTime(), actualStartAt.getTime())
  );
  const endAt = new Date(
    Math.min(windowEndAt.getTime(), actualEndAt.getTime())
  );

  if (endAt.getTime() <= startAt.getTime()) return 0;
  return clampMinutes(minutesDiff(startAt, endAt));
}

function computeOtMinutes(policy, shift, checkInAt, checkOutAt) {
  if (!checkInAt || !checkOutAt) return 0;

  const rule = s(policy.otRule);

  if (rule === "AFTER_SHIFT_END") {
    if (!shift || !isYmd(shift.date) || !isHHmm(shift.end)) return 0;

    const startLocal = isHHmm(shift.start)
      ? makeLocalDateTime(shift.date, shift.start)
      : null;
    let endLocal = makeLocalDateTime(shift.date, shift.end);

    if (startLocal && endLocal.getTime() <= startLocal.getTime()) {
      endLocal = new Date(endLocal.getTime() + 24 * 60 * 60000);
    }

    const otStartAt = new Date(
      endLocal.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    const raw = Math.max(0, minutesDiff(otStartAt, checkOutAt));
    return roundOtMinutes(raw, policy.otRounding);
  }

  if (rule === "AFTER_CLOCK_TIME") {
    const ymd = shift?.date && isYmd(shift.date) ? shift.date : null;
    const baseDate = ymd || null;
    if (!baseDate) return 0;

    const hasWindow =
      isHHmm(policy.otWindowStart) && isHHmm(policy.otWindowEnd);

    if (hasWindow) {
      let windowStartAt = makeLocalDateTime(baseDate, policy.otWindowStart);
      let windowEndAt = makeLocalDateTime(baseDate, policy.otWindowEnd);

      if (windowEndAt.getTime() <= windowStartAt.getTime()) {
        windowEndAt = new Date(windowEndAt.getTime() + 24 * 60 * 60000);
      }

      const raw = computeWindowOverlapMinutes(
        windowStartAt,
        windowEndAt,
        checkInAt,
        checkOutAt
      );
      return roundOtMinutes(raw, policy.otRounding);
    }

    const clock = isHHmm(policy.otClockTime) ? policy.otClockTime : "18:00";
    const clockAt = makeLocalDateTime(baseDate, clock);
    const otStartAt = new Date(
      clockAt.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    const raw = Math.max(0, minutesDiff(otStartAt, checkOutAt));
    return roundOtMinutes(raw, policy.otRounding);
  }

  if (rule === "AFTER_DAILY_HOURS") {
    const worked = computeWorkedMinutes(checkInAt, checkOutAt);
    const regular = clampMinutes(Number(policy.regularHoursPerDay || 8) * 60);
    const raw = Math.max(0, worked - regular);
    return roundOtMinutes(raw, policy.otRounding);
  }

  return 0;
}

function normalizeEmploymentType(v) {
  const t = s(v).toLowerCase();
  if (!t) return "";
  if (
    t === "fulltime" ||
    t === "full_time" ||
    t === "full-time" ||
    t === "ft"
  ) {
    return "fullTime";
  }
  if (
    t === "parttime" ||
    t === "part_time" ||
    t === "part-time" ||
    t === "pt"
  ) {
    return "partTime";
  }
  return s(v);
}

function pickOtClockByType(policy, empTypeRaw) {
  const empType = normalizeEmploymentType(empTypeRaw);
  const legacy = isHHmm(policy?.otClockTime) ? policy.otClockTime : "18:00";

  if (empType === "fullTime") {
    const v = s(policy?.fullTimeOtClockTime);
    return isHHmm(v) ? v : legacy;
  }
  if (empType === "partTime") {
    const v = s(policy?.partTimeOtClockTime);
    return isHHmm(v) ? v : legacy;
  }
  return legacy;
}

function resolveAttendanceMethod(reqMethod, biometricVerified) {
  const raw = s(reqMethod).toLowerCase();
  if (raw === "manual") return "manual";
  if (raw === "biometric") return "biometric";
  return biometricVerified ? "biometric" : "manual";
}

function ensureAttendanceMethodAllowed(policy, method) {
  const features = withFeatureDefaults(policy?.features || {});

  if (method === "biometric" && !features.fingerprintAttendance) {
    return "Fingerprint attendance is not enabled";
  }

  if (method === "manual" && !features.manualAttendance) {
    return "Manual attendance is not enabled";
  }

  if (policy?.realTimeAttendanceOnly && method !== "biometric") {
    return "Real-time attendance only";
  }

  return "";
}

function requireManualReasonIfNeeded(policy, method, note) {
  if (method !== "manual") return "";
  if (policy?.manualReasonRequired && !s(note)) {
    return "Manual attendance reason is required";
  }
  return "";
}

function isEmployeeEligibleForOt(role, empType, policy) {
  if (!policy?.employeeOnlyOt) return true;
  if (s(role) === "helper") return false;
  if (normalizeEmploymentType(empType) === "partTime") return false;
  return true;
}

function inferRoleFromSession(session) {
  return s(session?.staffId) ? "employee" : "helper";
}

function detectEarlyCheckIn({ policy, shift, checkInAt, role, workDate }) {
  const rules = attendanceRuleDefaults(policy);
  if (!rules.requireReasonForEarlyCheckIn) return false;

  if (s(role) === "helper") {
    const startAt = getShiftStartDateTime(shift);
    if (!startAt) return false;
    return checkInAt.getTime() < startAt.getTime();
  }

  const clinicOpenAt = getClinicOpenDateTime(workDate, policy);
  return checkInAt.getTime() < clinicOpenAt.getTime();
}

function detectEarlyCheckOut({ policy, shift, checkOutAt, role, workDate }) {
  const rules = attendanceRuleDefaults(policy);
  if (!rules.requireReasonForEarlyCheckOut) return false;

  if (s(role) === "helper") {
    const endAt = getShiftEndDateTime(shift);
    if (!endAt) return false;
    return checkOutAt.getTime() < endAt.getTime();
  }

  const clinicCloseAt = getClinicCloseDateTime(workDate, policy);
  return checkOutAt.getTime() < clinicCloseAt.getTime();
}

function detectLeftEarlyMinutes({
  shift,
  checkOutAt,
  toleranceMinutes = 0,
  role,
  policy,
  workDate,
}) {
  let endAt = null;

  if (s(role) === "helper") {
    endAt = getShiftEndDateTime(shift);
  } else {
    endAt = getClinicCloseDateTime(workDate, policy);
  }

  if (!endAt || !checkOutAt) return 0;

  const raw = minutesDiff(checkOutAt, endAt);
  const early = Math.max(0, raw - clampMinutes(toleranceMinutes));
  return clampMinutes(early);
}

function hasEarlyCheckoutReason(req) {
  return (
    !!s(req.body?.reasonCode) ||
    !!s(req.body?.reasonText) ||
    !!s(req.body?.note)
  );
}

// ======================================================
// manual request helpers
// ======================================================
function isStatusPendingManual(session) {
  return (
    s(session?.status) === "pending_manual" &&
    s(session?.approvalStatus) === "pending"
  );
}

function buildRequestedReason(req) {
  return {
    requestReasonCode: s(req.body?.reasonCode),
    requestReasonText: s(req.body?.reasonText || req.body?.note),
  };
}

function shouldRequireReason(policy, req) {
  return (
    !!policy?.manualReasonRequired &&
    !s(req.body?.reasonCode) &&
    !s(req.body?.reasonText) &&
    !s(req.body?.note)
  );
}

function getScheduleSnapshot({ policy, shift, workDate }) {
  const rules = attendanceRuleDefaults(policy);

  return {
    scheduledStart: s(shift?.start),
    scheduledEnd: s(shift?.end),
    clinicOpenTime: pickClinicOpenTime(policy, workDate),
    clinicCloseTime: pickClinicCloseTime(policy, workDate),
    normalMinutesBeforeOt: clampMinutes(
      Number(policy?.regularHoursPerDay || 8) * 60
    ),
    otWindowStart: s(policy?.otWindowStart),
    otWindowEnd: s(policy?.otWindowEnd),
    cutoffTime: rules.cutoffTime,
    graceMinutes: clampMinutes(policy?.graceLateMinutes || 0),
    leaveEarlyToleranceMinutes: clampMinutes(
      policy?.leaveEarlyToleranceMinutes || 0
    ),
  };
}

function buildSessionBaseForCreate({
  clinicId,
  principalId,
  principalType,
  staffId,
  userId,
  workDate,
  shift,
  policy,
  req,
}) {
  const snapshot = getScheduleSnapshot({ policy, shift, workDate });

  return {
    clinicId,
    principalId,
    principalType,
    staffId: staffId || "",
    userId: userId || "",
    shiftId: shift ? shift._id : null,
    workDate,
    checkInMethod: "manual",
    biometricVerifiedIn: false,
    checkOutMethod: "manual",
    biometricVerifiedOut: false,
    deviceId: s(req.body?.deviceId),
    note: s(req.body?.note),
    source: "manual",
    reasonCode: s(req.body?.reasonCode),
    reasonText: s(req.body?.reasonText),
    manualReason: s(req.body?.note),
    policyVersion: Number(policy.version || 0),
    suspiciousFlags: [],
    riskScore: 0,
    securityMeta: {
      inDistanceMeters: null,
      outDistanceMeters: null,
      inLocationSource: getLocationSource(req, "in"),
      outLocationSource: getLocationSource(req, "out"),
      inMocked: isMockLocation(req, "in"),
      outMocked: isMockLocation(req, "out"),
    },
    ...snapshot,
  };
}

function applyManualRequestFields(
  session,
  req,
  manualRequestType,
  requestedCheckInAt,
  requestedCheckOutAt,
  requesterId
) {
  const { requestReasonCode, requestReasonText } = buildRequestedReason(req);

  session.status = "pending_manual";
  session.approvalStatus = "pending";
  session.manualRequestType = manualRequestType;
  session.requestedCheckInAt = requestedCheckInAt || null;
  session.requestedCheckOutAt = requestedCheckOutAt || null;
  session.requestedBy = s(requesterId);
  session.requestedAt = new Date();
  session.requestReasonCode = requestReasonCode;
  session.requestReasonText = requestReasonText;
  session.manualLocked = true;

  if (s(req.body?.reasonCode)) session.reasonCode = s(req.body?.reasonCode);
  if (s(req.body?.reasonText)) session.reasonText = s(req.body?.reasonText);
  if (s(req.body?.note)) {
    session.note = s(req.body?.note);
    session.manualReason = s(req.body?.note);
  }

  session.approvedBy = "";
  session.approvedAt = null;
  session.approvalNote = "";
  session.rejectedBy = "";
  session.rejectedAt = null;
  session.rejectReason = "";
}

function clearManualRequestFields(session) {
  session.manualRequestType = "";
  session.requestedCheckInAt = null;
  session.requestedCheckOutAt = null;
  session.requestedBy = "";
  session.requestedAt = null;
  session.requestReasonCode = "";
  session.requestReasonText = "";
  session.manualLocked = false;
}

function buildManualRequestQueryForSelf({
  clinicId,
  principalId,
  workDate,
  approvalStatus,
}) {
  const q = {
    clinicId,
    principalId,
    manualRequestType: { $ne: "" },
  };

  if (isYmd(workDate)) q.workDate = workDate;

  const filter = normalizeApprovalFilter(approvalStatus);
  if (filter === "history") {
    q.approvalStatus = { $in: ["approved", "rejected"] };
  } else if (filter) {
    q.approvalStatus = filter;
  }

  return q;
}

function buildManualRequestQueryForClinic({
  clinicId,
  workDate,
  approvalStatus,
  staffIdOrPrincipal,
}) {
  const q = {
    clinicId,
    manualRequestType: { $ne: "" },
  };

  if (isYmd(workDate)) q.workDate = workDate;

  const filter = normalizeApprovalFilter(approvalStatus) || "pending";
  if (filter === "history") {
    q.approvalStatus = { $in: ["approved", "rejected"] };
  } else {
    q.approvalStatus = filter;
  }

  if (staffIdOrPrincipal) {
    q.$or = [
      { staffId: staffIdOrPrincipal },
      { principalId: staffIdOrPrincipal },
    ];
  }

  return q;
}

function determineRejectedStatus(session) {
  if (session.checkOutAt) return "closed";
  if (
    s(session.source) === "manual" &&
    s(session.checkInMethod) === "manual" &&
    !session.biometricVerifiedIn
  ) {
    return "cancelled";
  }
  return "open";
}

// ======================================================
// overtime sync
// ======================================================
async function syncOvertimeForSession({ session, policy, shift }) {
  try {
    const ownerUserId = s(session.userId) || "";
    let emp = null;

    if (ownerUserId) {
      try {
        emp = await getEmployeeByUserId(ownerUserId);
      } catch (_) {
        emp = null;
      }
    }

    const empType = normalizeEmploymentType(emp?.employmentType);
    const selectedClock = pickOtClockByType(policy, empType);
    const role = inferRoleFromSession(session);

    const policyForOt = {
      ...(policy.toObject?.() ?? policy),
      otClockTime: selectedClock,
    };

    const allowOtCalc = !!withFeatureDefaults(policy.features || {})
      .autoOtCalculation;
    const allowOtForThisUser = isEmployeeEligibleForOt(role, empType, policy);

    let otMinutes = 0;
    if (
      session.checkInAt &&
      session.checkOutAt &&
      allowOtCalc &&
      allowOtForThisUser
    ) {
      otMinutes = computeOtMinutes(
        policyForOt,
        shift,
        session.checkInAt,
        session.checkOutAt
      );
    }

    session.otMinutes = clampMinutes(otMinutes);

    const clinicIdOfSession = s(session.clinicId);
    const workDate = s(session.workDate);
    const monthKey = monthKeyFromYmd(workDate);

    const otMul = Number(
      emp?.otMultiplierNormal ||
        policyForOt.otMultiplier ||
        policy.otMultiplier ||
        1.5
    );
    const mul = Number.isFinite(otMul) && otMul > 0 ? otMul : 1.5;

    const principalIdForOt = s(session.principalId);
    const principalTypeForOt =
      s(session.principalType) || (s(session.staffId) ? "staff" : "user");
    const staffIdForOt = s(session.staffId);

    if (
      clampMinutes(session.otMinutes) > 0 &&
      monthKey &&
      s(session.status) === "closed"
    ) {
      await Overtime.updateOne(
        { clinicId: clinicIdOfSession, attendanceSessionId: session._id },
        {
          $set: {
            clinicId: clinicIdOfSession,
            principalId: principalIdForOt,
            principalType: principalTypeForOt,
            staffId: staffIdForOt,
            userId: ownerUserId || "",
            workDate,
            monthKey,
            minutes: clampMinutes(session.otMinutes),
            multiplier: mul,
            status: policy.requireOtApproval ? "pending" : "approved",
            source: "attendance",
            attendanceSessionId: session._id,
            note: s(session.note),
          },
          $setOnInsert: {
            approvedBy: "",
            approvedAt: null,
            rejectedBy: "",
            rejectedAt: null,
            rejectReason: "",
            lockedBy: "",
            lockedAt: null,
            lockedMonth: "",
          },
        },
        { upsert: true }
      );
    } else {
      await Overtime.deleteOne({
        clinicId: clinicIdOfSession,
        attendanceSessionId: session._id,
      });
    }

    return {
      employmentType: empType || null,
      selectedClock,
      rule: s(policyForOt.otRule),
      otMinutes: clampMinutes(session.otMinutes),
      eligibleForOt: allowOtForThisUser,
      requireApproval: !!policy.requireOtApproval,
    };
  } catch (e) {
    console.log("❌ Overtime sync failed:", e.message);
    return {
      employmentType: null,
      selectedClock: null,
      rule: s(policy?.otRule),
      otMinutes: clampMinutes(session.otMinutes),
      eligibleForOt: false,
      requireApproval: !!policy?.requireOtApproval,
    };
  }
}

async function recalcSessionByTimes({ session, policy, shift }) {
  const rules = attendanceRuleDefaults(policy);
  const role = inferRoleFromSession(session);

  ensureSecurityFields(session);

  session.lateMinutes =
    role === "helper" ? computeLateMinutes(policy, shift, session.checkInAt) : 0;

  if (session.checkOutAt) {
    session.workedMinutes = computeWorkedMinutes(
      session.checkInAt,
      session.checkOutAt
    );

    const leftEarlyMinutes = detectLeftEarlyMinutes({
      shift,
      checkOutAt: session.checkOutAt,
      toleranceMinutes:
        clampMinutes(session.leaveEarlyToleranceMinutes) ||
        clampMinutes(policy.leaveEarlyToleranceMinutes || 0),
      role,
      policy,
      workDate: s(session.workDate),
    });

    session.leftEarly = leftEarlyMinutes > 0;
    session.leftEarlyMinutes = leftEarlyMinutes;

    if (leftEarlyMinutes > 0) {
      session.abnormal = true;
      session.abnormalReasonCode = "LEFT_EARLY";
      session.abnormalReasonText =
        "Employee checked out before allowed end time";
      addSuspiciousFlag(session, "LEFT_EARLY", 10);
    } else if (s(session.abnormalReasonCode) === "LEFT_EARLY") {
      session.abnormal = false;
      session.abnormalReasonCode = "";
      session.abnormalReasonText = "";
    }

    if (
      session.workedMinutes > 0 &&
      session.workedMinutes < rules.minMinutesBeforeCheckout
    ) {
      session.abnormal = true;
      session.abnormalReasonCode = "CHECKOUT_TOO_FAST";
      session.abnormalReasonText =
        "Worked time is below minimum before checkout";
      addSuspiciousFlag(session, "CHECKOUT_TOO_FAST", 30);
    }
  } else {
    session.workedMinutes = 0;
    session.otMinutes = 0;
    session.leftEarly = false;
    session.leftEarlyMinutes = 0;
  }

  session.policyVersion = Number(policy.version || session.policyVersion || 0);
  session.riskScore = clampRisk(session.riskScore);
}

// ======================================================
// runtime resolution
// ======================================================
async function resolveRuntimeContext(req, workDate, shiftId = null) {
  const { clinicId, role, userId, staffId, principalId, principalType } =
    getPrincipal(req);

  if (!principalId) {
    return {
      ok: false,
      status: 401,
      body: { ok: false, message: "Missing userId/staffId in token" },
    };
  }

  let effectiveClinicId = s(clinicId);
  let shift = null;

  if (role === "employee" || role === "staff") {
    effectiveClinicId = await resolveEmployeeClinicIdFromStaff(
      req,
      effectiveClinicId
    );

    if (!effectiveClinicId) {
      return {
        ok: false,
        status: 401,
        body: { ok: false, message: "Cannot resolve clinicId for employee" },
      };
    }
  } else if (role === "helper") {
    shift = await loadShiftForSession({
      clinicId: effectiveClinicId,
      staffId,
      userId,
      workDate,
      shiftId,
    });

    if (!shift && !effectiveClinicId) {
      shift = await loadShiftForSession({
        clinicId: "",
        staffId,
        userId,
        workDate,
        shiftId,
      });
    }

    if (!shift) {
      return {
        ok: false,
        status: 409,
        body: {
          ok: false,
          code: "NO_SHIFT_TODAY",
          message: "วันนี้ไม่มีตารางงาน",
          workDate,
        },
      };
    }

    effectiveClinicId = s(shift.clinicId) || effectiveClinicId;

    if (!effectiveClinicId) {
      return {
        ok: false,
        status: 401,
        body: { ok: false, message: "Cannot resolve clinicId from helper shift" },
      };
    }
  } else {
    if (!effectiveClinicId) {
      return {
        ok: false,
        status: 401,
        body: { ok: false, message: "Missing clinicId" },
      };
    }
  }

  return {
    ok: true,
    role,
    userId,
    staffId,
    principalId,
    principalType,
    clinicId: effectiveClinicId,
    shift,
  };
}

// ======================================================
// POST /attendance/check-in
// ======================================================
async function checkIn(req, res) {
  try {
    const workDate = s(req.body?.workDate);
    const shiftId = req.body?.shiftId || null;

    if (!isYmd(workDate)) {
      return res
        .status(400)
        .json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    const ctx = await resolveRuntimeContext(req, workDate, shiftId);
    if (!ctx.ok) return res.status(ctx.status).json(ctx.body);

    const {
      role,
      userId,
      staffId,
      principalId,
      principalType,
      clinicId,
    } = ctx;

    let shift = ctx.shift || null;

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);
    const rules = attendanceRuleDefaults(policy);

    if ((role === "employee" || role === "staff") && !isClinicOpenDay(policy, workDate)) {
      return res.status(409).json({
        ok: false,
        code: "CLINIC_CLOSED_DAY",
        message: "วันนี้คลินิกปิดทำการ",
        workDate,
      });
    }

    const biometricVerified = !!req.body?.biometricVerified;
    const method = resolveAttendanceMethod(req.body?.method, biometricVerified);
    const methodErr = ensureAttendanceMethodAllowed(policy, method);
    if (methodErr) {
      return res.status(400).json({ ok: false, message: methodErr });
    }

    const manualReasonErr = requireManualReasonIfNeeded(
      policy,
      method,
      req.body?.note
    );
    if (manualReasonErr) {
      return res.status(400).json({ ok: false, message: manualReasonErr });
    }

    if (method === "biometric" && policy.requireBiometric && !biometricVerified) {
      return res.status(400).json({ ok: false, message: "Biometric required" });
    }

    const previousOpen = rules.blockNewCheckInIfPreviousOpen
      ? await findPreviousOpenSession({
          clinicId,
          principalId,
          workDate,
        })
      : null;

    if (previousOpen) {
      const out = buildCodeResponse(
        409,
        "MANUAL_REQUIRED_PREVIOUS_OPEN_SESSION",
        "Previous day session is still open. Please submit manual attendance request.",
        {
          previousSessionId: String(previousOpen._id || ""),
          previousWorkDate: s(previousOpen.workDate),
        }
      );
      return res.status(out.status).json(out.body);
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);
    const inLocationSource = getLocationSource(req, "in");
    const inMocked = isMockLocation(req, "in");

    if (!shift) {
      shift = await loadShiftForSession({
        clinicId,
        staffId,
        userId,
        workDate,
        shiftId,
      });
    }

    let inDistanceMeters = null;
    if (policy.requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        return res.status(400).json({ ok: false, message: "Location required" });
      }

      if (inMocked) {
        return res.status(400).json({
          ok: false,
          code: "FAKE_GPS_DETECTED",
          message: "ตรวจพบตำแหน่งที่อาจไม่ถูกต้องจากอุปกรณ์",
        });
      }

      const refLat = shift?.clinicLat;
      const refLng = shift?.clinicLng;

      if (Number.isFinite(refLat) && Number.isFinite(refLng)) {
        const dist = haversineMeters(refLat, refLng, lat, lng);
        inDistanceMeters = dist;
        const radius = Number(policy.geoRadiusMeters || 200);
        if (dist > radius) {
          return res.status(400).json({
            ok: false,
            message: "Outside allowed radius",
            distanceMeters: Math.round(dist),
            radiusMeters: radius,
          });
        }
      }
    }

    const existingOpen = await AttendanceSession.findOne({
      clinicId,
      principalId,
      workDate,
      status: "open",
    });

    if (existingOpen) {
      return res.status(409).json({
        ok: false,
        code: "ALREADY_CHECKED_IN",
        message: "Already checked-in (open session exists)",
        session: existingOpen,
      });
    }

    const existingClosed = await AttendanceSession.findOne({
      clinicId,
      principalId,
      workDate,
      status: "closed",
    }).lean();

    if (existingClosed) {
      return res.status(409).json({
        ok: false,
        code: "ATTENDANCE_ALREADY_COMPLETED",
        message: "Attendance already completed for today",
      });
    }

    const existingPendingManual = await AttendanceSession.findOne({
      clinicId,
      principalId,
      workDate,
      status: "pending_manual",
    }).lean();

    if (existingPendingManual) {
      return res.status(409).json({
        ok: false,
        code: "MANUAL_REQUEST_PENDING",
        message: "Manual attendance request is pending for this date",
      });
    }

    const checkInAt = new Date();

    if (role === "employee" || role === "staff") {
      const clinicOpenAt = getClinicOpenDateTime(workDate, policy);
      const clinicCloseAt = getClinicCloseDateTime(workDate, policy);

      if (checkInAt.getTime() < clinicOpenAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_NOT_OPEN",
          message: "คลินิกยังไม่เปิด",
          workDate,
          openTime: pickClinicOpenTime(policy, workDate),
        });
      }

      if (checkInAt.getTime() > clinicCloseAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_ALREADY_CLOSED",
          message: "คลินิกปิดแล้ว",
          workDate,
          closeTime: pickClinicCloseTime(policy, workDate),
        });
      }
    }

    if (
      method === "biometric" &&
      detectEarlyCheckIn({
        policy,
        shift,
        checkInAt,
        role,
        workDate,
      })
    ) {
      const out = buildCodeResponse(
        409,
        "MANUAL_REQUIRED_EARLY_CHECKIN",
        "Early check-in requires manual request and clinic approval.",
        {
          workDate,
          shiftStart: s(shift?.start),
          clinicOpenTime: pickClinicOpenTime(policy, workDate),
        }
      );
      return res.status(out.status).json(out.body);
    }

    const lateMinutes =
      role === "helper" ? computeLateMinutes(policy, shift, checkInAt) : 0;

    const snapshot = getScheduleSnapshot({ policy, shift, workDate });

    const created = await AttendanceSession.create({
      clinicId,
      principalId,
      principalType,
      staffId: staffId || "",
      userId: userId || "",
      shiftId: shift ? shift._id : null,
      workDate,
      checkInAt,
      checkInMethod: method,
      biometricVerifiedIn: method === "biometric" ? biometricVerified : false,
      deviceId: s(req.body?.deviceId),
      inLat: Number.isFinite(lat) ? lat : null,
      inLng: Number.isFinite(lng) ? lng : null,
      note: s(req.body?.note),
      source: method === "manual" ? "manual" : "fingerprint",
      reasonCode: s(req.body?.reasonCode),
      reasonText: s(req.body?.reasonText),
      manualReason: s(req.body?.note),
      lateMinutes,
      policyVersion: Number(policy.version || 0),
      suspiciousFlags: [],
      riskScore: 0,
      securityMeta: {
        inDistanceMeters: Number.isFinite(inDistanceMeters)
          ? Math.round(inDistanceMeters)
          : null,
        outDistanceMeters: null,
        inLocationSource,
        outLocationSource: "",
        inMocked,
        outMocked: false,
      },
      ...snapshot,
    });

    ensureSecurityFields(created);

    if (lateMinutes > 0) {
      addSuspiciousFlag(created, "LATE_CHECKIN", 5);
    }
    if (inMocked) {
      addSuspiciousFlag(created, "MOCK_LOCATION_IN", 50);
    }
    maybeFlagDistanceRisk(
      created,
      Number.isFinite(inDistanceMeters) ? inDistanceMeters : null,
      Number(policy.geoRadiusMeters || 200)
    );

    await created.save();

    return res.status(201).json({
      ok: true,
      session: created,
      currentSessionId: String(created._id || ""),
      policy: buildPublicPolicy(policy, workDate),
    });
  } catch (e) {
    return res
      .status(500)
      .json({ ok: false, message: "check-in failed", error: e.message });
  }
}

// ======================================================
// POST /attendance/check-out
// POST /attendance/:id/check-out
// ======================================================
async function checkOut(req, res) {
  try {
    const { userId, staffId, principalId } = getPrincipal(req);

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const id = s(req.params?.id);
    const bodyWorkDate = s(req.body?.workDate);

    let session = null;

    if (id) {
      session = await AttendanceSession.findById(id);
      if (!session) {
        return res.status(404).json({ ok: false, message: "Session not found" });
      }

      if (bodyWorkDate && isYmd(bodyWorkDate) && s(session.workDate) !== bodyWorkDate) {
        return res.status(409).json({
          ok: false,
          message: "Session workDate does not match requested workDate",
        });
      }
    } else {
      const q = {
        principalId,
        status: "open",
      };

      if (isYmd(bodyWorkDate)) q.workDate = bodyWorkDate;

      session = await AttendanceSession.findOne(q).sort({ checkInAt: -1 });

      if (!session) {
        return res.status(409).json({
          ok: false,
          code: "NO_OPEN_SESSION",
          message: "No open session to check-out",
        });
      }
    }

    if (s(session.principalId) !== principalId) {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (not your session)" });
    }

    if (session.status !== "open") {
      return res.status(409).json({
        ok: false,
        code: "SESSION_NOT_OPEN",
        message: "Session is not open",
      });
    }

    const effectiveClinicId = s(session.clinicId);
    if (!effectiveClinicId) {
      return res
        .status(400)
        .json({ ok: false, message: "Session clinicId is missing" });
    }

    const sessionRole = inferRoleFromSession(session);

    const policy = await getOrCreatePolicy(
      effectiveClinicId,
      userId || principalId
    );
    const rules = attendanceRuleDefaults(policy);

    if (
      sessionRole === "employee" &&
      !isClinicOpenDay(policy, s(session.workDate))
    ) {
      return res.status(409).json({
        ok: false,
        code: "CLINIC_CLOSED_DAY",
        message: "วันนี้คลินิกปิดทำการ",
        workDate: s(session.workDate),
      });
    }

    const biometricVerified = !!req.body?.biometricVerified;
    const method = resolveAttendanceMethod(req.body?.method, biometricVerified);
    const methodErr = ensureAttendanceMethodAllowed(policy, method);
    if (methodErr) {
      return res.status(400).json({ ok: false, message: methodErr });
    }

    const manualReasonErr = requireManualReasonIfNeeded(
      policy,
      method,
      req.body?.note
    );
    if (manualReasonErr) {
      return res.status(400).json({ ok: false, message: manualReasonErr });
    }

    if (method === "biometric" && policy.requireBiometric && !biometricVerified) {
      return res.status(400).json({ ok: false, message: "Biometric required" });
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);
    const outLocationSource = getLocationSource(req, "out");
    const outMocked = isMockLocation(req, "out");

    const shift = await loadShiftForSession({
      clinicId: effectiveClinicId,
      staffId: s(session.staffId) || staffId,
      userId: s(session.userId) || userId || "",
      workDate: s(session.workDate),
      shiftId: session.shiftId,
    });

    let outDistanceMeters = null;
    if (policy.requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        return res.status(400).json({ ok: false, message: "Location required" });
      }

      if (outMocked) {
        return res.status(400).json({
          ok: false,
          code: "FAKE_GPS_DETECTED",
          message: "ตรวจพบตำแหน่งที่อาจไม่ถูกต้องจากอุปกรณ์",
        });
      }

      const refLat = shift?.clinicLat;
      const refLng = shift?.clinicLng;

      if (Number.isFinite(refLat) && Number.isFinite(refLng)) {
        const dist = haversineMeters(refLat, refLng, lat, lng);
        outDistanceMeters = dist;
        const radius = Number(policy.geoRadiusMeters || 200);
        if (dist > radius) {
          return res.status(400).json({
            ok: false,
            message: "Outside allowed radius",
            distanceMeters: Math.round(dist),
            radiusMeters: radius,
          });
        }
      }
    }

    const checkOutAt = new Date();

    if (sessionRole === "employee") {
      const clinicOpenAt = getClinicOpenDateTime(s(session.workDate), policy);
      const clinicCloseAt = getClinicCloseDateTime(s(session.workDate), policy);

      if (checkOutAt.getTime() < clinicOpenAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_NOT_OPEN",
          message: "คลินิกยังไม่เปิด",
          workDate: s(session.workDate),
          openTime: pickClinicOpenTime(policy, s(session.workDate)),
        });
      }

      if (checkOutAt.getTime() > clinicCloseAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_ALREADY_CLOSED",
          message: "คลินิกปิดแล้ว",
          workDate: s(session.workDate),
          closeTime: pickClinicCloseTime(policy, s(session.workDate)),
        });
      }
    }

    if (
      method === "biometric" &&
      rules.forgotCheckoutManualOnly &&
      checkOutAt.getTime() >
        getCutoffDateTime(s(session.workDate), rules.cutoffTime).getTime()
    ) {
      const out = buildCodeResponse(
        409,
        "MANUAL_REQUIRED_AFTER_CUTOFF",
        "Check-out after cutoff is not allowed by biometric. Please submit manual request.",
        {
          workDate: s(session.workDate),
          cutoffTime: rules.cutoffTime,
        }
      );
      return res.status(out.status).json(out.body);
    }

    const workedMinutesNow = computeWorkedMinutes(session.checkInAt, checkOutAt);
    if (workedMinutesNow < rules.minMinutesBeforeCheckout) {
      const out = buildCodeResponse(
        409,
        "CHECKOUT_TOO_FAST",
        "Checkout is too fast.",
        {
          minMinutesBeforeCheckout: rules.minMinutesBeforeCheckout,
          workedMinutes: workedMinutesNow,
        }
      );
      return res.status(out.status).json(out.body);
    }

    const isEarlyCheckout = detectEarlyCheckOut({
      policy,
      shift,
      checkOutAt,
      role: sessionRole,
      workDate: s(session.workDate),
    });

    if (isEarlyCheckout && !hasEarlyCheckoutReason(req)) {
      const out = buildCodeResponse(
        409,
        "EARLY_CHECKOUT_REASON_REQUIRED",
        "Early check-out requires a reason before checkout is allowed.",
        {
          workDate: s(session.workDate),
          shiftEnd: s(shift?.end),
          clinicCloseTime: pickClinicCloseTime(policy, s(session.workDate)),
          requiresReason: true,
        }
      );
      return res.status(out.status).json(out.body);
    }

    ensureSecurityFields(session);

    session.checkOutAt = checkOutAt;
    session.status = "closed";
    session.checkOutMethod = method;
    session.biometricVerifiedOut = method === "biometric" ? biometricVerified : false;

    if (s(req.body?.deviceId)) session.deviceId = s(req.body?.deviceId);

    session.outLat = Number.isFinite(lat) ? lat : session.outLat;
    session.outLng = Number.isFinite(lng) ? lng : session.outLng;

    if (s(req.body?.reasonCode)) session.reasonCode = s(req.body?.reasonCode);
    if (s(req.body?.reasonText)) session.reasonText = s(req.body?.reasonText);
    if (s(req.body?.note)) {
      session.note = s(req.body?.note);
      session.manualReason = s(req.body?.note);
    }

    setLocationSecurityMeta({
      session,
      phase: "out",
      distanceMeters: Number.isFinite(outDistanceMeters) ? outDistanceMeters : null,
      locationSource: outLocationSource,
      mocked: outMocked,
    });

    if (outMocked) {
      addSuspiciousFlag(session, "MOCK_LOCATION_OUT", 50);
    }
    maybeFlagDistanceRisk(
      session,
      Number.isFinite(outDistanceMeters) ? outDistanceMeters : null,
      Number(policy.geoRadiusMeters || 200)
    );

    await recalcSessionByTimes({ session, policy, shift });

    if (isEarlyCheckout) {
      session.abnormal = true;
      session.abnormalReasonCode = "EARLY_CHECKOUT";
      session.abnormalReasonText =
        "Employee checked out before scheduled end time with reason";
      addSuspiciousFlag(session, "EARLY_CHECKOUT", 10);
    }

    const riskFlags = detectCheckoutRiskFlags({
      session,
      policy,
      shift,
      checkOutAt,
      role: sessionRole,
      workDate: s(session.workDate),
    });

    for (const item of riskFlags) {
      addSuspiciousFlag(session, item.code, item.risk);
    }

    session.riskScore = clampRisk(session.riskScore);

    await session.save();

    const otMeta = await syncOvertimeForSession({ session, policy, shift });

    await session.save();

    // ============================================
    // SEND EVENT TO TRUST SCORE SERVICE
    // ============================================
    await maybePostTrustScoreFromSession(session);

    return res.json({
      ok: true,
      session,
      otMeta,
      policy: buildPublicPolicy(policy, s(session.workDate)),
    });
  } catch (e) {
    return res
      .status(500)
      .json({ ok: false, message: "check-out failed", error: e.message });
  }
}

// ======================================================
// POST /attendance/manual-request
// ======================================================
async function submitManualRequest(req, res) {
  try {
    const {
      role,
      userId,
      staffId,
      principalId,
      principalType,
    } = getPrincipal(req);

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const workDate = s(req.body?.workDate);
    const manualRequestType = normalizeManualRequestType(
      req.body?.manualRequestType
    );
    const shiftId = req.body?.shiftId || null;

    if (!isYmd(workDate)) {
      return res
        .status(400)
        .json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    if (!manualRequestType) {
      return res.status(400).json({
        ok: false,
        message:
          "manualRequestType required (check_in | check_out | edit_both | forgot_checkout)",
      });
    }

    const ctx = await resolveRuntimeContext(req, workDate, shiftId);
    if (!ctx.ok) return res.status(ctx.status).json(ctx.body);

    const clinicId = ctx.clinicId;
    let shift = ctx.shift || null;

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);
    const features = withFeatureDefaults(policy?.features || {});
    if (!features.manualAttendance) {
      return res
        .status(400)
        .json({ ok: false, message: "Manual attendance is not enabled" });
    }

    if (shouldRequireReason(policy, req)) {
      return res.status(400).json({
        ok: false,
        message: "Manual attendance reason is required",
      });
    }

    const requestedCheckInAt = firstValidDate(
      req.body?.requestedCheckInAt,
      req.body?.checkInAt
    );
    const requestedCheckOutAt = firstValidDate(
      req.body?.requestedCheckOutAt,
      req.body?.checkOutAt
    );

    if (!shift) {
      shift = await loadShiftForSession({
        clinicId,
        staffId,
        userId,
        workDate,
        shiftId,
      });
    }

    const sameDaySessions = await AttendanceSession.find({
      clinicId,
      principalId,
      workDate,
    })
      .sort({ createdAt: -1, checkInAt: -1 })
      .exec();

    const pendingExisting = sameDaySessions.find((x) => isStatusPendingManual(x));
    if (pendingExisting) {
      return res.status(409).json({
        ok: false,
        code: "MANUAL_REQUEST_PENDING",
        message: "Manual attendance request is already pending for this date",
        sessionId: String(pendingExisting._id || ""),
      });
    }

    const openSession =
      sameDaySessions.find((x) => s(x.status) === "open") || null;
    const closedSession =
      sameDaySessions.find((x) => s(x.status) === "closed") || null;
    let targetSession = openSession || closedSession || null;

    if (manualRequestType === "check_in") {
      if (targetSession) {
        return res.status(409).json({
          ok: false,
          code: "SESSION_ALREADY_EXISTS",
          message:
            "A session already exists for this date. Use edit_both instead.",
        });
      }

      if (!requestedCheckInAt) {
        return res.status(400).json({
          ok: false,
          message: "requestedCheckInAt is required for manual check-in request",
        });
      }

      const created = new AttendanceSession(
        buildSessionBaseForCreate({
          clinicId,
          principalId,
          principalType,
          staffId,
          userId,
          workDate,
          shift,
          policy,
          req,
        })
      );

      applyManualRequestFields(
        created,
        req,
        manualRequestType,
        requestedCheckInAt,
        requestedCheckOutAt,
        userId || principalId
      );

      created.approvalStatus = policy.manualAttendanceRequireApproval
        ? "pending"
        : "approved";

      if (created.approvalStatus === "approved") {
        created.status = requestedCheckOutAt ? "closed" : "open";
        created.checkInAt = requestedCheckInAt;
        if (requestedCheckOutAt) created.checkOutAt = requestedCheckOutAt;
        clearManualRequestFields(created);
        await recalcSessionByTimes({ session: created, policy, shift });
      }

      await created.save();

      let otMeta = null;
      if (s(created.status) === "closed") {
        otMeta = await syncOvertimeForSession({
          session: created,
          policy,
          shift,
        });
        await created.save();
      }

      return res.status(201).json({
        ok: true,
        session: created,
        requiresApproval: created.approvalStatus === "pending",
        otMeta,
        policy: buildPublicPolicy(policy, workDate),
      });
    }

    if (manualRequestType === "check_out") {
      if (!openSession) {
        return res.status(409).json({
          ok: false,
          code: "OPEN_SESSION_REQUIRED",
          message:
            "Manual checkout request requires an open session for this date",
        });
      }

      if (!requestedCheckOutAt) {
        return res.status(400).json({
          ok: false,
          message:
            "requestedCheckOutAt is required for manual checkout request",
        });
      }

      targetSession = openSession;
    }

    if (manualRequestType === "forgot_checkout") {
      if (!requestedCheckOutAt) {
        return res.status(400).json({
          ok: false,
          message:
            "requestedCheckOutAt is required for forgot checkout request",
        });
      }

      if (openSession) {
        targetSession = openSession;
      } else if (closedSession) {
        return res.status(409).json({
          ok: false,
          code: "ATTENDANCE_ALREADY_COMPLETED",
          message:
            "Attendance already completed for this date. Use edit_both instead if correction is needed.",
        });
      } else if (targetSession && targetSession.checkInAt && !targetSession.checkOutAt) {
        targetSession = targetSession;
      } else {
        return res.status(409).json({
          ok: false,
          code: "CHECKIN_SESSION_REQUIRED",
          message:
            "Forgot checkout request requires an existing check-in session for this date",
        });
      }
    }

    if (manualRequestType === "edit_both") {
      if (!targetSession && !requestedCheckInAt) {
        return res.status(400).json({
          ok: false,
          message:
            "requestedCheckInAt is required when no session exists for edit_both",
        });
      }

      if (!targetSession) {
        targetSession = new AttendanceSession(
          buildSessionBaseForCreate({
            clinicId,
            principalId,
            principalType,
            staffId,
            userId,
            workDate,
            shift,
            policy,
            req,
          })
        );
      }
    }

    applyManualRequestFields(
      targetSession,
      req,
      manualRequestType,
      requestedCheckInAt,
      requestedCheckOutAt,
      userId || principalId
    );

    if (!s(targetSession.source)) targetSession.source = "manual";
    if (!s(targetSession.checkInMethod)) targetSession.checkInMethod = "manual";
    if (!s(targetSession.checkOutMethod)) targetSession.checkOutMethod = "manual";

    targetSession.approvalStatus = policy.manualAttendanceRequireApproval
      ? "pending"
      : "approved";

    if (targetSession.approvalStatus === "approved") {
      if (requestedCheckInAt) targetSession.checkInAt = requestedCheckInAt;
      if (requestedCheckOutAt) targetSession.checkOutAt = requestedCheckOutAt;

      targetSession.status = targetSession.checkOutAt ? "closed" : "open";
      clearManualRequestFields(targetSession);
      await recalcSessionByTimes({ session: targetSession, policy, shift });
    }

    await targetSession.save();

    let otMeta = null;
    if (s(targetSession.status) === "closed") {
      otMeta = await syncOvertimeForSession({
        session: targetSession,
        policy,
        shift,
      });
      await targetSession.save();
    }

    return res.status(201).json({
      ok: true,
      session: targetSession,
      requiresApproval: targetSession.approvalStatus === "pending",
      otMeta,
      policy: buildPublicPolicy(policy, workDate),
    });
  } catch (e) {
    if (e?.code === 11000) {
      return res.status(409).json({
        ok: false,
        code: "DUPLICATE_MAIN_SESSION",
        message: "A main session already exists for this date",
      });
    }
    return res.status(500).json({
      ok: false,
      message: "submit manual request failed",
      error: e.message,
    });
  }
}

// ======================================================
// GET /attendance/manual-request/my
// ======================================================
async function listMyManualRequests(req, res) {
  try {
    const { clinicId, principalId, userId, role } = getPrincipal(req);

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const workDate = s(req.query?.workDate);
    const approvalStatus = s(req.query?.approvalStatus);

    let effectiveClinicId = s(clinicId);

    if (role === "employee" || role === "staff") {
      effectiveClinicId = await resolveEmployeeClinicIdFromStaff(
        req,
        effectiveClinicId
      );
    }

    if (!effectiveClinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId" });
    }

    const q = buildManualRequestQueryForSelf({
      clinicId: effectiveClinicId,
      principalId,
      workDate,
      approvalStatus,
    });

    const items = await AttendanceSession.find(q)
      .sort({ workDate: -1, requestedAt: -1, createdAt: -1 })
      .lean();

    const policy = await getOrCreatePolicy(effectiveClinicId, userId || principalId);

    const normalizedItems = items.map((x) => {
      if (!Array.isArray(x.suspiciousFlags)) x.suspiciousFlags = [];
      if (!x.securityMeta) {
        x.securityMeta = {
          inDistanceMeters: null,
          outDistanceMeters: null,
          inLocationSource: "",
          outLocationSource: "",
          inMocked: false,
          outMocked: false,
        };
      }
      x.riskScore = clampRisk(x.riskScore || 0);
      return x;
    });

    const normalizedFilter = normalizeApprovalFilter(approvalStatus);

    return res.json({
      ok: true,
      items: normalizedItems,
      filter: {
        view:
          normalizedFilter === "history"
            ? "history"
            : normalizedFilter || "all",
        approvalStatus: normalizedFilter || "",
      },
      policy: buildPublicPolicy(policy, workDate),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "list my manual requests failed",
      error: e.message,
    });
  }
}

// ======================================================
// GET /attendance/manual-request/clinic
// ======================================================
async function listClinicManualRequests(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const actorUserId = s(req.user?.userId);

    if (!clinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }
    if (role !== "admin" && role !== "clinic_admin") {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (admin only)" });
    }

    const workDate = s(req.query?.workDate);
    const approvalStatus = s(req.query?.approvalStatus);
    const staffIdOrPrincipal = s(req.query?.staffId);

    const q = buildManualRequestQueryForClinic({
      clinicId,
      workDate,
      approvalStatus,
      staffIdOrPrincipal,
    });

    const items = await AttendanceSession.find(q)
      .sort({ requestedAt: -1, workDate: -1, createdAt: -1 })
      .lean();

    const policy = await getOrCreatePolicy(clinicId, actorUserId);

    const normalizedItems = items.map((x) => {
      if (!Array.isArray(x.suspiciousFlags)) x.suspiciousFlags = [];
      if (!x.securityMeta) {
        x.securityMeta = {
          inDistanceMeters: null,
          outDistanceMeters: null,
          inLocationSource: "",
          outLocationSource: "",
          inMocked: false,
          outMocked: false,
        };
      }
      x.riskScore = clampRisk(x.riskScore || 0);
      return x;
    });

    const normalizedFilter = normalizeApprovalFilter(approvalStatus) || "pending";

    return res.json({
      ok: true,
      items: normalizedItems,
      filter: {
        view: normalizedFilter === "pending" ? "queue" : "history",
        approvalStatus: normalizedFilter,
      },
      policy: buildPublicPolicy(policy, workDate),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "list clinic manual requests failed",
      error: e.message,
    });
  }
}

// ======================================================
// POST /attendance/manual-request/:id/approve
// ======================================================
async function approveManualRequest(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const actorUserId = s(req.user?.userId);
    const id = s(req.params?.id);

    if (!clinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }
    if (role !== "admin" && role !== "clinic_admin") {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (admin only)" });
    }
    if (!id) {
      return res
        .status(400)
        .json({ ok: false, message: "Request id is required" });
    }

    const session = await AttendanceSession.findById(id);
    if (!session) {
      return res
        .status(404)
        .json({ ok: false, message: "Manual request not found" });
    }
    if (s(session.clinicId) !== clinicId) {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (cross-clinic request)" });
    }
    if (!isStatusPendingManual(session)) {
      return res.status(409).json({
        ok: false,
        message: "Manual request is not pending approval",
      });
    }

    const policy = await getOrCreatePolicy(clinicId, actorUserId);
    if (policy.lockAfterPayrollClose && session.lockedByPayroll) {
      return res.status(409).json({
        ok: false,
        code: "PAYROLL_LOCKED",
        message: "Attendance is locked by payroll",
      });
    }

    const shift = await loadShiftForSession({
      clinicId: s(session.clinicId),
      staffId: s(session.staffId),
      userId: s(session.userId),
      workDate: s(session.workDate),
      shiftId: session.shiftId,
    });

    const requestedType = s(session.manualRequestType);
    const requestReasonCodeBeforeClear = s(session.requestReasonCode);
    const requestReasonTextBeforeClear = s(session.requestReasonText);

    const finalCheckInAt = session.requestedCheckInAt || session.checkInAt || null;
    const finalCheckOutAt =
      session.requestedCheckOutAt || session.checkOutAt || null;

    if (
      (requestedType === "check_in" || requestedType === "edit_both") &&
      !finalCheckInAt
    ) {
      return res.status(400).json({
        ok: false,
        message: "Requested check-in time is missing",
      });
    }

    if (
      (requestedType === "check_out" || requestedType === "forgot_checkout") &&
      !finalCheckOutAt
    ) {
      return res.status(400).json({
        ok: false,
        message: "Requested check-out time is missing",
      });
    }

    if (finalCheckInAt) {
      session.checkInAt = finalCheckInAt;
      session.checkInMethod = "manual";
      session.biometricVerifiedIn = false;
    }

    if (finalCheckOutAt) {
      session.checkOutAt = finalCheckOutAt;
      session.checkOutMethod = "manual";
      session.biometricVerifiedOut = false;
    }

    session.status = session.checkOutAt ? "closed" : "open";
    session.approvalStatus = "approved";
    session.approvedBy = actorUserId;
    session.approvedAt = new Date();
    session.approvalNote = s(req.body?.approvalNote);
    session.manualLocked = false;

    clearManualRequestFields(session);

    await recalcSessionByTimes({ session, policy, shift });

    if (!s(session.reasonCode) && requestReasonCodeBeforeClear) {
      session.reasonCode = requestReasonCodeBeforeClear;
    }
    if (!s(session.reasonText) && requestReasonTextBeforeClear) {
      session.reasonText = requestReasonTextBeforeClear;
    }

    await session.save();

    const otMeta = await syncOvertimeForSession({ session, policy, shift });
    await session.save();

    // ============================================
    // SEND EVENT TO TRUST SCORE SERVICE
    // ============================================
    if (s(session.status) === "closed") {
      await maybePostTrustScoreFromSession(session);
    }

    return res.json({
      ok: true,
      session,
      otMeta,
      policy: buildPublicPolicy(policy, s(session.workDate)),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "approve manual request failed",
      error: e.message,
    });
  }
}

// ======================================================
// POST /attendance/manual-request/:id/reject
// ======================================================
async function rejectManualRequest(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const actorUserId = s(req.user?.userId);
    const id = s(req.params?.id);

    if (!clinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }
    if (role !== "admin" && role !== "clinic_admin") {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (admin only)" });
    }
    if (!id) {
      return res
        .status(400)
        .json({ ok: false, message: "Request id is required" });
    }
    if (!s(req.body?.rejectReason)) {
      return res
        .status(400)
        .json({ ok: false, message: "rejectReason is required" });
    }

    const session = await AttendanceSession.findById(id);
    if (!session) {
      return res
        .status(404)
        .json({ ok: false, message: "Manual request not found" });
    }
    if (s(session.clinicId) !== clinicId) {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (cross-clinic request)" });
    }
    if (!isStatusPendingManual(session)) {
      return res.status(409).json({
        ok: false,
        message: "Manual request is not pending rejection",
      });
    }

    session.approvalStatus = "rejected";
    session.rejectedBy = actorUserId;
    session.rejectedAt = new Date();
    session.rejectReason = s(req.body?.rejectReason);
    session.manualLocked = false;

    session.status = determineRejectedStatus(session);

    if (s(session.status) === "cancelled") {
      session.checkOutAt = null;
      session.workedMinutes = 0;
      session.lateMinutes = 0;
      session.otMinutes = 0;
      session.leftEarly = false;
      session.leftEarlyMinutes = 0;
      session.abnormal = false;
      session.abnormalReasonCode = "";
      session.abnormalReasonText = "";
      session.suspiciousFlags = [];
      session.riskScore = 0;
      if (session.securityMeta) {
        session.securityMeta.outDistanceMeters = null;
        session.securityMeta.outLocationSource = "";
        session.securityMeta.outMocked = false;
      }
    }

    await session.save();

    return res.json({
      ok: true,
      session,
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "reject manual request failed",
      error: e.message,
    });
  }
}

// ======================================================
// GET /attendance/me
// ======================================================
async function listMySessions(req, res) {
  try {
    const { clinicId, principalId, userId, role } = getPrincipal(req);

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    let effectiveClinicId = s(clinicId);
    if (role === "employee" || role === "staff") {
      effectiveClinicId = await resolveEmployeeClinicIdFromStaff(
        req,
        effectiveClinicId
      );
    }

    if (!effectiveClinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId" });
    }

    const dateFrom = s(req.query?.dateFrom);
    const dateTo = s(req.query?.dateTo);

    const q = { clinicId: effectiveClinicId, principalId };
    if (isYmd(dateFrom) && isYmd(dateTo)) {
      q.workDate = { $gte: dateFrom, $lte: dateTo };
    }

    const items = await AttendanceSession.find(q)
      .sort({ checkInAt: -1 })
      .lean();
    const policy = await getOrCreatePolicy(effectiveClinicId, userId || principalId);

    const normalizedItems = items.map((x) => {
      if (!Array.isArray(x.suspiciousFlags)) x.suspiciousFlags = [];
      if (!x.securityMeta) {
        x.securityMeta = {
          inDistanceMeters: null,
          outDistanceMeters: null,
          inLocationSource: "",
          outLocationSource: "",
          inMocked: false,
          outMocked: false,
        };
      }
      x.riskScore = clampRisk(x.riskScore || 0);
      return x;
    });

    return res.json({
      ok: true,
      items: normalizedItems,
      policy: buildPublicPolicy(policy),
    });
  } catch (e) {
    return res
      .status(500)
      .json({ ok: false, message: "list failed", error: e.message });
  }
}

// ======================================================
// GET /attendance/clinic
// ======================================================
async function listClinicSessions(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

    if (!clinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    if (role !== "admin" && role !== "clinic_admin") {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (admin only)" });
    }

    const workDate = s(req.query?.workDate);
    const staffIdOrPrincipal = s(req.query?.staffId);

    const q = { clinicId };
    if (isYmd(workDate)) q.workDate = workDate;

    if (staffIdOrPrincipal) {
      q.$or = [
        { staffId: staffIdOrPrincipal },
        { principalId: staffIdOrPrincipal },
      ];
    }

    const items = await AttendanceSession.find(q)
      .sort({ checkInAt: -1 })
      .lean();
    const policy = await getOrCreatePolicy(clinicId, s(req.user?.userId));

    const normalizedItems = items.map((x) => {
      if (!Array.isArray(x.suspiciousFlags)) x.suspiciousFlags = [];
      if (!x.securityMeta) {
        x.securityMeta = {
          inDistanceMeters: null,
          outDistanceMeters: null,
          inLocationSource: "",
          outLocationSource: "",
          inMocked: false,
          outMocked: false,
        };
      }
      x.riskScore = clampRisk(x.riskScore || 0);
      return x;
    });

    return res.json({
      ok: true,
      items: normalizedItems,
      policy: buildPublicPolicy(policy, workDate),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "list clinic failed",
      error: e.message,
    });
  }
}

// ======================================================
// GET /attendance/me-preview
// ======================================================
async function myDayPreview(req, res) {
  try {
    const workDate = s(req.query?.workDate);
    if (!isYmd(workDate)) {
      return res
        .status(400)
        .json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    const ctx = await resolveRuntimeContext(req, workDate, null);
    if (!ctx.ok) return res.status(ctx.status).json(ctx.body);

    const {
      role,
      userId,
      principalId,
      clinicId,
    } = ctx;

    let shift = ctx.shift || null;

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);

    const sessions = await AttendanceSession.find({
      clinicId,
      principalId,
      workDate,
    })
      .sort({ checkInAt: -1, createdAt: -1 })
      .lean();

    const normalizedSessions = sessions.map((x) => {
      if (!Array.isArray(x.suspiciousFlags)) x.suspiciousFlags = [];
      if (!x.securityMeta) {
        x.securityMeta = {
          inDistanceMeters: null,
          outDistanceMeters: null,
          inLocationSource: "",
          outLocationSource: "",
          inMocked: false,
          outMocked: false,
        };
      }
      x.riskScore = clampRisk(x.riskScore || 0);
      return x;
    });

    const openSession =
      normalizedSessions.find((x) => s(x.status).toLowerCase() === "open") || null;

    const pendingManualSession =
      normalizedSessions.find((x) => s(x.status).toLowerCase() === "pending_manual") ||
      null;

    const closedSessions = normalizedSessions.filter(
      (x) => s(x.status).toLowerCase() === "closed"
    );

    const checkedIn =
      !!openSession || closedSessions.length > 0 || !!pendingManualSession;
    const checkedOut = !openSession && closedSessions.length > 0;

    const workedMinutes = closedSessions.reduce(
      (sum, x) => sum + clampMinutes(x.workedMinutes),
      0
    );

    const otMinutesRawFromSessions = closedSessions.reduce(
      (sum, x) => sum + clampMinutes(x.otMinutes),
      0
    );

    const approvedOt = await Overtime.find({
      clinicId,
      principalId,
      workDate,
      status: "approved",
    }).lean();

    const otMinutesApproved = approvedOt.reduce(
      (sum, x) => sum + clampMinutes(x.minutes),
      0
    );

    const suspiciousCount = normalizedSessions.reduce(
      (sum, x) => sum + (Array.isArray(x.suspiciousFlags) && x.suspiciousFlags.length > 0 ? 1 : 0),
      0
    );

    const totalRiskScore = normalizedSessions.reduce(
      (sum, x) => sum + clampRisk(x.riskScore || 0),
      0
    );

    let emp = null;
    if (userId) {
      try {
        emp = await getEmployeeByUserId(userId);
      } catch (_) {
        emp = null;
      }
    }

    if (!shift && role === "helper") {
      shift = await loadShiftForSession({
        clinicId,
        staffId: s(req.user?.staffId),
        userId: s(req.user?.userId),
        workDate,
        shiftId: null,
      });
    }

    const type = normalizeEmploymentType(emp?.employmentType);
    const hoursPerDay = Number(emp?.hoursPerDay || 8);
    const daysPerMonth = Number(emp?.workingDaysPerMonth || 26);

    let baseHourly = Number(emp?.hourlyRate || 0);
    if (type === "fullTime") {
      const monthly = Number(emp?.monthlySalary || 0);
      const denom = Math.max(1, daysPerMonth * hoursPerDay);
      baseHourly = monthly > 0 ? monthly / denom : 0;
    }

    const normalMinutes = Math.max(0, workedMinutes - otMinutesApproved);
    const normalPay = (normalMinutes / 60) * baseHourly;

    const otMul = Number(emp?.otMultiplierNormal || policy.otMultiplier || 1.5);
    const otPay = (otMinutesApproved / 60) * baseHourly * otMul;

    const checkInAt =
      openSession?.checkInAt ||
      pendingManualSession?.checkInAt ||
      closedSessions[0]?.checkInAt ||
      null;

    const checkOutAt = closedSessions[0]?.checkOutAt || null;

    let message = "วันนี้ยังไม่ได้เช็คอิน";
    if (pendingManualSession) {
      message = "วันนี้มีคำขอแก้ไขเวลา รออนุมัติ";
    } else if (checkedIn) {
      message = checkedOut
        ? "วันนี้เช็คอินและเช็คเอาท์แล้ว"
        : "วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)";
    }

    return res.json({
      ok: true,
      workDate,
      checkedIn,
      checkedOut,
      checkInAt,
      checkOutAt,
      message,
      attendance: {
        checkedIn,
        checkedOut,
        openSession,
        pendingManualSession,
        currentSessionId: openSession ? String(openSession._id || "") : "",
      },
      employee: emp || null,
      principal: {
        principalId,
        staffId: s(req.user?.staffId),
        userId: s(req.user?.userId),
      },
      policy: buildPublicPolicy(policy, workDate),
      summary: {
        workedMinutes,
        otMinutesApproved,
        otMinutesRawFromSessions,
        baseHourly,
        normalPay,
        otPay,
        totalPay: normalPay + otPay,
        suspiciousCount,
        totalRiskScore,
      },
      sessions: normalizedSessions,
      approvedOtRecords: approvedOt,
      runtime: {
        role,
        clinicId,
        clinicOpenDay: isClinicOpenDay(policy, workDate),
        clinicOpenTime: pickClinicOpenTime(policy, workDate),
        clinicCloseTime: pickClinicCloseTime(policy, workDate),
        shift: shift || null,
      },
    });
  } catch (e) {
    return res
      .status(500)
      .json({ ok: false, message: "preview failed", error: e.message });
  }
}

module.exports = {
  checkIn,
  checkOut,
  submitManualRequest,
  listMyManualRequests,
  listClinicManualRequests,
  approveManualRequest,
  rejectManualRequest,
  listMySessions,
  listClinicSessions,
  myDayPreview,
};