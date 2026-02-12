// backend/auth_user_service/middleware/auth.js
const { verifyToken } = require("../utils/jwt");

function extractToken(req) {
  const raw = String(req.headers.authorization || "").trim();
  if (!raw) return "";

  // รองรับ "Bearer <token>" แบบ case-insensitive และรองรับหลายช่องว่าง
  const parts = raw.split(" ").filter(Boolean);
  if (parts.length >= 2 && parts[0].toLowerCase() === "bearer") {
    return parts.slice(1).join(" ").trim();
  }

  // เผื่อ client ส่ง token ตรง ๆ (ไม่ใส่ Bearer)
  return raw;
}

function auth(req, res, next) {
  try {
    const token = extractToken(req);

    if (!token) {
      return res.status(401).json({ message: "Missing token" });
    }

    const decoded = verifyToken(token);
    // decoded ควรเป็น { userId, clinicId, role, staffId?, ... }
    req.user = decoded;

    return next();
  } catch (e) {
    // ✅ debug แบบสั้น อ่านง่าย (ไม่ log token)
    console.log("❌ auth_user_service auth failed:", e?.name || "", e?.message || e);
    return res.status(401).json({ message: "Invalid token" });
  }
}

function requireRole(roles = []) {
  return (req, res, next) => {
    if (!req.user?.role) {
      return res.status(401).json({ message: "Unauthorized" });
    }
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ message: "Forbidden" });
    }
    return next();
  };
}

module.exports = { auth, requireRole };
