// backend/auth_user_service/controllers/helperController.js
const User = require("../models/User");

// ---------------- helpers ----------------
function norm(s) {
  return String(s || "").trim();
}

function escapeRegex(s) {
  const v = String(s || "");
  return v.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function mustLogin(req) {
  if (!req.user) {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    throw err;
  }
}

/**
 * ✅ Align with canonicalRole() in auth middleware
 * allow clinic/admin style tokens
 */
function mustClinicOrAdmin(req) {
  const role = norm(req.user?.role).toLowerCase();
  const ok = role === "clinic" || role === "admin";
  if (!ok) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

function isHelperLikeUser(doc) {
  const role = norm(doc?.role).toLowerCase();
  const activeRole = norm(doc?.activeRole).toLowerCase();

  const roles = Array.isArray(doc?.roles)
    ? doc.roles.map((x) => norm(x).toLowerCase()).filter(Boolean)
    : [];

  return role === "helper" || activeRole === "helper" || roles.includes("helper");
}

function asObj(v) {
  return v && typeof v === "object" ? v : {};
}

function toNum(v) {
  if (v == null) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function pickLocation(raw) {
  const root = asObj(raw);
  const coords = asObj(root.coordinates);

  const lat =
    toNum(root.lat) ??
    toNum(root.latitude) ??
    toNum(coords.lat) ??
    toNum(coords.latitude);

  const lng =
    toNum(root.lng) ??
    toNum(root.longitude) ??
    toNum(root.lon) ??
    toNum(root.long) ??
    toNum(coords.lng) ??
    toNum(coords.longitude) ??
    toNum(coords.lon) ??
    toNum(coords.long);

  return {
    lat,
    lng,
    district: norm(root.district || root.amphoe),
    province: norm(root.province || root.changwat),
    address: norm(root.address || root.fullAddress),
    label: norm(root.label || root.locationLabel),
  };
}

function buildAreaText(location = {}) {
  const district = norm(location.district);
  const province = norm(location.province);
  const label = norm(location.label);
  const address = norm(location.address);

  if (district && province) return `${district}, ${province}`;
  if (province) return province;
  if (district) return district;
  if (label) return label;
  if (address) return address;
  return "";
}

function toHelperItem(doc) {
  const roles = Array.isArray(doc?.roles)
    ? doc.roles.map((x) => norm(x)).filter(Boolean)
    : [];

  const location = pickLocation(doc?.location);

  return {
    userId: norm(doc?.userId),
    fullName: norm(doc?.fullName),
    phone: norm(doc?.phone),
    email: norm(doc?.email),
    role: isHelperLikeUser(doc) ? "helper" : norm(doc?.role),
    activeRole: isHelperLikeUser(doc) ? "helper" : norm(doc?.activeRole),
    roles,
    clinicId: norm(doc?.clinicId),
    staffId: norm(doc?.staffId),

    // ✅ location
    location,
    areaText: buildAreaText(location),

    // ✅ convenience flat fields
    lat: location.lat,
    lng: location.lng,
    district: location.district,
    province: location.province,
    address: location.address,
    label: location.label,
  };
}

// =====================================================
// GET /helpers/search?q=...
// - ✅ GLOBAL helper marketplace search
// - ❌ ไม่ scope clinicId
// - ✅ คืน userId เป็น identity หลัก
// =====================================================
async function searchHelpers(req, res) {
  try {
    mustLogin(req);
    mustClinicOrAdmin(req);

    const q = norm(req.query.q);
    const limitRaw = parseInt(req.query.limit || "20", 10);
    const limit = Math.min(
      Math.max(Number.isFinite(limitRaw) ? limitRaw : 20, 1),
      50
    );

    const mongoQuery = {
      isActive: true,
      $or: [
        { role: "helper" },
        { activeRole: "helper" },
        { roles: "helper" },
      ],
    };

    if (q) {
      const safe = escapeRegex(q);
      const rx = new RegExp(safe, "i");
      const phoneRx = /^\d+$/.test(q) ? new RegExp(escapeRegex(q), "i") : rx;

      mongoQuery.$and = [
        {
          $or: [
            { fullName: rx },
            { phone: phoneRx },
            { userId: rx },
            { staffId: rx },
            { email: rx },
          ],
        },
      ];
    }

    const docs = await User.find(mongoQuery)
      .select(
        "userId fullName phone email role activeRole roles clinicId staffId isActive location"
      )
      .sort({ fullName: 1, createdAt: -1 })
      .limit(limit)
      .lean();

    const items = docs
      .filter(isHelperLikeUser)
      .map(toHelperItem)
      .filter((x) => x.userId);

    return res.json({
      ok: true,
      q,
      count: items.length,
      items,
    });
  } catch (e) {
    const code = e.statusCode || 500;
    return res.status(code).json({
      message: "searchHelpers failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// GET /helpers/by-userid/:userId
// - ✅ GLOBAL helper lookup by userId
// =====================================================
async function getHelperByUserId(req, res) {
  try {
    mustLogin(req);
    mustClinicOrAdmin(req);

    const userId = norm(req.params.userId);
    if (!userId) {
      return res.status(400).json({ message: "userId is required" });
    }

    const doc = await User.findOne({
      userId,
      isActive: true,
      $or: [
        { role: "helper" },
        { activeRole: "helper" },
        { roles: "helper" },
      ],
    })
      .select(
        "userId fullName phone email role activeRole roles clinicId staffId isActive location"
      )
      .lean();

    if (!doc || !isHelperLikeUser(doc)) {
      return res.status(404).json({ message: "helper not found" });
    }

    return res.json({
      ok: true,
      helper: toHelperItem(doc),
    });
  } catch (e) {
    const code = e.statusCode || 500;
    return res.status(code).json({
      message: "getHelperByUserId failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  searchHelpers,
  getHelperByUserId,
};