// backend/payroll_service/controllers/overtimeController.js
const mongoose = require("mongoose");
const Overtime = require("../models/Overtime");

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

/**
 * ✅ PRINCIPAL (รองรับ helper ไม่มี staffId)
 * - ถ้ามี staffId => principalId = staffId, principalType="staff"
 * - ถ้าไม่มี staffId => principalId = userId, principalType="user"
 */
function getPrincipal(req) {
  const clinicId = s(req.user?.clinicId);
  const role = s(req.user?.role);
  const userId = s(req.user?.userId);
  const staffId = s(req.user?.staffId);

  const principalId = staffId || userId;
  const principalType = staffId ? "staff" : "user";

  return { clinicId, role, userId, staffId, principalId, principalType };
}

// helper: accept either staffId (legacy) or principalId
function buildPrincipalQueryFromInput({ staffId, principalId }) {
  const sid = s(staffId);
  const pid = s(principalId);

  // if caller provides principalId, prefer it
  if (pid) return { principalId: pid };

  // legacy: if staffId provided, map to principalId as well
  if (sid) return { principalId: sid, staffId: sid };

  return null;
}

// ======================================================
// ✅ NEW helpers: time parsing (HH:mm) -> minutes
// ======================================================
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

  // รองรับข้ามวัน: 20:00 -> 02:00
  let end = b;
  if (end < a) end += 24 * 60;

  const diff = end - a;
  if (diff <= 0) return 0;
  return diff;
}

// ======================================================
// ✅ HELPERS (for payroll close / payslip)
// NOTE: ใช้ principalId เป็นแกนหลัก (รองรับ helper)
// ======================================================
async function sumApprovedMinutesForMonth({ clinicId, principalId, monthKey }) {
  const q = {
    clinicId: s(clinicId),
    principalId: s(principalId),
    monthKey: s(monthKey),
    status: "approved",
  };
  const rows = await Overtime.find(q).select({ minutes: 1 }).lean();
  return rows.reduce((a, x) => a + clampMinutes(x.minutes), 0);
}

async function sumApprovedMinutesForDay({ clinicId, principalId, workDate }) {
  const q = {
    clinicId: s(clinicId),
    principalId: s(principalId),
    workDate: s(workDate),
    status: "approved",
  };
  const rows = await Overtime.find(q).select({ minutes: 1 }).lean();
  return rows.reduce((a, x) => a + clampMinutes(x.minutes), 0);
}

// ======================================================
// ✅ STAFF/EMPLOYEE/HELPER (READ-ONLY)
// GET /overtime/my
// query: month=yyyy-MM (required)
//        status=pending|approved|rejected|locked (optional)
// ======================================================
async function listMy(req, res) {
  try {
    const { clinicId, role, staffId, userId, principalId, principalType } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!principalId) return res.status(401).json({ ok: false, message: "Missing userId/staffId in token" });

    // ✅ allow employee + helper (and optionally staff if some service uses that string)
    const allowed = ["employee", "helper", "staff"];
    if (role && !allowed.includes(role)) {
      return res.status(403).json({ ok: false, message: "Forbidden" });
    }

    const monthKey = parseMonthOrNull(req.query?.month);
    if (!monthKey) return res.status(400).json({ ok: false, message: "month required (yyyy-MM)" });

    const status = s(req.query?.status);

    const q = { clinicId, principalId, monthKey };
    if (status) q.status = status;

    const items = await Overtime.find(q).sort({ workDate: 1, createdAt: 1 }).lean();

    const sum = (st) =>
      items
        .filter((x) => s(x.status) === st)
        .reduce((a, x) => a + clampMinutes(x.minutes), 0);

    return res.json({
      ok: true,
      month: monthKey,
      principal: { principalId, principalType, staffId, userId },
      summary: {
        pendingMinutes: sum("pending"),
        approvedMinutes: sum("approved"),
        rejectedMinutes: sum("rejected"),
        lockedMinutes: sum("locked"),
      },
      items,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "list my overtime failed", error: e.message });
  }
}

