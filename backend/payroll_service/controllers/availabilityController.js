// controllers/availabilityController.js

const mongoose = require("mongoose");
const Availability = require("../models/Availability");
const Shift = require("../models/Shift");
const Clinic = require("../models/Clinic");
const {
  buildDistancePayload,
} = require("../utils/locationEngine");

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

function buildLocationLabel({
  district = "",
  province = "",
  address = "",
} = {}) {
  const d = s(district);
  const p = s(province);
  const a = s(address);

  if (d && p) return `${d}, ${p}`;
  if (p) return p;
  if (d) return d;
  if (a) return a;
  return "";
}

function isNearbyDistance(distanceKm) {
  const d = toNumOrNull(distanceKm);
  if (d === null) return false;
  return d <= 10;
}

function nearbyLabelFromDistance(distanceKm) {
  return isNearbyDistance(distanceKm) ? "ใกล้คลินิก" : "";
}

function normalizeUserLocation(req) {
  const loc = req.user?.location || {};

  const lat =
    toNumOrNull(loc?.lat) ??
    toNumOrNull(loc?.latitude) ??
    toNumOrNull(req.user?.lat) ??
    toNumOrNull(req.user?.latitude);

  const lng =
    toNumOrNull(loc?.lng) ??
    toNumOrNull(loc?.longitude) ??
    toNumOrNull(req.user?.lng) ??
    toNumOrNull(req.user?.longitude);

  const district = s(loc?.district || loc?.amphoe);
  const province = s(loc?.province || loc?.changwat);
  const address = s(loc?.address || loc?.fullAddress);
  const locationLabel =
    s(loc?.label || loc?.locationLabel) ||
    buildLocationLabel({ district, province, address });

  return {
    lat,
    lng,
    district,
    province,
    address,
    locationLabel,
  };
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

function compareOpenAvailabilityItems(a, b) {
  const aDist = toNumOrNull(a.distanceKm);
  const bDist = toNumOrNull(b.distanceKm);

  const aHasDist = aDist !== null;
  const bHasDist = bDist !== null;

  if (aHasDist && bHasDist) {
    if (aDist !== bDist) return aDist - bDist;
  } else if (aHasDist && !bHasDist) {
    return -1;
  } else if (!aHasDist && bHasDist) {
    return 1;
  }

  const aDate = s(a.date);
  const bDate = s(b.date);
  if (aDate !== bDate) return aDate.localeCompare(bDate);

  const aStart = timeToMin(a.start) ?? 0;
  const bStart = timeToMin(b.start) ?? 0;
  if (aStart !== bStart) return aStart - bStart;

  const aCreated = s(a.createdAt);
  const bCreated = s(b.createdAt);
  return aCreated.localeCompare(bCreated);
}

// ---------------- auth user fallback ----------------
function authBase() {
  return s(
    process.env.AUTH_USER_SERVICE_URL ||
      process.env.AUTH_SERVICE_URL ||
      "https://auth-user-service-afwu.onrender.com"
  ).replace(/\/+$/, "");
}

function internalKey() {
  return s(process.env.INTERNAL_KEY || process.env.INTERNAL_SERVICE_KEY);
}

async function fetchJson(url, headers = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);

  try {
    const res = await fetch(url, {
      method: "GET",
      headers,
      signal: ctrl.signal,
    });

    const text = await res.text();
    let data = null;

    try {
      data = text ? JSON.parse(text) : null;
    } catch (_) {
      data = null;
    }

    return {
      ok: res.ok,
      status: res.status,
      data,
      raw: text,
    };
  } catch (e) {
    return {
      ok: false,
      status: 0,
      data: null,
      raw: "",
      error: e.message || String(e),
    };
  } finally {
    clearTimeout(timer);
  }
}

