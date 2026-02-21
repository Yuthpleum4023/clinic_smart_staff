// controllers/availabilityController.js

const mongoose = require("mongoose");
const Availability = require("../models/Availability");
const Shift = require("../models/Shift");
const Clinic = require("../models/Clinic"); // ✅ NEW: ดึงข้อมูลคลินิกจาก Mongo

// ---------------- helpers ----------------
function normalizeRoles(r) {
  if (!r) return [];
  if (Array.isArray(r))
    return r.map((x) => String(x || "").trim()).filter(Boolean);
  return [String(r || "").trim()].filter(Boolean);
}

function mustRoleAny(req, roles = []) {
  const have = normalizeRoles(req.user?.role).map((x) => x.toLowerCase());
  const want = (roles || [])
    .map((x) => String(x || "").trim().toLowerCase())
    .filter(Boolean);
  const ok = have.some((x) => want.includes(x));
  if (!ok) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

function mustRole(req, roles = []) {
  const r = String(req.user?.role || "").trim().toLowerCase();
  const want = (roles || []).map((x) => String(x || "").trim().toLowerCase());
  if (!want.includes(r)) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

function s(v) {
  return (v ?? "").toString().trim();
}

function bad(msg, code = 400) {
  const err = new Error(msg);
  err.statusCode = code;
  throw err;
}

function getStaffIdStrict(req) {
  return s(req.user?.staffId);
}

function getUserId(req) {
  return s(req.user?.userId || req.user?.id || req.user?._id);
}

function getClinicIdStrict(req) {
  return s(req.user?.clinicId);
}

function getFullName(req, body) {
  return s(req.user?.fullName) || s(body?.fullName);
}

function getPhone(req, body) {
  return s(req.user?.phone) || s(body?.phone);
}

function isHHmm(x) {
  const t = s(x);
  return !!t && /^([01]\d|2[0-3]):[0-5]\d$/.test(t);
}

function isYMD(x) {
  const d = s(x);
  return !!d && /^\d{4}-\d{2}-\d{2}$/.test(d);
}

function timeToMin(hhmm) {
  const parts = s(hhmm).split(":");
  if (parts.length !== 2) return null;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (Number.isNaN(h) || Number.isNaN(m)) return null;
  return h * 60 + m;
}

function todayYMD() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function normalizeRoleValue(x) {
  const v = s(x).toLowerCase();
  if (!v) return "";
  if (
    v === "helper" ||
    v === "assistant" ||
    v === "ผู้ช่วย" ||
    v === "dental assistant"
  )
    return "ผู้ช่วย";
  return s(x);
}

function overlaps(aStart, aEnd, bStart, bEnd) {
  const a1 = timeToMin(aStart);
  const a2 = timeToMin(aEnd);
  const b1 = timeToMin(bStart);
  const b2 = timeToMin(bEnd);
  if ([a1, a2, b1, b2].some((x) => x === null)) return false;
  return Math.max(a1, b1) < Math.min(a2, b2);
}

function toNumOrNull(v) {
  if (v === null || v === undefined) return null;
  const t = String(v).trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isNaN(n) ? null : n;
}

// ---------------- staff: create mine ----------------
async function createAvailability(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffIdStrict(req);
    if (!staffId) bad("missing staffId in token (required)", 400);

    const userId = getUserId(req);

    const {
      date,
      start,
      end,
      role = "ผู้ช่วย",
      note = "",
      fullName: _fullNameBody = "",
      phone: _phoneBody = "",
    } = req.body || {};

    if (!isYMD(date)) bad("date required (YYYY-MM-DD)");
    if (!isHHmm(start) || !isHHmm(end)) bad("start/end must be HH:mm");

    const a = timeToMin(start);
    const b = timeToMin(end);
    if (a === null || b === null) bad("invalid time");
    if (b <= a) bad("end must be after start");

    const fullName = getFullName(req, req.body);
    const phone = getPhone(req, req.body);

    const sameDay = await Availability.find({
      staffId,
      date: s(date),
      status: { $ne: "cancelled" },
    }).lean();

    const hit = (sameDay || []).find((it) =>
      overlaps(it.start, it.end, start, end)
    );
    if (hit) {
      return res.status(409).json({
        ok: false,
        message: "time overlap with existing availability",
        overlap: hit,
      });
    }

    const doc = await Availability.create({
      staffId,
      userId: userId || "",
      date: s(date),
      start: s(start),
      end: s(end),
      role: s(role) || "ผู้ช่วย",
      note: s(note),

      fullName: s(fullName),
      phone: s(phone),

      status: "open",
      bookedByClinicId: "",
      bookedAt: null,

      shiftId: "",
      bookedNote: "",
      bookedHourlyRate: 0,

      // ✅ new field default
      clinicClearedAt: null,
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

    const staffId = getStaffIdStrict(req);
    if (!staffId) bad("missing staffId in token (required)", 400);

    const status = s(req.query.status);
    const q = { staffId };
    if (status) q.status = status;

    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();

    // =========================================================
    // ✅ ENRICH (SAFE): ถ้าสถานะ booked -> เติมข้อมูลคลินิกให้ helper โทร/ดูที่อยู่ได้
    // - ไม่แก้ schema Availability เพิ่ม field (return-only)
    // - เอาข้อมูลจาก Clinic collection ตาม bookedByClinicId
    // =========================================================
    const bookedClinicIds = Array.from(
      new Set(
        (items || [])
          .filter(
            (it) =>
              s(it.status).toLowerCase() === "booked" && s(it.bookedByClinicId)
          )
          .map((it) => s(it.bookedByClinicId))
      )
    );

    let clinicMap = {};
    if (bookedClinicIds.length > 0) {
      const clinics = await Clinic.find({
        clinicId: { $in: bookedClinicIds },
      }).lean();

      clinicMap = (clinics || []).reduce((acc, c) => {
        acc[s(c.clinicId)] = c;
        return acc;
      }, {});
    }

    const enriched = (items || []).map((it) => {
      if (s(it.status).toLowerCase() !== "booked") return it;

      const cid = s(it.bookedByClinicId);
      const c = clinicMap[cid];

      return {
        ...it,
        bookedClinicName: s(c?.name),
        bookedClinicPhone: s(c?.phone),
        bookedClinicAddress: s(c?.address),
        bookedClinicLat: c?.lat ?? null,
        bookedClinicLng: c?.lng ?? null,
      };
    });

    return res.json({ ok: true, items: enriched });
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

    const staffId = getStaffIdStrict(req);
    if (!staffId) bad("missing staffId in token (required)", 400);

    const id = s(req.params.id);
    if (!id) bad("missing id");
    if (!mongoose.Types.ObjectId.isValid(id)) bad("invalid id", 400);

    const doc = await Availability.findById(id);
    if (!doc) bad("availability not found", 404);
    if (s(doc.staffId) !== staffId) bad("forbidden", 403);

    doc.status = "cancelled";
    doc.bookedByClinicId = "";
    doc.bookedAt = null;

    doc.shiftId = "";
    doc.bookedNote = "";
    doc.bookedHourlyRate = 0;

    // staff cancel ก็ถือว่าเคลียร์ด้วย
    doc.clinicClearedAt = null;

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

    const date = s(req.query.date);
    const dateFrom = s(req.query.dateFrom);
    const dateTo = s(req.query.dateTo);
    const roleRaw = s(req.query.role);

    if (date && isYMD(date)) {
      q.date = date;
    } else if (dateFrom || dateTo) {
      q.date = {};
      if (dateFrom && isYMD(dateFrom)) q.date.$gte = dateFrom;
      if (dateTo && isYMD(dateTo)) q.date.$lte = dateTo;
      if (Object.keys(q.date).length === 0) delete q.date;
    } else {
      q.date = { $gte: todayYMD() };
    }

    if (roleRaw) q.role = normalizeRoleValue(roleRaw);

    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listOpenAvailabilities failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// ✅ NEW: clinic admin list booked (for clinic UI "ค้างไว้หลังจอง")
// GET /availabilities/booked
// - returns status=booked of this clinic, and NOT cleared yet
// =====================================================
async function listBookedAvailabilities(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicIdStrict(req);
    if (!clinicId) bad("missing clinicId in token (required)", 400);

    // optional filters (same style as /open)
    const q = {
      status: "booked",
      bookedByClinicId: clinicId,
      clinicClearedAt: null,
    };

    const date = s(req.query.date);
    const dateFrom = s(req.query.dateFrom);
    const dateTo = s(req.query.dateTo);

    if (date && isYMD(date)) {
      q.date = date;
    } else if (dateFrom || dateTo) {
      q.date = {};
      if (dateFrom && isYMD(dateFrom)) q.date.$gte = dateFrom;
      if (dateTo && isYMD(dateTo)) q.date.$lte = dateTo;
      if (Object.keys(q.date).length === 0) delete q.date;
    }

    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listBookedAvailabilities failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// ✅ NEW: clinic admin clear booked item
// POST /availabilities/:id/clear
// - DOES NOT re-open availability (กันกลับไปว่างซ้ำ)
// - just mark clinicClearedAt so it disappears from /booked list
// =====================================================
async function clearBookedAvailability(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicIdStrict(req);
    if (!clinicId) bad("missing clinicId in token (required)", 400);

    const id = s(req.params.id);
    if (!id) bad("missing id");
    if (!mongoose.Types.ObjectId.isValid(id)) bad("invalid id", 400);

    const doc = await Availability.findOneAndUpdate(
      {
        _id: id,
        status: "booked",
        bookedByClinicId: clinicId,
        clinicClearedAt: null,
      },
      { $set: { clinicClearedAt: new Date() } },
      { new: true }
    ).lean();

    if (!doc) {
      return res.status(409).json({
        ok: false,
        message: "cannot clear (not booked by this clinic or already cleared)",
      });
    }

    return res.json({ ok: true, availability: doc });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "clearBookedAvailability failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// ✅ booking: unchanged behavior + ensure clinicClearedAt reset
// + ✅ ENRICH CLINIC CONTACT FROM MONGO (Clinic)
// =====================================================
async function bookAvailability(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicIdStrict(req);
    if (!clinicId) bad("missing clinicId in token (required)", 400);

    const id = s(req.params.id);
    if (!id) bad("missing id");
    if (!mongoose.Types.ObjectId.isValid(id)) bad("invalid id", 400);

    const body = req.body || {};
    const bookedAt = new Date();

    const updated = await Availability.findOneAndUpdate(
      { _id: id, status: "open" },
      {
        $set: {
          status: "booked",
          bookedByClinicId: clinicId,
          bookedAt,

          bookedNote: s(body.note),
          bookedHourlyRate: (() => {
            const v = body.hourlyRate;
            const n =
              typeof v === "number"
                ? v
                : parseFloat(String(v || "").trim() || "0") || 0;
            return n;
          })(),

          // ✅ IMPORTANT: ถ้าเคยเคลียร์ไว้ แล้วจองใหม่ -> reset
          clinicClearedAt: null,
        },
      },
      { new: true }
    );

    if (!updated) {
      return res.status(409).json({
        ok: false,
        message: "availability is not open (maybe already booked/cancelled)",
      });
    }

    // ✅ NEW: อ่านข้อมูลคลินิกจาก Mongo (DB เป็นหลัก)
    const clinic = await Clinic.findOne({ clinicId }).lean();

    // DB default + body override ได้
    const clinicName = s(body.clinicName) || s(clinic?.name);
    const clinicPhone = s(body.clinicPhone) || s(clinic?.phone);
    const clinicAddress = s(body.clinicAddress) || s(clinic?.address);

    const clinicLat =
      body.clinicLat === undefined ? clinic?.lat : toNumOrNull(body.clinicLat);
    const clinicLng =
      body.clinicLng === undefined ? clinic?.lng : toNumOrNull(body.clinicLng);

    const shiftNote = s(body.note) || s(updated.note) || "";

    const hourlyRateRaw = body.hourlyRate;
    const hourlyRate =
      typeof hourlyRateRaw === "number"
        ? hourlyRateRaw
        : parseFloat(String(hourlyRateRaw || "").trim() || "0") || 0;

    const shiftPayload = {
      clinicId,
      staffId: s(updated.staffId),

      date: s(updated.date),
      start: s(updated.start),
      end: s(updated.end),

      status: "scheduled",
      minutesLate: 0,

      hourlyRate,
      note: shiftNote,

      // ✅ IMPORTANT: ใส่ meta คลินิกให้ผู้ช่วยโทรกลับได้
      clinicLat: clinicLat ?? null,
      clinicLng: clinicLng ?? null,
      clinicName: clinicName,
      clinicPhone: clinicPhone,
      clinicAddress: clinicAddress,
    };

    let shiftDoc = null;
    try {
      shiftDoc = await Shift.create(shiftPayload);

      await Availability.updateOne(
        { _id: id, status: "booked", bookedByClinicId: clinicId },
        { $set: { shiftId: String(shiftDoc._id) } }
      );
    } catch (e) {
      await Availability.updateOne(
        { _id: id, status: "booked", bookedByClinicId: clinicId },
        {
          $set: {
            status: "open",
            bookedByClinicId: "",
            bookedAt: null,

            shiftId: "",
            bookedNote: "",
            bookedHourlyRate: 0,

            clinicClearedAt: null,
          },
        }
      );
      throw e;
    }

    const latest = await Availability.findById(id).lean();

    return res.json({
      ok: true,
      availability: latest || updated,
      shift: shiftDoc,
    });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "bookAvailability failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  createAvailability,
  listMyAvailabilities,
  cancelAvailability,
  listOpenAvailabilities,
  listBookedAvailabilities, // ✅ NEW
  clearBookedAvailability, // ✅ NEW
  bookAvailability,
};