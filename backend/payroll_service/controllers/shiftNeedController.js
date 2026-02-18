// controllers/shiftNeedController.js
//
// ✅ FULL FILE (LONG-TERM FIX):
// - createNeed: auto-copy clinic meta from clinics by clinicId (token) + allow override
// - listOpenNeeds: ALWAYS prefer clinics collection meta (backfill & override) for old needs
// - listClinicNeeds: ALSO backfill & override (admin list หน้าคลินิกจะไม่ติด Leena House)
// - approveApplicant: if need meta missing/old -> prefer clinics meta before create Shift
// - applyNeed: require phone digits 9-10
//
// หมายเหตุ: ถ้าไม่มี models/Clinic.js ก็ยังทำงานได้ (จะไม่ enrich)

const ShiftNeed = require("../models/ShiftNeed");
const Shift = require("../models/Shift");

// ✅ OPTIONAL: ถ้ามี models/Clinic.js จะดึงพิกัด/ชื่อ/โทร/ที่อยู่คลินิกมาเติมให้อัตโนมัติ
let Clinic = null;
try {
  Clinic = require("../models/Clinic");
} catch (_) {
  Clinic = null;
}

// ---------------- helpers ----------------
function normalizeRoles(r) {
  if (!r) return [];
  if (Array.isArray(r))
    return r.map((x) => String(x || "").trim()).filter(Boolean);
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

function getClinicId(req) {
  return (req.user?.clinicId || "").toString().trim();
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

function bad(msg, code = 400) {
  const err = new Error(msg);
  err.statusCode = code;
  throw err;
}

// ✅ phone helpers
function normalizePhone(raw) {
  return String(raw || "")
    .trim()
    .replace(/[^\d]/g, "");
}

function validatePhoneDigits(phoneDigits) {
  if (!phoneDigits) return false;
  if (phoneDigits.length < 9 || phoneDigits.length > 10) return false;
  return true;
}

// ✅ clinic meta helpers
function s(v) {
  return (v ?? "").toString().trim();
}

function numOrNull(v) {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  if (Number.isNaN(n)) return null;
  if (!Number.isFinite(n)) return null;
  return n;
}

function isValidLatLng(lat, lng) {
  if (lat === null || lng === null) return false;
  if (typeof lat !== "number" || typeof lng !== "number") return false;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat < -90 || lat > 90) return false;
  if (lng < -180 || lng > 180) return false;
  return true;
}

function pickClinicMetaFromNeed(needDoc) {
  const n = needDoc?.toObject ? needDoc.toObject() : needDoc || {};

  const clinicName = s(
    n.clinicName || n.clinic_title || n.clinicTitle || n.name
  );
  const clinicPhone = s(n.clinicPhone || n.contactPhone || n.phone);
  const clinicAddress = s(
    n.clinicAddress || n.address || n.locationAddress || n.fullAddress
  );

  const lat =
    numOrNull(n.clinicLat) ??
    numOrNull(n.lat) ??
    numOrNull(n.location?.lat) ??
    numOrNull(n.location?.latitude) ??
    numOrNull(n.geo?.lat) ??
    numOrNull(n.geo?.latitude);

  const lng =
    numOrNull(n.clinicLng) ??
    numOrNull(n.lng) ??
    numOrNull(n.location?.lng) ??
    numOrNull(n.location?.longitude) ??
    numOrNull(n.geo?.lng) ??
    numOrNull(n.geo?.longitude);

  const ok = isValidLatLng(lat, lng);

  return {
    clinicLat: ok ? lat : null,
    clinicLng: ok ? lng : null,
    clinicName,
    clinicPhone,
    clinicAddress,
  };
}

// ✅ load clinic meta (single)
async function loadClinicMetaByClinicId(clinicId) {
  if (!Clinic) {
    return {
      clinicLat: null,
      clinicLng: null,
      clinicName: "",
      clinicPhone: "",
      clinicAddress: "",
    };
  }

  const cid = s(clinicId);
  if (!cid) {
    return {
      clinicLat: null,
      clinicLng: null,
      clinicName: "",
      clinicPhone: "",
      clinicAddress: "",
    };
  }

  const c = await Clinic.findOne({ clinicId: cid }).lean();
  if (!c) {
    return {
      clinicLat: null,
      clinicLng: null,
      clinicName: "",
      clinicPhone: "",
      clinicAddress: "",
    };
  }

  const lat0 = numOrNull(c.lat);
  const lng0 = numOrNull(c.lng);

  return {
    clinicLat: isValidLatLng(lat0, lng0) ? lat0 : null,
    clinicLng: isValidLatLng(lat0, lng0) ? lng0 : null,
    clinicName: s(c.name),
    clinicPhone: s(c.phone),
    clinicAddress: s(c.address),
  };
}

// ✅ load clinic meta (batch) for listOpenNeeds/listClinicNeeds
async function loadClinicMapByClinicIds(ids = []) {
  if (!Clinic) return new Map();

  const clean = [...new Set((ids || []).map((x) => s(x)).filter(Boolean))];
  if (!clean.length) return new Map();

  const rows = await Clinic.find({ clinicId: { $in: clean } }).lean();
  const m = new Map();
  for (const r of rows || []) {
    const lat0 = numOrNull(r.lat);
    const lng0 = numOrNull(r.lng);

    m.set(s(r.clinicId), {
      clinicLat: isValidLatLng(lat0, lng0) ? lat0 : null,
      clinicLng: isValidLatLng(lat0, lng0) ? lng0 : null,
      clinicName: s(r.name),
      clinicPhone: s(r.phone),
      clinicAddress: s(r.address),
    });
  }
  return m;
}

// ✅ merge rule (IMPORTANT):
// - prefer clinic meta from clinics collection when it exists (long-term fix for "Leena House stuck")
function mergeClinicMeta({ needMeta, clinicMeta }) {
  const out = { ...needMeta };

  // lat/lng: prefer need if valid, else clinic
  if (!isValidLatLng(numOrNull(out.clinicLat), numOrNull(out.clinicLng))) {
    out.clinicLat = clinicMeta?.clinicLat ?? null;
    out.clinicLng = clinicMeta?.clinicLng ?? null;
  }

  // name/phone/address: prefer clinic if it has non-empty value
  const cName = s(clinicMeta?.clinicName);
  const cPhone = s(clinicMeta?.clinicPhone);
  const cAddr = s(clinicMeta?.clinicAddress);

  if (cName) out.clinicName = cName;
  if (cPhone) out.clinicPhone = cPhone;
  if (cAddr) out.clinicAddress = cAddr;

  // ensure string
  out.clinicName = s(out.clinicName);
  out.clinicPhone = s(out.clinicPhone);
  out.clinicAddress = s(out.clinicAddress);

  return out;
}

// ---------------- admin: create need ----------------
async function createNeed(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const {
      title = "ต้องการผู้ช่วย",
      role = "ผู้ช่วย",
      date,
      start,
      end,
      hourlyRate,
      requiredCount = 1,
      note = "",

      // optional override
      clinicLat,
      clinicLng,
      clinicName,
      clinicPhone,
      clinicAddress,
    } = req.body || {};

    if (!date || !start || !end) bad("date/start/end required");
    if (!hourlyRate || Number(hourlyRate) <= 0) bad("hourlyRate must be > 0");
    if (Number(requiredCount) <= 0) bad("requiredCount must be > 0");

    const auto = await loadClinicMetaByClinicId(clinicId);

    // lat/lng: override > auto
    let lat = numOrNull(clinicLat);
    let lng = numOrNull(clinicLng);
    if (!isValidLatLng(lat, lng)) {
      lat = auto.clinicLat;
      lng = auto.clinicLng;
    }

    const need = await ShiftNeed.create({
      clinicId,
      title,
      role,
      date,
      start,
      end,
      hourlyRate: Number(hourlyRate),
      requiredCount: Number(requiredCount),
      note,
      status: "open",
      createdByUserId: req.user?.userId || "",

      clinicLat: isValidLatLng(lat, lng) ? lat : null,
      clinicLng: isValidLatLng(lat, lng) ? lng : null,

      // name/phone/address: override (if non-empty) else auto
      clinicName: s(clinicName) || auto.clinicName,
      clinicPhone: s(clinicPhone) || auto.clinicPhone,
      clinicAddress: s(clinicAddress) || auto.clinicAddress,
    });

    return res.status(201).json({ need });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "createNeed failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: list own clinic needs ----------------
async function listClinicNeeds(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const status = (req.query.status || "").toString().trim();
    const q = { clinicId };
    if (status) q.status = status;

    const items = await ShiftNeed.find(q).sort({ createdAt: -1 }).lean();

    // ✅ LONG-TERM FIX: override clinic meta from clinics (so old needs won't show Leena House)
    let clinicMap = new Map();
    if (Clinic && (items || []).length) {
      const clinicIds = (items || []).map((x) => s(x.clinicId)).filter(Boolean);
      clinicMap = await loadClinicMapByClinicIds(clinicIds);
    }

    const enriched = (items || []).map((n) => {
      const needMeta = pickClinicMetaFromNeed(n);
      const clinicMeta = clinicMap.get(s(n.clinicId)) || null;
      const merged = mergeClinicMeta({ needMeta, clinicMeta });

      return {
        ...n,
        clinicLat: merged.clinicLat ?? null,
        clinicLng: merged.clinicLng ?? null,
        clinicName: merged.clinicName || "",
        clinicPhone: merged.clinicPhone || "",
        clinicAddress: merged.clinicAddress || "",
        clinic: {
          name: merged.clinicName || "",
          phone: merged.clinicPhone || "",
          address: merged.clinicAddress || "",
          location: { lat: merged.clinicLat ?? null, lng: merged.clinicLng ?? null },
        },
      };
    });

    return res.json({ items: enriched });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listClinicNeeds failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- public (auth): list open needs ----------------
async function listOpenNeeds(req, res) {
  try {
    const staffId = getStaffId(req);

    const q = { status: "open" };
    const items = await ShiftNeed.find(q).sort({ date: 1, start: 1 }).lean();

    // ✅ FIX: backfill clinic meta from clinics
    let clinicMap = new Map();
    if (Clinic && (items || []).length) {
      const clinicIds = (items || []).map((x) => s(x.clinicId)).filter(Boolean);
      clinicMap = await loadClinicMapByClinicIds(clinicIds);
    }

    const enriched = (items || []).map((n) => {
      const applied =
        staffId &&
        (n.applicants || []).some((a) => String(a.staffId) === String(staffId));

      const needMeta = pickClinicMetaFromNeed(n);
      const clinicMeta = clinicMap.get(s(n.clinicId)) || null;

      // ✅ IMPORTANT: merged prefers clinics meta for name/phone/address (fix stuck data)
      const merged = mergeClinicMeta({ needMeta, clinicMeta });

      return {
        ...n,
        _applied: !!applied,

        clinicLat: merged.clinicLat ?? null,
        clinicLng: merged.clinicLng ?? null,
        clinicName: merged.clinicName || "",
        clinicPhone: merged.clinicPhone || "",
        clinicAddress: merged.clinicAddress || "",

        clinic: {
          name: merged.clinicName || "",
          phone: merged.clinicPhone || "",
          address: merged.clinicAddress || "",
          location: {
            lat: merged.clinicLat ?? null,
            lng: merged.clinicLng ?? null,
          },
        },
      };
    });

    return res.json({ items: enriched });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listOpenNeeds failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- staff/helper: apply ----------------
async function applyNeed(req, res) {
  try {
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffId(req);
    if (!staffId)
      bad("missing staffId in token (please add staffId to JWT)", 400);

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.status !== "open") bad("need is not open", 400);

    const already = (need.applicants || []).some(
      (a) => String(a.staffId) === String(staffId)
    );
    if (already) return res.json({ ok: true, message: "already applied" });

    const phoneDigits = normalizePhone(req.body?.phone);
    if (!validatePhoneDigits(phoneDigits)) {
      bad("phone required (9-10 digits)", 400);
    }

    need.applicants.push({
      staffId,
      userId: req.user?.userId || "",
      phone: phoneDigits,
      status: "pending",
      appliedAt: new Date(),
    });

    await need.save();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "applyNeed failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: list applicants ----------------
async function listApplicants(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id).lean();
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);

    return res.json({ applicants: need.applicants || [] });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listApplicants failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: approve applicant -> create Shift ----------------
async function approveApplicant(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const id = (req.params.id || "").toString();
    const { staffId } = req.body || {};
    const staff = (staffId || "").toString().trim();
    if (!staff) bad("staffId required");

    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);
    if (need.status !== "open") bad("need is not open", 400);

    const a = (need.applicants || []).find(
      (x) => String(x.staffId) === String(staff)
    );
    if (!a) bad("applicant not found", 404);

    need.applicants = (need.applicants || []).map((x) => ({
      ...x.toObject(),
      status: String(x.staffId) === String(staff) ? "approved" : "rejected",
    }));

    const needMeta = pickClinicMetaFromNeed(need);
    const clinicMeta = Clinic ? await loadClinicMetaByClinicId(need.clinicId) : null;

    // ✅ IMPORTANT: merged prefers clinic meta for name/phone/address
    const merged = mergeClinicMeta({ needMeta, clinicMeta });

    const shift = await Shift.create({
      clinicId: need.clinicId,
      staffId: staff,
      date: need.date,
      start: need.start,
      end: need.end,
      hourlyRate: need.hourlyRate,
      note: need.note || need.title || "Shift from ShiftNeed",
      status: "scheduled",

      clinicLat: merged.clinicLat ?? null,
      clinicLng: merged.clinicLng ?? null,
      clinicName: s(merged.clinicName),
      clinicPhone: s(merged.clinicPhone),
      clinicAddress: s(merged.clinicAddress),
    });

    if (Number(need.requiredCount || 1) <= 1) {
      need.status = "filled";
    }

    // ✅ optional: persist back to need to clean old docs
    need.clinicLat = merged.clinicLat ?? null;
    need.clinicLng = merged.clinicLng ?? null;
    need.clinicName = s(merged.clinicName);
    need.clinicPhone = s(merged.clinicPhone);
    need.clinicAddress = s(merged.clinicAddress);

    await need.save();

    return res.json({ ok: true, shift });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "approveApplicant failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: cancel need ----------------
async function cancelNeed(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);

    need.status = "cancelled";
    await need.save();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "cancelNeed failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  createNeed,
  listClinicNeeds,
  listOpenNeeds,
  applyNeed,
  listApplicants,
  approveApplicant,
  cancelNeed,
};