function normalizeRemoteUserLocation(payload) {
  const root = payload && typeof payload === "object" ? payload : {};
  const user =
    root.user && typeof root.user === "object"
      ? root.user
      : root.data && typeof root.data === "object"
      ? root.data
      : root;

  const loc =
    user.location && typeof user.location === "object" ? user.location : {};

  const lat =
    toNumOrNull(loc?.lat) ??
    toNumOrNull(loc?.latitude) ??
    toNumOrNull(user?.lat) ??
    toNumOrNull(user?.latitude);

  const lng =
    toNumOrNull(loc?.lng) ??
    toNumOrNull(loc?.longitude) ??
    toNumOrNull(user?.lng) ??
    toNumOrNull(user?.longitude);

  const district = s(
    loc?.district || loc?.amphoe || user?.district || user?.amphoe
  );
  const province = s(
    loc?.province || loc?.changwat || user?.province || user?.changwat
  );
  const address = s(
    loc?.address || loc?.fullAddress || user?.address || user?.fullAddress
  );
  const locationLabel =
    s(loc?.label || loc?.locationLabel || user?.locationLabel) ||
    buildLocationLabel({ district, province, address });

  return {
    lat,
    lng,
    district,
    province,
    address,
    locationLabel,
  };
}

function hasUsableLocation(loc) {
  if (!loc || typeof loc !== "object") return false;
  return (
    toNumOrNull(loc.lat) !== null ||
    toNumOrNull(loc.lng) !== null ||
    s(loc.locationLabel) !== "" ||
    s(loc.address) !== "" ||
    s(loc.district) !== "" ||
    s(loc.province) !== ""
  );
}

async function fetchSingleUserLocation(userKey) {
  const id = s(userKey);
  if (!id) return null;

  const base = authBase();
  const key = internalKey();

  const headers = {
    Accept: "application/json",
  };

  if (key) {
    headers["x-internal-key"] = key;
    headers["x-service-key"] = key;
    headers["authorization"] = `Bearer ${key}`;
  }

  const candidates = [
    `${base}/internal/users/${encodeURIComponent(id)}`,
    `${base}/users/${encodeURIComponent(id)}`,
    `${base}/users/public/${encodeURIComponent(id)}`,
    `${base}/api/users/${encodeURIComponent(id)}`,
    `${base}/api/users/public/${encodeURIComponent(id)}`,
  ];

  for (const url of candidates) {
    const rs = await fetchJson(url, headers);
    if (!rs.ok || !rs.data) continue;

    const loc = normalizeRemoteUserLocation(rs.data);
    if (hasUsableLocation(loc)) return loc;
  }

  return null;
}

async function fetchUserLocationsMap(userKeys = []) {
  const ids = Array.from(
    new Set((userKeys || []).map((x) => s(x)).filter(Boolean))
  );

  const out = {};
  for (const id of ids) {
    try {
      const loc = await fetchSingleUserLocation(id);
      if (hasUsableLocation(loc)) {
        out[id] = loc;
      }
    } catch (_) {
      // ปล่อยผ่าน เพื่อไม่ให้ list พังทั้งหน้า
    }
  }
  return out;
}

function mergeAvailabilityLocation(it, fallbackLoc) {
  const ownLat = toNumOrNull(it?.lat);
  const ownLng = toNumOrNull(it?.lng);
  const ownDistrict = s(it?.district);
  const ownProvince = s(it?.province);
  const ownAddress = s(it?.address);
  const ownLocationLabel =
    s(it?.locationLabel) ||
    buildLocationLabel({
      district: ownDistrict,
      province: ownProvince,
      address: ownAddress,
    });

  const fb = fallbackLoc || {};

  const lat = ownLat !== null ? ownLat : toNumOrNull(fb.lat);
  const lng = ownLng !== null ? ownLng : toNumOrNull(fb.lng);
  const district = ownDistrict || s(fb.district);
  const province = ownProvince || s(fb.province);
  const address = ownAddress || s(fb.address);
  const locationLabel =
    ownLocationLabel ||
    s(fb.locationLabel) ||
    buildLocationLabel({ district, province, address });

  return {
    lat,
    lng,
    district,
    province,
    address,
    locationLabel,
  };
}

