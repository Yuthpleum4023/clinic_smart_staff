// controllers/availabilityController.js

const mongoose = require("mongoose");
const Availability = require("../models/Availability");
const Shift = require("../models/Shift");
const Clinic = require("../models/Clinic");

// ---------------- helpers ----------------
function normalizeRoles(r) {
  if (!r) return [];
  if (Array.isArray(r)) {
    return r.map((x) => String(x || "").trim()).filter(Boolean);
  }
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

// helper token บางแบบไม่มี staffId
function getActorId(req) {
  const staffId = getStaffIdStrict(req);
  if (staffId) return staffId;

  const userId = getUserId(req);
  if (userId) return userId;

  return "";
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
  ) {
    return "ผู้ช่วย";
  }
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

function buildLocationLabel({ district = "", province = "", address = "" } = {}) {
  const d = s(district);
  const p = s(province);
  const a = s(address);

  if (d && p) return `${d}, ${p}`;
  if (p) return p;
  if (d) return d;
  if (a) return a;
  return "";
}

function toRad(v) {
  return (v * Math.PI) / 180;
}

function distanceKmBetween(lat1, lng1, lat2, lng2) {
  const aLat = toNumOrNull(lat1);
  const aLng = toNumOrNull(lng1);
  const bLat = toNumOrNull(lat2);
  const bLng = toNumOrNull(lng2);

  if (
    aLat === null ||
    aLng === null ||
    bLat === null ||
    bLng === null
  ) {
    return null;
  }

  const R = 6371;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);

  const x =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(aLat)) *
      Math.cos(toRad(bLat)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
  const km = R * c;

  if (!Number.isFinite(km)) return null;
  return km;
}

function roundDistanceKm(km) {
  if (km === null || km === undefined || !Number.isFinite(Number(km))) {
    return null;
  }
  const n = Number(km);
  if (n < 10) return Math.round(n * 10) / 10;
  return Math.round(n);
}

function formatDistanceKm(km) {
  const rounded = roundDistanceKm(km);
  if (rounded === null) return "";
  if (rounded < 10) return `${rounded.toFixed(1)} กม.`;
  return `${Math.round(rounded)} กม.`;
}

async function getClinicContext(req) {
  const clinicId = getClinicIdStrict(req);
  if (!clinicId) return null;

  const clinic = await Clinic.findOne({ clinicId }).lean();
  if (!clinic) return null;

  const district = s(clinic?.district);
  const province = s(clinic?.province);
  const address = s(clinic?.address);

  return {
    clinicId: s(clinic?.clinicId),
    name: s(clinic?.name),
    phone: s(clinic?.phone),
    address,
    lat: toNumOrNull(clinic?.lat),
    lng: toNumOrNull(clinic?.lng),
    district,
    province,
    locationLabel:
      s(clinic?.locationLabel) ||
      buildLocationLabel({ district, province, address }),
  };
}

