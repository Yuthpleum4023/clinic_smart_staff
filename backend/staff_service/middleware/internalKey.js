// middleware/internalKey.js

function s(v) {
  return String(v || "").trim();
}

function getInternalKey() {
  return s(
    process.env.STAFF_SERVICE_INTERNAL_KEY ||
    process.env.INTERNAL_SERVICE_KEY
  );
}

function requireInternalKey(req, res, next) {
  try {
    const incoming =
      s(req.headers["x-internal-key"]) ||
      s(req.headers["internal_service_key"]);

    const expected = getInternalKey();

    if (!expected) {
      return res.status(500).json({
        ok: false,
        message: "Internal key not configured",
      });
    }

    if (!incoming || incoming !== expected) {
      return res.status(403).json({
        ok: false,
        message: "Forbidden (invalid internal key)",
      });
    }

    return next();
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "Internal auth error",
    });
  }
}

module.exports = { requireInternalKey };