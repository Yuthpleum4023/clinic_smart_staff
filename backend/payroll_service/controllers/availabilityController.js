// controllers/availabilityController.js
//
// ✅ FINAL FIX (MATCH models/Availability.js) + ENRICH CONTACT FROM TOKEN
// - staffId ต้องมาจาก req.user.staffId เท่านั้น (ห้ามเอา userId มาแทน staffId)
// - userId เก็บแยก field userId
// - ✅ ENRICH: fullName/phone มาจาก token เป็นหลัก (req.user.fullName/req.user.phone)
//   -> ไม่ต้อง query user ซ้ำ
//   -> กัน client ปลอมข้อมูล
// - /open: ไม่กรอง clinicId แน่นอน + role filter แบบ normalize กันส่งค่าคนละภาษา
// - overlap: กันเวลาซ้อนทับจริง (ไม่ใช่แค่ start/end ตรงกัน)
//
// ✅ NEW (BOOKING):
// - POST /availabilities/:id/book (admin) -> mark availability booked + create Shift
// - กันจองซ้อนด้วย atomic update: status ต้องเป็น open เท่านั้น
// - ถ้าสร้าง Shift fail -> rollback availability กลับ open (กันระบบค้าง)
//
// Endpoints:
// - POST   /availabilities              (helper/staff) create mine
// - GET    /availabilities/me           (helper/staff) list mine
// - PATCH  /availabilities/:id/cancel   (helper/staff) cancel mine
// - GET    /availabilities/open         (admin) list open for clinic to browse
// - POST   /availabilities/:id/book     (admin) book + create Shift
//
// Query for /open:
//   ?date=YYYY-MM-DD
//   ?dateFrom=YYYY-MM-DD&dateTo=YYYY-MM-DD
//   ?role=...   (optional; supports ไทย/อังกฤษแบบหลวม ๆ)
//

const mongoose = require("mongoose");
const Availability = require("../models/Availability");
const Shift = require("../models/Shift");

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

// ✅ staffId ต้องมาจาก staffId เท่านั้น (schema required)
function getStaffIdStrict(req) {
  return s(req.user?.staffId);
}

// ✅ userId แยก field (optional)
function getUserId(req) {
  return s(req.user?.userId || req.user?.id || req.user?._id);
}

// ✅ clinicId (admin token) — ใช้ตอนจองเพื่อสร้าง Shift
function getClinicIdStrict(req) {
  return s(req.user?.clinicId);
}

// ✅ ENRICH CONTACT FROM TOKEN (primary) with fallback from body (secondary)
function getFullName(req, body) {
  return s(req.user?.fullName) || s(body?.fullName);
}

function getPhone(req, body) {
  return s(req.user?.phone) || s(body?.phone);
}

// time format "HH:mm"
function isHHmm(x) {
  const t = s(x);
  return !!t && /^([01]\d|2[0-3]):[0-5]\d$/.test(t);
}

// date "YYYY-MM-DD"
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

// role normalize: รองรับไทย/อังกฤษหลวม ๆ
function normalizeRoleValue(x) {
  const v = s(x).toLowerCase();
  if (!v) return "";

  // map อังกฤษ -> ไทย default ใน schema
  if (
    v === "helper" ||
    v === "assistant" ||
    v === "ผู้ช่วย" ||
    v === "dental assistant"
  )
    return "ผู้ช่วย";

  // ถ้าท่านมี role อื่นในอนาคต ค่อยเติม map ตรงนี้
  return s(x); // default: ใช้ตามที่ส่งมา
}

// overlap: ช่วง [start,end) ซ้อนกันไหม
function overlaps(aStart, aEnd, bStart, bEnd) {
  const a1 = timeToMin(aStart);
  const a2 = timeToMin(aEnd);
  const b1 = timeToMin(bStart);
  const b2 = timeToMin(bEnd);
  if ([a1, a2, b1, b2].some((x) => x === null)) return false;
  return Math.max(a1, b1) < Math.min(a2, b2);
}

