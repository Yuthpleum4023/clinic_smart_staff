const mongoose = require("mongoose");
const TrustScore = require("../models/TrustScore");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function asArray(v) {
  return Array.isArray(v) ? v : [];
}

function asObj(v) {
  return v && typeof v === "object" ? v : {};
}

function escapeRegex(v) {
  return String(v || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isValidStaffId(v) {
  const x = s(v);
  return x.startsWith("stf_") && x.length >= 6;
}

function isValidUserId(v) {
  const x = s(v);
  return x.startsWith("usr_") && x.length >= 6;
}

function authBase() {
  return s(
    process.env.AUTH_USER_SERVICE_URL ||
      "https://auth-user-service-afwu.onrender.com"
  ).replace(/\/+$/, "");
}

function internalKey() {
  return s(process.env.INTERNAL_KEY || process.env.INTERNAL_SERVICE_KEY);
}

async function fetchJson(url, headers = {}) {
  const ctrl = new AbortController();
  const timeout = setTimeout(() => ctrl.abort(), 15000);

  try {
    const r = await fetch(url, {
      method: "GET",
      headers,
      signal: ctrl.signal,
    });

    const data = await r.json().catch(() => ({}));
    return { ok: r.ok, status: r.status, data };
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeStats(doc) {
  return {
    totalShifts: n(doc?.totalShifts),
    completed: n(doc?.completed),
    late: n(doc?.late),
    noShow: n(doc?.noShow),
    cancelledEarly: n(doc?.cancelledEarly ?? doc?.cancelled),
  };
}

function pickLocation(raw) {
  const root = asObj(raw);
  const coords = asObj(root.coordinates);

  const lat =
    n(
      root.lat ??
        root.latitude ??
        coords.lat ??
        coords.latitude,
      NaN
    );

  const lng =
    n(
      root.lng ??
        root.longitude ??
        root.lon ??
        root.long ??
        coords.lng ??
        coords.longitude ??
        coords.lon ??
        coords.long,
      NaN
    );

  return {
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    district: s(root.district || root.amphoe),
    province: s(root.province || root.changwat),
    address: s(root.address || root.fullAddress),
    label: s(root.label || root.locationLabel),
  };
}

function buildAreaText(location = {}) {
  const district = s(location.district);
  const province = s(location.province);
  const label = s(location.label);
  const address = s(location.address);

  if (district && province) return `${district}, ${province}`;
  if (province) return province;
  if (district) return district;
  if (label) return label;
  if (address) return address;
  return "";
}

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  if (
    !Number.isFinite(lat1) ||
    !Number.isFinite(lng1) ||
    !Number.isFinite(lat2) ||
    !Number.isFinite(lng2)
  ) {
    return null;
  }

  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 100) / 100;
}

function formatDistanceText(distanceKm) {
  if (!Number.isFinite(distanceKm)) return "";
  if (distanceKm < 1) return `${Math.round(distanceKm * 1000)} ม.`;
  return `${distanceKm.toFixed(distanceKm < 10 ? 1 : 0)} กม.`;
}

function toScorePayload(doc) {
  if (!doc) {
    return {
      trustScore: 80,
      flags: [],
      badges: [],
      stats: {
        totalShifts: 0,
        completed: 0,
        late: 0,
        noShow: 0,
        cancelledEarly: 0,
      },
      level: "unknown",
      levelLabel: "ยังไม่มีข้อมูล",
      fullName: "",
      name: "",
      phone: "",
      role: "",
      userId: "",
      principalId: "",
      staffId: "",
      updatedAt: null,
      location: {
        lat: null,
        lng: null,
        district: "",
        province: "",
        address: "",
        label: "",
      },
      areaText: "",
      distanceKm: null,
      distanceText: "",
      nearClinic: false,
    };
  }

  const location = pickLocation(doc.location);

  return {
    userId: isValidUserId(doc.userId) ? s(doc.userId) : "",
    principalId: s(doc.principalId),
    staffId: isValidStaffId(doc.staffId) ? s(doc.staffId) : "",
    fullName: s(doc.fullName),
    name: s(doc.name),
    phone: s(doc.phone),
    role: s(doc.role),

    trustScore: n(doc.trustScore, 80),
    flags: Array.isArray(doc.flags) ? doc.flags : [],
    badges: Array.isArray(doc.badges) ? doc.badges : [],
    stats: normalizeStats(doc),
    level: s(doc.level),
    levelLabel: s(doc.levelLabel),
    updatedAt: doc.updatedAt || null,

    location,
    areaText: buildAreaText(location),
    distanceKm: null,
    distanceText: "",
    nearClinic: false,
  };
}

function isBetterDoc(nextDoc, currentDoc) {
  if (!currentDoc) return true;
  if (!nextDoc) return false;

  const nextScore = n(nextDoc.trustScore, 0);
  const currentScore = n(currentDoc.trustScore, 0);

  if (nextScore !== currentScore) {
    return nextScore > currentScore;
  }

  const nextTime = new Date(nextDoc.updatedAt || 0).getTime();
  const currentTime = new Date(currentDoc.updatedAt || 0).getTime();

  return nextTime > currentTime;
}

function isBetterItem(nextItem, currentItem) {
  if (!currentItem) return true;
  if (!nextItem) return false;

  const nextScore = n(nextItem.trustScore, 0);
  const currentScore = n(currentItem.trustScore, 0);
  if (nextScore !== currentScore) return nextScore > currentScore;

  const nextShifts = n(nextItem?.stats?.totalShifts, 0);
  const currentShifts = n(currentItem?.stats?.totalShifts, 0);
  if (nextShifts !== currentShifts) return nextShifts > currentShifts;

  const nextCompleted = n(nextItem?.stats?.completed, 0);
  const currentCompleted = n(currentItem?.stats?.completed, 0);
  if (nextCompleted !== currentCompleted) return nextCompleted > currentCompleted;

  const nextTime = new Date(nextItem.updatedAt || 0).getTime();
  const currentTime = new Date(currentItem.updatedAt || 0).getTime();
  return nextTime > currentTime;
}

function makeIdentityKey(item) {
  const userId = s(item.userId);
  if (isValidUserId(userId)) return `u:${userId}`;

  const staffId = s(item.staffId);
  if (isValidStaffId(staffId)) return `s:${staffId}`;

  const phone = s(item.phone);
  if (phone) return `p:${phone}`;

  const fullName = s(item.fullName) || s(item.name);
  if (fullName) return `n:${fullName.toLowerCase()}`;

  return "";
}

function dedupeItems(items) {
  const map = new Map();

  for (const raw of Array.isArray(items) ? items : []) {
    const item = asObj(raw);
    const key = makeIdentityKey(item);

    if (!key) continue;

    const current = map.get(key);
    if (isBetterItem(item, current)) {
      map.set(key, item);
    }
  }

  return Array.from(map.values());
}

function pickRole(user = {}, scoreDoc = null) {
  const direct = s(user.role);
  if (direct) return direct;

  const activeRole = s(user.activeRole);
  if (activeRole) return activeRole;

  const roles = asArray(user.roles).map((x) => s(x)).filter(Boolean);
  if (roles.length > 0) return roles[0];

  const scoreRole = s(scoreDoc?.role);
  if (scoreRole) return scoreRole;

  return "helper";
}

function normalizeAuthUser(raw) {
  const u = asObj(raw);
  const profile = asObj(u.profile);
  const user = asObj(u.user);

  const rawUserId =
    s(u.userId) ||
    s(u.id) ||
    s(u._id) ||
    s(user.userId) ||
    s(user.id) ||
    s(user._id);

  const rawStaffId =
    s(u.staffId) ||
    s(profile.staffId) ||
    s(user.staffId);

  const fullName =
    s(u.fullName) ||
    s(u.name) ||
    s(profile.fullName) ||
    s(profile.name) ||
    s(user.fullName) ||
    s(user.name);

  const phone =
    s(u.phone) ||
    s(profile.phone) ||
    s(user.phone);

  const location = pickLocation(
    u.location ||
      profile.location ||
      user.location
  );

  return {
    ...u,
    userId: isValidUserId(rawUserId) ? rawUserId : "",
    staffId: isValidStaffId(rawStaffId) ? rawStaffId : "",
    fullName,
    name: s(u.name) || s(profile.name) || s(user.name) || fullName,
    phone,
    role: pickRole(u),
    activeRole: s(u.activeRole) || s(user.activeRole),
    roles: asArray(u.roles).length > 0 ? asArray(u.roles) : asArray(user.roles),
    location,
    areaText: buildAreaText(location),
  };
}

function mergeHelperWithScore(user, scoreDoc) {
  const normalizedUser = normalizeAuthUser(user);
  const scorePayload = toScorePayload(scoreDoc);

  const userId = normalizedUser.userId || scorePayload.userId;
  const staffId = normalizedUser.staffId || scorePayload.staffId;

  const fullName =
    s(normalizedUser.fullName) ||
    s(normalizedUser.name) ||
    s(scorePayload.fullName) ||
    s(scorePayload.name);

  const phone = s(normalizedUser.phone) || s(scorePayload.phone);
  const role = pickRole(normalizedUser, scoreDoc);

  const userLocation = pickLocation(normalizedUser.location);
  const scoreLocation = pickLocation(scorePayload.location);

  const location = {
    lat: userLocation.lat ?? scoreLocation.lat,
    lng: userLocation.lng ?? scoreLocation.lng,
    district: userLocation.district || scoreLocation.district,
    province: userLocation.province || scoreLocation.province,
    address: userLocation.address || scoreLocation.address,
    label: userLocation.label || scoreLocation.label,
  };

  return {
    ...normalizedUser,
    ...scorePayload,

    userId: isValidUserId(userId) ? userId : "",
    principalId:
      s(scorePayload.principalId) ||
      (isValidUserId(userId) ? userId : ""),
    staffId: isValidStaffId(staffId) ? staffId : "",
    fullName,
    name: s(normalizedUser.name) || s(scorePayload.name) || fullName,
    phone,
    role,
    location,
    areaText: buildAreaText(location),
  };
}

function buildScoreMaps(scoreDocs) {
  const byUserId = new Map();
  const byStaffId = new Map();

  for (const d of scoreDocs) {
    const userId = isValidUserId(d.userId) ? s(d.userId) : "";
    const staffId = isValidStaffId(d.staffId) ? s(d.staffId) : "";

    if (userId) {
      const current = byUserId.get(userId);
      if (isBetterDoc(d, current)) {
        byUserId.set(userId, d);
      }
    }

    if (staffId) {
      const current = byStaffId.get(staffId);
      if (isBetterDoc(d, current)) {
        byStaffId.set(staffId, d);
      }
    }
  }

  return { byUserId, byStaffId };
}

async function loadScoreDocsByIdentity(items) {
  const userIds = items.map((x) => s(x.userId)).filter(isValidUserId);
  const staffIds = items.map((x) => s(x.staffId)).filter(isValidStaffId);

  const or = [];
  if (userIds.length > 0) or.push({ userId: { $in: userIds } });
  if (staffIds.length > 0) or.push({ staffId: { $in: staffIds } });

  if (or.length === 0) return [];

  return TrustScore.find({ $or: or })
    .select(
      [
        "userId",
        "principalId",
        "staffId",
        "fullName",
        "name",
        "phone",
        "role",
        "trustScore",
        "totalShifts",
        "completed",
        "late",
        "noShow",
        "cancelledEarly",
        "cancelled",
        "flags",
        "badges",
        "level",
        "levelLabel",
        "updatedAt",
        "location",
      ].join(" ")
    )
    .lean();
}

async function searchUsersFallback(q, limit, clinicLat = null, clinicLng = null) {
  const db = mongoose.connection?.db;
  if (!db) return [];

  const query = s(q);
  if (!query) return [];

  const regex = new RegExp(escapeRegex(query), "i");

  const docs = await db
    .collection("users")
    .find({
      isActive: true,
      $and: [
        {
          $or: [
            { fullName: regex },
            { phone: regex },
            { userId: regex },
            { staffId: regex },
            { employeeCode: regex },
          ],
        },
        {
          $or: [
            { role: { $in: ["helper", "employee"] } },
            { activeRole: { $in: ["helper", "employee"] } },
            { roles: { $in: ["helper", "employee"] } },
          ],
        },
      ],
    })
    .project({
      userId: 1,
      staffId: 1,
      fullName: 1,
      phone: 1,
      role: 1,
      activeRole: 1,
      roles: 1,
      clinicId: 1,
      email: 1,
      location: 1,
    })
    .limit(limit)
    .toArray();

  const normalizedUsers = docs.map(normalizeAuthUser);
  const scoreDocs = await loadScoreDocsByIdentity(normalizedUsers);
  const { byUserId, byStaffId } = buildScoreMaps(scoreDocs);

  const merged = normalizedUsers.map((u) => {
    const userId = s(u.userId);
    const staffId = s(u.staffId);

    const scoreDoc =
      (userId ? byUserId.get(userId) : null) ||
      (staffId ? byStaffId.get(staffId) : null) ||
      null;

    const item = {
      ...mergeHelperWithScore(u, scoreDoc),
      source: "users_fallback",
    };

    const location = pickLocation(item.location);
    const distanceKm = haversineKm(clinicLat, clinicLng, location.lat, location.lng);

    return {
      ...item,
      distanceKm,
      distanceText: formatDistanceText(distanceKm),
      nearClinic: Number.isFinite(distanceKm) ? distanceKm <= 10 : false,
      areaText: buildAreaText(location),
    };
  });

  return dedupeItems(merged);
}

async function searchTrustScoreFallback(q, limit, clinicLat = null, clinicLng = null) {
  const query = s(q);
  if (!query) return [];

  const regex = new RegExp(escapeRegex(query), "i");

  const docs = await TrustScore.find({
    $or: [
      { fullName: regex },
      { name: regex },
      { phone: regex },
      { userId: regex },
      { staffId: regex },
    ],
  })
    .select(
      [
        "userId",
        "principalId",
        "staffId",
        "fullName",
        "name",
        "phone",
        "role",
        "trustScore",
        "totalShifts",
        "completed",
        "late",
        "noShow",
        "cancelledEarly",
        "cancelled",
        "flags",
        "badges",
        "level",
        "levelLabel",
        "updatedAt",
        "location",
      ].join(" ")
    )
    .sort({ trustScore: -1, updatedAt: -1 })
    .limit(limit)
    .lean();

  const dedup = new Map();

  for (const d of docs) {
    const userId = isValidUserId(d.userId) ? s(d.userId) : "";
    const staffId = isValidStaffId(d.staffId) ? s(d.staffId) : "";
    const principalId = s(d.principalId);
    const key = userId || staffId || principalId;

    if (!key) continue;

    const current = dedup.get(key);
    if (isBetterDoc(d, current)) {
      dedup.set(key, d);
    }
  }

  const items = Array.from(dedup.values()).map((d) => {
    const payload = toScorePayload(d);
    const location = pickLocation(payload.location);
    const distanceKm = haversineKm(clinicLat, clinicLng, location.lat, location.lng);

    return {
      userId: payload.userId,
      principalId: payload.principalId,
      staffId: payload.staffId,
      fullName: payload.fullName,
      name: payload.name || payload.fullName,
      phone: payload.phone,
      role: payload.role || "helper",
      trustScore: payload.trustScore,
      flags: payload.flags,
      badges: payload.badges,
      stats: payload.stats,
      level: payload.level,
      levelLabel: payload.levelLabel,
      updatedAt: payload.updatedAt,
      location,
      areaText: buildAreaText(location),
      distanceKm,
      distanceText: formatDistanceText(distanceKm),
      nearClinic: Number.isFinite(distanceKm) ? distanceKm <= 10 : false,
      source: "trustscore_fallback",
    };
  });

  return dedupeItems(items);
}

async function searchHelpers(req, res) {
  try {
    const q = s(req.query.q);
    const limitRaw = parseInt(req.query.limit || "20", 10);
    const limit = Math.min(
      Math.max(Number.isFinite(limitRaw) ? limitRaw : 20, 1),
      50
    );

    const clinicLat = n(req.query.clinicLat, NaN);
    const clinicLng = n(req.query.clinicLng, NaN);

    if (!q) {
      return res.json({
        ok: true,
        q,
        count: 0,
        source: "empty_query",
        items: [],
      });
    }

    const base = authBase();
    const key = internalKey();

    const headers = {
      "Content-Type": "application/json",
      ...(key ? { "X-Internal-Key": key } : {}),
      ...(req.headers.authorization
        ? { Authorization: req.headers.authorization }
        : {}),
    };

    const clinicQuery =
      Number.isFinite(clinicLat) && Number.isFinite(clinicLng)
        ? `&clinicLat=${encodeURIComponent(clinicLat)}&clinicLng=${encodeURIComponent(clinicLng)}`
        : "";

    const candidates = [
      `${base}/helpers/search?limit=${limit}&q=${encodeURIComponent(q)}${clinicQuery}`,
      `${base}/api/helpers/search?limit=${limit}&q=${encodeURIComponent(q)}${clinicQuery}`,
    ];

    let payload = null;
    let lastErr = null;

    for (const url of candidates) {
      const r = await fetchJson(url, headers);
      if (r.ok) {
        payload = r.data;
        break;
      }
      lastErr = r;
    }

    if (!payload) {
      const userFallbackItems = await searchUsersFallback(q, limit, clinicLat, clinicLng);
      if (userFallbackItems.length > 0) {
        return res.json({
          ok: true,
          q,
          count: userFallbackItems.length,
          source: "users_fallback_after_auth_error",
          fallbackReason: lastErr?.status || 500,
          items: userFallbackItems,
        });
      }

      const trustFallbackItems = await searchTrustScoreFallback(q, limit, clinicLat, clinicLng);
      if (trustFallbackItems.length > 0) {
        return res.json({
          ok: true,
          q,
          count: trustFallbackItems.length,
          source: "trustscore_fallback_after_auth_error",
          fallbackReason: lastErr?.status || 500,
          items: trustFallbackItems,
        });
      }

      return res.status(lastErr?.status || 500).json(
        lastErr?.data || {
          message: "helper search failed",
        }
      );
    }

    const rawItems = Array.isArray(payload.items) ? payload.items : [];
    const items = rawItems.map(normalizeAuthUser);

    const scoreDocs = await loadScoreDocsByIdentity(items);
    const { byUserId, byStaffId } = buildScoreMaps(scoreDocs);

    const results = dedupeItems(
      items.map((u) => {
        const userId = s(u.userId);
        const staffId = s(u.staffId);

        const scoreDoc =
          (userId ? byUserId.get(userId) : null) ||
          (staffId ? byStaffId.get(staffId) : null) ||
          null;

        const item = mergeHelperWithScore(u, scoreDoc);
        const location = pickLocation(item.location);
        const distanceKm = haversineKm(clinicLat, clinicLng, location.lat, location.lng);

        return {
          ...item,
          location,
          areaText: buildAreaText(location),
          distanceKm,
          distanceText: formatDistanceText(distanceKm),
          nearClinic: Number.isFinite(distanceKm) ? distanceKm <= 10 : false,
        };
      })
    );

    if (results.length === 0) {
      const userFallbackItems = await searchUsersFallback(q, limit, clinicLat, clinicLng);
      if (userFallbackItems.length > 0) {
        return res.json({
          ok: true,
          q,
          count: userFallbackItems.length,
          source: "users_fallback_after_empty_auth_result",
          items: userFallbackItems,
        });
      }

      const trustFallbackItems = await searchTrustScoreFallback(q, limit, clinicLat, clinicLng);
      if (trustFallbackItems.length > 0) {
        return res.json({
          ok: true,
          q,
          count: trustFallbackItems.length,
          source: "trustscore_fallback_after_empty_auth_result",
          items: trustFallbackItems,
        });
      }
    }

    return res.json({
      ok: true,
      q,
      count: results.length,
      source: "global_helper_search_with_trustscore",
      items: results,
    });
  } catch (e) {
    return res.status(500).json({
      message: "searchHelpers failed",
      error: e.message || String(e),
    });
  }
}

async function getHelperScoreByUserId(req, res) {
  try {
    const userId = s(req.params.userId);
    if (!userId) {
      return res.status(400).json({ message: "userId required" });
    }

    const docs = await TrustScore.find({ userId })
      .select(
        [
          "userId",
          "principalId",
          "staffId",
          "fullName",
          "name",
          "phone",
          "role",
          "trustScore",
          "totalShifts",
          "completed",
          "late",
          "noShow",
          "cancelledEarly",
          "cancelled",
          "flags",
          "badges",
          "level",
          "levelLabel",
          "updatedAt",
          "location",
        ].join(" ")
      )
      .lean();

    let bestDoc = null;
    for (const d of docs) {
      if (isBetterDoc(d, bestDoc)) {
        bestDoc = d;
      }
    }

    const payload = toScorePayload(bestDoc);
    const location = pickLocation(payload.location);

    return res.json({
      ok: true,
      userId,
      ...payload,
      location,
      areaText: buildAreaText(location),
    });
  } catch (e) {
    return res.status(500).json({
      message: "getHelperScoreByUserId failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  searchHelpers,
  getHelperScoreByUserId,
};