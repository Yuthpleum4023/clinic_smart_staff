const jwt = require("jsonwebtoken");

module.exports = function auth(req, res, next) {
  try {
    const h = req.headers.authorization || "";
    const token = h.startsWith("Bearer ") ? h.slice(7) : "";
    if (!token) return res.status(401).json({ message: "Missing token" });

    const secret = process.env.JWT_SECRET || "super_secret_change_me";
    const payload = jwt.verify(token, secret, {
      issuer: process.env.JWT_ISSUER || undefined,
    });

    req.user = payload;
    return next();
  } catch (e) {
    return res.status(401).json({
      message: "Invalid token",
      error: e.message || String(e),
    });
  }
};
