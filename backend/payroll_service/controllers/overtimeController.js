// backend/payroll_service/controllers/overtimeController.js
//
// ✅ PRODUCTION OVERTIME CONTROLLER
// ------------------------------------------------------
// ✅ Supports:
// - Auto OT from attendance source="attendance"
// - Admin manual OT source="manual"
// - Employee/user request OT source="manual_user"
//
// ✅ Important production fix:
// - Admin manual OT is saved as REAL backend Overtime record
// - Admin manual OT defaults to status="approved"
// - approvedMinutes is set immediately
// - Payroll close can include it even when staff cannot scan fingerprint
//
// ✅ Why:
// - policy.requireOtApproval=true should affect employee/user requests,
//   not block admin manual input from payroll.
// ------------------------------------------------------

const mongoose = require("mongoose");
const Overtime = require("../models/Overtime");
const ClinicPolicy = require("../models/ClinicPolicy");

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

/**
 * ✅ Normalize role name for policy comparison
 * - admin => clinic_admin
 * - clinicadmin => clinic_admin
 * - keep others as lowercase trimmed
 */
function normalizeRoleForPolicy(role) {
  const r = s(role).toLowerCase();
  if (!r) return "";
  if (r === "admin") return "clinic_admin";
  if (r === "clinicadmin") return "clinic_admin";
  return r;
}

/**
 * ✅ PRINCIPAL
 * รองรับทั้ง req.user และ req.userCtx
 */
