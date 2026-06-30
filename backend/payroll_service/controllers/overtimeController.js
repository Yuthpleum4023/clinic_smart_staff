// backend/payroll_service/controllers/overtimeController.js
//
// ✅ PRODUCTION OVERTIME CONTROLLER
// ------------------------------------------------------
// ✅ Supports:
// - Auto OT from attendance source="attendance"
// - Admin manual OT source="manual"
// - Employee/user request OT source="manual_user"
//
// ✅ Production fixes:
// - Admin manual OT is saved as REAL backend Overtime record
// - Admin manual OT defaults to status="approved"
// - approvedMinutes is set immediately
// - Payroll close can include it even when staff cannot scan fingerprint
// - Admin manual OT is idempotent:
//   same clinic + staff/principal + workDate + source=manual => update existing row
// - Avoid 409 for normal admin edit/save flow
// - Better identity matching: staffId / employeeId / principalId / linkedUserId / employeeUserId / userId
//
// ✅ Important:
// - policy.requireOtApproval=true affects employee/user requests,
//   not admin manual input.
// ------------------------------------------------------

const mongoose = require("mongoose");
const Overtime = require("../models/Overtime");
const ClinicPolicy = require("../models/ClinicPolicy");
const AttendanceSession = require("../models/AttendanceSession");

function s(v) {
  return String(v || "").trim();
}

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "").trim());
}

function isYm(v) {
  return /^\d{4}-\d{2}$/.test(String(v || "").trim());
}

function clampMinutes(v) {
  const n = Math.floor(Number(v || 0));
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, n);
}

function toMonthKey(workDate) {
  return isYmd(workDate) ? String(workDate).slice(0, 7) : "";
}

function parseMonthOrNull(month) {
  const m = s(month);
  if (!isYm(m)) return null;
  return m;
}


function isHHmm(v) {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(s(v));
}

function makeBangkokDateTime(workDate, hhmm) {
  if (!isYmd(workDate) || !isHHmm(hhmm)) return null;
  return new Date(`${workDate}T${s(hhmm)}:00.000+07:00`);
}

function formatBangkokHHmm(date) {
  const d = date instanceof Date ? date : new Date(date);
  if (!d || Number.isNaN(d.getTime())) return "";

  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Bangkok",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(d);

  const hour = parts.find((x) => x.type === "hour")?.value || "00";
  const minute = parts.find((x) => x.type === "minute")?.value || "00";
  return `${hour}:${minute}`;
}

function dateMax(a, b) {
  return new Date(Math.max(a.getTime(), b.getTime()));
}

function dateMin(a, b) {
  return new Date(Math.min(a.getTime(), b.getTime()));
}

function computeAttendanceOtByLatestPolicy(policy, session) {
  const workDate = s(session?.workDate);
  const checkInAt = session?.checkInAt ? new Date(session.checkInAt) : null;
  const checkOutAt = session?.checkOutAt ? new Date(session.checkOutAt) : null;

  if (
    !isYmd(workDate) ||
    !checkInAt ||
    !checkOutAt ||
    Number.isNaN(checkInAt.getTime()) ||
    Number.isNaN(checkOutAt.getTime()) ||
    checkOutAt.getTime() <= checkInAt.getTime()
  ) {
    return { minutes: 0, start: "", end: "", reason: "invalid_attendance_time" };
  }

  const otWindowStart = isHHmm(policy?.otWindowStart)
    ? s(policy.otWindowStart)
    : "18:00";

  const otWindowEnd = isHHmm(policy?.otWindowEnd)
    ? s(policy.otWindowEnd)
    : "21:00";

  const otStartAt = makeBangkokDateTime(workDate, otWindowStart);
  let otEndAt = makeBangkokDateTime(workDate, otWindowEnd);

  if (!otStartAt || !otEndAt) {
    return { minutes: 0, start: "", end: "", reason: "invalid_ot_policy_time" };
  }

  // รองรับ OT ข้ามวัน เช่น 22:00-02:00
  if (otEndAt.getTime() <= otStartAt.getTime()) {
    otEndAt = new Date(otEndAt.getTime() + 24 * 60 * 60 * 1000);
  }

  const paidStartAt = dateMax(checkInAt, otStartAt);
  const paidEndAt = dateMin(checkOutAt, otEndAt);

  if (paidEndAt.getTime() <= paidStartAt.getTime()) {
    return {
      minutes: 0,
      start: "",
      end: "",
      policyStart: otWindowStart,
      policyEnd: otWindowEnd,
      reason: "no_overlap_with_ot_window",
    };
  }

  const minutes = clampMinutes((paidEndAt.getTime() - paidStartAt.getTime()) / 60000);

  return {
    minutes,
    start: formatBangkokHHmm(paidStartAt),
    end: formatBangkokHHmm(paidEndAt),
    policyStart: otWindowStart,
    policyEnd: otWindowEnd,
    reason: "ok",
  };
}

