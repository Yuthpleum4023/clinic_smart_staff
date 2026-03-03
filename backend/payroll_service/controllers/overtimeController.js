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
 * ✅ PRINCIPAL (รองรับทั้ง req.user และ req.userCtx)
 */
function getPrincipal(req) {
  const u = req.user || {};
  const uc = req.userCtx || {};

  const clinicId = s(u.clinicId || uc.clinicId);
  const role = s(u.role || uc.role);
  const userId = s(u.userId || uc.userId);

  // ✅ staffId ต้องรองรับทั้ง user และ userCtx + legacy employeeId
  const staffId = s(u.staffId || u.employeeId || uc.staffId || uc.employeeId || "");

  const principalId = staffId || userId;
  const principalType = staffId ? "staff" : "user";

  return { clinicId, role, userId, staffId, principalId, principalType };
}

// helper
function buildPrincipalQueryFromInput({ staffId, principalId }) {
  const sid = s(staffId);
  const pid = s(principalId);

  if (pid) return { principalId: pid };
  if (sid) return { principalId: sid, staffId: sid };

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

// ===================== SUMMARY HELPERS =====================

async function sumApprovedMinutesForMonth({ clinicId, principalId, monthKey }) {
  const rows = await Overtime.find({
    clinicId,
    principalId,
    monthKey,
    status: "approved",
  })
    .select({ minutes: 1 })
    .lean();

  return rows.reduce((a, x) => a + clampMinutes(x.minutes), 0);
}

async function sumApprovedMinutesForDay({ clinicId, principalId, workDate }) {
  const rows = await Overtime.find({
    clinicId,
    principalId,
    workDate,
    status: "approved",
  })
    .select({ minutes: 1 })
    .lean();

  return rows.reduce((a, x) => a + clampMinutes(x.minutes), 0);
}

// ======================================================
// ✅ LIST MY (employee/helper)
// ======================================================
async function listMy(req, res) {
  try {
    const { clinicId, role, staffId, userId, principalId, principalType } =
      getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });

    if (!principalId)
      return res.status(401).json({ ok: false, message: "Missing principalId" });

    const allowed = ["employee", "helper", "staff"];
    if (role && !allowed.includes(role))
      return res.status(403).json({ ok: false, message: "Forbidden" });

    const monthKey = parseMonthOrNull(req.query?.month);
    if (!monthKey)
      return res.status(400).json({ ok: false, message: "month required" });

    const status = s(req.query?.status);

    const q = { clinicId, principalId, monthKey };
    if (status) q.status = status;

    const items = await Overtime.find(q)
      .sort({ workDate: 1, createdAt: 1 })
      .lean();

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
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ LIST FOR STAFF (admin view)  <<< สำคัญ: กันพัง Render
// - รองรับ: /overtime/staff/:staffId?month=yyyy-MM&status=...
// - หรือส่ง staffId/principalId ผ่าน query
// ======================================================
async function listForStaff(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });

    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

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
    if (!pQuery)
      return res
        .status(400)
        .json({ ok: false, message: "staffId or principalId required" });

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
// ✅ STANDARD USER REQUEST (PENDING) - employee/helper
// ======================================================
async function requestOt(req, res) {
  try {
    const { clinicId, role, userId, staffId, principalId, principalType } =
      getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });

    if (!principalId)
      return res.status(401).json({ ok: false, message: "Missing principalId" });

    const allowed = ["employee", "helper", "staff"];
    if (role && !allowed.includes(role))
      return res.status(403).json({ ok: false, message: "Forbidden" });

    const workDate = s(req.body?.workDate);
    const start = s(req.body?.start);
    const end = s(req.body?.end);

    if (!isYmd(workDate))
      return res.status(400).json({ ok: false, message: "Invalid workDate" });

    const computed = computeMinutesFromStartEnd(start, end);
    if (computed == null)
      return res.status(400).json({ ok: false, message: "Invalid time format" });

    if (computed <= 0)
      return res.status(400).json({ ok: false, message: "OT must be > 0" });

    const multiplier = Number(req.body?.multiplier);
    const mul = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1.5;

    const created = await Overtime.create({
      clinicId,
      principalId,
      principalType,
      staffId: staffId || "",
      userId: userId || "",
      workDate,
      monthKey: toMonthKey(workDate),
      minutes: computed,
      multiplier: mul,
      status: "pending",
      source: "manual_user",
      note: s(req.body?.note),
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
// ✅ ADMIN CREATE MANUAL OT
// - ใช้ได้ทั้ง minutes หรือ start/end
// ======================================================
async function createManual(req, res) {
  try {
    const { clinicId, role, userId } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });

    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const workDate = s(req.body?.workDate);
    if (!isYmd(workDate))
      return res.status(400).json({ ok: false, message: "Invalid workDate" });

    const staffId = s(req.body?.staffId || req.body?.employeeId);
    const principalId = s(req.body?.principalId) || staffId;

    if (!principalId)
      return res
        .status(400)
        .json({ ok: false, message: "staffId/principalId required" });

    // minutes direct OR compute from start/end
    let minutes = clampMinutes(req.body?.minutes);
    if (!minutes) {
      const start = s(req.body?.start);
      const end = s(req.body?.end);
      const computed = computeMinutesFromStartEnd(start, end);
      if (computed == null)
        return res.status(400).json({ ok: false, message: "Invalid time format" });
      minutes = computed;
    }

    if (minutes <= 0)
      return res.status(400).json({ ok: false, message: "OT must be > 0" });

    const multiplier = Number(req.body?.multiplier);
    const mul = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1.5;

    const created = await Overtime.create({
      clinicId,
      principalId,
      principalType: "staff",
      staffId: staffId || "",
      userId: "",

      workDate,
      monthKey: toMonthKey(workDate),
      minutes,
      multiplier: mul,
      status: "pending",
      source: "manual",
      note: s(req.body?.note),
      createdBy: userId || "admin",
    });

    return res.status(201).json({ ok: true, overtime: created });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ ADMIN UPDATE OT
// - แก้ minutes/multiplier/note ได้ (ถ้าไม่ locked)
// ======================================================
async function updateOne(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });

    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const id = s(req.params?.id);
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId)
      return res.status(404).json({ ok: false, message: "Not found" });

    if (!canMutateStatus(ot))
      return res.status(409).json({ ok: false, message: "Locked" });

    const patch = {};

    if (req.body?.minutes != null) {
      const m = clampMinutes(req.body.minutes);
      if (m <= 0)
        return res.status(400).json({ ok: false, message: "minutes must be > 0" });
      patch.minutes = m;
    } else {
      // optional start/end update -> recompute
      const start = s(req.body?.start);
      const end = s(req.body?.end);
      if (start && end) {
        const computed = computeMinutesFromStartEnd(start, end);
        if (computed == null)
          return res.status(400).json({ ok: false, message: "Invalid time format" });
        if (computed <= 0)
          return res.status(400).json({ ok: false, message: "OT must be > 0" });
        patch.minutes = computed;
      }
    }

    if (req.body?.multiplier != null) {
      const multiplier = Number(req.body.multiplier);
      if (!Number.isFinite(multiplier) || multiplier <= 0)
        return res.status(400).json({ ok: false, message: "Invalid multiplier" });
      patch.multiplier = multiplier;
    }

    if (req.body?.note != null) patch.note = s(req.body.note);

    // ไม่ให้ admin เปลี่ยน status แปลก ๆ ผ่าน updateOne (ใช้ approve/reject/bulk)
    if (Object.keys(patch).length === 0)
      return res.json({ ok: true, overtime: ot });

    await Overtime.updateOne({ _id: ot._id }, { $set: patch });
    const fresh = await Overtime.findById(ot._id).lean();

    return res.json({ ok: true, overtime: fresh });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ ADMIN APPROVE / REJECT