function mergeLocationSources(primaryLoc, fallbackLoc) {
  const a = primaryLoc || {};
  const b = fallbackLoc || {};

  const lat =
    toNumOrNull(a.lat) !== null ? toNumOrNull(a.lat) : toNumOrNull(b.lat);
  const lng =
    toNumOrNull(a.lng) !== null ? toNumOrNull(a.lng) : toNumOrNull(b.lng);

  const district = s(a.district) || s(b.district);
  const province = s(a.province) || s(b.province);
  const address = s(a.address) || s(b.address);
  const locationLabel =
    s(a.locationLabel) ||
    s(b.locationLabel) ||
    buildLocationLabel({ district, province, address });

  return {
    lat,
    lng,
    district,
    province,
    address,
    locationLabel,
  };
}

async function resolveCreateAvailabilityLocation(req, body = {}) {
  const tokenLocation = normalizeUserLocation(req);

  const bodyLocation = {
    lat:
      toNumOrNull(body?.lat) ??
      toNumOrNull(body?.latitude) ??
      toNumOrNull(body?.location?.lat) ??
      toNumOrNull(body?.location?.latitude),
    lng:
      toNumOrNull(body?.lng) ??
      toNumOrNull(body?.longitude) ??
      toNumOrNull(body?.location?.lng) ??
      toNumOrNull(body?.location?.longitude),
    district: s(
      body?.district || body?.location?.district || body?.location?.amphoe
    ),
    province: s(
      body?.province || body?.location?.province || body?.location?.changwat
    ),
    address: s(
      body?.address || body?.location?.address || body?.location?.fullAddress
    ),
    locationLabel:
      s(
        body?.locationLabel ||
          body?.location?.label ||
          body?.location?.locationLabel
      ) || "",
  };

  const mergedBodyAndToken = mergeLocationSources(bodyLocation, tokenLocation);
  if (hasUsableLocation(mergedBodyAndToken)) {
    return mergedBodyAndToken;
  }

  const keysToTry = Array.from(
    new Set(
      [getUserId(req), getStaffIdStrict(req), getActorId(req)]
        .map(s)
        .filter(Boolean)
    )
  );

  for (const key of keysToTry) {
    try {
      const remoteLoc = await fetchSingleUserLocation(key);
      const merged = mergeLocationSources(mergedBodyAndToken, remoteLoc);
      if (hasUsableLocation(merged)) {
        return merged;
      }
    } catch (e) {
      console.error(
        "resolveCreateAvailabilityLocation fallback error:",
        e.message || String(e)
      );
    }
  }

  return mergedBodyAndToken;
}