// ---------------- staff: create mine ----------------
async function createAvailability(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffIdStrict(req);
    if (!staffId) bad("missing staffId in token (required)", 400);

    const userId = getUserId(req); // optional

    const {
      date,
      start,
      end,
      role = "ผู้ช่วย",
      note = "",
      // ❗ ยังรับไว้เพื่อ backward-compatible แต่จะ enrich จาก token เป็นหลัก
      fullName: _fullNameBody = "",
      phone: _phoneBody = "",
    } = req.body || {};

    if (!isYMD(date)) bad("date required (YYYY-MM-DD)");
    if (!isHHmm(start) || !isHHmm(end)) bad("start/end must be HH:mm");

    const a = timeToMin(start);
    const b = timeToMin(end);
    if (a === null || b === null) bad("invalid time");
    if (b <= a) bad("end must be after start");

    // ✅ ENRICH contact from token (primary) with fallback from body (secondary)
    const fullName = getFullName(req, req.body);
    const phone = getPhone(req, req.body);

    // ✅ กันซ้อนทับจริง (เฉพาะรายการที่ยังไม่ cancelled)
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

      // ✅ contact fields for clinic to call
      fullName: s(fullName),
      phone: s(phone),

      status: "open",
      bookedByClinicId: "",
      bookedAt: null,
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
    const roleRaw = s(req.query.role);

    if (date && isYMD(date)) {
      q.date = date;
    } else if (dateFrom || dateTo) {
      q.date = {};
      if (dateFrom && isYMD(dateFrom)) q.date.$gte = dateFrom;
      if (dateTo && isYMD(dateTo)) q.date.$lte = dateTo;
      if (Object.keys(q.date).length === 0) delete q.date;
    } else {
      // default: วันนี้ขึ้นไป กันของเก่าท่วม (ถ้าไม่อยาก default นี้ ลบบรรทัดนี้ได้)
      q.date = { $gte: todayYMD() };
    }

    // ✅ role filter แบบ normalize กันส่ง helper/ผู้ช่วย แล้วไม่ match
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
// ✅ NEW: clinic admin book availability -> create Shift
// POST /availabilities/:id/book
// body (optional): { note?, hourlyRate?, clinicLat?, clinicLng?, clinicName?, clinicPhone?, clinicAddress? }
// =====================================================
async function bookAvailability(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicIdStrict(req);
    if (!clinicId) bad("missing clinicId in token (required)", 400);

    const id = s(req.params.id);
    if (!id) bad("missing id");
    if (!mongoose.Types.ObjectId.isValid(id)) bad("invalid id", 400);

    // 1) atomic mark booked (กันจองซ้อน)
    const bookedAt = new Date();

    const updated = await Availability.findOneAndUpdate(
      { _id: id, status: "open" },
      {
        $set: {
          status: "booked",
          bookedByClinicId: clinicId,
          bookedAt,
        },
      },
      { new: true }
    );

    if (!updated) {
      // ถ้าไม่เจอ แปลว่า: ไม่มีรายการ หรือถูกจอง/ยกเลิกไปแล้ว
      return res.status(409).json({
        ok: false,
        message: "availability is not open (maybe already booked/cancelled)",
      });
    }

    // 2) create Shift (ปลายทางระบบ)
    //    - staffId มาจาก availability
    //    - clinicId มาจาก token admin
    const body = req.body || {};
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

      // optional: ถ้าคลินิกอยากส่งพิกัด/ชื่อมา (ไม่ส่งก็ไม่พัง)
      clinicLat:
        body.clinicLat === null || body.clinicLat === undefined
          ? null
          : Number(body.clinicLat),
      clinicLng:
        body.clinicLng === null || body.clinicLng === undefined
          ? null
          : Number(body.clinicLng),

      clinicName: s(body.clinicName),
      clinicPhone: s(body.clinicPhone),
      clinicAddress: s(body.clinicAddress),
    };

    // กัน NaN
    if (Number.isNaN(shiftPayload.clinicLat)) shiftPayload.clinicLat = null;
    if (Number.isNaN(shiftPayload.clinicLng)) shiftPayload.clinicLng = null;

    let shiftDoc = null;
    try {
      shiftDoc = await Shift.create(shiftPayload);
    } catch (e) {
      // 3) rollback availability ถ้าสร้าง shift fail (กันระบบค้าง booked)
      await Availability.updateOne(
        { _id: id, status: "booked", bookedByClinicId: clinicId },
        {
          $set: { status: "open", bookedByClinicId: "", bookedAt: null },
        }
      );

      throw e;
    }

    return res.json({
      ok: true,
      availability: updated,
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
  bookAvailability, // ✅ NEW
};