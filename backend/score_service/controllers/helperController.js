const TrustScore = require("../models/TrustScore");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
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

function toScorePayload(doc) {
  if (!doc) {
    return {
      trustScore: null,
      flags: [],
      badges: [],
      stats: null,
      level: "",
      levelLabel: "",
      fullName: "",
      name: "",
      phone: "",
      role: "",
      userId: "",
      principalId: "",
      staffId: "",
    };
  }

  return {
    userId: s(doc.userId),
    principalId: s(doc.principalId),
    staffId: s(doc.staffId),
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

function mergeHelperWithScore(user, scoreDoc) {
  const userId = s(user.userId || scoreDoc?.userId);
  const staffId = s(user.staffId || scoreDoc?.staffId);

  const fullName =
    s(user.fullName) || s(user.name) || s(scoreDoc?.fullName) || s(scoreDoc?.name);

  const phone = s(user.phone) || s(scoreDoc?.phone);
  const role = s(user.role) || s(scoreDoc?.role) || "helper";

  return {
    ...user,
    userId,
    staffId,
    fullName,
    name: s(user.name) || s(scoreDoc?.name),
    phone,
    role,
    ...toScorePayload(scoreDoc),
    fullName,
    phone,
    role,
  };
}

async function searchHelpers(req, res) {
  try {
    const q = s(req.query.q);
    const limitRaw = parseInt(req.query.limit || "20", 10);
    const limit = Math.min(
      Math.max(Number.isFinite(limitRaw) ? limitRaw : 20, 1),
      50
    );

    const base = authBase();
    const key = internalKey();

    const headers = {
      "Content-Type": "application/json",
      ...(key ? { "X-Internal-Key": key } : {}),
      ...(req.headers.authorization
        ? { Authorization: req.headers.authorization }
        : {}),
    };

    const candidates = [
      `${base}/helpers/search?limit=${limit}&q=${encodeURIComponent(q)}`,
      `${base}/api/helpers/search?limit=${limit}&q=${encodeURIComponent(q)}`,
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
      return res.status(lastErr?.status || 500).json(
        lastErr?.data || {
          message: "helper search failed",
        }
      );
    }

    const items = Array.isArray(payload.items) ? payload.items : [];

    const userIds = items.map((x) => s(x.userId)).filter(Boolean);
    const staffIds = items.map((x) => s(x.staffId)).filter(Boolean);

    const or = [];
    if (userIds.length > 0) or.push({ userId: { $in: userIds } });
    if (staffIds.length > 0) or.push({ staffId: { $in: staffIds } });

    const scoreDocs =
      or.length > 0
        ? await TrustScore.find({ $or: or })
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
              ].join(" ")
            )
            .lean()
        : [];

    const byUserId = new Map();
    const byStaffId = new Map();

    for (const d of scoreDocs) {
      const userId = s(d.userId);
      const staffId = s(d.staffId);

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

    const results = items.map((u) => {
      const userId = s(u.userId);
      const staffId = s(u.staffId);

      const scoreDoc =
        (userId ? byUserId.get(userId) : null) ||
        (staffId ? byStaffId.get(staffId) : null) ||
        null;

      return mergeHelperWithScore(u, scoreDoc);
    });

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
        ].join(" ")
      )
      .lean();

    let bestDoc = null;
    for (const d of docs) {
      if (isBetterDoc(d, bestDoc)) {
        bestDoc = d;
      }
    }

    if (!bestDoc) {
      return res.json({
        ok: true,
        userId,
        fullName: "",
        name: "",
        phone: "",
        role: "helper",
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
      });
    }

    return res.json({
      ok: true,
      userId,
      ...toScorePayload(bestDoc),
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