// ======================================================
// ✅ NEW: STANDARD USER ส่ง OT เอง (PENDING)
// POST /overtime/request
// body: { workDate(yyyy-MM-dd), start(HH:mm), end(HH:mm), multiplier?, note? }
// - ผูก clinicId/principalId จาก token (กันปลอม)
// - status="pending", source="manual_user"
// ======================================================
async function requestOt(req, res) {
  try {
    const { clinicId, role, userId, staffId, principalId, principalType } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!principalId) return res.status(401).json({ ok: false, message: "Missing userId/staffId in token" });

    const allowed = ["employee", "helper", "staff"];
    if (role && !allowed.includes(role)) {
      return res.status(403).json({ ok: false, message: "Forbidden" });
    }

    const workDate = s(req.body?.workDate);
    const start = s(req.body?.start);
    const end = s(req.body?.end);

    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    const computed = computeMinutesFromStartEnd(start, end);
    if (computed == null) {
      return res.status(400).json({ ok: false, message: "start/end required (HH:mm)" });
    }
    if (computed <= 0) {
      return res.status(400).json({ ok: false, message: "OT minutes must be > 0" });
    }

    const multiplier = Number(req.body?.multiplier);
    const mul = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1.5;

    const created = await Overtime.create({
      clinicId,

      // ✅ required by model
      principalId,
      principalType,

      // ✅ keep legacy fields for payrollCloseController compatibility
      staffId: staffId || "",
      userId: userId || "",

      workDate,
      monthKey: toMonthKey(workDate),
      minutes: computed,
      multiplier: mul,

      status: "pending",
      source: "manual_user",
      note: s(req.body?.note),

      approvedBy: "",
      approvedAt: null,
      rejectedBy: "",
      rejectedAt: null,
      rejectReason: "",
      lockedBy: "",
      lockedAt: null,
      lockedMonth: "",
    });

    return res.status(201).json({
      ok: true,
      overtime: created.toObject(),
      submittedBy: { principalId, principalType },
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "request overtime failed", error: e.message });
  }
}

// ======================================================
// ✅ ADMIN LIST
// GET /overtime   (admin)
// query: month=yyyy-MM (required)
//        principalId=... (recommended) OR staffId=... (legacy)
//        status=pending|approved|rejected|locked (optional)
// ======================================================
async function listForStaff(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const monthKey = parseMonthOrNull(req.query?.month);
    if (!monthKey) return res.status(400).json({ ok: false, message: "month required (yyyy-MM)" });

    const status = s(req.query?.status);

    const principalId = s(req.query?.principalId);
    const staffId = s(req.query?.staffId);

    const principalQ = buildPrincipalQueryFromInput({ staffId, principalId });
    if (!principalQ) {
      return res.status(400).json({ ok: false, message: "principalId or staffId required" });
    }

    const q = { clinicId, monthKey, ...principalQ };
    if (status) q.status = status;

    const items = await Overtime.find(q).sort({ workDate: 1, createdAt: 1 }).lean();

    const sum = (st) =>
      items
        .filter((x) => s(x.status) === st)
        .reduce((a, x) => a + clampMinutes(x.minutes), 0);

    return res.json({
      ok: true,
      month: monthKey,
      requested: { principalId: principalId || null, staffId: staffId || null },
      summary: {
        pendingMinutes: sum("pending"),
        approvedMinutes: sum("approved"),
        rejectedMinutes: sum("rejected"),
        lockedMinutes: sum("locked"),
      },
      items,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "list overtime failed", error: e.message });
  }
}

