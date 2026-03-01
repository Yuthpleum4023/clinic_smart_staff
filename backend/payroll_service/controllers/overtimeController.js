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

function parseMonthOrThrow(month) {
  const m = s(month);
  if (!isYm(m)) return null;
  return m;
}

function canMutateStatus(ot) {
  return s(ot.status) !== "locked";
}

// ======================================================
// GET /overtime
// query: month=yyyy-MM (required)
//        staffId=... (required)
//        status=pending|approved|rejected|locked (optional)
// ======================================================
async function listForStaff(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const monthKey = parseMonthOrThrow(req.query?.month);
    if (!monthKey) return res.status(400).json({ ok: false, message: "month required (yyyy-MM)" });

    const staffId = s(req.query?.staffId);
    if (!staffId) return res.status(400).json({ ok: false, message: "staffId required" });

    const status = s(req.query?.status);
    const q = { clinicId, staffId, monthKey };
    if (status) q.status = status;

    const items = await Overtime.find(q).sort({ workDate: 1, createdAt: 1 }).lean();

    // summary
    const sum = (st) => items.filter((x) => x.status === st).reduce((a, x) => a + clampMinutes(x.minutes), 0);

    return res.json({
      ok: true,
      month: monthKey,
      staffId,
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
// POST /overtime/manual
// body: { staffId, userId?, workDate(yyyy-MM-dd), minutes, multiplier?, note? }
// ======================================================
async function createManual(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const adminUserId = s(req.user?.userId);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const staffId = s(req.body?.staffId);
    const workDate = s(req.body?.workDate);
    const minutes = clampMinutes(req.body?.minutes);

    if (!staffId) return res.status(400).json({ ok: false, message: "staffId required" });
    if (!isYmd(workDate)) return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    if (minutes <= 0) return res.status(400).json({ ok: false, message: "minutes must be > 0" });

    const monthKey = toMonthKey(workDate);
    const multiplier = Number(req.body?.multiplier);
    const mul = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1.5;

    const created = await Overtime.create({
      clinicId,
      staffId,
      userId: s(req.body?.userId),
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
// PATCH /overtime/:id
// body: { minutes?, multiplier?, note? }  (admin)
// - only if not locked
// ======================================================
async function updateOne(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

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
      if (!(Number.isFinite(x) && x > 0)) return res.status(400).json({ ok: false, message: "multiplier must be > 0" });
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
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const adminUserId = s(req.user?.userId);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const id = s(req.params.id);
    if (!mongoose.Types.ObjectId.isValid(id)) return res.status(400).json({ ok: false, message: "Invalid id" });

    const ot = await Overtime.findById(id);
    if (!ot || s(ot.clinicId) !== clinicId) return res.status(404).json({ ok: false, message: "Overtime not found" });

    if (!canMutateStatus(ot)) return res.status(409).json({ ok: false, message: "Locked overtime cannot be approved" });

    // approve only pending/rejected -> approved (your call; I allow pending/rejected)
    ot.status = "approved";
    ot.approvedBy = adminUserId;
    ot.approvedAt = new Date();

    // clear reject
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
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const adminUserId = s(req.user?.userId);

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

    // clear approve
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
// body: { staffId, month(yyyy-MM) }
// - approve all pending for that staff+month
// ======================================================
async function bulkApproveMonth(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const adminUserId = s(req.user?.userId);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const staffId = s(req.body?.staffId);
    const monthKey = parseMonthOrThrow(req.body?.month);

    if (!staffId) return res.status(400).json({ ok: false, message: "staffId required" });
    if (!monthKey) return res.status(400).json({ ok: false, message: "month required (yyyy-MM)" });

    const now = new Date();

    const r = await Overtime.updateMany(
      { clinicId, staffId, monthKey, status: "pending" },
      {
        $set: { status: "approved", approvedBy: adminUserId, approvedAt: now, rejectedBy: "", rejectedAt: null, rejectReason: "" },
      }
    );

    return res.json({ ok: true, staffId, month: monthKey, matched: r.matchedCount ?? r.n, modified: r.modifiedCount ?? r.nModified });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "bulk approve month failed", error: e.message });
  }
}

// ======================================================
// PATCH /overtime/bulk-approve/day  (admin)
// body: { staffId, workDate(yyyy-MM-dd) }
// - approve all pending for that staff+day
// ======================================================
async function bulkApproveDay(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);
    const adminUserId = s(req.user?.userId);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const staffId = s(req.body?.staffId);
    const workDate = s(req.body?.workDate);

    if (!staffId) return res.status(400).json({ ok: false, message: "staffId required" });
    if (!isYmd(workDate)) return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });

    const monthKey = toMonthKey(workDate);
    const now = new Date();

    const r = await Overtime.updateMany(
      { clinicId, staffId, monthKey, workDate, status: "pending" },
      {
        $set: { status: "approved", approvedBy: adminUserId, approvedAt: now, rejectedBy: "", rejectedAt: null, rejectReason: "" },
      }
    );

    return res.json({ ok: true, staffId, workDate, matched: r.matchedCount ?? r.n, modified: r.modifiedCount ?? r.nModified });
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
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

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
  listForStaff,
  createManual,
  updateOne,
  approveOne,
  rejectOne,
  bulkApproveMonth,
  bulkApproveDay,
  removeOne,
};