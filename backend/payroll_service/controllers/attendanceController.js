const mongoose = require("mongoose");
const AttendanceSession = require("../models/AttendanceSession");
const Shift = require("../models/Shift");
const ClinicPolicy = require("../models/ClinicPolicy");
const Overtime = require("../models/Overtime");
const {
  getEmployeeByUserId,
  getEmployeeByStaffId,
} = require("../utils/staffClient");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = null) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function isHHmm(v) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(s(v));
}

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(s(v));
}

function clampMinutes(v) {
  const x = Math.floor(Number(v || 0));
  return Number.isFinite(x) ? Math.max(0, x) : 0;
}

function clampRisk(v) {
  const x = Math.floor(Number(v || 0));
  if (!Number.isFinite(x)) return 0;
  return Math.max(0, Math.min(100, x));
}

function makeLocalDateTime(dateYmd, timeHHmm) {
  return new Date(`${dateYmd}T${timeHHmm}:00+07:00`);
}

function minutesDiff(a, b) {
  return Math.floor((b.getTime() - a.getTime()) / 60000);
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

function monthKeyFromYmd(workDate) {
  return isYmd(workDate) ? s(workDate).slice(0, 7) : "";
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
  return R * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

function normalizeStringArray(value, fallback = []) {
  if (Array.isArray(value)) return value.map((x) => s(x)).filter(Boolean);
  if (typeof value === "string") return s(value) ? [s(value)] : fallback;
  return fallback;
}

function truthyBool(v) {
  if (v === true) return true;
  const t = s(v).toLowerCase();
  return t === "true" || t === "1" || t === "yes";
}

function normalizeManualRequestType(v) {
  const t = s(v);
  return ["check_in", "check_out", "edit_both", "forgot_checkout"].includes(t)
    ? t
    : "";
}

function normalizeApprovalFilter(v) {
  const t = s(v).toLowerCase();
  return ["pending", "approved", "rejected", "history"].includes(t) ? t : "";
}

function buildCodeResponse(status, code, message, extra = {}) {
  return { status, body: { ok: false, code, message, ...extra } };
}

function isTooManyRequestsError(err) {
  return Number(err?.status || 0) === 429;
}

function getBearerToken(req) {
  return s(req.headers?.authorization);
}

function normalizeObjectIdString(value) {
  const text = s(value);
  if (!text) return "";
  return mongoose.Types.ObjectId.isValid(text) ? text : "";
}

function getBodyStaffId(req) {
  return (
    s(req.body?.staffId) ||
    s(req.body?.employeeId) ||
    s(req.params?.staffId) ||
    s(req.params?.employeeId) ||
    s(req.query?.staffId) ||
    s(req.query?.employeeId)
  );
}

function getRequestedShiftId(req) {
  return req.body?.shiftId || req.params?.shiftId || req.query?.shiftId || null;
}

function getPrincipal(req) {
  const clinicId = s(req.user?.clinicId);
  const role = s(req.user?.role);
  const userId = s(req.user?.userId);
  const staffId = s(req.user?.staffId) || getBodyStaffId(req);
  const principalId = userId || staffId;
  const principalType = staffId ? "staff" : "user";
  return { clinicId, role, userId, staffId, principalId, principalType };
}

function buildAttendanceActorOr({
  principalId = "",
  userId = "",
  staffId = "",
}) {
  const pid = s(principalId);
  const uid = s(userId);
  const sid = s(staffId);
  const out = [];

  if (pid) {
    out.push({ principalId: pid });
    out.push({ userId: pid });
    out.push({ helperUserId: pid });
    out.push({ assignedUserId: pid });
    out.push({ actorUserId: pid });
    out.push({ helperId: pid });
  }

  if (uid) {
    out.push({ userId: uid });
    out.push({ helperUserId: uid });
    out.push({ assignedUserId: uid });
    out.push({ actorUserId: uid });
    out.push({ helperId: uid });
    out.push({ principalId: uid });
  }

  if (sid) {
    out.push({ staffId: sid });
    out.push({ employeeId: sid });
    out.push({ principalId: sid });
  }

  const seen = new Set();
  return out.filter((x) => {
    const key = JSON.stringify(x);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function buildDateRangeClause(dateFrom = "", dateTo = "") {
  if (isYmd(dateFrom) && isYmd(dateTo)) {
    return { workDate: { $gte: dateFrom, $lte: dateTo } };
  }
  if (isYmd(dateFrom)) {
    return { workDate: { $gte: dateFrom } };
  }
  if (isYmd(dateTo)) {
    return { workDate: { $lte: dateTo } };
  }
  return null;
}

function buildShiftMatchClause(shiftId = "") {
  const normalizedShiftId = normalizeObjectIdString(shiftId);
  if (!normalizedShiftId) return null;

  return {
    $or: [
      { shiftId: normalizedShiftId },
      { shiftId: new mongoose.Types.ObjectId(normalizedShiftId) },
    ],
  };
}

function buildMyAttendanceQuery({
  clinicId = "",
  principalId = "",
  userId = "",
  staffId = "",
  dateFrom = "",
  dateTo = "",
  shiftId = "",
}) {
  const and = [];

  if (s(clinicId)) and.push({ clinicId: s(clinicId) });

  const actorOr = buildAttendanceActorOr({ principalId, userId, staffId });
  if (actorOr.length) and.push({ $or: actorOr });

  const dateClause = buildDateRangeClause(dateFrom, dateTo);
  if (dateClause) and.push(dateClause);

  const shiftClause = buildShiftMatchClause(shiftId);
  if (shiftClause) and.push(shiftClause);

  if (!and.length) return {};
  if (and.length === 1) return and[0];
  return { $and: and };
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
  if (!Array.isArray(session.suspiciousFlags)) session.suspiciousFlags = [];
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
  if (!Number.isFinite(Number(session.riskScore))) session.riskScore = 0;
}

function addSuspiciousFlag(session, flag, risk = 0) {
  ensureSecurityFields(session);
  const f = s(flag);
  if (!f) return;
  if (!session.suspiciousFlags.includes(f)) session.suspiciousFlags.push(f);
  session.riskScore = clampRisk(
    Number(session.riskScore || 0) + clampRisk(risk)
  );
}

function setLocationSecurityMeta({
  session,
  phase,
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
  if (!Number.isFinite(distanceMeters) || !Number.isFinite(allowedRadius)) {
    return;
  }
  const ratio = distanceMeters / Math.max(1, allowedRadius);
  if (ratio >= 0.9 && ratio <= 1) {
    addSuspiciousFlag(session, "NEAR_GEOFENCE_EDGE", 5);
  }
  if (distanceMeters > allowedRadius) {
    addSuspiciousFlag(session, "OUTSIDE_ALLOWED_RADIUS", 40);
  }
}

function extractClinicDisplayName(value) {
  if (!value || typeof value !== "object") return "";

  return s(
    value.clinicName ||
      value.clinic?.name ||
      value.clinic?.clinicName ||
      value.clinic?.title ||
      value.clinicTitle ||
      value.clinicDisplayName ||
      value.locationName ||
      value.workplaceName ||
      value.hospitalName ||
      value.branchName ||
      value.name
  );
}

function extractShiftDisplayName(value) {
  if (!value || typeof value !== "object") return "";

  return s(
    value.shiftName ||
      value.title ||
      value.shiftTitle ||
      value.position ||
      value.roleName ||
      value.jobTitle ||
      value.label
  );
}

function buildManualRequestRouteHint(sessionLike = {}) {
  const sessionId = s(sessionLike._id || sessionLike.sessionId);
  const clinicId = s(sessionLike.clinicId);
  const workDate = s(sessionLike.workDate);

  return {
    action: "OPEN_PENDING_MANUAL_REQUEST",
    screen: "AttendanceHistoryDetail",
    tab: "manual_requests",
    sessionId,
    clinicId,
    workDate,
  };
}

function buildResolveAttendanceRouteHint(sessionLike = {}) {
  const sessionId = s(sessionLike._id || sessionLike.sessionId);
  const clinicId = s(sessionLike.clinicId);
  const workDate = s(sessionLike.workDate);
  const shiftId =
    typeof sessionLike.shiftId === "object"
      ? s(sessionLike.shiftId?._id || sessionLike.shiftId?.id)
      : s(sessionLike.shiftId);

  return {
    action: "OPEN_ATTENDANCE_HISTORY_DETAIL",
    screen: "AttendanceHistoryDetail",
    sessionId,
    clinicId,
    workDate,
    shiftId,
  };
}

function normalizeSessionItem(x) {
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

  const shiftIdText =
    typeof x.shiftId === "object" && x.shiftId !== null
      ? s(x.shiftId._id || x.shiftId.id)
      : s(x.shiftId);

  x.shiftId = shiftIdText || x.shiftId || null;
  x.clinicId = s(x.clinicId);
  x.clinicName = s(x.clinicName || extractClinicDisplayName(x));
  x.shiftName = s(x.shiftName || extractShiftDisplayName(x));

  return x;
}

const ATTENDANCE_TIMEZONE = "Asia/Bangkok";
const ENFORCED_GEOFENCE_RADIUS_METERS = 200;

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
    const internalKey = getScoreServiceInternalKey();
    if (!base || !internalKey) return;

    const r = await fetch(`${base}/events/attendance`, {
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
  if (!clinicId || !staffId) return null;

  const ownerUserId = s(session.userId);
  let emp = null;

  if (ownerUserId) {
    try {
      emp = await getEmployeeByUserId(ownerUserId);
    } catch (_) {
      emp = null;
    }
  }

  let status = "completed";
  if (Number(session.lateMinutes || 0) > 0) status = "late";
  if (Number(session.leftEarlyMinutes || 0) > 0) status = "cancelled_early";

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

function getEnforcedGeoRadius(policy) {
  const radius = Number(
    policy?.geoRadiusMeters ?? ENFORCED_GEOFENCE_RADIUS_METERS
  );
  if (!Number.isFinite(radius) || radius <= 0) {
    return ENFORCED_GEOFENCE_RADIUS_METERS;
  }
  return ENFORCED_GEOFENCE_RADIUS_METERS;
}

function shouldRequireLocationForAttendance(policy) {
  const features = withFeatureDefaults(policy?.features || {});
  if (!features.fingerprintAttendance) return false;
  return true;
}

function mustRespectClinicHours(role) {
  const r = s(role).toLowerCase();
  return r === "employee" || r === "staff" || r === "helper";
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

  lines.push(
    `การสแกนลงเวลาต้องอยู่ในรัศมี ${getEnforcedGeoRadius(policy)} เมตรจากคลินิก`
  );

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
    lines.push(
      `OT จะคิดเฉพาะช่วง ${policy.otWindowStart} - ${policy.otWindowEnd}`
    );
    lines.push("เวลานอกช่วงดังกล่าวจะไม่ถูกนำมาคิดเป็น OT");
  }
  if (policy?.requireOtApproval) {
    lines.push("OT ต้องได้รับการอนุมัติก่อนจึงจะถูกนำไปคิดเงิน");
  }
  if (policy?.lockAfterPayrollClose) {
    lines.push(
      "เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาทำงานย้อนหลังได้"
    );
  }

  return lines;
}

function getWeekdayKey(dateYmd) {
  const d = new Date(`${dateYmd}T00:00:00+07:00`);
  return [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ][d.getDay()];
}

function getWeeklyDaySchedule(policy, workDate) {
  return policy?.weeklySchedule?.[getWeekdayKey(workDate)] || null;
}

function isClinicOpenDay(policy, workDate) {
  const day = getWeeklyDaySchedule(policy, workDate);
  if (!day) return true;
  return day.enabled !== false;
}

function pickClinicOpenTime(policy, workDate) {
  const day = getWeeklyDaySchedule(policy, workDate);
  if (day?.enabled && isHHmm(day?.start)) return s(day.start);

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
  if (day?.enabled && isHHmm(day?.end)) return s(day.end);

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

function getReferenceCoordinateCandidates(shift, policy, session = null) {
  const candidates = [
    [shift?.clinicLat, shift?.clinicLng],
    [shift?.clinic?.lat, shift?.clinic?.lng],
    [shift?.clinic?.location?.lat, shift?.clinic?.location?.lng],
    [shift?.location?.lat, shift?.location?.lng],
    [shift?.lat, shift?.lng],

    [session?.clinicLat, session?.clinicLng],
    [session?.location?.lat, session?.location?.lng],

    [policy?.clinicLat, policy?.clinicLng],
    [policy?.location?.lat, policy?.location?.lng],
    [policy?.clinicLocation?.lat, policy?.clinicLocation?.lng],
    [policy?.referenceLat, policy?.referenceLng],
  ];

  for (const [latRaw, lngRaw] of candidates) {
    const lat = n(latRaw, null);
    const lng = n(lngRaw, null);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      return { lat, lng };
    }
  }

  return null;
}

function buildLocationRequirementError() {
  return buildCodeResponse(
    409,
    "CLINIC_LOCATION_NOT_SET",
    "ยังไม่ได้ตั้งค่าพิกัดอ้างอิงของคลินิก"
  );
}

function buildLocationRequiredError() {
  return buildCodeResponse(
    400,
    "LOCATION_REQUIRED",
    "กรุณาเปิดตำแหน่งเพื่อสแกนลงเวลา"
  );
}

function buildOutsideRadiusError(distanceMeters, radiusMeters) {
  return buildCodeResponse(
    400,
    "OUTSIDE_ALLOWED_RADIUS",
    "อยู่นอกพื้นที่คลินิกที่กำหนด",
    {
      distanceMeters: Number.isFinite(distanceMeters)
        ? Math.round(distanceMeters)
        : null,
      radiusMeters: Number.isFinite(radiusMeters)
        ? Math.round(radiusMeters)
        : getEnforcedGeoRadius(),
    }
  );
}

function buildPublicPolicy(policy, workDate = "") {
  const features = withFeatureDefaults(policy?.features || {});
  const rules = attendanceRuleDefaults(policy);
  const wd = isYmd(workDate) ? workDate : "";

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
    timezone: s(policy?.timezone || ATTENDANCE_TIMEZONE) || ATTENDANCE_TIMEZONE,

    fullTimeOtClockTime: s(policy?.fullTimeOtClockTime),
    partTimeOtClockTime: s(policy?.partTimeOtClockTime),
    otClockTime: s(policy?.otClockTime),
    otWindowStart: s(policy?.otWindowStart),
    otWindowEnd: s(policy?.otWindowEnd),

    openTime,
    closeTime,
    clinicOpenDay: wd ? isClinicOpenDay(policy, wd) : true,

    requireBiometric: true,
    requireLocation: true,
    geoRadiusMeters: getEnforcedGeoRadius(policy),

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
    otApprovalRoles: normalizeStringArray(
      policy?.otApprovalRoles,
      ["clinic_admin"]
    ),

    features: {
      ...features,
      fingerprintAttendance: true,
      manualAttendance: true,
      policyHumanReadable: true,
    },

    humanReadable: buildHumanReadablePolicy({
      ...(policy || {}),
      requireLocation: true,
      geoRadiusMeters: getEnforcedGeoRadius(policy),
      timezone: s(policy?.timezone || ATTENDANCE_TIMEZONE) || ATTENDANCE_TIMEZONE,
    }),
  };
}

async function getOrCreatePolicy(clinicId, userId) {
  let p = await ClinicPolicy.findOne({ clinicId });

  if (!p) {
    p = await ClinicPolicy.create({
      clinicId,
      timezone: ATTENDANCE_TIMEZONE,

      requireBiometric: true,
      requireLocation: true,
      geoRadiusMeters: ENFORCED_GEOFENCE_RADIUS_METERS,

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
  } else {
    let changed = false;

    if (s(p.timezone) !== ATTENDANCE_TIMEZONE) {
      p.timezone = ATTENDANCE_TIMEZONE;
      changed = true;
    }

    if (p.requireBiometric !== true) {
      p.requireBiometric = true;
      changed = true;
    }

    if (p.requireLocation !== true) {
      p.requireLocation = true;
      changed = true;
    }

    if (Number(p.geoRadiusMeters) !== ENFORCED_GEOFENCE_RADIUS_METERS) {
      p.geoRadiusMeters = ENFORCED_GEOFENCE_RADIUS_METERS;
      changed = true;
    }

    if (!p.features || typeof p.features !== "object") {
      p.features = {};
      changed = true;
    }

    const nextFeatures = withFeatureDefaults(p.features || {});
    if (JSON.stringify(nextFeatures) !== JSON.stringify(p.features || {})) {
      p.features = nextFeatures;
      changed = true;
    }

    if (changed) {
      p.updatedBy = s(userId);
      p.version = Number(p.version || 1) + 1;
      await p.save();
    }
  }

  return p;
}

function createRequestMemo(req) {
  if (!req._attendanceMemo || typeof req._attendanceMemo !== "object") {
    req._attendanceMemo = {
      employeeByStaffId: new Map(),
      employeeByUserId: new Map(),
      verifiedEmployee: null,
      runtimeContext: new Map(),
      helperShiftAssignments: new Map(),
    };
  }
  return req._attendanceMemo;
}

function makeRuntimeContextKey(req, workDate, shiftId = null) {
  return [
    s(workDate),
    s(shiftId),
    s(req.user?.role),
    s(req.user?.userId),
    s(req.user?.staffId),
    s(req.user?.clinicId),
    getBodyStaffId(req),
  ].join("|");
}

function buildBusyEmployeeServiceResponse(extra = {}) {
  return buildCodeResponse(
    503,
    "EMPLOYEE_SERVICE_BUSY",
    "ระบบข้อมูลพนักงานกำลังถูกใช้งานหนาแน่น กรุณาลองใหม่อีกครั้ง",
    { upstreamStatus: 429, ...extra }
  );
}

function getStaffCandidates(req) {
  return Array.from(
    new Set([s(req.user?.staffId), getBodyStaffId(req)].filter(Boolean))
  );
}

function shouldContinueLookupAfterError(err) {
  const status = Number(err?.status || 0);
  return [400, 401, 403, 404].includes(status);
}

async function memoizedGetEmployeeByStaffId(req, staffId, token = "") {
  const key = s(staffId);
  if (!key) return null;

  const memo = createRequestMemo(req);
  if (memo.employeeByStaffId.has(key)) {
    const cached = memo.employeeByStaffId.get(key);
    if (cached.ok) return cached.value;
    throw cached.error;
  }

  try {
    const value = await getEmployeeByStaffId(key, token);
    memo.employeeByStaffId.set(key, { ok: true, value });
    return value;
  } catch (error) {
    memo.employeeByStaffId.set(key, { ok: false, error });
    throw error;
  }
}

async function memoizedGetEmployeeByUserId(req, userId, token = "") {
  const key = s(userId);
  if (!key) return null;

  const memo = createRequestMemo(req);
  if (memo.employeeByUserId.has(key)) {
    const cached = memo.employeeByUserId.get(key);
    if (cached.ok) return cached.value;
    throw cached.error;
  }

  try {
    const value = await getEmployeeByUserId(key, token);
    memo.employeeByUserId.set(key, { ok: true, value });
    return value;
  } catch (error) {
    memo.employeeByUserId.set(key, { ok: false, error });
    throw error;
  }
}

function normalizeEmployeeRecord(emp) {
  if (!emp || typeof emp !== "object") return null;

  const clinicId = s(
    emp.clinicId ||
      emp.clinic?._id ||
      emp.clinic?.id ||
      emp.clinic?.clinicId
  );

  const userId = s(
    emp.userId ||
      emp.linkedUserId ||
      emp.user?._id ||
      emp.user?.id ||
      emp.accountUserId
  );

  const staffId = s(
    emp.staffId ||
      emp.employeeCode ||
      emp.code ||
      emp._id ||
      emp.id
  );

  const rawStatus = s(
    emp.status || emp.employeeStatus || emp.employmentStatus
  ).toLowerCase();

  const activeFlag =
    emp.active === undefined && emp.isActive === undefined
      ? null
      : !!(emp.active ?? emp.isActive);

  const deleted =
    !!emp.deleted ||
    !!emp.isDeleted ||
    !!emp.archived ||
    !!emp.isArchived;

  const suspended =
    !!emp.suspended ||
    !!emp.isSuspended ||
    rawStatus === "suspended";

  const terminated =
    !!emp.terminated ||
    !!emp.isTerminated ||
    rawStatus === "terminated";

  const inactive =
    activeFlag === false ||
    !!emp.inactive ||
    !!emp.isInactive ||
    ["inactive", "disabled"].includes(rawStatus);

  const verified =
    emp.verified === undefined && emp.isVerified === undefined
      ? true
      : !!(emp.verified || emp.isVerified);

  return {
    raw: emp,
    employeeId: s(emp._id || emp.id),
    clinicId,
    userId,
    staffId,
    fullName: s(emp.fullName || emp.name),
    name: s(emp.name || emp.fullName),
    employmentType: s(emp.employmentType),
    status: rawStatus,
    verified,
    deleted,
    suspended,
    terminated,
    inactive,
    _fallback: !!emp._fallback,
  };
}

function buildFallbackEmployeeFromToken(req, fallbackClinicId = "") {
  return normalizeEmployeeRecord({
    _fallback: true,
    clinicId: s(fallbackClinicId || req.user?.clinicId),
    userId: s(req.user?.userId),
    staffId: s(req.user?.staffId) || getBodyStaffId(req),
    fullName: s(req.user?.fullName || req.user?.name),
    name: s(req.user?.name || req.user?.fullName),
    employmentType: s(req.user?.employmentType || "fullTime"),
    verified: true,
    active: true,
    deleted: false,
    suspended: false,
    terminated: false,
    inactive: false,
    status: "active",
  });
}

function isEmployeeAttendanceAllowed(employee) {
  if (!employee) {
    return {
      ok: false,
      code: "EMPLOYEE_NOT_FOUND",
      message: "Employee not found",
    };
  }

  if (employee._fallback === true) {
    return { ok: true, code: "", message: "" };
  }

  if (employee.deleted) {
    return {
      ok: false,
      code: "EMPLOYEE_DELETED",
      message: "Employee record is deleted/archived",
    };
  }

  if (employee.suspended) {
    return {
      ok: false,
      code: "EMPLOYEE_SUSPENDED",
      message: "Employee is suspended",
    };
  }

  if (employee.terminated) {
    return {
      ok: false,
      code: "EMPLOYEE_TERMINATED",
      message: "Employee is terminated",
    };
  }

  if (employee.inactive) {
    return {
      ok: false,
      code: "EMPLOYEE_INACTIVE",
      message: "Employee is inactive",
    };
  }

  if (!employee.verified) {
    return {
      ok: false,
      code: "EMPLOYEE_NOT_VERIFIED",
      message: "Employee is not verified yet",
    };
  }

  return { ok: true, code: "", message: "" };
}

async function fetchEmployeeForRequest(
  req,
  { preferStaffId = true, fallbackClinicId = "" } = {}
) {
  const token = getBearerToken(req);
  const tokenUserId = s(req.user?.userId);
  const staffCandidates = getStaffCandidates(req);

  let raw = null;
  let lastHardError = null;
  let saw429 = false;

  const tryByStaff = async (candidateStaffId) => {
    try {
      return await memoizedGetEmployeeByStaffId(req, candidateStaffId, token);
    } catch (e) {
      if (isTooManyRequestsError(e)) {
        saw429 = true;
        return null;
      }
      if (!shouldContinueLookupAfterError(e)) lastHardError = e;
      return null;
    }
  };

  const tryByUser = async (candidateUserId) => {
    try {
      return await memoizedGetEmployeeByUserId(req, candidateUserId, token);
    } catch (e) {
      if (isTooManyRequestsError(e)) {
        saw429 = true;
        return null;
      }
      if (!shouldContinueLookupAfterError(e)) lastHardError = e;
      return null;
    }
  };

  if (preferStaffId) {
    for (const sid of staffCandidates) {
      raw = await tryByStaff(sid);
      if (raw || lastHardError) break;
    }
  }

  if (!raw && !lastHardError && tokenUserId) {
    raw = await tryByUser(tokenUserId);
  }

  if (!raw && !lastHardError && !preferStaffId) {
    for (const sid of staffCandidates) {
      raw = await tryByStaff(sid);
      if (raw || lastHardError) break;
    }
  }

  if (!raw && lastHardError) throw lastHardError;
  if (!raw && saw429) {
    return buildFallbackEmployeeFromToken(req, fallbackClinicId);
  }

  return normalizeEmployeeRecord(raw);
}

async function ensureVerifiedEmployeeFromRequest(req, fallbackClinicId = "") {
  const memo = createRequestMemo(req);

  const cacheKey = [
    s(fallbackClinicId || req.user?.clinicId),
    s(req.user?.userId),
    s(req.user?.staffId),
    getBodyStaffId(req),
  ].join("|");

  if (memo.verifiedEmployee && memo.verifiedEmployee.key === cacheKey) {
    return memo.verifiedEmployee.value;
  }

  const tokenClinicId = s(fallbackClinicId || req.user?.clinicId);
  const tokenStaffId = s(req.user?.staffId);
  const tokenUserId = s(req.user?.userId);
  const bodyStaffId = getBodyStaffId(req);

  let employee = null;

  try {
    employee = await fetchEmployeeForRequest(req, {
      preferStaffId: true,
      fallbackClinicId: tokenClinicId,
    });
  } catch (e) {
    const out = isTooManyRequestsError(e)
      ? buildBusyEmployeeServiceResponse({
          tokenUserId,
          tokenStaffId,
          bodyStaffId,
          tokenClinicId,
        })
      : buildCodeResponse(
          Number(e?.status || 503),
          "EMPLOYEE_LOOKUP_FAILED",
          e?.message || "Cannot verify employee from token",
          { tokenUserId, tokenStaffId, bodyStaffId, tokenClinicId }
        );

    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  if (!employee) {
    const out = buildCodeResponse(
      404,
      "EMPLOYEE_NOT_FOUND",
      "Employee not found",
      {
        tokenUserId,
        tokenStaffId,
        bodyStaffId,
        tokenClinicId,
      }
    );
    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  const allow = isEmployeeAttendanceAllowed(employee);
  if (!allow.ok) {
    const out = buildCodeResponse(403, allow.code, allow.message, {
      tokenUserId,
      tokenStaffId,
      bodyStaffId,
      tokenClinicId,
    });
    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  if (
    bodyStaffId &&
    employee.staffId &&
    employee.staffId !== bodyStaffId &&
    !employee._fallback
  ) {
    const out = buildCodeResponse(
      403,
      "REQUEST_STAFF_MISMATCH",
      "Requested staffId does not match employee record",
      {
        requestStaffId: bodyStaffId,
        employeeStaffId: employee.staffId,
      }
    );
    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  if (
    tokenStaffId &&
    employee.staffId &&
    employee.staffId !== tokenStaffId &&
    !employee._fallback
  ) {
    const out = buildCodeResponse(
      403,
      "EMPLOYEE_STAFF_MISMATCH",
      "Token staffId does not match employee record",
      {
        tokenStaffId,
        employeeStaffId: employee.staffId,
      }
    );
    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  if (
    tokenUserId &&
    employee.userId &&
    employee.userId !== tokenUserId &&
    !employee._fallback
  ) {
    const out = buildCodeResponse(
      403,
      "EMPLOYEE_USER_MISMATCH",
      "Token userId does not match employee record",
      {
        tokenUserId,
        employeeUserId: employee.userId,
      }
    );
    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  if (
    tokenClinicId &&
    employee.clinicId &&
    employee.clinicId !== tokenClinicId &&
    !employee._fallback
  ) {
    const out = buildCodeResponse(
      403,
      "EMPLOYEE_CLINIC_MISMATCH",
      "Employee does not belong to this clinic",
      {
        tokenClinicId,
        employeeClinicId: employee.clinicId,
      }
    );
    memo.verifiedEmployee = { key: cacheKey, value: out };
    return out;
  }

  const out = {
    ok: true,
    employee,
    clinicId: employee.clinicId || tokenClinicId,
    userId: employee.userId || tokenUserId,
    staffId: employee.staffId || tokenStaffId || bodyStaffId,
  };

  memo.verifiedEmployee = { key: cacheKey, value: out };
  return out;
}

async function ensureSessionEmployeeAccess(req, session) {
  const token = getBearerToken(req);
  const tokenStaffId = s(req.user?.staffId);
  const tokenUserId = s(req.user?.userId);
  const tokenClinicId = s(req.user?.clinicId);
  const sessionStaffId = s(session?.staffId);
  const sessionUserId = s(session?.userId);
  const sessionClinicId = s(session?.clinicId);
  const bodyStaffId = getBodyStaffId(req);

  let raw = null;
  let saw429 = false;

  if (sessionStaffId) {
    try {
      raw = await memoizedGetEmployeeByStaffId(req, sessionStaffId, token);
    } catch (e) {
      if (isTooManyRequestsError(e)) {
        saw429 = true;
      } else if (!shouldContinueLookupAfterError(e)) {
        return buildCodeResponse(
          Number(e?.status || 503),
          "SESSION_EMPLOYEE_LOOKUP_FAILED",
          e?.message || "Cannot verify employee session"
        );
      }
    }
  }

  if (!raw && sessionUserId) {
    try {
      raw = await memoizedGetEmployeeByUserId(req, sessionUserId, token);
    } catch (e) {
      if (isTooManyRequestsError(e)) {
        saw429 = true;
      } else if (!shouldContinueLookupAfterError(e)) {
        return buildCodeResponse(
          Number(e?.status || 503),
          "SESSION_EMPLOYEE_LOOKUP_FAILED",
          e?.message || "Cannot verify employee session"
        );
      }
    }
  }

  if (!raw && saw429) {
    const fallbackEmployee = buildFallbackEmployeeFromToken(
      req,
      sessionClinicId || tokenClinicId
    );

    if (!fallbackEmployee) return buildBusyEmployeeServiceResponse();

    if (
      sessionStaffId &&
      fallbackEmployee.staffId &&
      fallbackEmployee.staffId !== sessionStaffId
    ) {
      return buildCodeResponse(
        403,
        "SESSION_EMPLOYEE_STAFF_MISMATCH",
        "Session staffId does not match employee record"
      );
    }

    if (
      sessionUserId &&
      fallbackEmployee.userId &&
      fallbackEmployee.userId !== sessionUserId
    ) {
      return buildCodeResponse(
        403,
        "SESSION_EMPLOYEE_USER_MISMATCH",
        "Session userId does not match employee record"
      );
    }

    if (
      sessionClinicId &&
      fallbackEmployee.clinicId &&
      fallbackEmployee.clinicId !== sessionClinicId
    ) {
      return buildCodeResponse(
        403,
        "SESSION_EMPLOYEE_CLINIC_MISMATCH",
        "Session clinicId does not match employee record"
      );
    }

    return { ok: true, employee: fallbackEmployee };
  }

  const employee = normalizeEmployeeRecord(raw);
  if (!employee) {
    return buildCodeResponse(
      404,
      "SESSION_EMPLOYEE_NOT_FOUND",
      "Employee not found for this session"
    );
  }

  const allow = isEmployeeAttendanceAllowed(employee);
  if (!allow.ok) return buildCodeResponse(403, allow.code, allow.message);

  if (bodyStaffId && employee.staffId && employee.staffId !== bodyStaffId) {
    return buildCodeResponse(
      403,
      "REQUEST_STAFF_MISMATCH",
      "Requested staffId does not match employee record",
      {
        requestStaffId: bodyStaffId,
        employeeStaffId: employee.staffId,
      }
    );
  }

  if (sessionStaffId && employee.staffId && employee.staffId !== sessionStaffId) {
    return buildCodeResponse(
      403,
      "SESSION_EMPLOYEE_STAFF_MISMATCH",
      "Session staffId does not match employee record"
    );
  }

  if (sessionUserId && employee.userId && employee.userId !== sessionUserId) {
    return buildCodeResponse(
      403,
      "SESSION_EMPLOYEE_USER_MISMATCH",
      "Session userId does not match employee record"
    );
  }

  if (sessionClinicId && employee.clinicId && employee.clinicId !== sessionClinicId) {
    return buildCodeResponse(
      403,
      "SESSION_EMPLOYEE_CLINIC_MISMATCH",
      "Session clinicId does not match employee record"
    );
  }

  if (tokenStaffId && employee.staffId && tokenStaffId !== employee.staffId) {
    return buildCodeResponse(
      403,
      "TOKEN_EMPLOYEE_STAFF_MISMATCH",
      "Current user is not the owner of this employee session"
    );
  }

  if (tokenUserId && employee.userId && tokenUserId !== employee.userId) {
    return buildCodeResponse(
      403,
      "TOKEN_EMPLOYEE_USER_MISMATCH",
      "Current user is not the owner of this employee session"
    );
  }

  if (tokenClinicId && employee.clinicId && tokenClinicId !== employee.clinicId) {
    return buildCodeResponse(
      403,
      "TOKEN_EMPLOYEE_CLINIC_MISMATCH",
      "Current user clinic does not match employee clinic"
    );
  }

  return { ok: true, employee };
}
function rejectIfMockLocationAnywhere(req) {
  const inMock = isMockLocation(req, "in");
  const outMock = isMockLocation(req, "out");

  if (inMock || outMock) {
    return buildCodeResponse(
      400,
      "FAKE_GPS_DETECTED",
      "ตรวจพบการใช้ตำแหน่งปลอม (Mock Location) ระบบไม่อนุญาตให้ลงเวลา"
    );
  }

  return null;
}

async function resolveSelfClinicFilter(req, fallbackClinicId = "") {
  const role = s(req.user?.role);
  const requestedClinicId =
    s(req.query?.clinicId) ||
    s(req.body?.clinicId) ||
    s(req.params?.clinicId);

  if (role === "helper") {
    return {
      ok: true,
      clinicId: requestedClinicId || "",
      scope: requestedClinicId ? "requested" : "all",
    };
  }

  if (role === "employee" || role === "staff") {
    const verify = await ensureVerifiedEmployeeFromRequest(req, fallbackClinicId);
    if (!verify.ok) {
      return { ok: false, status: verify.status, body: verify.body };
    }
    return {
      ok: true,
      clinicId: s(verify.clinicId),
      scope: "employee_home_clinic",
    };
  }

  return {
    ok: true,
    clinicId: requestedClinicId || s(fallbackClinicId),
    scope: requestedClinicId ? "requested" : "token_default",
  };
}

function buildHelperShiftUserOr(userId) {
  const uid = s(userId);
  if (!uid) return [];
  return [
    { helperUserId: uid },
    { userId: uid },
    { helperId: uid },
    { assignedUserId: uid },
    { acceptedHelperUserId: uid },
    { selectedHelperUserId: uid },
    { bookedHelperUserId: uid },
    { "helper.userId": uid },
    { "helper.id": uid },
    { "helper._id": uid },
  ];
}

function dedupeShifts(shifts) {
  const out = [];
  const seen = new Set();

  for (const sh of Array.isArray(shifts) ? shifts : []) {
    const key = String(sh?._id || sh?.id || "");
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(sh);
  }

  return out;
}

function getNestedValue(obj, path) {
  return String(path || "")
    .split(".")
    .filter(Boolean)
    .reduce((acc, key) => (acc == null ? undefined : acc[key]), obj);
}

function valuesToComparableSet(value) {
  const out = new Set();

  const pushOne = (v) => {
    if (v == null) return;

    if (Array.isArray(v)) {
      v.forEach(pushOne);
      return;
    }

    if (typeof v === "object") {
      if (v._id != null) pushOne(v._id);
      if (v.id != null) pushOne(v.id);
      if (v.userId != null) pushOne(v.userId);
      if (v.staffId != null) pushOne(v.staffId);
      return;
    }

    const text = s(v);
    if (text) out.add(text);
  };

  pushOne(value);
  return out;
}

function shiftBelongsToHelper(
  shift,
  { principalId = "", userId = "", staffId = "" }
) {
  if (!shift || typeof shift !== "object") return false;

  const wanted = new Set(
    [s(principalId), s(userId), s(staffId)].filter(Boolean)
  );
  if (!wanted.size) return false;

  const candidatePaths = [
    "principalId",
    "userId",
    "helperUserId",
    "helperId",
    "assignedUserId",
    "acceptedHelperUserId",
    "selectedHelperUserId",
    "bookedHelperUserId",
    "staffId",
    "employeeId",
    "helper.userId",
    "helper.id",
    "helper._id",
  ];

  for (const path of candidatePaths) {
    const values = valuesToComparableSet(getNestedValue(shift, path));
    for (const one of values) {
      if (wanted.has(one)) return true;
    }
  }

  return false;
}

function extractShiftClinicName(shift) {
  return s(
    shift?.clinicName ||
      shift?.clinic?.name ||
      shift?.clinic?.clinicName ||
      shift?.clinic?.title ||
      shift?.locationName ||
      shift?.workplaceName ||
      shift?.hospitalName
  );
}

function extractShiftTitle(shift) {
  return s(
    shift?.title ||
      shift?.shiftTitle ||
      shift?.position ||
      shift?.roleName ||
      shift?.jobTitle
  );
}

function validateExplicitShiftForHelper({
  shift,
  workDate,
  principalId,
  userId,
  staffId,
}) {
  if (!shift) {
    return buildCodeResponse(404, "SHIFT_NOT_FOUND", "ไม่พบกะงานที่เลือก");
  }

  if (!shiftBelongsToHelper(shift, { principalId, userId, staffId })) {
    return buildCodeResponse(
      403,
      "SHIFT_NOT_ASSIGNED_TO_HELPER",
      "กะงานนี้ไม่ได้ถูกมอบหมายให้ผู้ใช้งานคนนี้"
    );
  }

  const shiftDate = s(shift.date);
  if (isYmd(workDate) && shiftDate && shiftDate !== workDate) {
    return buildCodeResponse(
      409,
      "SHIFT_DATE_MISMATCH",
      "กะงานที่เลือกไม่ตรงกับวันที่สแกน",
      {
        requestedWorkDate: workDate,
        shiftDate,
      }
    );
  }

  const shiftClinicId = s(shift.clinicId);
  if (!shiftClinicId) {
    return buildCodeResponse(
      409,
      "SHIFT_CLINIC_MISSING",
      "กะงานที่เลือกไม่มี clinicId"
    );
  }

  return {
    ok: true,
    shift,
    clinicId: shiftClinicId,
  };
}

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

function pickBestShiftForTime(shifts, now = new Date()) {
  if (!Array.isArray(shifts) || !shifts.length) return null;

  const prepared = shifts
    .map((sh) => ({
      sh,
      startAt: getShiftStartDateTime(sh),
      endAt: getShiftEndDateTime(sh),
    }))
    .filter((x) => x.startAt && x.endAt);

  if (!prepared.length) return shifts[0] || null;

  const active = prepared.filter(
    (x) =>
      now.getTime() >= x.startAt.getTime() &&
      now.getTime() <= x.endAt.getTime()
  );

  if (active.length === 1) return active[0].sh;

  if (active.length > 1) {
    return { _conflict: true, candidates: active.map((x) => x.sh) };
  }

  const near = prepared
    .map((x) => ({
      ...x,
      distanceMs: Math.min(
        Math.abs(now.getTime() - x.startAt.getTime()),
        Math.abs(now.getTime() - x.endAt.getTime())
      ),
    }))
    .sort((a, b) => a.distanceMs - b.distanceMs);

  return near[0]?.sh || null;
}

function normalizeShiftClinicId(shift) {
  return s(
    shift?.clinicId ||
      shift?.clinic?._id ||
      shift?.clinic?.id ||
      shift?.clinic?.clinicId
  );
}

function normalizeShiftDate(shift) {
  return s(shift?.date || shift?.workDate || shift?.shiftDate);
}

function normalizeShiftTimeValue(value) {
  const text = s(value);
  return isHHmm(text) ? text : "";
}

function normalizeShiftLite(shift) {
  if (!shift || typeof shift !== "object") return null;

  const _id = s(shift._id || shift.id);
  if (!_id) return null;

  const clinicId = normalizeShiftClinicId(shift);
  const date = normalizeShiftDate(shift);
  const start = normalizeShiftTimeValue(shift.start || shift.startTime);
  const end = normalizeShiftTimeValue(shift.end || shift.endTime);

  return {
    ...shift,
    _id,
    id: _id,
    clinicId,
    date,
    start,
    end,
    clinicName: extractShiftClinicName(shift),
    title: extractShiftTitle(shift),
  };
}

function getShiftMemoKey({
  clinicId = "",
  staffId = "",
  userId = "",
  workDate = "",
  shiftId = "",
}) {
  return [s(clinicId), s(staffId), s(userId), s(workDate), s(shiftId)].join(
    "|"
  );
}

async function loadShiftCandidatesForSession({
  clinicId,
  staffId,
  userId,
  workDate,
  shiftId,
}) {
  const normalizedShiftId = normalizeObjectIdString(shiftId);
  if (normalizedShiftId) {
    const one = await Shift.findById(normalizedShiftId).lean();
    const lite = normalizeShiftLite(one);
    return lite ? [lite] : [];
  }

  const cid = s(clinicId);
  const date = s(workDate);
  const sid = s(staffId);
  const uid = s(userId);

  if (!date) return [];

  const queries = [];

  if (sid) {
    const q = { date, staffId: sid };
    if (cid) q.clinicId = cid;
    queries.push(q);
  }

  const helperOr = buildHelperShiftUserOr(uid);
  if (helperOr.length) {
    const q = { date, $or: helperOr };
    if (cid) q.clinicId = cid;
    queries.push(q);
  }

  if (!queries.length) return [];

  const results = await Promise.all(
    queries.map((q) =>
      Shift.find(q).sort({ start: 1, createdAt: -1 }).lean()
    )
  );

  return dedupeShifts(results.flat().map(normalizeShiftLite).filter(Boolean));
}

async function loadShiftForSession({
  clinicId,
  staffId,
  userId,
  workDate,
  shiftId,
}) {
  const normalizedShiftId = normalizeObjectIdString(shiftId);
  if (normalizedShiftId) {
    const sh = await Shift.findById(normalizedShiftId).lean();
    return normalizeShiftLite(sh);
  }

  const candidates = await loadShiftCandidatesForSession({
    clinicId,
    staffId,
    userId,
    workDate,
    shiftId: "",
  });

  if (!candidates.length) return null;

  const picked = pickBestShiftForTime(candidates, new Date());
  if (picked?._conflict) return null;

  return normalizeShiftLite(picked || null);
}

async function loadHelperAssignedShifts(
  req,
  { userId, workDate, clinicId = "" }
) {
  const memo = createRequestMemo(req);
  const key = getShiftMemoKey({
    clinicId,
    staffId: "",
    userId,
    workDate,
    shiftId: "",
  });

  if (memo.helperShiftAssignments.has(key)) {
    return memo.helperShiftAssignments.get(key);
  }

  let items = await loadShiftCandidatesForSession({
    clinicId,
    staffId: "",
    userId,
    workDate,
    shiftId: "",
  });

  if (!items.length && clinicId) {
    items = await loadShiftCandidatesForSession({
      clinicId: "",
      staffId: "",
      userId,
      workDate,
      shiftId: "",
    });
  }

  const out = dedupeShifts(items.map(normalizeShiftLite).filter(Boolean));
  memo.helperShiftAssignments.set(key, out);
  return out;
}

function buildRuntimeShiftSnapshot(shift) {
  const sh = normalizeShiftLite(shift);
  if (!sh) return null;

  return {
    _id: s(sh._id),
    id: s(sh.id || sh._id),
    clinicId: s(sh.clinicId),
    clinicName: s(sh.clinicName),
    date: s(sh.date),
    start: s(sh.start),
    end: s(sh.end),
    title: s(sh.title),
    clinicLat: n(sh.clinicLat, null),
    clinicLng: n(sh.clinicLng, null),
  };
}

function buildRuntimeAvailableShifts(shifts) {
  return dedupeShifts(
    (Array.isArray(shifts) ? shifts : [])
      .map(buildRuntimeShiftSnapshot)
      .filter(Boolean)
  );
}

async function resolveHelperShiftForRuntime(
  req,
  {
    principalId,
    userId,
    staffId,
    workDate,
    explicitShiftId = "",
    fallbackClinicId = "",
  }
) {
  const normalizedExplicitShiftId = normalizeObjectIdString(explicitShiftId);

  if (normalizedExplicitShiftId) {
    const explicitShift = await loadShiftForSession({
      clinicId: "",
      staffId,
      userId,
      workDate,
      shiftId: normalizedExplicitShiftId,
    });

    const explicitCheck = validateExplicitShiftForHelper({
      shift: explicitShift,
      workDate,
      principalId,
      userId,
      staffId,
    });

    if (!explicitCheck.ok) return explicitCheck;

    const selected = buildRuntimeShiftSnapshot(explicitCheck.shift);

    return {
      ok: true,
      shift: selected,
      clinicId: s(explicitCheck.clinicId),
      shiftSelectionMode: "explicit",
      availableShifts: selected ? [selected] : [],
    };
  }

  let candidates = await loadHelperAssignedShifts(req, {
    userId,
    workDate,
    clinicId: fallbackClinicId,
  });

  if (!candidates.length && fallbackClinicId) {
    candidates = await loadHelperAssignedShifts(req, {
      userId,
      workDate,
      clinicId: "",
    });
  }

  if (!candidates.length) {
    return buildCodeResponse(409, "NO_SHIFT_TODAY", "วันนี้ไม่มีตารางงาน", {
      workDate,
    });
  }

  if (candidates.length === 1) {
    const only = buildRuntimeShiftSnapshot(candidates[0]);
    return {
      ok: true,
      shift: only,
      clinicId: s(only?.clinicId),
      shiftSelectionMode: "single_auto",
      availableShifts: only ? [only] : [],
    };
  }

  const picked = pickBestShiftForTime(candidates, new Date());

  if (picked?._conflict) {
    return buildCodeResponse(
      409,
      "MULTIPLE_ACTIVE_SHIFTS",
      "พบหลายกะงานในช่วงเวลาเดียวกัน กรุณาเลือกกะงาน/คลินิกก่อนสแกน",
      {
        workDate,
        candidates: buildRuntimeAvailableShifts(picked.candidates || []),
      }
    );
  }

  const pickedShift = buildRuntimeShiftSnapshot(picked);
  if (!pickedShift) {
    return buildCodeResponse(
      409,
      "SHIFT_NOT_RESOLVED",
      "ไม่สามารถระบุกะงานที่กำลังทำอยู่ได้ กรุณาเลือกกะงานก่อนสแกน",
      {
        workDate,
        candidates: buildRuntimeAvailableShifts(candidates),
      }
    );
  }

  return {
    ok: true,
    shift: pickedShift,
    clinicId: s(pickedShift.clinicId),
    shiftSelectionMode: "time_auto",
    availableShifts: buildRuntimeAvailableShifts(candidates),
  };
}

async function findPreviousOpenSession({ principalId, workDate }) {
  return AttendanceSession.findOne({
    principalId: s(principalId),
    status: "open",
    workDate: { $lt: workDate },
  })
    .sort({ workDate: -1, checkInAt: -1 })
    .lean();
}

async function findPreviousPendingManualSession({ principalId, workDate }) {
  return AttendanceSession.findOne({
    principalId: s(principalId),
    status: "pending_manual",
    approvalStatus: "pending",
    workDate: { $lt: workDate },
  })
    .sort({ workDate: -1, requestedAt: -1, createdAt: -1 })
    .lean();
}

function toBlockedPreviousSessionPayload(session) {
  if (!session) return null;

  const shiftId =
    typeof session.shiftId === "object"
      ? s(session.shiftId?._id || session.shiftId?.id)
      : s(session.shiftId);

  const clinicName = s(session.clinicName || extractClinicDisplayName(session));
  const shiftName = s(session.shiftName || extractShiftDisplayName(session));
  const routeHint =
    s(session.status) === "pending_manual"
      ? buildManualRequestRouteHint(session)
      : buildResolveAttendanceRouteHint(session);

  return {
    sessionId: String(session._id || ""),
    clinicId: s(session.clinicId),
    clinicName,
    workDate: s(session.workDate),
    shiftId,
    shiftName,
    status: s(session.status),
    approvalStatus: s(session.approvalStatus),
    manualRequestType: s(session.manualRequestType),
    requestedAt: session.requestedAt || null,
    checkInAt: session.checkInAt || null,
    checkOutAt: session.checkOutAt || null,
    routeHint,
  };
}

function buildPreviousAttendancePendingResponse(previousSession) {
  const previous = toBlockedPreviousSessionPayload(previousSession);
  const routeHint =
    previous?.routeHint ||
    buildResolveAttendanceRouteHint(previousSession || {});

  return buildCodeResponse(
    409,
    "PREVIOUS_ATTENDANCE_PENDING",
    "ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาส่งคำขอแก้ไขรายการเดิมและรออนุมัติก่อนจึงจะเริ่มรายการใหม่ได้",
    {
      action: "REQUIRE_FIX_PREVIOUS",
      nextAction: routeHint.action,
      routeHint,
      previousSession: previous,
      pendingContext: previous,
      previousSessionId: previous?.sessionId || "",
      previousClinicId: previous?.clinicId || "",
      previousClinicName: previous?.clinicName || "",
      previousWorkDate: previous?.workDate || "",
      previousShiftId: previous?.shiftId || "",
      previousShiftName: previous?.shiftName || "",
    }
  );
}

async function findOpenSessionsForPrincipal({
  principalId = "",
  userId = "",
  staffId = "",
  workDate = "",
  clinicId = "",
  shiftId = "",
}) {
  const actorOr = buildAttendanceActorOr({ principalId, userId, staffId });
  if (!actorOr.length) return [];

  const q = {
    status: "open",
    $or: actorOr,
  };

  if (isYmd(workDate)) q.workDate = workDate;
  if (s(clinicId)) q.clinicId = s(clinicId);

  const normalizedShiftId = normalizeObjectIdString(shiftId);
  if (normalizedShiftId) {
    q.$and = [buildShiftMatchClause(normalizedShiftId)];
  }

  return AttendanceSession.find(q).sort({ checkInAt: -1 }).lean();
}

function getCutoffDateTime(workDate, cutoffTime) {
  const cutoff = isHHmm(cutoffTime) ? cutoffTime : "03:00";
  const base = makeLocalDateTime(workDate, cutoff);
  return new Date(base.getTime() + 24 * 60 * 60000);
}

function computeLateMinutes(policy, shift, checkInAt) {
  if (!shift || !isYmd(shift.date) || !isHHmm(shift.start)) return 0;
  const shiftStart = makeLocalDateTime(shift.date, shift.start);
  return clampMinutes(
    Math.max(
      0,
      minutesDiff(shiftStart, checkInAt) -
        clampMinutes(policy.graceLateMinutes)
    )
  );
}

function computeWorkedMinutes(checkInAt, checkOutAt) {
  if (!checkInAt || !checkOutAt) return 0;
  return clampMinutes(minutesDiff(checkInAt, checkOutAt));
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

    return roundOtMinutes(
      Math.max(0, minutesDiff(otStartAt, checkOutAt)),
      policy.otRounding
    );
  }

  if (rule === "AFTER_CLOCK_TIME") {
    const baseDate = shift?.date && isYmd(shift.date) ? shift.date : null;
    if (!baseDate) return 0;

    if (isHHmm(policy.otWindowStart) && isHHmm(policy.otWindowEnd)) {
      let windowStartAt = makeLocalDateTime(baseDate, policy.otWindowStart);
      let windowEndAt = makeLocalDateTime(baseDate, policy.otWindowEnd);

      if (windowEndAt.getTime() <= windowStartAt.getTime()) {
        windowEndAt = new Date(windowEndAt.getTime() + 24 * 60 * 60000);
      }

      return roundOtMinutes(
        computeWindowOverlapMinutes(
          windowStartAt,
          windowEndAt,
          checkInAt,
          checkOutAt
        ),
        policy.otRounding
      );
    }

    const clock = isHHmm(policy.otClockTime) ? policy.otClockTime : "18:00";
    const clockAt = makeLocalDateTime(baseDate, clock);
    const otStartAt = new Date(
      clockAt.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    return roundOtMinutes(
      Math.max(0, minutesDiff(otStartAt, checkOutAt)),
      policy.otRounding
    );
  }

  if (rule === "AFTER_DAILY_HOURS") {
    const worked = computeWorkedMinutes(checkInAt, checkOutAt);
    const regular = clampMinutes(Number(policy.regularHoursPerDay || 8) * 60);
    return roundOtMinutes(Math.max(0, worked - regular), policy.otRounding);
  }

  return 0;
}

function normalizeEmploymentType(v) {
  const t = s(v).toLowerCase();
  if (!t) return "";
  if (["fulltime", "full_time", "full-time", "ft"].includes(t)) {
    return "fullTime";
  }
  if (["parttime", "part_time", "part-time", "pt"].includes(t)) {
    return "partTime";
  }
  return s(v);
}

function pickOtClockByType(policy, empTypeRaw) {
  const empType = normalizeEmploymentType(empTypeRaw);
  const legacy = isHHmm(policy?.otClockTime) ? policy.otClockTime : "18:00";

  if (empType === "fullTime") {
    return isHHmm(policy?.fullTimeOtClockTime)
      ? policy.fullTimeOtClockTime
      : legacy;
  }

  if (empType === "partTime") {
    return isHHmm(policy?.partTimeOtClockTime)
      ? policy.partTimeOtClockTime
      : legacy;
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

  return checkInAt.getTime() < getClinicOpenDateTime(workDate, policy).getTime();
}

function detectEarlyCheckOut({ policy, shift, checkOutAt, role, workDate }) {
  const rules = attendanceRuleDefaults(policy);
  if (!rules.requireReasonForEarlyCheckOut) return false;

  if (s(role) === "helper") {
    const endAt = getShiftEndDateTime(shift);
    if (!endAt) return false;
    return checkOutAt.getTime() < endAt.getTime();
  }

  return checkOutAt.getTime() < getClinicCloseDateTime(workDate, policy).getTime();
}

function detectLeftEarlyMinutes({
  shift,
  checkOutAt,
  toleranceMinutes = 0,
  role,
  policy,
  workDate,
}) {
  const endAt =
    s(role) === "helper"
      ? getShiftEndDateTime(shift)
      : getClinicCloseDateTime(workDate, policy);

  if (!endAt || !checkOutAt) return 0;

  return clampMinutes(
    Math.max(
      0,
      minutesDiff(checkOutAt, endAt) - clampMinutes(toleranceMinutes)
    )
  );
}

function hasEarlyCheckoutReason(req) {
  return (
    !!s(req.body?.reasonCode) ||
    !!s(req.body?.reasonText) ||
    !!s(req.body?.note)
  );
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
  const worked = clampMinutes(
    computeWorkedMinutes(session.checkInAt, checkOutAt)
  );

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
  return {
    clinicId,
    clinicName: s(shift?.clinicName),
    shiftName: s(shift?.title),
    principalId,
    principalType,
    staffId: staffId || "",
    userId: userId || "",
    helperUserId: userId || "",
    actorUserId: userId || "",
    assignedUserId: userId || "",
    helperId: userId || "",

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

    ...getScheduleSnapshot({ policy, shift, workDate }),
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
  const q = { manualRequestType: { $ne: "" } };

  if (s(clinicId)) q.clinicId = s(clinicId);
  if (s(principalId)) q.principalId = s(principalId);
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

async function syncOvertimeForSession({ session, policy, shift }) {
  try {
    const ownerUserId = s(session.userId);
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

function buildRuntimeSessionQuery({
  clinicId,
  principalId,
  userId,
  staffId,
  workDate,
  shiftId = "",
}) {
  const q = {
    clinicId: s(clinicId),
    $or: buildAttendanceActorOr({ principalId, userId, staffId }),
    workDate: s(workDate),
  };

  const normalizedShiftId = normalizeObjectIdString(shiftId);
  if (normalizedShiftId) {
    q.$and = [buildShiftMatchClause(normalizedShiftId)];
  }

  return q;
}

async function resolveRuntimeContext(req, workDate, shiftId = null) {
  const memo = createRequestMemo(req);
  const runtimeKey = makeRuntimeContextKey(req, workDate, shiftId);

  if (memo.runtimeContext.has(runtimeKey)) {
    return memo.runtimeContext.get(runtimeKey);
  }

  const {
    clinicId,
    role,
    userId,
    staffId,
    principalId,
    principalType,
  } = getPrincipal(req);

  if (!principalId) {
    const out = {
      ok: false,
      status: 401,
      body: { ok: false, message: "Missing userId/staffId in token" },
    };
    memo.runtimeContext.set(runtimeKey, out);
    return out;
  }

  let effectiveClinicId = s(clinicId);
  let effectiveUserId = s(userId);
  let effectiveStaffId = s(staffId);
  let shift = null;
  let employee = null;
  let availableShifts = [];
  let shiftSelectionMode = "";

  if (role === "employee" || role === "staff") {
    const verify = await ensureVerifiedEmployeeFromRequest(req, effectiveClinicId);
    if (!verify.ok) {
      const out = { ok: false, status: verify.status, body: verify.body };
      memo.runtimeContext.set(runtimeKey, out);
      return out;
    }

    employee = verify.employee;
    effectiveClinicId = s(verify.clinicId);
    effectiveUserId = s(verify.userId);
    effectiveStaffId = s(verify.staffId);

    if (!effectiveClinicId) {
      const out = {
        ok: false,
        status: 401,
        body: { ok: false, message: "Cannot resolve clinicId for employee" },
      };
      memo.runtimeContext.set(runtimeKey, out);
      return out;
    }
  } else if (role === "helper") {
    const helperShiftResult = await resolveHelperShiftForRuntime(req, {
      principalId,
      userId: effectiveUserId,
      staffId: effectiveStaffId,
      workDate,
      explicitShiftId: shiftId,
      fallbackClinicId: effectiveClinicId,
    });

    if (!helperShiftResult.ok) {
      const out = {
        ok: false,
        status: helperShiftResult.status,
        body: helperShiftResult.body,
      };
      memo.runtimeContext.set(runtimeKey, out);
      return out;
    }

    shift = buildRuntimeShiftSnapshot(helperShiftResult.shift);
    availableShifts = buildRuntimeAvailableShifts(
      helperShiftResult.availableShifts || []
    );
    shiftSelectionMode = s(helperShiftResult.shiftSelectionMode);
    effectiveClinicId = s(helperShiftResult.clinicId) || effectiveClinicId;

    if (!effectiveClinicId) {
      const out = {
        ok: false,
        status: 401,
        body: {
          ok: false,
          code: "SHIFT_CLINIC_MISSING",
          message: "Cannot resolve clinicId from helper shift",
        },
      };
      memo.runtimeContext.set(runtimeKey, out);
      return out;
    }
  } else {
    if (!effectiveClinicId) {
      const out = {
        ok: false,
        status: 401,
        body: { ok: false, message: "Missing clinicId" },
      };
      memo.runtimeContext.set(runtimeKey, out);
      return out;
    }
  }

  const out = {
    ok: true,
    role,
    userId: effectiveUserId,
    staffId: effectiveStaffId,
    principalId,
    principalType,
    clinicId: effectiveClinicId,
    shift,
    employee,
    availableShifts,
    shiftSelectionMode,
  };

  memo.runtimeContext.set(runtimeKey, out);
  return out;
}
async function checkIn(req, res) {
  try {
    const mockErr = rejectIfMockLocationAnywhere(req);
    if (mockErr) return res.status(mockErr.status).json(mockErr.body);

    const workDate = s(req.body?.workDate);
    const shiftId = getRequestedShiftId(req);

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
      availableShifts,
      shiftSelectionMode,
    } = ctx;

    let shift = buildRuntimeShiftSnapshot(ctx.shift) || null;

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);
    const rules = attendanceRuleDefaults(policy);

    if (mustRespectClinicHours(role) && !isClinicOpenDay(policy, workDate)) {
      return res.status(409).json({
        ok: false,
        code: "CLINIC_CLOSED_DAY",
        message: "วันนี้คลินิกปิดทำการ",
        workDate,
        clinicId,
      });
    }

    const previousOpen = rules.blockNewCheckInIfPreviousOpen
      ? await findPreviousOpenSession({ principalId, workDate })
      : null;

    if (previousOpen) {
      const out = buildPreviousAttendancePendingResponse(previousOpen);
      return res.status(out.status).json(out.body);
    }

    const previousPendingManual = await findPreviousPendingManualSession({
      principalId,
      workDate,
    });

    if (previousPendingManual) {
      const out = buildPreviousAttendancePendingResponse(previousPendingManual);
      return res.status(out.status).json(out.body);
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

    if (!shift && role === "helper") {
      return res.status(409).json({
        ok: false,
        code: "SHIFT_NOT_RESOLVED",
        message: "ไม่สามารถระบุกะงานที่กำลังทำอยู่ได้ กรุณาเลือกกะงานก่อนสแกน",
        workDate,
        availableShifts,
      });
    }

    if (!shift) {
      shift = buildRuntimeShiftSnapshot(
        await loadShiftForSession({
          clinicId,
          staffId,
          userId,
          workDate,
          shiftId,
        })
      );
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);
    const inLocationSource = getLocationSource(req, "in");
    const inMocked = isMockLocation(req, "in");

    let inDistanceMeters = null;
    const requireLocation = shouldRequireLocationForAttendance(policy);

    if (requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        const out = buildLocationRequiredError();
        return res.status(out.status).json(out.body);
      }

      const ref = getReferenceCoordinateCandidates(shift, policy);
      if (!ref) {
        const out = buildLocationRequirementError();
        return res.status(out.status).json(out.body);
      }

      const dist = haversineMeters(ref.lat, ref.lng, lat, lng);
      inDistanceMeters = dist;
      const radius = getEnforcedGeoRadius(policy);

      if (dist > radius) {
        const out = buildOutsideRadiusError(dist, radius);
        return res.status(out.status).json(out.body);
      }
    }

    const existingOpenAnywhere = await findOpenSessionsForPrincipal({
      principalId,
      userId,
      staffId,
      workDate: "",
    });

    if (existingOpenAnywhere.length > 1) {
      return res.status(409).json({
        ok: false,
        code: "MULTIPLE_OPEN_SESSIONS",
        message:
          "พบ open session มากกว่าหนึ่งรายการ กรุณาให้ผู้ดูแลตรวจสอบข้อมูลก่อน",
        sessions: existingOpenAnywhere.map((x) =>
          toBlockedPreviousSessionPayload(x)
        ),
      });
    }

    if (existingOpenAnywhere.length === 1) {
      const open = existingOpenAnywhere[0];

      const openShiftId =
        typeof open.shiftId === "object"
          ? s(open.shiftId?._id || open.shiftId?.id)
          : s(open.shiftId);

      const sameClinic = s(open.clinicId) === s(clinicId);
      const sameWorkDate = s(open.workDate) === workDate;
      const sameShift =
        s(role) === "helper"
          ? !!s(shift?._id) && openShiftId === s(shift?._id)
          : true;

      if (sameClinic && sameWorkDate && sameShift) {
        return res.status(409).json({
          ok: false,
          code: "ALREADY_CHECKED_IN",
          message:
            role === "helper"
              ? "เช็คอินกะนี้แล้ว"
              : "เช็คอินวันนี้แล้ว",
          existingSessionId: String(open._id || ""),
          existingClinicId: s(open.clinicId),
          existingClinicName: s(
            open.clinicName || extractClinicDisplayName(open)
          ),
          existingWorkDate: s(open.workDate),
          existingShiftId: openShiftId,
          existingShiftName: s(
            open.shiftName || extractShiftDisplayName(open)
          ),
          routeHint: buildResolveAttendanceRouteHint(open),
        });
      }

      const out = buildPreviousAttendancePendingResponse(open);
      return res.status(out.status).json(out.body);
    }

    const sameDayBaseQuery = buildRuntimeSessionQuery({
      clinicId,
      principalId,
      userId,
      staffId,
      workDate,
      shiftId: role === "helper" ? s(shift?._id) : "",
    });

    const existingClosed = await AttendanceSession.findOne({
      ...sameDayBaseQuery,
      status: "closed",
    }).lean();

    if (existingClosed) {
      return res.status(409).json({
        ok: false,
        code: "ATTENDANCE_ALREADY_COMPLETED",
        message:
          role === "helper"
            ? "Attendance already completed for this shift/date"
            : "Attendance already completed for today",
        sessionId: String(existingClosed._id || ""),
        clinicId: s(existingClosed.clinicId),
        clinicName: s(
          existingClosed.clinicName || extractClinicDisplayName(existingClosed)
        ),
        workDate: s(existingClosed.workDate),
        shiftId:
          typeof existingClosed.shiftId === "object"
            ? s(existingClosed.shiftId?._id || existingClosed.shiftId?.id)
            : s(existingClosed.shiftId),
        shiftName: s(
          existingClosed.shiftName || extractShiftDisplayName(existingClosed)
        ),
        routeHint: buildResolveAttendanceRouteHint(existingClosed),
      });
    }

    const existingPendingManual = await AttendanceSession.findOne({
      ...sameDayBaseQuery,
      status: "pending_manual",
    }).lean();

    if (existingPendingManual) {
      return res.status(409).json({
        ok: false,
        code: "MANUAL_REQUEST_PENDING",
        message:
          role === "helper"
            ? "Manual attendance request is pending for this shift/date"
            : "Manual attendance request is pending for this date",
        sessionId: String(existingPendingManual._id || ""),
        clinicId: s(existingPendingManual.clinicId),
        clinicName: s(
          existingPendingManual.clinicName ||
            extractClinicDisplayName(existingPendingManual)
        ),
        workDate: s(existingPendingManual.workDate),
        shiftId:
          typeof existingPendingManual.shiftId === "object"
            ? s(
                existingPendingManual.shiftId?._id ||
                  existingPendingManual.shiftId?.id
              )
            : s(existingPendingManual.shiftId),
        shiftName: s(
          existingPendingManual.shiftName ||
            extractShiftDisplayName(existingPendingManual)
        ),
        routeHint: buildManualRequestRouteHint(existingPendingManual),
        pendingContext: toBlockedPreviousSessionPayload(existingPendingManual),
      });
    }

    const checkInAt = new Date();

    if (mustRespectClinicHours(role)) {
      const clinicOpenAt = getClinicOpenDateTime(workDate, policy);
      const clinicCloseAt = getClinicCloseDateTime(workDate, policy);

      if (checkInAt.getTime() < clinicOpenAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_NOT_OPEN",
          message: "คลินิกยังไม่เปิด",
          workDate,
          clinicId,
          openTime: pickClinicOpenTime(policy, workDate),
        });
      }

      if (checkInAt.getTime() > clinicCloseAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_ALREADY_CLOSED",
          message: "คลินิกปิดแล้ว",
          workDate,
          clinicId,
          closeTime: pickClinicCloseTime(policy, workDate),
        });
      }
    }

    if (
      method === "biometric" &&
      detectEarlyCheckIn({ policy, shift, checkInAt, role, workDate })
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

    const payload = {
      clinicId,
      clinicName: s(shift?.clinicName),
      shiftName: s(shift?.title),
      principalId,
      principalType,
      staffId: staffId || "",
      userId: userId || "",
      helperUserId: userId || "",
      actorUserId: userId || "",
      assignedUserId: userId || "",
      helperId: userId || "",

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

      ...getScheduleSnapshot({ policy, shift, workDate }),
    };

    const created = new AttendanceSession(payload);
    ensureSecurityFields(created);

    if (lateMinutes > 0) addSuspiciousFlag(created, "LATE_CHECKIN", 5);
    maybeFlagDistanceRisk(
      created,
      Number.isFinite(inDistanceMeters) ? inDistanceMeters : null,
      getEnforcedGeoRadius(policy)
    );

    await created.save();

    return res.status(201).json({
      ok: true,
      session: created,
      currentSessionId: String(created._id || ""),
      policy: buildPublicPolicy(policy, workDate),
      runtime: {
        role,
        clinicId,
        shift: shift || null,
        shiftSelectionMode: shiftSelectionMode || "",
        availableShifts,
      },
    });
  } catch (e) {
    console.log("❌ check-in failed:", e?.message || e);
    return res
      .status(500)
      .json({ ok: false, message: "check-in failed", error: e.message });
  }
}

async function checkOut(req, res) {
  try {
    const mockErr = rejectIfMockLocationAnywhere(req);
    if (mockErr) return res.status(mockErr.status).json(mockErr.body);

    const { userId, staffId, principalId } = getPrincipal(req);

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const id = s(req.params?.id);
    const bodyWorkDate = s(req.body?.workDate);
    const requestedShiftId = normalizeObjectIdString(getRequestedShiftId(req));

    let session = null;
    if (id) {
      session = await AttendanceSession.findById(id);
      if (!session) {
        return res.status(404).json({ ok: false, message: "Session not found" });
      }

      if (
        bodyWorkDate &&
        isYmd(bodyWorkDate) &&
        s(session.workDate) !== bodyWorkDate
      ) {
        return res.status(409).json({
          ok: false,
          message: "Session workDate does not match requested workDate",
        });
      }
    } else {
      const q = {
        status: "open",
        $or: buildAttendanceActorOr({ principalId, userId, staffId }),
      };

      if (isYmd(bodyWorkDate)) q.workDate = bodyWorkDate;

      if (requestedShiftId) {
        q.$and = [buildShiftMatchClause(requestedShiftId)];
      }

      const openSessions = await AttendanceSession.find(q).sort({
        checkInAt: -1,
        createdAt: -1,
      });

      if (!openSessions.length) {
        return res.status(409).json({
          ok: false,
          code: "NO_OPEN_SESSION",
          message: requestedShiftId
            ? "ไม่พบรายการเช็คอินที่เปิดอยู่สำหรับกะนี้"
            : "No open session to check-out",
        });
      }

      if (openSessions.length > 1) {
        return res.status(409).json({
          ok: false,
          code: "MULTIPLE_OPEN_SESSIONS",
          message:
            "พบ open session มากกว่าหนึ่งรายการ กรุณาระบุ session ที่ต้องการปิด",
          sessions: openSessions.map((x) => ({
            _id: String(x._id || ""),
            clinicId: s(x.clinicId),
            clinicName: s(x.clinicName || extractClinicDisplayName(x)),
            workDate: s(x.workDate),
            shiftId:
              typeof x.shiftId === "object"
                ? s(x.shiftId?._id || x.shiftId?.id)
                : s(x.shiftId),
            shiftName: s(x.shiftName || extractShiftDisplayName(x)),
            checkInAt: x.checkInAt,
            routeHint: buildResolveAttendanceRouteHint(x),
          })),
        });
      }

      session = openSessions[0];
    }

    const ownershipOr = buildAttendanceActorOr({ principalId, userId, staffId });
    const owned = ownershipOr.some((cond) =>
      Object.entries(cond).every(([k, v]) => s(session?.[k]) === s(v))
    );

    if (!owned) {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (not your session)" });
    }

    if (s(session.status) !== "open") {
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

    if (sessionRole === "employee") {
      const verify = await ensureSessionEmployeeAccess(req, session);
      if (!verify.ok) return res.status(verify.status).json(verify.body);
    }

    const policy = await getOrCreatePolicy(
      effectiveClinicId,
      userId || principalId
    );
    const rules = attendanceRuleDefaults(policy);

    if (
      mustRespectClinicHours(sessionRole) &&
      !isClinicOpenDay(policy, s(session.workDate))
    ) {
      return res.status(409).json({
        ok: false,
        code: "CLINIC_CLOSED_DAY",
        message: "วันนี้คลินิกปิดทำการ",
        workDate: s(session.workDate),
        clinicId: effectiveClinicId,
      });
    }

    const previousPendingManual = await findPreviousPendingManualSession({
      principalId,
      workDate: s(session.workDate),
    });

    if (
      previousPendingManual &&
      String(previousPendingManual._id || "") !== String(session._id || "")
    ) {
      const out = buildPreviousAttendancePendingResponse(previousPendingManual);
      return res.status(out.status).json(out.body);
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

    const sessionShiftId =
      typeof session.shiftId === "object"
        ? s(session.shiftId?._id || session.shiftId?.id)
        : s(session.shiftId);

    if (
      sessionRole === "helper" &&
      requestedShiftId &&
      sessionShiftId &&
      requestedShiftId !== sessionShiftId
    ) {
      return res.status(409).json({
        ok: false,
        code: "SHIFT_NOT_RESOLVED",
        message: "กะที่เลือกไม่ตรงกับ session ที่เปิดอยู่",
        requestedShiftId,
        sessionShiftId,
      });
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);
    const outLocationSource = getLocationSource(req, "out");
    const outMocked = isMockLocation(req, "out");

    const shift = buildRuntimeShiftSnapshot(
      await loadShiftForSession({
        clinicId: effectiveClinicId,
        staffId: s(session.staffId) || staffId,
        userId: s(session.userId) || userId || "",
        workDate: s(session.workDate),
        shiftId: sessionShiftId,
      })
    );

    if (sessionRole === "helper" && !shift) {
      return res.status(409).json({
        ok: false,
        code: "SHIFT_NOT_RESOLVED",
        message:
          "ไม่สามารถระบุกะงานของ session ที่เปิดอยู่ได้ กรุณาเลือกกะใหม่แล้วลองอีกครั้ง",
        workDate: s(session.workDate),
        shiftId: sessionShiftId,
      });
    }

    let outDistanceMeters = null;
    const requireLocation = shouldRequireLocationForAttendance(policy);

    if (requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        const out = buildLocationRequiredError();
        return res.status(out.status).json(out.body);
      }

      const ref = getReferenceCoordinateCandidates(shift, policy, session);
      if (!ref) {
        const out = buildLocationRequirementError();
        return res.status(out.status).json(out.body);
      }

      const dist = haversineMeters(ref.lat, ref.lng, lat, lng);
      outDistanceMeters = dist;
      const radius = getEnforcedGeoRadius(policy);

      if (dist > radius) {
        const out = buildOutsideRadiusError(dist, radius);
        return res.status(out.status).json(out.body);
      }
    }

    const checkOutAt = new Date();

    if (mustRespectClinicHours(sessionRole)) {
      const clinicOpenAt = getClinicOpenDateTime(s(session.workDate), policy);
      const clinicCloseAt = getClinicCloseDateTime(s(session.workDate), policy);

      if (checkOutAt.getTime() < clinicOpenAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_NOT_OPEN",
          message: "คลินิกยังไม่เปิด",
          workDate: s(session.workDate),
          clinicId: effectiveClinicId,
          openTime: pickClinicOpenTime(policy, s(session.workDate)),
        });
      }

      if (checkOutAt.getTime() > clinicCloseAt.getTime()) {
        return res.status(409).json({
          ok: false,
          code: "CLINIC_ALREADY_CLOSED",
          message: "คลินิกปิดแล้ว",
          workDate: s(session.workDate),
          clinicId: effectiveClinicId,
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
        { workDate: s(session.workDate), cutoffTime: rules.cutoffTime }
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
    session.biometricVerifiedOut =
      method === "biometric" ? biometricVerified : false;

    if (s(req.body?.deviceId)) session.deviceId = s(req.body?.deviceId);
    session.outLat = Number.isFinite(lat) ? lat : session.outLat;
    session.outLng = Number.isFinite(lng) ? lng : session.outLng;

    if (!s(session.clinicName)) {
      session.clinicName = s(
        shift?.clinicName || extractClinicDisplayName(session)
      );
    }
    if (!s(session.shiftName)) {
      session.shiftName = s(shift?.title || extractShiftDisplayName(session));
    }

    if (s(req.body?.reasonCode)) session.reasonCode = s(req.body?.reasonCode);
    if (s(req.body?.reasonText)) session.reasonText = s(req.body?.reasonText);
    if (s(req.body?.note)) {
      session.note = s(req.body?.note);
      session.manualReason = s(req.body?.note);
    }

    setLocationSecurityMeta({
      session,
      phase: "out",
      distanceMeters: Number.isFinite(outDistanceMeters)
        ? outDistanceMeters
        : null,
      locationSource: outLocationSource,
      mocked: outMocked,
    });

    maybeFlagDistanceRisk(
      session,
      Number.isFinite(outDistanceMeters) ? outDistanceMeters : null,
      getEnforcedGeoRadius(policy)
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
    await maybePostTrustScoreFromSession(session);

    return res.json({
      ok: true,
      session,
      otMeta,
      policy: buildPublicPolicy(policy, s(session.workDate)),
      runtime: {
        role: sessionRole,
        clinicId: effectiveClinicId,
        shift: shift || null,
      },
    });
  } catch (e) {
    console.log("❌ check-out failed:", e?.message || e);
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
    const { principalId } = getPrincipal(req);

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const workDate = s(req.body?.workDate);
    const manualRequestType = normalizeManualRequestType(
      req.body?.manualRequestType
    );
    const shiftId = getRequestedShiftId(req);

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

    const {
      userId,
      staffId,
      principalId: resolvedPrincipalId,
      principalType,
      clinicId,
      role,
    } = ctx;

    let shift = buildRuntimeShiftSnapshot(ctx.shift) || null;
    const policy = await getOrCreatePolicy(
      clinicId,
      userId || resolvedPrincipalId
    );
    const features = withFeatureDefaults(policy?.features || {});

    if (!features.manualAttendance) {
      return res
        .status(400)
        .json({ ok: false, message: "Manual attendance is not enabled" });
    }

    if (shouldRequireReason(policy, req)) {
      return res
        .status(400)
        .json({ ok: false, message: "Manual attendance reason is required" });
    }

    const requestedCheckInAt = firstValidDate(
      req.body?.requestedCheckInAt,
      req.body?.checkInAt
    );
    const requestedCheckOutAt = firstValidDate(
      req.body?.requestedCheckOutAt,
      req.body?.checkOutAt
    );

    if (!shift && role === "helper") {
      return res.status(409).json({
        ok: false,
        code: "SHIFT_NOT_RESOLVED",
        message: "กรุณาเลือกกะก่อนส่งคำขอแก้ไขเวลา",
        workDate,
      });
    }

    if (!shift) {
      shift = buildRuntimeShiftSnapshot(
        await loadShiftForSession({
          clinicId,
          staffId,
          userId,
          workDate,
          shiftId,
        })
      );
    }

    const previousPendingManual = await findPreviousPendingManualSession({
      principalId: resolvedPrincipalId,
      workDate,
    });

    const sameDayQuery = buildRuntimeSessionQuery({
      clinicId,
      principalId: resolvedPrincipalId,
      userId,
      staffId,
      workDate,
      shiftId: role === "helper" ? s(shift?._id) : "",
    });

    const sameDaySessions = await AttendanceSession.find(sameDayQuery).sort({
      createdAt: -1,
      checkInAt: -1,
    });

    const pendingExisting =
      sameDaySessions.find((x) => isStatusPendingManual(x)) || null;
    if (pendingExisting) {
      return res.status(409).json({
        ok: false,
        code: "MANUAL_REQUEST_PENDING",
        message:
          role === "helper"
            ? "Manual attendance request is already pending for this shift/date"
            : "Manual attendance request is already pending for this date",
        sessionId: String(pendingExisting._id || ""),
        clinicId: s(pendingExisting.clinicId),
        clinicName: s(
          pendingExisting.clinicName || extractClinicDisplayName(pendingExisting)
        ),
        workDate: s(pendingExisting.workDate),
        shiftId:
          typeof pendingExisting.shiftId === "object"
            ? s(pendingExisting.shiftId?._id || pendingExisting.shiftId?.id)
            : s(pendingExisting.shiftId),
        shiftName: s(
          pendingExisting.shiftName || extractShiftDisplayName(pendingExisting)
        ),
        routeHint: buildManualRequestRouteHint(pendingExisting),
        pendingContext: toBlockedPreviousSessionPayload(pendingExisting),
      });
    }

    const openSession =
      sameDaySessions.find((x) => s(x.status) === "open") || null;
    const closedSession =
      sameDaySessions.find((x) => s(x.status) === "closed") || null;
    let targetSession = openSession || closedSession || null;

    const previousDaySession =
      previousPendingManual &&
      s(previousPendingManual.workDate) !== workDate
        ? await AttendanceSession.findById(previousPendingManual._id)
        : null;

    if (
      previousDaySession &&
      s(previousDaySession.principalId) === s(resolvedPrincipalId) &&
      isStatusPendingManual(previousDaySession)
    ) {
      const previousType = s(previousDaySession.manualRequestType);
      const requestReasonCode = s(req.body?.reasonCode);
      const requestReasonText = s(req.body?.reasonText || req.body?.note);

      const requestedAtFromBody = firstValidDate(
        req.body?.requestedCheckOutAt,
        req.body?.checkOutAt,
        req.body?.requestedCheckInAt,
        req.body?.checkInAt
      );

      if (!requestedAtFromBody) {
        return res.status(400).json({
          ok: false,
          code: "PREVIOUS_REQUEST_TIME_REQUIRED",
          message: "กรุณาระบุเวลาที่ต้องการแก้ไขสำหรับรายการค้างของวันก่อน",
          previousSessionId: String(previousDaySession._id || ""),
          previousWorkDate: s(previousDaySession.workDate),
          previousClinicId: s(previousDaySession.clinicId),
          previousClinicName: s(
            previousDaySession.clinicName ||
              extractClinicDisplayName(previousDaySession)
          ),
          previousShiftId:
            typeof previousDaySession.shiftId === "object"
              ? s(
                  previousDaySession.shiftId?._id ||
                    previousDaySession.shiftId?.id
                )
              : s(previousDaySession.shiftId),
          previousShiftName: s(
            previousDaySession.shiftName ||
              extractShiftDisplayName(previousDaySession)
          ),
          routeHint: buildManualRequestRouteHint(previousDaySession),
        });
      }

      if (
        ![
          "forgot_checkout",
          "check_out",
          "edit_both",
          "check_in",
          "",
        ].includes(previousType)
      ) {
        return res.status(409).json({
          ok: false,
          code: "PREVIOUS_REQUEST_NOT_EDITABLE",
          message: "รายการค้างของวันก่อนอยู่ในสถานะที่ไม่สามารถแก้ไขต่อได้",
          previousSessionId: String(previousDaySession._id || ""),
          previousWorkDate: s(previousDaySession.workDate),
          previousClinicId: s(previousDaySession.clinicId),
          previousClinicName: s(
            previousDaySession.clinicName ||
              extractClinicDisplayName(previousDaySession)
          ),
          previousShiftId:
            typeof previousDaySession.shiftId === "object"
              ? s(
                  previousDaySession.shiftId?._id ||
                    previousDaySession.shiftId?.id
                )
              : s(previousDaySession.shiftId),
          previousShiftName: s(
            previousDaySession.shiftName ||
              extractShiftDisplayName(previousDaySession)
          ),
          routeHint: buildManualRequestRouteHint(previousDaySession),
        });
      }

      if (
        previousType === "forgot_checkout" ||
        previousType === "check_out" ||
        (previousDaySession.checkInAt && !previousDaySession.checkOutAt)
      ) {
        previousDaySession.manualRequestType = "forgot_checkout";
        previousDaySession.requestedCheckOutAt = requestedAtFromBody;
      } else if (!previousDaySession.checkInAt) {
        previousDaySession.manualRequestType = "check_in";
        previousDaySession.requestedCheckInAt = requestedAtFromBody;
      } else {
        previousDaySession.manualRequestType = "edit_both";
        if (
          !previousDaySession.requestedCheckInAt &&
          previousDaySession.checkInAt
        ) {
          previousDaySession.requestedCheckInAt =
            previousDaySession.checkInAt;
        }
        previousDaySession.requestedCheckOutAt = requestedAtFromBody;
      }

      previousDaySession.status = "pending_manual";
      previousDaySession.approvalStatus = "pending";
      previousDaySession.manualLocked = true;
      previousDaySession.requestedBy = s(userId || resolvedPrincipalId);
      previousDaySession.requestedAt = new Date();

      if (requestReasonCode) {
        previousDaySession.requestReasonCode = requestReasonCode;
        previousDaySession.reasonCode = requestReasonCode;
      }

      if (requestReasonText) {
        previousDaySession.requestReasonText = requestReasonText;
        previousDaySession.reasonText = requestReasonText;
        previousDaySession.note = requestReasonText;
        previousDaySession.manualReason = requestReasonText;
      }

      if (!s(previousDaySession.clinicName)) {
        previousDaySession.clinicName = s(
          extractClinicDisplayName(previousDaySession)
        );
      }
      if (!s(previousDaySession.shiftName)) {
        previousDaySession.shiftName = s(
          extractShiftDisplayName(previousDaySession)
        );
      }

      await previousDaySession.save();

      return res.status(200).json({
        ok: true,
        updatedPreviousPendingRequest: true,
        requiresApproval: true,
        session: previousDaySession,
        message:
          "อัปเดตรายการค้างของวันก่อนเรียบร้อยแล้ว กรุณารอการอนุมัติก่อนจึงจะเริ่มรายการใหม่ได้",
        blockNewAttendanceUntilApproved: true,
        previousSessionId: String(previousDaySession._id || ""),
        previousWorkDate: s(previousDaySession.workDate),
        previousClinicId: s(previousDaySession.clinicId),
        previousClinicName: s(
          previousDaySession.clinicName ||
            extractClinicDisplayName(previousDaySession)
        ),
        previousShiftId:
          typeof previousDaySession.shiftId === "object"
            ? s(
                previousDaySession.shiftId?._id ||
                  previousDaySession.shiftId?.id
              )
            : s(previousDaySession.shiftId),
        previousShiftName: s(
          previousDaySession.shiftName ||
            extractShiftDisplayName(previousDaySession)
        ),
        routeHint: buildManualRequestRouteHint(previousDaySession),
        pendingContext: toBlockedPreviousSessionPayload(previousDaySession),
        policy: buildPublicPolicy(policy, s(previousDaySession.workDate)),
      });
    }

    if (manualRequestType === "check_in") {
      if (targetSession) {
        return res.status(409).json({
          ok: false,
          code: "SESSION_ALREADY_EXISTS",
          message:
            role === "helper"
              ? "A session already exists for this shift/date. Use edit_both instead."
              : "A session already exists for this date. Use edit_both instead.",
          sessionId: String(targetSession._id || ""),
          clinicId: s(targetSession.clinicId),
          clinicName: s(
            targetSession.clinicName || extractClinicDisplayName(targetSession)
          ),
          workDate: s(targetSession.workDate),
          shiftId:
            typeof targetSession.shiftId === "object"
              ? s(targetSession.shiftId?._id || targetSession.shiftId?.id)
              : s(targetSession.shiftId),
          shiftName: s(
            targetSession.shiftName || extractShiftDisplayName(targetSession)
          ),
          routeHint: buildResolveAttendanceRouteHint(targetSession),
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
          principalId: resolvedPrincipalId,
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
        userId || resolvedPrincipalId
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
        runtime: {
          role,
          clinicId,
          shift: shift || null,
        },
      });
    }

    if (manualRequestType === "check_out") {
      if (!openSession) {
        return res.status(409).json({
          ok: false,
          code: "OPEN_SESSION_REQUIRED",
          message:
            role === "helper"
              ? "Manual checkout request requires an open session for this shift/date"
              : "Manual checkout request requires an open session for this date",
        });
      }

      if (!requestedCheckOutAt) {
        return res.status(400).json({
          ok: false,
          message: "requestedCheckOutAt is required for manual checkout request",
        });
      }

      targetSession = openSession;
    }

    if (manualRequestType === "forgot_checkout") {
      if (!requestedCheckOutAt) {
        return res.status(400).json({
          ok: false,
          message: "requestedCheckOutAt is required for forgot checkout request",
        });
      }

      if (openSession) {
        targetSession = openSession;
      } else if (closedSession) {
        return res.status(409).json({
          ok: false,
          code: "ATTENDANCE_ALREADY_COMPLETED",
          message:
            role === "helper"
              ? "Attendance already completed for this shift/date. Use edit_both instead if correction is needed."
              : "Attendance already completed for this date. Use edit_both instead if correction is needed.",
          sessionId: String(closedSession._id || ""),
          clinicId: s(closedSession.clinicId),
          clinicName: s(
            closedSession.clinicName || extractClinicDisplayName(closedSession)
          ),
          workDate: s(closedSession.workDate),
          shiftId:
            typeof closedSession.shiftId === "object"
              ? s(closedSession.shiftId?._id || closedSession.shiftId?.id)
              : s(closedSession.shiftId),
          shiftName: s(
            closedSession.shiftName || extractShiftDisplayName(closedSession)
          ),
          routeHint: buildResolveAttendanceRouteHint(closedSession),
        });
      } else if (
        !(targetSession && targetSession.checkInAt && !targetSession.checkOutAt)
      ) {
        return res.status(409).json({
          ok: false,
          code: "CHECKIN_SESSION_REQUIRED",
          message:
            role === "helper"
              ? "Forgot checkout request requires an existing check-in session for this shift/date"
              : "Forgot checkout request requires an existing check-in session for this date",
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
            principalId: resolvedPrincipalId,
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

    if (targetSession && !s(targetSession.clinicName)) {
      targetSession.clinicName = s(
        shift?.clinicName || extractClinicDisplayName(targetSession)
      );
    }
    if (targetSession && !s(targetSession.shiftName)) {
      targetSession.shiftName = s(
        shift?.title || extractShiftDisplayName(targetSession)
      );
    }

    applyManualRequestFields(
      targetSession,
      req,
      manualRequestType,
      requestedCheckInAt,
      requestedCheckOutAt,
      userId || resolvedPrincipalId
    );

    if (!s(targetSession.source)) targetSession.source = "manual";
    if (!s(targetSession.checkInMethod)) targetSession.checkInMethod = "manual";
    if (!s(targetSession.checkOutMethod)) {
      targetSession.checkOutMethod = "manual";
    }

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
      runtime: {
        role,
        clinicId,
        shift: shift || null,
      },
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
    const shiftId = normalizeObjectIdString(getRequestedShiftId(req));

    const clinicScope = await resolveSelfClinicFilter(req, clinicId);
    if (!clinicScope.ok) {
      return res.status(clinicScope.status).json(clinicScope.body);
    }

    const effectiveClinicId = s(clinicScope.clinicId);
    const q = buildManualRequestQueryForSelf({
      clinicId: effectiveClinicId,
      principalId,
      workDate,
      approvalStatus,
    });

    if (role === "helper" && shiftId) {
      q.$and = [
        ...(Array.isArray(q.$and) ? q.$and : []),
        buildShiftMatchClause(shiftId),
      ];
    }

    const items = await AttendanceSession.find(q)
      .sort({ workDate: -1, requestedAt: -1, createdAt: -1 })
      .lean();

    const policy = effectiveClinicId
      ? await getOrCreatePolicy(effectiveClinicId, userId || principalId)
      : null;

    const normalizedItems = items.map(normalizeSessionItem);
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
      clinicScope: {
        clinicId: effectiveClinicId || "",
        scope: clinicScope.scope,
      },
      policy: policy ? buildPublicPolicy(policy, workDate) : null,
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "list my manual requests failed",
      error: e.message,
    });
  }
}

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
    const normalizedItems = items.map(normalizeSessionItem);
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
      return res.status(403).json({
        ok: false,
        message: "Forbidden (cross-clinic request)",
      });
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

    const shift = buildRuntimeShiftSnapshot(
      await loadShiftForSession({
        clinicId: s(session.clinicId),
        staffId: s(session.staffId),
        userId: s(session.userId),
        workDate: s(session.workDate),
        shiftId:
          typeof session.shiftId === "object"
            ? s(session.shiftId?._id || session.shiftId?.id)
            : s(session.shiftId),
      })
    );

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
      return res
        .status(400)
        .json({ ok: false, message: "Requested check-in time is missing" });
    }

    if (
      (requestedType === "check_out" || requestedType === "forgot_checkout") &&
      !finalCheckOutAt
    ) {
      return res
        .status(400)
        .json({ ok: false, message: "Requested check-out time is missing" });
    }

    ensureSecurityFields(session);

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

    if (!s(session.clinicName)) {
      session.clinicName = s(
        shift?.clinicName || extractClinicDisplayName(session)
      );
    }
    if (!s(session.shiftName)) {
      session.shiftName = s(shift?.title || extractShiftDisplayName(session));
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
      return res.status(403).json({
        ok: false,
        message: "Forbidden (cross-clinic request)",
      });
    }

    if (!isStatusPendingManual(session)) {
      return res.status(409).json({
        ok: false,
        message: "Manual request is not pending rejection",
      });
    }

    if (!s(session.clinicName)) {
      session.clinicName = s(extractClinicDisplayName(session));
    }
    if (!s(session.shiftName)) {
      session.shiftName = s(extractShiftDisplayName(session));
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
    return res.json({ ok: true, session });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "reject manual request failed",
      error: e.message,
    });
  }
}

async function listMySessions(req, res) {
  try {
    const { clinicId, principalId, userId, staffId, role } = getPrincipal(req);

    if (!principalId && !userId && !staffId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const dateFrom = s(req.query?.dateFrom);
    const dateTo = s(req.query?.dateTo);
    const requestedShiftId = normalizeObjectIdString(getRequestedShiftId(req));

    const clinicScope = await resolveSelfClinicFilter(req, clinicId);
    if (!clinicScope.ok) {
      return res.status(clinicScope.status).json(clinicScope.body);
    }

    const requestedClinicId = s(clinicScope.clinicId);

    const q = buildMyAttendanceQuery({
      clinicId: requestedClinicId,
      principalId,
      userId,
      staffId,
      dateFrom,
      dateTo,
      shiftId: role === "helper" ? requestedShiftId : "",
    });

    const items = await AttendanceSession.find(q)
      .sort({ workDate: -1, checkInAt: -1, createdAt: -1 })
      .lean();

    const policy =
      requestedClinicId && role !== "helper"
        ? await getOrCreatePolicy(
            requestedClinicId,
            userId || principalId || staffId
          )
        : null;

    const normalizedItems = items.map(normalizeSessionItem);

    return res.json({
      ok: true,
      items: normalizedItems,
      clinicScope: {
        clinicId: requestedClinicId || "",
        scope:
          role === "helper" && !requestedClinicId
            ? "all_clinics"
            : clinicScope.scope,
      },
      filters: {
        dateFrom: isYmd(dateFrom) ? dateFrom : "",
        dateTo: isYmd(dateTo) ? dateTo : "",
        shiftId: role === "helper" ? requestedShiftId || "" : "",
      },
      policy: policy ? buildPublicPolicy(policy) : null,
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "list failed",
      error: e.message,
    });
  }
}

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
    const requestedShiftId = normalizeObjectIdString(getRequestedShiftId(req));

    const q = { clinicId };
    if (isYmd(workDate)) q.workDate = workDate;

    if (staffIdOrPrincipal) {
      q.$or = [
        { staffId: staffIdOrPrincipal },
        { principalId: staffIdOrPrincipal },
        { userId: staffIdOrPrincipal },
        { helperUserId: staffIdOrPrincipal },
        { assignedUserId: staffIdOrPrincipal },
      ];
    }

    if (requestedShiftId) {
      q.$and = [buildShiftMatchClause(requestedShiftId)];
    }

    const items = await AttendanceSession.find(q)
      .sort({ checkInAt: -1 })
      .lean();
    const policy = await getOrCreatePolicy(clinicId, s(req.user?.userId));

    return res.json({
      ok: true,
      items: items.map(normalizeSessionItem),
      filters: {
        workDate: isYmd(workDate) ? workDate : "",
        staffId: staffIdOrPrincipal || "",
        shiftId: requestedShiftId || "",
      },
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

async function myDayPreview(req, res) {
  try {
    const workDate = s(req.query?.workDate);
    const shiftId = getRequestedShiftId(req);

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
      principalId,
      clinicId,
      staffId,
      employee: ctxEmployee,
      availableShifts,
      shiftSelectionMode,
    } = ctx;

    let shift = buildRuntimeShiftSnapshot(ctx.shift) || null;
    const policy = await getOrCreatePolicy(clinicId, userId || principalId);

    const previousOpen = await findPreviousOpenSession({ principalId, workDate });
    if (previousOpen) {
      const out = buildPreviousAttendancePendingResponse(previousOpen);
      return res.status(out.status).json({
        ...out.body,
        workDate,
        attendance: {
          checkedIn: false,
          checkedOut: false,
          openSession: null,
          pendingManualSession: null,
          currentSessionId: "",
        },
        sessions: [],
        runtime: {
          role,
          clinicId,
          clinicOpenDay: isClinicOpenDay(policy, workDate),
          clinicOpenTime: pickClinicOpenTime(policy, workDate),
          clinicCloseTime: pickClinicCloseTime(policy, workDate),
          shift: shift || null,
          shiftSelectionMode: shiftSelectionMode || "",
          availableShifts: availableShifts || [],
        },
        policy: buildPublicPolicy(policy, workDate),
      });
    }

    const previousPendingManual = await findPreviousPendingManualSession({
      principalId,
      workDate,
    });

    if (previousPendingManual) {
      const out = buildPreviousAttendancePendingResponse(previousPendingManual);
      return res.status(out.status).json({
        ...out.body,
        workDate,
        attendance: {
          checkedIn: false,
          checkedOut: false,
          openSession: null,
          pendingManualSession: previousPendingManual,
          currentSessionId: "",
        },
        sessions: [],
        runtime: {
          role,
          clinicId,
          clinicOpenDay: isClinicOpenDay(policy, workDate),
          clinicOpenTime: pickClinicOpenTime(policy, workDate),
          clinicCloseTime: pickClinicCloseTime(policy, workDate),
          shift: shift || null,
          shiftSelectionMode: shiftSelectionMode || "",
          availableShifts: availableShifts || [],
        },
        policy: buildPublicPolicy(policy, workDate),
      });
    }

    const sessionsQuery = buildRuntimeSessionQuery({
      clinicId,
      principalId,
      userId,
      staffId,
      workDate,
      shiftId: role === "helper" ? s(shift?._id) : "",
    });

    const sessions = await AttendanceSession.find(sessionsQuery)
      .sort({ checkInAt: -1, createdAt: -1 })
      .lean();

    const normalizedSessions = sessions.map(normalizeSessionItem);

    const openSession =
      normalizedSessions.find((x) => s(x.status).toLowerCase() === "open") ||
      null;

    const pendingManualSession =
      normalizedSessions.find(
        (x) => s(x.status).toLowerCase() === "pending_manual"
      ) || null;

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

    const approvedOtQuery = {
      clinicId,
      principalId,
      workDate,
      status: "approved",
    };

    const normalizedShiftId = normalizeObjectIdString(s(shift?._id));
    if (role === "helper" && normalizedShiftId) {
      approvedOtQuery.attendanceSessionId = {
        $in: closedSessions
          .map((x) => normalizeObjectIdString(x._id))
          .filter(Boolean)
          .map((oneId) => new mongoose.Types.ObjectId(oneId)),
      };
    }

    const approvedOt = await Overtime.find(approvedOtQuery).lean();

    const otMinutesApproved = approvedOt.reduce(
      (sum, x) => sum + clampMinutes(x.minutes),
      0
    );

    const suspiciousCount = normalizedSessions.reduce(
      (sum, x) =>
        sum +
        (Array.isArray(x.suspiciousFlags) && x.suspiciousFlags.length > 0
          ? 1
          : 0),
      0
    );

    const totalRiskScore = normalizedSessions.reduce(
      (sum, x) => sum + clampRisk(x.riskScore || 0),
      0
    );

    let emp = ctxEmployee?.raw || null;
    if (!emp && userId) {
      try {
        emp = await memoizedGetEmployeeByUserId(req, userId, getBearerToken(req));
      } catch (_) {
        emp = null;
      }
    }

    if (!shift && role === "helper") {
      const helperShiftResult = await resolveHelperShiftForRuntime(req, {
        principalId,
        userId,
        staffId,
        workDate,
        explicitShiftId: shiftId,
        fallbackClinicId: clinicId,
      });

      if (helperShiftResult.ok) {
        shift = buildRuntimeShiftSnapshot(helperShiftResult.shift);
      }
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

    if (role === "helper" && shift) {
      if (checkedIn && !checkedOut) {
        message = `เช็คอินแล้วสำหรับกะ ${s(
          shift.clinicName || shift.title || shift._id
        )}`;
      } else if (checkedIn && checkedOut) {
        message = "กะนี้เสร็จสิ้นแล้ว";
      } else {
        message = `พร้อมสแกนสำหรับกะ ${s(
          shift.clinicName || shift.title || shift._id
        )}`;
      }
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
      principal: { principalId, staffId, userId },
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
        shiftSelectionMode: shiftSelectionMode || "",
        availableShifts: availableShifts || [],
      },
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "preview failed",
      error: e.message,
    });
  }
}

async function backfillPreviousPendingRequestIfNeeded({
  principalId,
  currentWorkDate,
  requestedCheckOutAt,
  reasonCode = "",
  reasonText = "",
  requesterId = "",
}) {
  const previousPending = await findPreviousPendingManualSession({
    principalId,
    workDate: currentWorkDate,
  });

  if (!previousPending) {
    return {
      ok: false,
      reason: "NO_PREVIOUS_PENDING",
    };
  }

  if (s(previousPending.workDate) === s(currentWorkDate)) {
    return {
      ok: false,
      reason: "SAME_DAY_PENDING",
    };
  }

  const session = await AttendanceSession.findById(previousPending._id);
  if (!session) {
    return {
      ok: false,
      reason: "PREVIOUS_PENDING_NOT_FOUND",
    };
  }

  if (!isStatusPendingManual(session)) {
    return {
      ok: false,
      reason: "PREVIOUS_PENDING_NOT_ACTIVE",
    };
  }

  if (!requestedCheckOutAt) {
    return {
      ok: false,
      reason: "REQUESTED_CHECKOUT_REQUIRED",
      session,
    };
  }

  const prevType = s(session.manualRequestType);

  if (
    prevType === "forgot_checkout" ||
    prevType === "check_out" ||
    (session.checkInAt && !session.checkOutAt)
  ) {
    session.manualRequestType = "forgot_checkout";
    session.requestedCheckOutAt = requestedCheckOutAt;
  } else if (!session.checkInAt) {
    session.manualRequestType = "check_in";
    session.requestedCheckInAt = requestedCheckOutAt;
  } else {
    session.manualRequestType = "edit_both";
    if (!session.requestedCheckInAt && session.checkInAt) {
      session.requestedCheckInAt = session.checkInAt;
    }
    session.requestedCheckOutAt = requestedCheckOutAt;
  }

  session.status = "pending_manual";
  session.approvalStatus = "pending";
  session.manualLocked = true;
  session.requestedBy = s(requesterId);
  session.requestedAt = new Date();

  if (!s(session.clinicName)) {
    session.clinicName = s(extractClinicDisplayName(session));
  }
  if (!s(session.shiftName)) {
    session.shiftName = s(extractShiftDisplayName(session));
  }

  if (s(reasonCode)) {
    session.requestReasonCode = s(reasonCode);
    session.reasonCode = s(reasonCode);
  }

  if (s(reasonText)) {
    session.requestReasonText = s(reasonText);
    session.reasonText = s(reasonText);
    session.note = s(reasonText);
    session.manualReason = s(reasonText);
  }

  await session.save();

  return {
    ok: true,
    updated: true,
    session,
  };
}

async function rebuildPendingPreviousByCurrentRequest(
  req,
  currentWorkDate,
  principalId
) {
  const requestedCheckOutAt = firstValidDate(
    req.body?.requestedCheckOutAt,
    req.body?.checkOutAt,
    req.body?.requestedCheckInAt,
    req.body?.checkInAt
  );

  return backfillPreviousPendingRequestIfNeeded({
    principalId,
    currentWorkDate,
    requestedCheckOutAt,
    reasonCode: s(req.body?.reasonCode),
    reasonText: s(req.body?.reasonText || req.body?.note),
    requesterId:
      s(req.user?.userId) || s(req.user?.staffId) || s(principalId),
  });
}

async function explainPreviousPendingForPreview(req, res, workDate, ctx, policy) {
  const previousPendingManual = await findPreviousPendingManualSession({
    principalId: s(ctx.principalId),
    workDate,
  });

  if (!previousPendingManual) return false;

  const out = buildPreviousAttendancePendingResponse(previousPendingManual);
  res.status(out.status).json({
    ...out.body,
    workDate,
    attendance: {
      checkedIn: false,
      checkedOut: false,
      openSession: null,
      pendingManualSession: previousPendingManual,
      currentSessionId: "",
    },
    sessions: [],
    runtime: {
      role: ctx.role,
      clinicId: ctx.clinicId,
      clinicOpenDay: isClinicOpenDay(policy, workDate),
      clinicOpenTime: pickClinicOpenTime(policy, workDate),
      clinicCloseTime: pickClinicCloseTime(policy, workDate),
      shift: ctx.shift || null,
      shiftSelectionMode: ctx.shiftSelectionMode || "",
      availableShifts: ctx.availableShifts || [],
    },
    policy: buildPublicPolicy(policy, workDate),
  });
  return true;
}

async function explainPreviousOpenForPreview(req, res, workDate, ctx, policy) {
  const previousOpen = await findPreviousOpenSession({
    principalId: s(ctx.principalId),
    workDate,
  });

  if (!previousOpen) return false;

  const out = buildPreviousAttendancePendingResponse(previousOpen);
  res.status(out.status).json({
    ...out.body,
    workDate,
    attendance: {
      checkedIn: false,
      checkedOut: false,
      openSession: null,
      pendingManualSession: null,
      currentSessionId: "",
    },
    sessions: [],
    runtime: {
      role: ctx.role,
      clinicId: ctx.clinicId,
      clinicOpenDay: isClinicOpenDay(policy, workDate),
      clinicOpenTime: pickClinicOpenTime(policy, workDate),
      clinicCloseTime: pickClinicCloseTime(policy, workDate),
      shift: ctx.shift || null,
      shiftSelectionMode: ctx.shiftSelectionMode || "",
      availableShifts: ctx.availableShifts || [],
    },
    policy: buildPublicPolicy(policy, workDate),
  });
  return true;
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