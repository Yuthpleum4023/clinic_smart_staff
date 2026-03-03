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
  const staffId = s(u.staffId || u.employeeId || "");

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
  }).select({ minutes: 1 }).lean();

  return rows.reduce((a, x) => a + clampMinutes(x.minutes), 0);
}

async function sumApprovedMinutesForDay({ clinicId, principalId, workDate }) {
  const rows = await Overtime.find({
    clinicId,
    principalId,
    workDate,
    status: "approved",
  }).select({ minutes: 1 }).lean();

  return rows.reduce((a, x) => a + clampMinutes(x.minutes), 0);
}

// ======================================================
// ✅ LIST MY
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
// ✅ STANDARD USER REQUEST (PENDING)
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