// ======================================================
// ✅ ADMIN CREATE MANUAL OT
// POST /overtime/manual  (admin)
// body: {
//   staffId? (employee), userId? (helper), workDate(yyyy-MM-dd), minutes,
//   multiplier?, note?
// }
// - principalId = staffId || userId (required by model)
// ======================================================
async function createManual(req, res) {
  try {
    const { clinicId, role, userId: adminUserId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const staffId = s(req.body?.staffId);
    const targetUserId = s(req.body?.userId); // helper can be usr_...
    const workDate = s(req.body?.workDate);
    const minutes = clampMinutes(req.body?.minutes);

    if (!isYmd(workDate)) return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    if (minutes <= 0) return res.status(400).json({ ok: false, message: "minutes must be > 0" });

    const principalId = staffId || targetUserId;
    const principalType = staffId ? "staff" : "user";

    if (!principalId) {
      return res.status(400).json({ ok: false, message: "staffId or userId required" });
    }

    const monthKey = toMonthKey(workDate);
    const multiplier = Number(req.body?.multiplier);
    const mul = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1.5;

    const created = await Overtime.create({
      clinicId,

      // ✅ required by model
      principalId,
      principalType,

      // optional legacy/audit fields
      staffId: staffId || "",
      userId: targetUserId || "",

      workDate,
      monthKey,
      minutes,
      multiplier: mul,
      status: "pending",
      source: "manual",
      note: s(req.body?.note),

      approvedBy: "",
      approvedAt: null,
      rejectedBy: "",
      rejectedAt: null,
      rejectReason: "",
      lockedBy: "",
      lockedAt: null,
      lockedMonth: "",
    });

    return res.status(201).json({ ok: true, overtime: created.toObject(), createdBy: adminUserId });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "create manual overtime failed", error: e.message });
  }
}

// ======================================================
// PATCH /overtime/:id  (admin)
// body: { minutes?, multiplier?, note? }
// - only if not locked
// ======================================================
async function updateOne(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const id = s(req.params.id);
    if (!mongoose.Types.ObjectId.isValid(id)) return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId) return res.status(404).json({ ok: false, message: "Overtime not found" });

    if (!canMutateStatus(ot)) return res.status(409).json({ ok: false, message: "Locked overtime cannot be edited" });

    if (req.body?.minutes !== undefined) {
      const m = clampMinutes(req.body.minutes);
      if (m <= 0) return res.status(400).json({ ok: false, message: "minutes must be > 0" });
      ot.minutes = m;
    }

    if (req.body?.multiplier !== undefined) {
      const x = Number(req.body.multiplier);
      if (!(Number.isFinite(x) && x > 0))
        return res.status(400).json({ ok: false, message: "multiplier must be > 0" });
      ot.multiplier = x;
    }

    if (req.body?.note !== undefined) {
      ot.note = s(req.body.note);
    }

    await ot.save();
    return res.json({ ok: true, overtime: ot.toObject() });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "update overtime failed", error: e.message });
  }
}

// ======================================================
// PATCH /overtime/:id/approve  (admin)
// ======================================================
async function approveOne(req, res) {
  try {
    const { clinicId, role, userId: adminUserId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const id = s(req.params.id);
    if (!mongoose.Types.ObjectId.isValid(id)) return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId) return res.status(404).json({ ok: false, message: "Overtime not found" });

    if (!canMutateStatus(ot)) return res.status(409).json({ ok: false, message: "Locked overtime cannot be approved" });

    ot.status = "approved";
    ot.approvedBy = adminUserId;
    ot.approvedAt = new Date();

    ot.rejectedBy = "";
    ot.rejectedAt = null;
    ot.rejectReason = "";

    await ot.save();
    return res.json({ ok: true, overtime: ot.toObject() });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "approve overtime failed", error: e.message });
  }
}

// ======================================================
// PATCH /overtime/:id/reject  (admin)
// body: { reason? }
// ======================================================
async function rejectOne(req, res) {
  try {
    const { clinicId, role, userId: adminUserId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const id = s(req.params.id);
    if (!mongoose.Types.ObjectId.isValid(id)) return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId) return res.status(404).json({ ok: false, message: "Overtime not found" });

    if (!canMutateStatus(ot)) return res.status(409).json({ ok: false, message: "Locked overtime cannot be rejected" });

    ot.status = "rejected";
    ot.rejectedBy = adminUserId;
    ot.rejectedAt = new Date();
    ot.rejectReason = s(req.body?.reason);

    ot.approvedBy = "";
    ot.approvedAt = null;

    await ot.save();
    return res.json({ ok: true, overtime: ot.toObject() });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "reject overtime failed", error: e.message });
  }
}

