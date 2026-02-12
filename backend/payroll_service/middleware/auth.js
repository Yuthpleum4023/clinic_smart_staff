const jwt = require("jsonwebtoken");

function extractToken(req) {
  const raw = String(req.headers.authorization || "").trim();
  if (!raw) return "";

  // ตัด quote ครอบทั้งก้อน เช่น "aaa.bbb.ccc"
  let cleaned = raw;
  if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
    cleaned = cleaned.slice(1, -1).trim();
  }

  const parts = cleaned.split(" ").filter(Boolean);

  // รองรับ Bearer case-insensitive
  if (parts.length >= 2 && parts[0].toLowerCase() === "bearer") {
    return parts.slice(1).join(" ").trim();
  }

  // เผื่อ client ส่ง token ตรง ๆ
  return cleaned;
}

function auth(req, res, next) {
  try {
    const token = extractToken(req);

    console.log("======================================");
    console.log("🔐 AUTH CHECK");
    console.log("🔐 Authorization:", req.headers.authorization ? "YES" : "NO");
    console.log("🔐 Token Preview:", String(token).slice(0, 30));
    console.log("🔐 Token Dots:", (String(token).match(/\./g) || []).length);

    if (!token) {
      console.log("❌ Missing token");
      return res.status(401).json({ message: "Missing token" });
    }

    // JWT ต้องมี dot อย่างน้อย 2 จุด
    const dotCount = (String(token).match(/\./g) || []).length;
    if (dotCount < 2) {
      console.log("❌ JWT malformed (structure)");
      return res.status(401).json({ message: "Invalid token (malformed)" });
    }

    const payload = jwt.verify(token, process.env.JWT_SECRET);

    console.log("✅ JWT OK:", payload);

    req.user = payload;
    next();
  } catch (err) {
    console.log("❌ JWT ERROR:", err.name, err.message);

    return res.status(401).json({
      message: "Invalid token",
      error: err.message,
    });
  }
}

module.exports = auth;