// ======================================================
async function approveOne(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const id = s(req.params?.id);
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId)
      return res.status(404).json({ ok: false, message: "Not found" });

    if (!canMutateStatus(ot))
      return res.status(409).json({ ok: false, message: "Locked" });

    await Overtime.updateOne(
      { _id: ot._id },
      { $set: { status: "approved", approvedAt: new Date() } }
    );

    const fresh = await Overtime.findById(ot._id).lean();
    return res.json({ ok: true, overtime: fresh });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

async function rejectOne(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const id = s(req.params?.id);
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId)
      return res.status(404).json({ ok: false, message: "Not found" });

    if (!canMutateStatus(ot))
      return res.status(409).json({ ok: false, message: "Locked" });

    await Overtime.updateOne(
      { _id: ot._id },
      { $set: { status: "rejected", rejectedAt: new Date(), rejectNote: s(req.body?.note) } }
    );

    const fresh = await Overtime.findById(ot._id).lean();
    return res.json({ ok: true, overtime: fresh });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ BULK APPROVE (MONTH / DAY) - admin
// ======================================================
async function bulkApproveMonth(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const monthKey = parseMonthOrNull(req.body?.month || req.query?.month);
    if (!monthKey)
      return res.status(400).json({ ok: false, message: "month required (yyyy-MM)" });

    const staffId = s(req.body?.staffId || req.body?.employeeId || req.query?.staffId || req.query?.employeeId);
    const principalId = s(req.body?.principalId || req.query?.principalId) || staffId;

    if (!principalId)
      return res.status(400).json({ ok: false, message: "staffId/principalId required" });

    const q = {
      clinicId,
      principalId,
      monthKey,
      status: "pending",
    };

    // อย่าไปแตะ locked (แต่ pending ไม่ใช่ locked อยู่แล้ว)
    const r = await Overtime.updateMany(q, {
      $set: { status: "approved", approvedAt: new Date() },
    });

    return res.json({
      ok: true,
      month: monthKey,
      matched: r.matchedCount ?? r.n ?? 0,
      modified: r.modifiedCount ?? r.nModified ?? 0,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

async function bulkApproveDay(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });
    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const workDate = s(req.body?.workDate || req.query?.workDate);
    if (!isYmd(workDate))
      return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });

    const staffId = s(req.body?.staffId || req.body?.employeeId || req.query?.staffId || req.query?.employeeId);
    const principalId = s(req.body?.principalId || req.query?.principalId) || staffId;

    if (!principalId)
      return res.status(400).json({ ok: false, message: "staffId/principalId required" });

    const q = {
      clinicId,
      principalId,
      workDate,
      status: "pending",
    };

    const r = await Overtime.updateMany(q, {
      $set: { status: "approved", approvedAt: new Date() },
    });

    return res.json({
      ok: true,
      workDate,
      matched: r.matchedCount ?? r.n ?? 0,
      modified: r.modifiedCount ?? r.nModified ?? 0,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ======================================================
// ✅ DELETE (รองรับ manual_user ด้วย)
// ======================================================
async function removeOne(req, res) {
  try {
    const { clinicId, role } = getPrincipal(req);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId" });

    if (role !== "admin")
      return res.status(403).json({ ok: false, message: "Admin only" });

    const id = s(req.params.id);
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId)
      return res.status(404).json({ ok: false, message: "Not found" });

    if (!canMutateStatus(ot))
      return res.status(409).json({ ok: false, message: "Locked" });

    const src = s(ot.source);
    if (!["manual", "manual_user"].includes(src))
      return res
        .status(409)
        .json({ ok: false, message: "Cannot delete auto OT" });

    await Overtime.deleteOne({ _id: ot._id });

    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
}

// ✅ Safety: กัน export พังเงียบ ๆ
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