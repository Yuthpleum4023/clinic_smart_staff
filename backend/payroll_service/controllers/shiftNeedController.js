// controllers/shiftNeedController.js
//
// ✅ FULL FILE (LONG-TERM FIX + DURABLE HELPER WITHOUT staffId)
// ✅ PATCH NEW (STORE READY):
// - enrich clinicDistrict / clinicProvince / clinicLocationLabel
// - listOpenNeeds รองรับ helperLat/helperLng จาก query เพื่อคำนวณ distanceKm / distanceText
// - ✅ NEW: sort nearest first
// - ✅ NEW: isNearby / nearbyLabel
//
// helper call example:
//   GET /shift-needs/open?helperLat=7.0084&helperLng=100.4747
//

const ShiftNeed = require("../models/ShiftNeed");
const Shift = require("../models/Shift");

let Clinic = null;
try {
  Clinic = require("../models/Clinic");
} catch (_) {
  Clinic = null;
}

// ---------------- helpers ----------------
function normalizeRoles(r) {
  if (!r) return [];
  if (Array.isArray(r)) {
    return r.map((x) => String(x || "").trim()).filter(Boolean);
  }
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

function getStaffIdStrict(req) {
  return (req.user?.staffId || "").toString().trim();
}

function getUserId(req) {
  return (
    (req.user?.userId || req.user?.id || req.user?._id || "").toString().trim()
  );
}

function bad(msg, code = 400) {
  const err = new Error(msg);
  err.statusCode = code;
  throw err;
}

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

function ensureApplicantsArray(doc) {
  if (!doc) return [];
  if (Array.isArray(doc.applicants)) return doc.applicants;
  doc.applicants = [];
  return doc.applicants;
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
  const aLat = numOrNull(lat1);
  const aLng = numOrNull(lng1);
  const bLat = numOrNull(lat2);
  const bLng = numOrNull(lng2);

  if (!isValidLatLng(aLat, aLng) || !isValidLatLng(bLat, bLng)) {
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

function getHelperQueryLatLng(req) {
  const lat =
    numOrNull(req.query?.helperLat) ??
    numOrNull(req.query?.lat) ??
    numOrNull(req.user?.lat) ??
    numOrNull(req.user?.latitude);

  const lng =
    numOrNull(req.query?.helperLng) ??
    numOrNull(req.query?.lng) ??
    numOrNull(req.user?.lng) ??
    numOrNull(req.user?.longitude);

  if (!isValidLatLng(lat, lng)) {
    return { helperLat: null, helperLng: null };
  }

  return { helperLat: lat, helperLng: lng };
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

  const clinicDistrict = s(
    n.clinicDistrict || n.district || n.area || n.amphoe
  );
  const clinicProvince = s(
    n.clinicProvince || n.province || n.changwat || n.state
  );
  const clinicLocationLabel =
    s(n.clinicLocationLabel || n.locationLabel) ||
    buildLocationLabel({
      district: clinicDistrict,
      province: clinicProvince,
      address: clinicAddress,
    });

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
    clinicDistrict,
    clinicProvince,
    clinicLocationLabel,
  };
}

async function loadClinicMetaByClinicId(clinicId) {
  if (!Clinic) {
    return {
      clinicLat: null,
      clinicLng: null,
      clinicName: "",
      clinicPhone: "",
      clinicAddress: "",
      clinicDistrict: "",
      clinicProvince: "",
      clinicLocationLabel: "",
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
      clinicDistrict: "",
      clinicProvince: "",
      clinicLocationLabel: "",
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
      clinicDistrict: "",
      clinicProvince: "",
      clinicLocationLabel: "",
    };
  }

  const lat0 = numOrNull(c.lat);
  const lng0 = numOrNull(c.lng);
  const district = s(c.district);
  const province = s(c.province);
  const address = s(c.address);

  return {
    clinicLat: isValidLatLng(lat0, lng0) ? lat0 : null,
    clinicLng: isValidLatLng(lat0, lng0) ? lng0 : null,
    clinicName: s(c.name),
    clinicPhone: s(c.phone),
    clinicAddress: address,
    clinicDistrict: district,
    clinicProvince: province,
    clinicLocationLabel:
      s(c.locationLabel) ||
      buildLocationLabel({ district, province, address }),
  };
}

async function loadClinicMapByClinicIds(ids = []) {
  if (!Clinic) return new Map();

  const clean = [...new Set((ids || []).map((x) => s(x)).filter(Boolean))];
  if (!clean.length) return new Map();

  const rows = await Clinic.find({ clinicId: { $in: clean } }).lean();
  const m = new Map();

  for (const r of rows || []) {
    const lat0 = numOrNull(r.lat);
    const lng0 = numOrNull(r.lng);
    const district = s(r.district);
    const province = s(r.province);
    const address = s(r.address);

    m.set(s(r.clinicId), {
      clinicLat: isValidLatLng(lat0, lng0) ? lat0 : null,
      clinicLng: isValidLatLng(lat0, lng0) ? lng0 : null,
      clinicName: s(r.name),
      clinicPhone: s(r.phone),
      clinicAddress: address,
      clinicDistrict: district,
      clinicProvince: province,
      clinicLocationLabel:
        s(r.locationLabel) ||
        buildLocationLabel({ district, province, address }),
    });
  }
  return m;
}

function mergeClinicMeta({ needMeta, clinicMeta }) {
  const out = { ...needMeta };

  if (!isValidLatLng(numOrNull(out.clinicLat), numOrNull(out.clinicLng))) {
    out.clinicLat = clinicMeta?.clinicLat ?? null;
    out.clinicLng = clinicMeta?.clinicLng ?? null;
  }

  const cName = s(clinicMeta?.clinicName);
  const cPhone = s(clinicMeta?.clinicPhone);
  const cAddr = s(clinicMeta?.clinicAddress);
  const cDistrict = s(clinicMeta?.clinicDistrict);
  const cProvince = s(clinicMeta?.clinicProvince);
  const cLocationLabel = s(clinicMeta?.clinicLocationLabel);

  if (cName) out.clinicName = cName;
  if (cPhone) out.clinicPhone = cPhone;
  if (cAddr) out.clinicAddress = cAddr;
  if (cDistrict) out.clinicDistrict = cDistrict;
  if (cProvince) out.clinicProvince = cProvince;
  if (cLocationLabel) out.clinicLocationLabel = cLocationLabel;

  out.clinicName = s(out.clinicName);
  out.clinicPhone = s(out.clinicPhone);
  out.clinicAddress = s(out.clinicAddress);
  out.clinicDistrict = s(out.clinicDistrict);
  out.clinicProvince = s(out.clinicProvince);
  out.clinicLocationLabel =
    s(out.clinicLocationLabel) ||
    buildLocationLabel({
      district: out.clinicDistrict,
      province: out.clinicProvince,
      address: out.clinicAddress,
    });

  return out;
}

function applicantMatches(app, { staffId, userId }) {
  const aStaff = s(app?.staffId);
  const aUser = s(app?.userId);

  if (userId && aUser && aUser === userId) return true;
  if (staffId && aStaff && aStaff === staffId) return true;

  return false;
}

function pickApplicantKey(app) {
  const uid = s(app?.userId);
  if (uid) return { kind: "userId", value: uid };

  const sid = s(app?.staffId);
  if (sid) return { kind: "staffId", value: sid };

  return { kind: "none", value: "" };
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

      clinicLat,
      clinicLng,
      clinicName,
      clinicPhone,
      clinicAddress,
      clinicDistrict,
      clinicProvince,
      clinicLocationLabel,
    } = req.body || {};

    if (!date || !start || !end) bad("date/start/end required");
    if (!hourlyRate || Number(hourlyRate) <= 0) bad("hourlyRate must be > 0");
    if (Number(requiredCount) <= 0) bad("requiredCount must be > 0");

    const auto = await loadClinicMetaByClinicId(clinicId);

    let lat = numOrNull(clinicLat);
    let lng = numOrNull(clinicLng);
    if (!isValidLatLng(lat, lng)) {
      lat = auto.clinicLat;
      lng = auto.clinicLng;
    }

    const districtText = s(clinicDistrict) || auto.clinicDistrict;
    const provinceText = s(clinicProvince) || auto.clinicProvince;
    const addressText = s(clinicAddress) || auto.clinicAddress;
    const locationLabelText =
      s(clinicLocationLabel) ||
      auto.clinicLocationLabel ||
      buildLocationLabel({
        district: districtText,
        province: provinceText,
        address: addressText,
      });

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

      clinicName: s(clinicName) || auto.clinicName,
      clinicPhone: s(clinicPhone) || auto.clinicPhone,
      clinicAddress: addressText,
      clinicDistrict: districtText,
      clinicProvince: provinceText,
      clinicLocationLabel: locationLabelText,
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
        clinicDistrict: merged.clinicDistrict || "",
        clinicProvince: merged.clinicProvince || "",
        clinicLocationLabel: merged.clinicLocationLabel || "",
        clinic: {
          name: merged.clinicName || "",
          phone: merged.clinicPhone || "",
          address: merged.clinicAddress || "",
          district: merged.clinicDistrict || "",
          province: merged.clinicProvince || "",
          locationLabel: merged.clinicLocationLabel || "",
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
      message: "listClinicNeeds failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- public/auth: list open needs ----------------
async function listOpenNeeds(req, res) {
  try {
    const staffId = getStaffIdStrict(req);
    const userId = getUserId(req);

    const { helperLat, helperLng } = getHelperQueryLatLng(req);
    const hasHelperLocation = isValidLatLng(helperLat, helperLng);

    const q = { status: "open" };
    const items = await ShiftNeed.find(q).lean();

    let clinicMap = new Map();
    if (Clinic && (items || []).length) {
      const clinicIds = (items || []).map((x) => s(x.clinicId)).filter(Boolean);
      clinicMap = await loadClinicMapByClinicIds(clinicIds);
    }

    const enriched = (items || []).map((n) => {
      const applicants = Array.isArray(n.applicants) ? n.applicants : [];

      const applied = applicants.some((a) =>
        applicantMatches(a, { staffId, userId })
      );

      const needMeta = pickClinicMetaFromNeed(n);
      const clinicMeta = clinicMap.get(s(n.clinicId)) || null;
      const merged = mergeClinicMeta({ needMeta, clinicMeta });

      const rawDistanceKm = hasHelperLocation
        ? distanceKmBetween(
            helperLat,
            helperLng,
            merged.clinicLat,
            merged.clinicLng
          )
        : null;

      const distanceKm = roundDistanceKm(rawDistanceKm);
      const distanceText = formatDistanceKm(rawDistanceKm);

      const isNearby =
        typeof distanceKm === "number" && Number.isFinite(distanceKm)
          ? distanceKm <= 5
          : false;

      return {
        ...n,
        _applied: !!applied,

        clinicLat: merged.clinicLat ?? null,
        clinicLng: merged.clinicLng ?? null,
        clinicName: merged.clinicName || "",
        clinicPhone: merged.clinicPhone || "",
        clinicAddress: merged.clinicAddress || "",
        clinicDistrict: merged.clinicDistrict || "",
        clinicProvince: merged.clinicProvince || "",
        clinicLocationLabel: merged.clinicLocationLabel || "",

        distanceKm,
        distanceText,
        isNearby,
        nearbyLabel: isNearby ? "ใกล้คุณ" : "",

        clinic: {
          name: merged.clinicName || "",
          phone: merged.clinicPhone || "",
          address: merged.clinicAddress || "",
          district: merged.clinicDistrict || "",
          province: merged.clinicProvince || "",
          locationLabel: merged.clinicLocationLabel || "",
          location: {
            lat: merged.clinicLat ?? null,
            lng: merged.clinicLng ?? null,
          },
        },
      };
    });

    enriched.sort((a, b) => {
      const aDist = numOrNull(a.distanceKm);
      const bDist = numOrNull(b.distanceKm);

      const aHas = typeof aDist === "number" && Number.isFinite(aDist);
      const bHas = typeof bDist === "number" && Number.isFinite(bDist);

      if (aHas && bHas) {
        if (aDist !== bDist) return aDist - bDist;
      }

      if (aHas && !bHas) return -1;
      if (!aHas && bHas) return 1;

      const aDate = s(a.date);
      const bDate = s(b.date);
      if (aDate !== bDate) return aDate.localeCompare(bDate);

      const aStart = s(a.start);
      const bStart = s(b.start);
      if (aStart !== bStart) return aStart.localeCompare(bStart);

      const aCreated = s(a.createdAt);
      const bCreated = s(b.createdAt);
      return bCreated.localeCompare(aCreated);
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

    const role = s(req.user?.role);
    const staffId = getStaffIdStrict(req);
    const userId = getUserId(req);

    if (role === "helper" && !userId) {
      bad("missing userId in token", 400);
    }
    if (role !== "helper" && !staffId) {
      bad("missing staffId in token", 400);
    }

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.status !== "open") bad("need is not open", 400);

    const applicants = ensureApplicantsArray(need);

    const already = applicants.some((a) =>
      applicantMatches(a, { staffId, userId })
    );
    if (already) return res.json({ ok: true, message: "already applied" });

    const phoneDigits = normalizePhone(req.body?.phone);
    if (!validatePhoneDigits(phoneDigits)) {
      bad("phone required (9-10 digits)", 400);
    }

    const staffIdForApplicant =
      staffId || (role === "helper" ? userId : "");

    if (!staffIdForApplicant) {
      bad("missing applicant identity", 400);
    }

    applicants.push({
      staffId: staffIdForApplicant,
      userId: userId || "",
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

    const applicants = Array.isArray(need.applicants) ? need.applicants : [];
    return res.json({ applicants });
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

    const staff = s(req.body?.staffId);
    const uid = s(req.body?.userId);

    if (!staff && !uid) bad("staffId or userId required");

    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);
    if (need.status !== "open") bad("need is not open", 400);

    const applicants = ensureApplicantsArray(need);

    const a = applicants.find((x) =>
      applicantMatches(x, { staffId: staff, userId: uid })
    );
    if (!a) bad("applicant not found", 404);

    const key = pickApplicantKey(a);

    need.applicants = applicants.map((x) => {
      const xo = x?.toObject ? x.toObject() : x;
      const k2 = pickApplicantKey(xo);

      const approved =
        k2.kind !== "none" &&
        key.kind === k2.kind &&
        String(key.value) === String(k2.value);

      return {
        ...xo,
        status: approved ? "approved" : "rejected",
      };
    });

    const needMeta = pickClinicMetaFromNeed(need);
    const clinicMeta = Clinic
      ? await loadClinicMetaByClinicId(need.clinicId)
      : null;

    const merged = mergeClinicMeta({ needMeta, clinicMeta });

    const applicantUserId = s(a.userId);
    const applicantStaffId = s(a.staffId);

    const shift = await Shift.create({
      clinicId: need.clinicId,
      staffId: applicantStaffId || applicantUserId || staff || uid,
      helperUserId: applicantUserId || "",

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

    need.clinicLat = merged.clinicLat ?? null;
    need.clinicLng = merged.clinicLng ?? null;
    need.clinicName = s(merged.clinicName);
    need.clinicPhone = s(merged.clinicPhone);
    need.clinicAddress = s(merged.clinicAddress);
    need.clinicDistrict = s(merged.clinicDistrict);
    need.clinicProvince = s(merged.clinicProvince);
    need.clinicLocationLabel = s(merged.clinicLocationLabel);

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