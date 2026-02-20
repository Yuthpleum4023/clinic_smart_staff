// controllers/availabilityController.js
//
// ✅ Availability (ตารางว่างผู้ช่วย)
// - staff สร้าง/ดูของตัวเอง
// - clinic admin ดู open ทั้งระบบ
//
// Endpoints:
// - POST   /availabilities              (helper/staff) create mine
// - GET    /availabilities/me           (helper/staff) list mine
// - PATCH  /availabilities/:id/cancel   (helper/staff) cancel mine
// - GET    /availabilities/open         (admin) list open for clinic to browse
//
// Query for /open:
//   ?date=YYYY-MM-DD
//   ?dateFrom=YYYY-MM-DD&dateTo=YYYY-MM-DD
//   ?role=ผู้ช่วย
//

const Availability = require("../models/Availability");

// ---------------- helpers ----------------
function normalizeRoles(r) {
  if (!r) return [];
  if (Array.isArray(r)) return r.map((x) => String(x || "").trim()).filter(Boolean);
  return [String(r || "").trim()].filter(Boolean);
}

function mustRoleAny(req, roles = []) {
  const have = normalizeRoles(req.user?.role);
  const want = (roles || []).map((x) => String(x || "").trim()).filter(Boolean);
  const ok = have.some((x) => want.includes(x));
  if (!ok) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

function mustRole(req, roles = []) {
  const r = req.user?.role;
  if (!roles.includes(r)) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

function getStaffId(req) {
  return (
    (req.user?.staffId ||
      req.user?.userId ||
      req.user?.id ||
      req.user?._id ||
      "")
      .toString()
      .trim()
  );
}

function s(v) {
  return (v ?? "").toString().trim();
}

function bad(msg, code = 400) {
  const err = new Error(msg);
  err.statusCode = code;
  throw err;
}

// time format "HH:mm"
function isHHmm(x) {
  const t = s(x);
  if (!t) return false;
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(t);
}

// date "YYYY-MM-DD"
function isYMD(x) {
  const d = s(x);
  if (!d) return false;
  return /^\d{4}-\d{2}-\d{2}$/.test(d);
}

function timeToMin(hhmm) {
  const [h, m] = s(hhmm).split(":").map((x) => parseInt(x, 10));
  if (Number.isNaN(h) || Number.isNaN(m)) return null;
  return h * 60 + m;
}

// ---------------- staff: create mine ----------------
async function createAvailability(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffId(req);
    if (!staffId) bad("missing staffId in token", 400);

    const {
      date,
      start,
      end,
      role = "ผู้ช่วย",
      note = "",
      fullName = "",
      phone = "",
    } = req.body || {};

    if (!isYMD(date)) bad("date required (YYYY-MM-DD)");
    if (!isHHmm(start) || !isHHmm(end)) bad("start/end must be HH:mm");

    const a = timeToMin(start);
    const b = timeToMin(end);
    if (a === null || b === null) bad("invalid time");
    if (b <= a) bad("end must be after start");

    // กันซ้อน: staffId + date + time overlap แบบง่าย (same start/end)
    const exists = await Availability.findOne({
      staffId,
      date: s(date),
      start: s(start),
      end: s(end),
      status: { $ne: "cancelled" },
    }).lean();

    if (exists) {
      return res.json({ ok: true, availability: exists, message: "already exists" });
    }

    const doc = await Availability.create({
      staffId,
      userId: s(req.user?.userId || ""),
      date: s(date),
      start: s(start),
      end: s(end),
      role: s(role) || "ผู้ช่วย",
      note: s(note),
      fullName: s(fullName),
      phone: s(phone),
      status: "open",
    });

    return res.status(201).json({ ok: true, availability: doc });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "createAvailability failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- staff: list mine ----------------
async function listMyAvailabilities(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffId(req);
    if (!staffId) bad("missing staffId in token", 400);

    const status = s(req.query.status);
    const q = { staffId };
    if (status) q.status = status;

    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listMyAvailabilities failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- staff: cancel mine ----------------
async function cancelAvailability(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffId(req);
    if (!staffId) bad("missing staffId in token", 400);

    const id = s(req.params.id);
    if (!id) bad("missing id");

    const doc = await Availability.findById(id);
    if (!doc) bad("availability not found", 404);
    if (s(doc.staffId) !== staffId) bad("forbidden", 403);

    doc.status = "cancelled";
    await doc.save();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "cancelAvailability failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- clinic admin: list open ----------------
async function listOpenAvailabilities(req, res) {
  try {
    mustRole(req, ["admin"]);

    const q = { status: "open" };

    // filters
    const date = s(req.query.date);
    const dateFrom = s(req.query.dateFrom);
    const dateTo = s(req.query.dateTo);
    const role = s(req.query.role);

    if (date && isYMD(date)) {
      q.date = date;
    } else if (dateFrom || dateTo) {
      q.date = {};
      if (dateFrom && isYMD(dateFrom)) q.date.$gte = dateFrom;
      if (dateTo && isYMD(dateTo)) q.date.$lte = dateTo;
      if (Object.keys(q.date).length === 0) delete q.date;
    }

    if (role) q.role = role;

    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listOpenAvailabilities failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  createAvailability,
  listMyAvailabilities,
  cancelAvailability,
  listOpenAvailabilities,
};