// ======================================================
// PATCH /overtime/bulk-approve/month  (admin)
// body: { principalId? , staffId? , month(yyyy-MM) }
// - approve all pending for that principal+month
// ======================================================
async function bulkApproveMonth(req, res) {
  try {
    const { clinicId, role, userId: adminUserId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const principalId = s(req.body?.principalId);
    const staffId = s(req.body?.staffId);
    const monthKey = parseMonthOrNull(req.body?.month);

    if (!monthKey) return res.status(400).json({ ok: false, message: "month required (yyyy-MM)" });

    const principalQ = buildPrincipalQueryFromInput({ staffId, principalId });
    if (!principalQ) return res.status(400).json({ ok: false, message: "principalId or staffId required" });

    const now = new Date();

    const r = await Overtime.updateMany(
      { clinicId, monthKey, status: "pending", principalId: principalQ.principalId },
      {
        $set: {
          status: "approved",
          approvedBy: adminUserId,
          approvedAt: now,
          rejectedBy: "",
          rejectedAt: null,
          rejectReason: "",
        },
      }
    );

    return res.json({
      ok: true,
      month: monthKey,
      principalId: principalQ.principalId,
      matched: r.matchedCount ?? r.n,
      modified: r.modifiedCount ?? r.nModified,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "bulk approve month failed", error: e.message });
  }
}

// ======================================================
// PATCH /overtime/bulk-approve/day  (admin)
// body: { principalId? , staffId? , workDate(yyyy-MM-dd) }
// - approve all pending for that principal+day
// ======================================================
async function bulkApproveDay(req, res) {
  try {
    const { clinicId, role, userId: adminUserId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const principalId = s(req.body?.principalId);
    const staffId = s(req.body?.staffId);
    const workDate = s(req.body?.workDate);

    if (!isYmd(workDate)) return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });

    const principalQ = buildPrincipalQueryFromInput({ staffId, principalId });
    if (!principalQ) return res.status(400).json({ ok: false, message: "principalId or staffId required" });

    const monthKey = toMonthKey(workDate);
    const now = new Date();

    const r = await Overtime.updateMany(
      { clinicId, monthKey, workDate, status: "pending", principalId: principalQ.principalId },
      {
        $set: {
          status: "approved",
          approvedBy: adminUserId,
          approvedAt: now,
          rejectedBy: "",
          rejectedAt: null,
          rejectReason: "",
        },
      }
    );

    return res.json({
      ok: true,
      workDate,
      principalId: principalQ.principalId,
      matched: r.matchedCount ?? r.n,
      modified: r.modifiedCount ?? r.nModified,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "bulk approve day failed", error: e.message });
  }
}

// ======================================================
// DELETE /overtime/:id  (admin)
// - allow delete only if not locked, and source=manual (safe)
// ======================================================
async function removeOne(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const id = s(req.params.id);
    if (!mongoose.Types.ObjectId.isValid(id)) return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId) return res.status(404).json({ ok: false, message: "Overtime not found" });

    if (!canMutateStatus(ot)) return res.status(409).json({ ok: false, message: "Locked overtime cannot be deleted" });
    if (s(ot.source) !== "manual") return res.status(409).json({ ok: false, message: "Only manual overtime can be deleted" });

    await Overtime.deleteOne({ _id: ot._id });
    return res.json({ ok: true, deleted: true });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "delete overtime failed", error: e.message });
  }
}

module.exports = {
  // ✅ staff/employee/helper
  listMy,

  // ✅ NEW
  requestOt,

  // ✅ admin
  listForStaff,
  createManual,
  updateOne,
  approveOne,
  rejectOne,
  bulkApproveMonth,
  bulkApproveDay,
  removeOne,

  // ✅ helpers (optional export for payrollClose/payroll preview)
  sumApprovedMinutesForMonth,
  sumApprovedMinutesForDay,
};