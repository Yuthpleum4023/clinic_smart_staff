// middleware/authMiddleware.js
//
// ✅ FULL FILE — JWT Bearer + X-Internal-Key (Internal calls)
// - ถ้ามี X-Internal-Key และตรงกับ process.env.INTERNAL_KEY -> ผ่านเลย
//   -> req.internal = true
//   -> req.user = { role: 'system', internal: true }
// - ถ้าไม่ใช่ internal -> บังคับ JWT Bearer ตามเดิม
//
// ต้องตั้ง ENV บน Render:
// - INTERNAL_KEY=super_long_random_key_64chars_or_more
// - JWT_SECRET=... (ของเดิม)
//
// หมายเหตุ: ยังคง issuer check ตามของเดิมไว้

const jwt = require("jsonwebtoken");

function getBearerToken(req) {
  const h = req.headers.authorization || req.headers.Authorization || "";
  const s = String(h || "");
  return s.startsWith("Bearer ") ? s.slice(7).trim() : "";
}

module.exports = function auth(req, res, next) {
  try {
    // =========================
    // ✅ INTERNAL KEY PATH
    // =========================
    const internalKey =
      req.headers["x-internal-key"] ||
      req.headers["X-Internal-Key"] ||
      req.headers["x_internal_key"] ||
      req.headers["x-internal_key"];

    const expected = (process.env.INTERNAL_KEY || "").trim();

    if (expected && internalKey && String(internalKey).trim() === expected) {
      req.internal = true;
      req.user = { role: "system", internal: true };
      return next();
    }

    // =========================
    // ✅ JWT PATH (ของเดิม)
    // =========================
    const token = getBearerToken(req);
    if (!token) return res.status(401).json({ message: "Missing token" });

    const secret = process.env.JWT_SECRET || "super_secret_change_me";

    const payload = jwt.verify(token, secret, {
      issuer: process.env.JWT_ISSUER || undefined,
    });

    req.internal = false;
    req.user = payload;
    return next();
  } catch (e) {
    return res.status(401).json({
      message: "Invalid token",
      error: e.message || String(e),
    });
  }
};