// ---------------- staff/helper: create mine ----------------
async function createAvailability(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const actorId = getActorId(req);
    if (!actorId) {
      bad("missing identity in token (staffId/userId required)", 400);
    }

    const userId = getUserId(req);

    const {
      date,
      start,
      end,
      role = "ผู้ช่วย",
      note = "",
      fullName: _fullNameBody = "",
      phone: _phoneBody = "",
      lat = null,
      lng = null,
      district = "",
      province = "",
      address = "",
      locationLabel = "",
    } = req.body || {};

    if (!isYMD(date)) bad("date required (YYYY-MM-DD)");
    if (!isHHmm(start) || !isHHmm(end)) bad("start/end must be HH:mm");

    const a = timeToMin(start);
    const b = timeToMin(end);
    if (a === null || b === null) bad("invalid time");
    if (b <= a) bad("end must be after start");

    const fullName = getFullName(req, req.body);
    const phone = getPhone(req, req.body);

    const latNum = toNumOrNull(lat);
    const lngNum = toNumOrNull(lng);
    const districtText = s(district);
    const provinceText = s(province);
    const addressText = s(address);
    const locationLabelText =
      s(locationLabel) ||
      buildLocationLabel({
        district: districtText,
        province: provinceText,
        address: addressText,
      });

    const sameDay = await Availability.find({
      staffId: actorId,
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
      staffId: actorId,
      userId: userId || "",

      fullName: s(fullName),
      phone: s(phone),

      lat: latNum,
      lng: lngNum,
      district: districtText,
      province: provinceText,
      address: addressText,
      locationLabel: locationLabelText,

      date: s(date),
      start: s(start),
      end: s(end),
      role: s(role) || "ผู้ช่วย",
      note: s(note),

      status: "open",
      bookedByClinicId: "",
      bookedAt: null,

      shiftId: "",
      bookedNote: "",
      bookedHourlyRate: 0,

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

// ---------------- staff/helper: list mine ----------------
async function listMyAvailabilities(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const actorId = getActorId(req);
    if (!actorId) {
      bad("missing identity in token (staffId/userId required)", 400);
    }

    const status = s(req.query.status);
    const q = { staffId: actorId };
    if (status) q.status = status;

    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();

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

      const clinicDistrict = s(c?.district);
      const clinicProvince = s(c?.province);
      const clinicAddress = s(c?.address);

      const bookedClinicLocationLabel =
        s(c?.locationLabel) ||
        buildLocationLabel({
          district: clinicDistrict,
          province: clinicProvince,
          address: clinicAddress,
        });

      const distanceKm = distanceKmBetween(
        it?.lat,
        it?.lng,
        c?.lat,
        c?.lng
      );

      return {
        ...it,
        bookedClinicName: s(c?.name),
        bookedClinicPhone: s(c?.phone),
        bookedClinicAddress: clinicAddress,
        bookedClinicLat: toNumOrNull(c?.lat),
        bookedClinicLng: toNumOrNull(c?.lng),
        bookedClinicDistrict: clinicDistrict,
        bookedClinicProvince: clinicProvince,
        bookedClinicLocationLabel: bookedClinicLocationLabel,
        bookedClinicDistanceKm: roundDistanceKm(distanceKm),
        bookedClinicDistanceText: formatDistanceKm(distanceKm),
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

// ---------------- staff/helper: cancel mine ----------------
async function cancelAvailability(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const actorId = getActorId(req);
    if (!actorId) {
      bad("missing identity in token (staffId/userId required)", 400);
    }

    const id = s(req.params.id);
    if (!id) bad("missing id");
    if (!mongoose.Types.ObjectId.isValid(id)) bad("invalid id", 400);

    const doc = await Availability.findById(id);
    if (!doc) bad("availability not found", 404);

    if (s(doc.staffId) !== actorId) bad("forbidden", 403);

    doc.status = "cancelled";
    doc.bookedByClinicId = "";
    doc.bookedAt = null;

    doc.shiftId = "";
    doc.bookedNote = "";
    doc.bookedHourlyRate = 0;

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

    const clinicCtx = await getClinicContext(req);
    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();

    const enriched = (items || []).map((it) => {
      const itemLocationLabel =
        s(it.locationLabel) ||
        buildLocationLabel({
          district: it?.district,
          province: it?.province,
          address: it?.address,
        });

      const distanceKm = clinicCtx
        ? distanceKmBetween(clinicCtx.lat, clinicCtx.lng, it?.lat, it?.lng)
        : null;

      return {
        ...it,
        locationLabel: itemLocationLabel,
        distanceKm: roundDistanceKm(distanceKm),
        distanceText: formatDistanceKm(distanceKm),
      };
    });

    return res.json({
      ok: true,
      clinic: clinicCtx
        ? {
            clinicId: clinicCtx.clinicId,
            name: clinicCtx.name,
            locationLabel: clinicCtx.locationLabel,
            lat: clinicCtx.lat,
            lng: clinicCtx.lng,
          }
        : null,
      items: enriched,
    });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listOpenAvailabilities failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// clinic admin list booked
// =====================================================
async function listBookedAvailabilities(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicIdStrict(req);
    if (!clinicId) bad("missing clinicId in token (required)", 400);

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
// clinic admin clear booked item
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
// booking
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

    const clinic = await Clinic.findOne({ clinicId }).lean();

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
  listBookedAvailabilities,
  clearBookedAvailability,
  bookAvailability,
};