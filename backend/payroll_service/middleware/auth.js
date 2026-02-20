const jwt = require("jsonwebtoken");

const AUTH_LOG =
  String(process.env.AUTH_LOG || "false").toLowerCase() === "true";

function normStr(v) {
  return String(v || "").trim();
}

function extractToken(req) {
  const raw = normStr(req.headers.authorization);
  if (!raw) return "";

  // ตัด quote ครอบทั้งก้อน เช่น "aaa.bbb.ccc"
  let cleaned = raw;

  if (
    (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
    (cleaned.startsWith("'") && cleaned.endsWith("'"))
  ) {
    cleaned = normStr(cleaned.slice(1, -1));
  }

  const parts = cleaned.split(" ").filter(Boolean);

  // รองรับ Bearer case-insensitive
  if (parts.length >= 2 && parts[0].toLowerCase() === "bearer") {
    return normStr(parts.slice(1).join(" "));
  }

  // เผื่อ client ส่ง token ตรง ๆ
  return cleaned;
}

function auth(req, res, next) {
  try {
    const token = extractToken(req);

    if (AUTH_LOG) {
      console.log("======================================");
      console.log("🔐 AUTH CHECK");
      console.log(
        "🔐 Authorization:",
        req.headers.authorization ? "YES" : "NO"
      );
      console.log("🔐 Token Preview:", String(token).slice(0, 30));
      console.log(
        "🔐 Token Dots:",
        (String(token).match(/\./g) || []).length
      );
    }

    if (!token) {
      if (AUTH_LOG) console.log("❌ Missing token");
      return res.status(401).json({ message: "Missing token" });
    }

    // JWT ต้องมี dot อย่างน้อย 2 จุด
    const dotCount = (String(token).match(/\./g) || []).length;
    if (dotCount < 2) {
      if (AUTH_LOG) console.log("❌ JWT malformed (structure)");
      return res.status(401).json({
        message: "Invalid token (malformed)",
      });
    }

    const payload = jwt.verify(token, process.env.JWT_SECRET);

    if (AUTH_LOG) {
      console.log("✅ JWT OK:", payload);
    }

    // ✅ SAFE NORMALIZATION (แก้ ghost bug ว่าง)
    req.user = {
      userId: normStr(payload.userId),
      clinicId: normStr(payload.clinicId),
      role: normStr(payload.role),
      staffId: normStr(payload.staffId),

      // ✅ FIX สำคัญที่สุด
      fullName: normStr(payload.fullName),
      phone: normStr(payload.phone),
      email: normStr(payload.email),

      id: normStr(payload.id),
    };

    next();
  } catch (err) {
    if (AUTH_LOG)
      console.log("❌ JWT ERROR:", err.name, err.message);

    return res.status(401).json({
      message: "Invalid token",
      error: err.message,
    });
  }
}

module.exports = auth;