function buildTargetAttendanceOr({ principalId, staffId, userId }) {
  const out = [];

  if (principalId) out.push({ principalId });
  if (staffId) {
    out.push({ staffId });
    out.push({ principalId: staffId });
  }
  if (userId) {
    out.push({ userId });
    out.push({ principalId: userId });
  }

  // de-duplicate
  const seen = new Set();
  return out.filter((x) => {
    const key = JSON.stringify(x);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function canMutateStatus(ot) {
  return s(ot.status) !== "locked";
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

function normalizeRoleForPolicy(role) {
  const r = s(role).toLowerCase();
  if (!r) return "";

  if (r === "admin") return "clinic_admin";
  if (r === "clinicadmin") return "clinic_admin";
  if (r === "clinic_admin") return "clinic_admin";

  return r;
}

function getPrincipal(req) {
  const u = req.user || {};
  const uc = req.userCtx || {};

  const clinicId = s(u.clinicId || uc.clinicId);

  const role = s(
    u.role ||
      u.activeRole ||
      u.userRole ||
      uc.role ||
      uc.activeRole ||
      uc.userRole
  );

  const userId = s(
    u.userId ||
      u.id ||
      u._id ||
      uc.userId ||
      uc.id ||
      uc._id ||
      ""
  );

  const staffId = s(
    u.staffId ||
      u.employeeId ||
      uc.staffId ||
      uc.employeeId ||
      ""
  );

  const principalId = staffId || userId;
  const principalType = staffId ? "staff" : "user";

  return {
    clinicId,
    role,
    userId,
    staffId,
    principalId,
    principalType,
  };
}

async function getOrCreatePolicy(clinicId, userId) {
  let p = await ClinicPolicy.findOne({ clinicId });

  if (!p) {
    p = await ClinicPolicy.create({
      clinicId,
      timezone: "Asia/Bangkok",

      requireBiometric: true,
      requireLocation: true,
      geoRadiusMeters: 200,
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

function canApproveOtByRole(policy, role) {
  const actorRole = normalizeRoleForPolicy(role);

  const allowed = normalizeStringArray(policy?.otApprovalRoles, [
    "clinic_admin",
  ]).map(normalizeRoleForPolicy);

  return !!actorRole && allowed.includes(actorRole);
}

function identityOrConditions({ staffId, principalId, userId }) {
  const sid = s(staffId);
  const pid = s(principalId);
  const uid = s(userId);

  const out = [];

  if (pid) out.push({ principalId: pid });
  if (pid) out.push({ staffId: pid });
  if (pid) out.push({ userId: pid });

  if (sid) out.push({ principalId: sid });
  if (sid) out.push({ staffId: sid });

  if (uid) out.push({ principalId: uid });
  if (uid) out.push({ userId: uid });

  const seen = new Set();
  return out.filter((x) => {
    const key = JSON.stringify(x);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function buildPrincipalQueryFromInput({ staffId, principalId, userId }) {
  const ors = identityOrConditions({ staffId, principalId, userId });

  if (!ors.length) return null;
  return { $or: ors };
}

// ===================== TIME HELPERS =====================

function parseHHmmToMinutes(v) {
  const t = s(v);
  const parts = t.split(":");
  if (parts.length !== 2) return null;

  const hh = Number(parts[0]);
  const mm = Number(parts[1]);

  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  if (hh < 0 || hh > 23) return null;
  if (mm < 0 || mm > 59) return null;

  return hh * 60 + mm;
}

function computeMinutesFromStartEnd(startHHmm, endHHmm) {
  const a = parseHHmmToMinutes(startHHmm);
  const b = parseHHmmToMinutes(endHHmm);

  if (a == null || b == null) return null;

  let end = b;
  if (end < a) end += 24 * 60;

  const diff = end - a;
  if (diff <= 0) return 0;

  return diff;
}

function readStartTime(body) {
  return s(body?.start || body?.startTime || body?.fromTime);
}

function readEndTime(body) {
  return s(body?.end || body?.endTime || body?.toTime);
}

function readIdentityFromBody(body) {
  const staffId = s(
    body?.staffId ||
      body?.employeeId ||
      body?.staff_id ||
      body?.employee_id ||
      ""
  );

  const userId = s(
    body?.employeeUserId ||
      body?.linkedUserId ||
      body?.linked_user_id ||
      body?.principalUserId ||
      body?.userId ||
      body?.user_id ||
      ""
  );

  const principalId = s(body?.principalId || body?.principal_id) || staffId || userId;

  const principalTypeInput = s(body?.principalType).toLowerCase();

  const principalType =
    principalTypeInput === "user" || principalTypeInput === "staff"
      ? principalTypeInput
      : staffId
      ? "staff"
      : "user";

  return {
    staffId,
    userId,
    principalId,
    principalType,
  };
}

// ===================== SUMMARY HELPERS =====================

async function sumApprovedMinutesForMonth({ clinicId, principalId, monthKey }) {
  const pid = s(principalId);

  const rows = await Overtime.find({
    clinicId,
    monthKey,
    status: "approved",
    ...(pid
      ? {
          $or: [{ principalId: pid }, { staffId: pid }, { userId: pid }],
        }
      : {}),
  })
    .select({ approvedMinutes: 1, minutes: 1 })
    .lean();

  return rows.reduce(
    (a, x) =>
      a +
      clampMinutes(
        x.approvedMinutes != null ? x.approvedMinutes : x.minutes
      ),
    0
  );
}

async function sumApprovedMinutesForDay({ clinicId, principalId, workDate }) {
  const pid = s(principalId);

  const rows = await Overtime.find({
    clinicId,
    workDate,
    status: "approved",
    ...(pid
      ? {
          $or: [{ principalId: pid }, { staffId: pid }, { userId: pid }],
        }
      : {}),
  })
    .select({ approvedMinutes: 1, minutes: 1 })
    .lean();

  return rows.reduce(
    (a, x) =>
      a +
      clampMinutes(
        x.approvedMinutes != null ? x.approvedMinutes : x.minutes
      ),
    0
  );
}

// ======================================================
// ✅ LIST MY
// ======================================================
async function listMy(req, res) {
  try {
    const { clinicId, role, staffId, userId, principalId, principalType } =
      getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing principalId" });
    }

    const allowed = ["employee", "helper", "staff", "admin", "clinic_admin"];
    if (role && !allowed.includes(role)) {
      return res.status(403).json({ ok: false, message: "Forbidden" });
    }

    const monthKey = parseMonthOrNull(req.query?.month);
    if (!monthKey) {
      return res.status(400).json({ ok: false, message: "month required" });
    }

    const status = s(req.query?.status);

    const targetStaffId = s(
      req.query?.staffId ||
        req.query?.employeeId ||
        req.body?.staffId ||
        req.body?.employeeId ||
        ""
    );

    const targetUserId = s(
      req.query?.employeeUserId ||
        req.query?.linkedUserId ||
        req.query?.userId ||
        req.body?.employeeUserId ||
        req.body?.linkedUserId ||
        req.body?.userId ||
        ""
    );

    const targetPrincipalId = s(req.query?.principalId || req.body?.principalId);

    let q = { clinicId, monthKey };
    if (status) q.status = status;

    if (
      (role === "admin" || role === "clinic_admin") &&
      (targetStaffId || targetPrincipalId || targetUserId)
    ) {
      const pQuery = buildPrincipalQueryFromInput({
        staffId: targetStaffId,
        principalId: targetPrincipalId,
        userId: targetUserId,
      });

      if (!pQuery) {
        return res.status(400).json({
          ok: false,
          message: "staffId/principalId/userId required",
        });
      }

      q = { ...q, ...pQuery };
    } else {
      const selfPid = s(principalId);
      q = {
        ...q,
        $or: [{ principalId: selfPid }, { staffId: selfPid }, { userId: selfPid }],
      };
    }

    const items = await Overtime.find(q)
      .sort({ workDate: 1, createdAt: 1 })
      .lean();

    const sum = (st) =>
      items
        .filter((x) => s(x.status) === st)
        .reduce(
          (a, x) =>
            a +
            clampMinutes(
              x.approvedMinutes != null ? x.approvedMinutes : x.minutes
            ),
          0
        );

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);

    return res.json({
      ok: true,
      month: monthKey,
      principal: { principalId, principalType, staffId, userId },
      hint:
        role === "admin" || role === "clinic_admin"
          ? "Admin can pass ?staffId=... or ?principalId=... to view specific staff OT."
          : undefined,
      summary: {
        pendingMinutes: sum("pending"),
        approvedMinutes: sum("approved"),
        rejectedMinutes: sum("rejected"),
        lockedMinutes: sum("locked"),
      },
      policy: {
        requireOtApproval: !!policy.requireOtApproval,
        otApprovalRoles: normalizeStringArray(policy.otApprovalRoles, [
          "clinic_admin",
        ]),
        features: withFeatureDefaults(policy.features || {}),
      },
      items,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ LIST FOR STAFF (admin view)
// ======================================================
async function listForStaff(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const monthKey = parseMonthOrNull(req.query?.month);
    const status = s(req.query?.status);

    const staffId = s(
      req.params?.staffId ||
        req.params?.employeeId ||
        req.query?.staffId ||
        req.query?.employeeId ||
        req.body?.staffId ||
        req.body?.employeeId ||
        ""
    );

    const userIdFilter = s(
      req.query?.employeeUserId ||
        req.query?.linkedUserId ||
        req.query?.userId ||
        req.body?.employeeUserId ||
        req.body?.linkedUserId ||
        req.body?.userId ||
        ""
    );

    const principalId = s(req.query?.principalId || req.body?.principalId);

    const pQuery = buildPrincipalQueryFromInput({
      staffId,
      principalId,
      userId: userIdFilter,
    });

    if (!pQuery) {
      return res.status(400).json({
        ok: false,
        message: "staffId or principalId or userId required",
      });
    }

    const q = { clinicId, ...pQuery };
    if (monthKey) q.monthKey = monthKey;
    if (status) q.status = status;

    const items = await Overtime.find(q)
      .sort({ workDate: 1, createdAt: 1 })
      .limit(500)
      .lean();

    return res.json({
      ok: true,
      filter: {
        month: monthKey || "",
        status: status || "",
        staffId,
        principalId,
        userId: userIdFilter,
      },
      items,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ STANDARD USER REQUEST (PENDING)
// employee/helper/staff
// ======================================================
async function requestOt(req, res) {
  try {
    const { clinicId, role, userId, staffId, principalId, principalType } =
      getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    if (!principalId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing principalId" });
    }

    const allowed = ["employee", "helper", "staff"];
    if (role && !allowed.includes(role)) {
      return res.status(403).json({ ok: false, message: "Forbidden" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);
    const features = withFeatureDefaults(policy.features || {});

    if (features.autoOtCalculation) {
      return res.status(409).json({
        ok: false,
        message:
          "Manual OT request is disabled when auto OT calculation is enabled",
      });
    }

    if (policy.employeeOnlyOt && role === "helper") {
      return res.status(403).json({
        ok: false,
        code: "OT_NOT_ALLOWED_FOR_HELPER",
        message: "OT is not allowed for helper in this clinic policy",
      });
    }

    const workDate = s(req.body?.workDate || req.body?.date);
    const start = readStartTime(req.body);
    const end = readEndTime(req.body);
    const note = s(req.body?.note || req.body?.reason);

    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "Invalid workDate" });
    }

    const computed = computeMinutesFromStartEnd(start, end);

    if (computed == null) {
      return res
        .status(400)
        .json({ ok: false, message: "Invalid time format" });
    }

    if (computed <= 0) {
      return res.status(400).json({ ok: false, message: "OT must be > 0" });
    }

    if (!note) {
      return res
        .status(400)
        .json({ ok: false, message: "OT reason is required" });
    }

    const duplicate = await Overtime.findOne({
      clinicId,
      workDate,
      source: "manual_user",
      status: { $in: ["pending", "approved", "locked"] },
      $or: [{ principalId }, { staffId: principalId }, { userId: principalId }],
    }).lean();

    if (duplicate) {
      return res.status(409).json({
        ok: false,
        code: "OT_REQUEST_ALREADY_EXISTS",
        message: "An OT request already exists for this date",
        overtimeId: String(duplicate._id || ""),
        overtime: duplicate,
      });
    }

    const multiplier = Number(req.body?.multiplier);
    const mul =
      Number.isFinite(multiplier) && multiplier > 0
        ? multiplier
        : Number(policy.otMultiplier || 1.5);

    const created = await Overtime.create({
      clinicId,
      principalId,
      principalType,
      staffId: staffId || "",
      userId: userId || "",

      workDate,
      monthKey: toMonthKey(workDate),

      start,
      end,
      startTime: start,
      endTime: end,

      minutes: computed,
      approvedMinutes: 0,
      multiplier: mul,

      status: "pending",
      source: "manual_user",
      note,

      approvedBy: "",
      approvedAt: null,
      rejectedBy: "",
      rejectedAt: null,
      rejectReason: "",
    });

    return res.status(201).json({
      ok: true,
      overtime: created,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ ADMIN CREATE / UPDATE MANUAL OT
// ======================================================
// ✅ Production rule:
// - Admin manual OT defaults approved
// - If active manual OT exists same staff/date, update it instead of 409
// - If locked, return 409 because payroll has locked it
// ======================================================
async function createManual(req, res) {
  try {
    const { clinicId, role, userId: actorUserId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, actorUserId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const workDate = s(req.body?.workDate || req.body?.date);

    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "Invalid workDate" });
    }

    const identity = readIdentityFromBody(req.body || {});
    const { staffId, userId, principalId, principalType } = identity;

    if (!principalId) {
      return res.status(400).json({
        ok: false,
        message: "staffId/principalId/userId required",
      });
    }

    let minutes = clampMinutes(
      req.body?.minutes ??
        req.body?.approvedMinutes ??
        req.body?.approvedOtMinutes ??
        req.body?.otMinutes
    );

    const start = readStartTime(req.body);
    const end = readEndTime(req.body);

    if (!minutes) {
      const computed = computeMinutesFromStartEnd(start, end);

      if (computed == null) {
        return res.status(400).json({
          ok: false,
          message: "Invalid time format",
        });
      }

      minutes = computed;
    }

    if (minutes <= 0) {
      return res.status(400).json({ ok: false, message: "OT must be > 0" });
    }

    let requestedApprovedMinutes =
      req.body?.approvedMinutes != null
        ? clampMinutes(req.body.approvedMinutes)
        : minutes;

    if (requestedApprovedMinutes <= 0) {
      requestedApprovedMinutes = minutes;
    }

    if (requestedApprovedMinutes > minutes) {
      return res.status(400).json({
        ok: false,
        message: "approvedMinutes cannot exceed minutes",
      });
    }

    const multiplierInput = Number(req.body?.multiplier);
    const multiplier =
      Number.isFinite(multiplierInput) && multiplierInput > 0
        ? multiplierInput
        : Number(policy.otMultiplier || 1.5);

    if (!Number.isFinite(multiplier) || multiplier <= 0) {
      return res.status(400).json({
        ok: false,
        message: "Invalid multiplier",
      });
    }

    const note = s(req.body?.note || req.body?.reason || "Admin manual OT");

    const asPending =
      req.body?.asPending === true || s(req.body?.status).toLowerCase() === "pending";

    const status = asPending ? "pending" : "approved";
    const approvedMinutes = status === "approved" ? requestedApprovedMinutes : 0;

    const now = new Date();
    const actor = s(actorUserId) || "admin";

    const activeMatch = {
      clinicId,
      workDate,
      source: "manual",
      status: { $in: ["pending", "approved", "locked"] },
      ...buildPrincipalQueryFromInput({
        staffId,
        principalId,
        userId,
      }),
    };

    const existing = await Overtime.findOne(activeMatch);

    if (existing && s(existing.status) === "locked") {
      return res.status(409).json({
        ok: false,
        code: "MANUAL_OT_LOCKED",
        message:
          "Manual OT for this date is locked by payroll. Recalculate/unlock payroll flow is required.",
        overtime: existing,
      });
    }

    const patch = {
      clinicId,
      principalId,
      principalType,
      staffId: staffId || "",
      userId: userId || "",

      workDate,
      monthKey: toMonthKey(workDate),

      start,
      end,
      startTime: start,
      endTime: end,

      minutes,
      approvedMinutes,
      multiplier,

      status,
      source: "manual",

      note,
      createdBy: actor,

      approvedBy: status === "approved" ? actor : "",
      approvedAt: status === "approved" ? now : null,

      rejectedBy: "",
      rejectedAt: null,
      rejectReason: "",
    };

    if (existing) {
      await Overtime.updateOne(
        { _id: existing._id },
        {
          $set: patch,
          $unset: { attendanceSessionId: "" },
        }
      );

      const fresh = await Overtime.findById(existing._id).lean();

      return res.status(200).json({
        ok: true,
        updated: true,
        created: false,
        message:
          status === "approved"
            ? "Manual OT updated and approved"
            : "Manual OT updated as pending",
        overtime: fresh,
      });
    }

    try {
      const created = await Overtime.create(patch);

      return res.status(201).json({
        ok: true,
        updated: false,
        created: true,
        message:
          status === "approved"
            ? "Manual OT saved and approved"
            : "Manual OT saved as pending",
        overtime: created,
      });
    } catch (e) {
      if (e && e.code === 11000) {
        const recovered = await Overtime.findOne(activeMatch).lean();

        if (recovered) {
          return res.status(200).json({
            ok: true,
            updated: false,
            created: false,
            recovered: true,
            message:
              "Manual OT already existed. Returned existing record instead of failing.",
            overtime: recovered,
          });
        }

        return res.status(409).json({
          ok: false,
          code: "OT_DUPLICATE_INDEX_NEEDS_CLEANUP",
          message:
            "Duplicate index blocked manual OT save. Please deploy updated Overtime model and run Mongo index cleanup for attendanceSessionId.",
          details: {
            keyPattern: e.keyPattern || null,
            keyValue: e.keyValue || null,
          },
        });
      }

      throw e;
    }
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ ADMIN UPDATE OT
// ======================================================
async function updateOne(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const id = s(req.params?.id);

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ ok: false, message: "Invalid id" });
    }

    const ot = await Overtime.findById(id);

    if (!ot || s(ot.clinicId) !== clinicId) {
      return res.status(404).json({ ok: false, message: "Not found" });
    }

    if (!canMutateStatus(ot)) {
      return res.status(409).json({ ok: false, message: "Locked" });
    }

    const patch = {};

    const start = readStartTime(req.body);
    const end = readEndTime(req.body);

    if (start) {
      patch.start = start;
      patch.startTime = start;
    }

    if (end) {
      patch.end = end;
      patch.endTime = end;
    }

    if (req.body?.minutes != null || req.body?.otMinutes != null) {
      const m = clampMinutes(req.body.minutes ?? req.body.otMinutes);

      if (m <= 0) {
        return res
          .status(400)
          .json({ ok: false, message: "minutes must be > 0" });
      }

      patch.minutes = m;

      if (s(ot.status) === "approved") {
        patch.approvedMinutes = m;
      }
    } else if (start && end) {
      const computed = computeMinutesFromStartEnd(start, end);

      if (computed == null) {
        return res
          .status(400)
          .json({ ok: false, message: "Invalid time format" });
      }

      if (computed <= 0) {
        return res.status(400).json({ ok: false, message: "OT must be > 0" });
      }

      patch.minutes = computed;

      if (s(ot.status) === "approved") {
        patch.approvedMinutes = computed;
      }
    }

    if (req.body?.approvedMinutes != null) {
      const approvedMinutes = clampMinutes(req.body.approvedMinutes);
      const maxMinutes = clampMinutes(patch.minutes ?? ot.minutes);

      if (approvedMinutes < 0 || approvedMinutes > maxMinutes) {
        return res
          .status(400)
          .json({ ok: false, message: "Invalid approvedMinutes" });
      }

      patch.approvedMinutes = approvedMinutes;
    }

    if (req.body?.multiplier != null) {
      const multiplier = Number(req.body.multiplier);

      if (!Number.isFinite(multiplier) || multiplier <= 0) {
        return res
          .status(400)
          .json({ ok: false, message: "Invalid multiplier" });
      }

      patch.multiplier = multiplier;
    }

    if (req.body?.note != null || req.body?.reason != null) {
      patch.note = s(req.body.note || req.body.reason);
    }

    if (Object.keys(patch).length === 0) {
      return res.json({ ok: true, overtime: ot });
    }

    await Overtime.updateOne({ _id: ot._id }, { $set: patch });
    const fresh = await Overtime.findById(ot._id).lean();

    return res.json({ ok: true, overtime: fresh });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ ADMIN APPROVE
// ======================================================
async function approveOne(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const id = s(req.params?.id);

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ ok: false, message: "Invalid id" });
    }

    const ot = await Overtime.findById(id);

    if (!ot || s(ot.clinicId) !== clinicId) {
      return res.status(404).json({ ok: false, message: "Not found" });
    }

    if (!canMutateStatus(ot)) {
      return res.status(409).json({ ok: false, message: "Locked" });
    }

    const approvedMinutesInput = req.body?.approvedMinutes;

    const approvedMinutes =
      approvedMinutesInput != null
        ? clampMinutes(approvedMinutesInput)
        : clampMinutes(ot.minutes);

    if (approvedMinutes > clampMinutes(ot.minutes)) {
      return res.status(400).json({
        ok: false,
        message: "approvedMinutes cannot exceed minutes",
      });
    }

    await Overtime.updateOne(
      { _id: ot._id },
      {
        $set: {
          status: "approved",
          approvedMinutes,
          approvedAt: new Date(),
          approvedBy: s(userId) || "admin",
          rejectedAt: null,
          rejectedBy: "",
          rejectReason: "",
        },
      }
    );

    const fresh = await Overtime.findById(ot._id).lean();
    return res.json({ ok: true, overtime: fresh });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ ADMIN REJECT
// ======================================================
async function rejectOne(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const id = s(req.params?.id);

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ ok: false, message: "Invalid id" });
    }

    const ot = await Overtime.findById(id);

    if (!ot || s(ot.clinicId) !== clinicId) {
      return res.status(404).json({ ok: false, message: "Not found" });
    }

    if (!canMutateStatus(ot)) {
      return res.status(409).json({ ok: false, message: "Locked" });
    }

    await Overtime.updateOne(
      { _id: ot._id },
      {
        $set: {
          status: "rejected",
          approvedMinutes: 0,
          rejectedAt: new Date(),
          rejectedBy: s(userId) || "admin",
          rejectReason: s(req.body?.note || req.body?.reason),
        },
      }
    );

    const fresh = await Overtime.findById(ot._id).lean();
    return res.json({ ok: true, overtime: fresh });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ BULK APPROVE MONTH
// ======================================================
async function bulkApproveMonth(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const monthKey = parseMonthOrNull(req.body?.month || req.query?.month);

    if (!monthKey) {
      return res
        .status(400)
        .json({ ok: false, message: "month required (yyyy-MM)" });
    }

    const identity = readIdentityFromBody({
      ...req.query,
      ...req.body,
    });

    const pQuery = buildPrincipalQueryFromInput(identity);

    if (!pQuery) {
      return res.status(400).json({
        ok: false,
        message: "staffId/principalId/userId required",
      });
    }

    const pendingRows = await Overtime.find({
      clinicId,
      monthKey,
      status: "pending",
      ...pQuery,
    }).select({ _id: 1, minutes: 1 });

    if (!pendingRows.length) {
      return res.json({
        ok: true,
        month: monthKey,
        matched: 0,
        modified: 0,
      });
    }

    const approvedAt = new Date();
    let modified = 0;

    for (const row of pendingRows) {
      const r = await Overtime.updateOne(
        { _id: row._id },
        {
          $set: {
            status: "approved",
            approvedAt,
            approvedBy: s(userId) || "admin",
            approvedMinutes: clampMinutes(row.minutes),
          },
        }
      );

      modified += r.modifiedCount ?? r.nModified ?? 0;
    }

    return res.json({
      ok: true,
      month: monthKey,
      matched: pendingRows.length,
      modified,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ BULK APPROVE DAY
// ======================================================
async function bulkApproveDay(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const workDate = s(req.body?.workDate || req.query?.workDate);

    if (!isYmd(workDate)) {
      return res.status(400).json({
        ok: false,
        message: "workDate required (yyyy-MM-dd)",
      });
    }

    const identity = readIdentityFromBody({
      ...req.query,
      ...req.body,
    });

    const pQuery = buildPrincipalQueryFromInput(identity);

    if (!pQuery) {
      return res.status(400).json({
        ok: false,
        message: "staffId/principalId/userId required",
      });
    }

    const pendingRows = await Overtime.find({
      clinicId,
      workDate,
      status: "pending",
      ...pQuery,
    }).select({ _id: 1, minutes: 1 });

    if (!pendingRows.length) {
      return res.json({
        ok: true,
        workDate,
        matched: 0,
        modified: 0,
      });
    }

    const approvedAt = new Date();
    let modified = 0;

    for (const row of pendingRows) {
      const r = await Overtime.updateOne(
        { _id: row._id },
        {
          $set: {
            status: "approved",
            approvedAt,
            approvedBy: s(userId) || "admin",
            approvedMinutes: clampMinutes(row.minutes),
          },
        }
      );

      modified += r.modifiedCount ?? r.nModified ?? 0;
    }

    return res.json({
      ok: true,
      workDate,
      matched: pendingRows.length,
      modified,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}


// ======================================================
// ✅ RECALCULATE ATTENDANCE OT
// คำนวณ OT จาก AttendanceSession ตาม ClinicPolicy ล่าสุด
// ใช้สำหรับกรณี admin เปลี่ยน OT policy แล้วต้องสร้าง/update OT ใหม่
// ======================================================
async function recalculateAttendance(req, res) {
  try {
    const { clinicId, role, userId: actorId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, actorId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const workDate = s(req.body?.workDate || req.query?.workDate);
    const month = parseMonthOrNull(req.body?.month || req.query?.month);

    if (workDate && !isYmd(workDate)) {
      return res.status(400).json({
        ok: false,
        message: "Invalid workDate. Use yyyy-MM-dd",
      });
    }

    if (!workDate && !month) {
      return res.status(400).json({
        ok: false,
        message: "workDate or month required",
      });
    }

    const principalId = s(
      req.body?.principalId ||
        req.body?.employeeId ||
        req.body?.staffId ||
        req.body?.userId ||
        req.query?.principalId ||
        req.query?.employeeId ||
        req.query?.staffId ||
        req.query?.userId
    );

    const staffId = s(req.body?.staffId || req.body?.employeeId || req.query?.staffId || req.query?.employeeId);
    const targetUserId = s(req.body?.userId || req.query?.userId);

    const identityOr = buildTargetAttendanceOr({
      principalId,
      staffId,
      userId: targetUserId,
    });

    if (!identityOr.length) {
      return res.status(400).json({
        ok: false,
        message: "principalId, staffId, employeeId, or userId required",
      });
    }

    const attendanceQuery = {
      clinicId,
      status: "closed",
      checkInAt: { $ne: null },
      checkOutAt: { $ne: null },
      $or: identityOr,
    };

    if (workDate) {
      attendanceQuery.workDate = workDate;
    } else {
      attendanceQuery.workDate = { $regex: `^${month}-` };
    }

    const sessions = await AttendanceSession.find(attendanceQuery).sort({
      workDate: 1,
      checkInAt: 1,
      createdAt: 1,
    });

    let created = 0;
    let updated = 0;
    let removed = 0;
    let skipped = 0;

    const results = [];

    for (const session of sessions) {
      const sessionWorkDate = s(session.workDate);
      const sessionPrincipalId = s(session.principalId || session.staffId || session.userId);
      const calc = computeAttendanceOtByLatestPolicy(policy, session);

      const existing = await Overtime.findOne({
        clinicId,
        source: "attendance",
        $or: [
          { attendanceSessionId: session._id },
          {
            principalId: sessionPrincipalId,
            workDate: sessionWorkDate,
          },
        ],
      });

      const existingStatus = s(existing?.status);

      // ไม่แตะรายการที่ approve/locked แล้ว เพื่อความปลอดภัยของ payroll/audit
      if (existing && ["approved", "locked"].includes(existingStatus)) {
        skipped += 1;
        results.push({
          workDate: sessionWorkDate,
          attendanceSessionId: String(session._id),
          action: "skipped_approved_or_locked",
          status: existingStatus,
          minutes: existing.minutes,
        });
        continue;
      }

      if (calc.minutes <= 0) {
        if (existing) {
          await Overtime.deleteOne({ _id: existing._id });
          removed += 1;
          results.push({
            workDate: sessionWorkDate,
            attendanceSessionId: String(session._id),
            action: "removed_no_ot",
            reason: calc.reason,
          });
        } else {
          skipped += 1;
          results.push({
            workDate: sessionWorkDate,
            attendanceSessionId: String(session._id),
            action: "skipped_no_ot",
            reason: calc.reason,
          });
        }
        continue;
      }

      const multiplierRaw =
        policy?.otMultiplier ??
        policy?.normalOtMultiplier ??
        policy?.defaultOtMultiplier ??
        1.5;

      const multiplier = Number.isFinite(Number(multiplierRaw))
        ? Number(multiplierRaw)
        : 1.5;

      const payload = {
        clinicId,
        principalId: sessionPrincipalId,
        principalType: s(session.principalType) || "staff",
        staffId: s(session.staffId),
        userId: s(session.userId),
        workDate: sessionWorkDate,
        monthKey: toMonthKey(sessionWorkDate),

        start: calc.start,
        end: calc.end,
        startTime: calc.start,
        endTime: calc.end,

        minutes: clampMinutes(calc.minutes),
        approvedMinutes: 0,
        multiplier,

        status: "pending",
        source: "attendance",
        attendanceSessionId: session._id,

        approvedBy: "",
        approvedAt: null,
        rejectedBy: "",
        rejectedAt: null,
        rejectReason: "",

        createdBy: s(actorId) || "admin",
        note: `Recalculated from attendance using latest OT policy ${calc.policyStart}-${calc.policyEnd}`,
      };

      if (existing) {
        existing.set(payload);
        await existing.save();
        updated += 1;
        results.push({
          workDate: sessionWorkDate,
          attendanceSessionId: String(session._id),
          overtimeId: String(existing._id),
          action: "updated",
          minutes: payload.minutes,
          start: payload.start,
          end: payload.end,
        });
      } else {
        const createdDoc = await Overtime.create(payload);
        created += 1;
        results.push({
          workDate: sessionWorkDate,
          attendanceSessionId: String(session._id),
          overtimeId: String(createdDoc._id),
          action: "created",
          minutes: payload.minutes,
          start: payload.start,
          end: payload.end,
        });
      }
    }

    return res.json({
      ok: true,
      action: "recalculate_attendance_ot",
      clinicId,
      workDate: workDate || "",
      month: month || "",
      policy: {
        otWindowStart: s(policy?.otWindowStart),
        otWindowEnd: s(policy?.otWindowEnd),
      },
      matchedSessions: sessions.length,
      created,
      updated,
      removed,
      skipped,
      results,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ DELETE
// รองรับ manual, manual_user และ attendance OT ที่ยังแก้ไขได้
// ห้ามลบรายการที่ locked / approved / payroll closed ตาม canMutateStatus()
// ======================================================
async function removeOne(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const id = s(req.params.id);

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ ok: false, message: "Invalid id" });
    }

    const ot = await Overtime.findById(id);

    if (!ot || s(ot.clinicId) !== clinicId) {
      return res.status(404).json({ ok: false, message: "Not found" });
    }

    if (!canMutateStatus(ot)) {
      return res.status(409).json({ ok: false, message: "Locked" });
    }

    const src = s(ot.source);
    const status = s(ot.status);

    // Attendance OT comes from real scan data.
    // If it has already been approved, do not delete it directly.
    // Admin should reject/recalculate only while it is still pending/rejected.
    if (src === "attendance" && status === "approved") {
      return res.status(409).json({
        ok: false,
        message: "Cannot delete approved attendance OT",
      });
    }

    // Allow admin to delete OT records that are still mutable.
    // This is needed when clinic OT policy changes and a pending attendance OT
    // must be removed/re-created from the latest policy.
    //
    // Safety is still enforced above by canMutateStatus(ot), so approved,
    // locked, or payroll-closed OT records remain protected.
    const deletableSources = ["manual", "manual_user", "attendance"];

    if (!deletableSources.includes(src)) {
      return res.status(409).json({
        ok: false,
        message: "Cannot delete this OT source",
        source: src,
      });
    }

    await Overtime.deleteOne({ _id: ot._id });

    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ✅ Safety
function _assertFn(name, fn) {
  if (typeof fn !== "function") {
    throw new Error(`overtimeController: ${name} is not defined`);
  }
}

_assertFn("listMy", listMy);
_assertFn("requestOt", requestOt);
_assertFn("listForStaff", listForStaff);
_assertFn("createManual", createManual);
_assertFn("updateOne", updateOne);
_assertFn("approveOne", approveOne);
_assertFn("rejectOne", rejectOne);
_assertFn("bulkApproveMonth", bulkApproveMonth);
_assertFn("bulkApproveDay", bulkApproveDay);
_assertFn("recalculateAttendance", recalculateAttendance);
_assertFn("removeOne", removeOne);

module.exports = {
  listMy,
  requestOt,
  listForStaff,
  createManual,
  updateOne,
  approveOne,
  rejectOne,
  bulkApproveMonth,
  bulkApproveDay,
  recalculateAttendance,
  removeOne,
  sumApprovedMinutesForMonth,
  sumApprovedMinutesForDay,
};