function getPrincipal(req) {
  const u = req.user || {};
  const uc = req.userCtx || {};

  const clinicId = s(u.clinicId || uc.clinicId);
  const role = s(u.role || uc.role);
  const userId = s(u.userId || uc.userId);

  const staffId = s(
    u.staffId || u.employeeId || uc.staffId || uc.employeeId || ""
  );

  const principalId = staffId || userId;
  const principalType = staffId ? "staff" : "user";

  return { clinicId, role, userId, staffId, principalId, principalType };
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

function buildPrincipalQueryFromInput({ staffId, principalId }) {
  const sid = s(staffId);
  const pid = s(principalId);

  if (pid && sid) {
    return {
      $or: [{ principalId: pid }, { staffId: sid }, { principalId: sid }],
    };
  }

  if (pid) {
    return { $or: [{ principalId: pid }, { staffId: pid }] };
  }

  if (sid) {
    return { $or: [{ principalId: sid }, { staffId: sid }] };
  }

  return null;
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

// ===================== SUMMARY HELPERS =====================

async function sumApprovedMinutesForMonth({ clinicId, principalId, monthKey }) {
  const pid = s(principalId);

  const rows = await Overtime.find({
    clinicId,
    monthKey,
    status: "approved",
    ...(pid ? { $or: [{ principalId: pid }, { staffId: pid }] } : {}),
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
    ...(pid ? { $or: [{ principalId: pid }, { staffId: pid }] } : {}),
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

    const targetStaffId =
      s(req.query?.staffId) ||
      s(req.query?.employeeId) ||
      s(req.body?.staffId) ||
      s(req.body?.employeeId);

    const targetPrincipalId =
      s(req.query?.principalId) || s(req.body?.principalId);

    let q = { clinicId, monthKey };
    if (status) q.status = status;

    if (
      (role === "admin" || role === "clinic_admin") &&
      (targetStaffId || targetPrincipalId)
    ) {
      const pQuery = buildPrincipalQueryFromInput({
        staffId: targetStaffId,
        principalId: targetPrincipalId,
      });

      if (!pQuery) {
        return res.status(400).json({
          ok: false,
          message: "staffId/principalId required",
        });
      }

      q = { ...q, ...pQuery };
    } else {
      const selfPid = s(principalId);
      q = {
        ...q,
        $or: [{ principalId: selfPid }, { staffId: selfPid }],
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

    const staffId =
      s(req.params?.staffId) ||
      s(req.params?.employeeId) ||
      s(req.query?.staffId) ||
      s(req.query?.employeeId) ||
      s(req.body?.staffId) ||
      s(req.body?.employeeId);

    const principalId = s(req.query?.principalId) || s(req.body?.principalId);

    const pQuery = buildPrincipalQueryFromInput({ staffId, principalId });
    if (!pQuery) {
      return res
        .status(400)
        .json({ ok: false, message: "staffId or principalId required" });
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
      filter: { month: monthKey || "", status: status || "" },
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
      status: { $in: ["pending", "approved"] },
      $or: [{ principalId }, { staffId: principalId }],
    }).lean();

    if (duplicate) {
      return res.status(409).json({
        ok: false,
        code: "OT_REQUEST_ALREADY_EXISTS",
        message: "An OT request already exists for this date",
        overtimeId: String(duplicate._id || ""),
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
// ✅ ADMIN CREATE / UPSERT MANUAL OT
// ======================================================
// ✅ PRODUCTION RULE:
// - Admin manual OT is a real backend Overtime record
// - Default status = approved because admin is the approver
// - approvedMinutes is set immediately
// - Payroll close can include it immediately
// - Idempotent per clinic/principal/workDate/source=manual
//
// ✅ If you ever want admin to create pending OT instead:
// - send { asPending: true }
// ======================================================
async function createManual(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    if (!canApproveOtByRole(policy, role)) {
      return res.status(403).json({ ok: false, message: "Admin only" });
    }

    const workDate = s(req.body?.workDate || req.body?.date);
    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "Invalid workDate" });
    }

    const staffId = s(req.body?.staffId || req.body?.employeeId);
    const explicitUserId = s(req.body?.userId);

    const principalId =
      s(req.body?.principalId) || staffId || explicitUserId;

    if (!principalId) {
      return res.status(400).json({
        ok: false,
        message: "staffId/principalId/userId required",
      });
    }

    const principalTypeInput = s(req.body?.principalType).toLowerCase();

    const principalType =
      principalTypeInput === "user" || principalTypeInput === "staff"
        ? principalTypeInput
        : staffId
        ? "staff"
        : "user";

    let minutes = clampMinutes(
      req.body?.minutes ??
        req.body?.approvedMinutes ??
        req.body?.approvedOtMinutes ??
        req.body?.otMinutes
    );

    if (!minutes) {
      const start = readStartTime(req.body);
      const end = readEndTime(req.body);
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

    const note = s(req.body?.note || req.body?.reason);

    // ✅ สำคัญมาก:
    // admin manual OT ต้อง approved ทันทีเพื่อให้ payroll close เอาไปคำนวณได้
    // policy.requireOtApproval ยังใช้กับ manual_user request ได้ แต่ไม่ควร block admin input
    const asPending =
      req.body?.asPending === true || s(req.body?.status) === "pending";

    const status = asPending ? "pending" : "approved";
    const approvedMinutes = status === "approved" ? requestedApprovedMinutes : 0;

    const now = new Date();
    const actor = s(userId) || "admin";

    const filter = {
      clinicId,
      principalId,
      workDate,
      source: "manual",
      status: { $in: ["pending", "approved"] },
    };

    const patch = {
      clinicId,
      principalId,
      principalType,
      staffId: staffId || "",
      userId: explicitUserId || "",

      workDate,
      monthKey: toMonthKey(workDate),

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

    const overtime = await Overtime.findOneAndUpdate(
      filter,
      { $set: patch },
      {
        new: true,
        upsert: true,
        setDefaultsOnInsert: true,
      }
    ).lean();

    return res.status(201).json({
      ok: true,
      message:
        status === "approved"
          ? "Manual OT saved and approved"
          : "Manual OT saved as pending",
      overtime,
    });
  } catch (e) {
    if (e && e.code === 11000) {
      return res.status(409).json({
        ok: false,
        code: "MANUAL_OT_ALREADY_EXISTS_OR_LOCKED",
        message:
          "Manual OT already exists for this staff/date or is locked by payroll. Please update/recalculate through the correct flow.",
      });
    }

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
    } else {
      const start = readStartTime(req.body);
      const end = readEndTime(req.body);

      if (start && end) {
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

    const staffId = s(
      req.body?.staffId ||
        req.body?.employeeId ||
        req.query?.staffId ||
        req.query?.employeeId
    );

    const principalId =
      s(req.body?.principalId || req.query?.principalId) || staffId;

    if (!principalId) {
      return res
        .status(400)
        .json({ ok: false, message: "staffId/principalId required" });
    }

    const principalMatch = buildPrincipalQueryFromInput({
      staffId: staffId || principalId,
      principalId,
    });

    if (!principalMatch) {
      return res
        .status(400)
        .json({ ok: false, message: "staffId/principalId required" });
    }

    const pendingRows = await Overtime.find({
      clinicId,
      monthKey,
      status: "pending",
      ...principalMatch,
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

    const staffId = s(
      req.body?.staffId ||
        req.body?.employeeId ||
        req.query?.staffId ||
        req.query?.employeeId
    );

    const principalId =
      s(req.body?.principalId || req.query?.principalId) || staffId;

    if (!principalId) {
      return res
        .status(400)
        .json({ ok: false, message: "staffId/principalId required" });
    }

    const principalMatch = buildPrincipalQueryFromInput({
      staffId: staffId || principalId,
      principalId,
    });

    if (!principalMatch) {
      return res
        .status(400)
        .json({ ok: false, message: "staffId/principalId required" });
    }

    const pendingRows = await Overtime.find({
      clinicId,
      workDate,
      status: "pending",
      ...principalMatch,
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
// ✅ DELETE
// รองรับ manual และ manual_user
// ไม่ให้ลบ auto attendance OT
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
    if (!["manual", "manual_user"].includes(src)) {
      return res
        .status(409)
        .json({ ok: false, message: "Cannot delete auto OT" });
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
  removeOne,
  sumApprovedMinutesForMonth,
  sumApprovedMinutesForDay,
};