async function buildEnrichedAvailabilityItems(items, clinicCtx) {
  const safeItems = Array.isArray(items) ? items : [];

  const fallbackUserKeys = Array.from(
    new Set(
      safeItems
        .filter((it) => {
          const noLat = toNumOrNull(it?.lat) === null;
          const noLng = toNumOrNull(it?.lng) === null;
          const noLabel = s(it?.locationLabel) === "";
          const noDistrict = s(it?.district) === "";
          const noProvince = s(it?.province) === "";
          const noAddress = s(it?.address) === "";
          return (
            noLat &&
            noLng &&
            noLabel &&
            noDistrict &&
            noProvince &&
            noAddress
          );
        })
        .map((it) => s(it?.userId) || s(it?.staffId))
        .filter(Boolean)
    )
  );

  const remoteLocationMap =
    fallbackUserKeys.length > 0
      ? await fetchUserLocationsMap(fallbackUserKeys)
      : {};

  const enriched = safeItems.map((it) => {
    const lookupKey = s(it?.userId) || s(it?.staffId);
    const mergedLoc = mergeAvailabilityLocation(
      it,
      remoteLocationMap[lookupKey]
    );

    const distancePayload = clinicCtx
      ? buildDistancePayload(
          { lat: clinicCtx?.lat, lng: clinicCtx?.lng },
          { lat: mergedLoc?.lat, lng: mergedLoc?.lng }
        )
      : {
          distanceKm: null,
          distanceText: "",
          nearClinic: false,
        };

    return {
      ...it,
      lat: mergedLoc.lat,
      lng: mergedLoc.lng,
      district: mergedLoc.district,
      province: mergedLoc.province,
      address: mergedLoc.address,
      locationLabel: mergedLoc.locationLabel,
      distanceKm: distancePayload.distanceKm,
      distanceText: distancePayload.distanceText,
      isNearby: distancePayload.nearClinic,
      nearbyLabel: distancePayload.nearClinic ? "ใกล้คลินิก" : "",
    };
  });

  return {
    fallbackUserKeys,
    remoteLocationMap,
    enriched,
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
    } = req.body || {};

    if (!isYMD(date)) bad("date required (YYYY-MM-DD)");
    if (!isHHmm(start) || !isHHmm(end)) bad("start/end must be HH:mm");

    const a = timeToMin(start);
    const b = timeToMin(end);
    if (a === null || b === null) bad("invalid time");
    if (b <= a) bad("end must be after start");

    const fullName = getFullName(req, req.body);
    const phone = getPhone(req, req.body);

    const resolvedLocation = await resolveCreateAvailabilityLocation(
      req,
      req.body
    );

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

      lat: resolvedLocation.lat,
      lng: resolvedLocation.lng,
      district: s(resolvedLocation.district),
      province: s(resolvedLocation.province),
      address: s(resolvedLocation.address),
      locationLabel: s(resolvedLocation.locationLabel),

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

    return res.status(201).json({
      ok: true,
      availability: doc,
      locationResolved: {
        lat: resolvedLocation.lat,
        lng: resolvedLocation.lng,
        district: s(resolvedLocation.district),
        province: s(resolvedLocation.province),
        address: s(resolvedLocation.address),
        locationLabel: s(resolvedLocation.locationLabel),
      },
    });
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

      const distancePayload = buildDistancePayload(
        { lat: it?.lat, lng: it?.lng },
        { lat: c?.lat, lng: c?.lng }
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
        bookedClinicDistanceKm: distancePayload.distanceKm,
        bookedClinicDistanceText: distancePayload.distanceText,
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
    mustRoleAny(req, ["admin", "clinic_admin"]);

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

    const { fallbackUserKeys, remoteLocationMap, enriched } =
      await buildEnrichedAvailabilityItems(items, clinicCtx);

    console.log("OPEN clinicCtx =>", clinicCtx);
    console.log("OPEN fallback userKeys =>", fallbackUserKeys);
    console.log(
      "OPEN remoteLocationMap keys =>",
      Object.keys(remoteLocationMap || {})
    );
    console.log(
      "OPEN enriched preview =>",
      (enriched || []).map((x) => ({
        id: String(x._id || ""),
        userId: s(x.userId),
        staffId: s(x.staffId),
        fullName: x.fullName,
        lat: x.lat,
        lng: x.lng,
        locationLabel: x.locationLabel,
        distanceKm: x.distanceKm,
        distanceText: x.distanceText,
        isNearby: x.isNearby,
        nearbyLabel: x.nearbyLabel,
      }))
    );

    enriched.sort(compareOpenAvailabilityItems);

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
    mustRoleAny(req, ["admin", "clinic_admin"]);

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

    const clinicCtx = await getClinicContext(req);
    const items = await Availability.find(q).sort({ date: 1, start: 1 }).lean();

    const { fallbackUserKeys, remoteLocationMap, enriched } =
      await buildEnrichedAvailabilityItems(items, clinicCtx);

    console.log("BOOKED clinicCtx =>", clinicCtx);
    console.log("BOOKED fallback userKeys =>", fallbackUserKeys);
    console.log(
      "BOOKED remoteLocationMap keys =>",
      Object.keys(remoteLocationMap || {})
    );
    console.log(
      "BOOKED enriched preview =>",
      (enriched || []).map((x) => ({
        id: String(x._id || ""),
        userId: s(x.userId),
        staffId: s(x.staffId),
        fullName: x.fullName,
        lat: x.lat,
        lng: x.lng,
        locationLabel: x.locationLabel,
        distanceKm: x.distanceKm,
        distanceText: x.distanceText,
        isNearby: x.isNearby,
        nearbyLabel: x.nearbyLabel,
      }))
    );

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
    mustRoleAny(req, ["admin", "clinic_admin"]);

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
    mustRoleAny(req, ["admin", "clinic_admin"]);

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
      helperUserId: s(updated.userId),

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