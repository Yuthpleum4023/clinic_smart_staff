const jwt = require("jsonwebtoken");
const { s, lower } = require("../utils/strings");

function canonicalRole(roleRaw) {
  const r = lower(roleRaw);

  if (
    r === "admin" ||
    r === "clinic" ||
    r === "clinic_admin" ||
    r === "clinicadmin" ||
    r === "owner"
  ) {
    return "admin";
  }

  if (r === "employee" || r === "staff" || r === "emp") {
    return "employee";
  }

  if (r === "helper") return "helper";

  return r;
}

function cleanQuoted(v) {
  const value = s(v);
  if (!value) return "";
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return s(value.slice(1, -1));
  }
  return value;
}

function extractToken(req) {
  const raw = cleanQuoted(req.headers.authorization || "");
  if (!raw) return "";

  const parts = raw.split(" ").filter(Boolean);
  if (parts.length >= 2 && lower(parts[0]) === "bearer") {
    return cleanQuoted(parts.slice(1).join(" "));
  }
  return raw;
}

function auth(req, res, next) {
  try {
    const token = extractToken(req);
    if (!token) {
      return res.status(401).json({
        ok: false,
        code: "MISSING_TOKEN",
        message: "Missing token",
      });
    }

    if (!process.env.JWT_SECRET) {
      return res.status(500).json({
        ok: false,
        code: "JWT_SECRET_NOT_CONFIGURED",
        message: "Authentication is not configured",
      });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET) || {};

    const activeRole = canonicalRole(decoded.activeRole || "");
    const roleFromToken = canonicalRole(decoded.role || "");
    const rolesArr = Array.isArray(decoded.roles)
      ? decoded.roles.map(canonicalRole).filter(Boolean)
      : [];

    const effectiveRole = activeRole || roleFromToken;
    const roleSet = new Set(rolesArr);
    if (effectiveRole) roleSet.add(effectiveRole);

    req.user = {
      ...decoded,
      userId: s(decoded.userId),
      clinicId: s(decoded.clinicId),
      staffId: s(decoded.staffId),
      role: effectiveRole,
      activeRole: effectiveRole,
      roles: Array.from(roleSet),
    };

    return next();
  } catch (_) {
    return res.status(401).json({
      ok: false,
      code: "INVALID_TOKEN",
      message: "Invalid token",
    });
  }
}

function requireRole(roles = []) {
  const allowed = (Array.isArray(roles) ? roles : [roles])
    .map(canonicalRole)
    .filter(Boolean);

  return (req, res, next) => {
    const effective = canonicalRole(req.user?.role);
    const allRoles = Array.isArray(req.user?.roles)
      ? req.user.roles.map(canonicalRole).filter(Boolean)
      : [];

    if (!effective && allRoles.length === 0) {
      return res.status(401).json({
        ok: false,
        code: "UNAUTHORIZED",
        message: "Unauthorized",
      });
    }

    if (
      (effective && allowed.includes(effective)) ||
      allRoles.some((r) => allowed.includes(r))
    ) {
      return next();
    }

    return res.status(403).json({
      ok: false,
      code: "FORBIDDEN",
      message: "Forbidden",
    });
  };
}

function requireClinic(req, res, next) {
  const clinicId = s(req.user?.clinicId);
  if (!clinicId) {
    return res.status(401).json({
      ok: false,
      code: "CLINIC_ID_REQUIRED",
      message: "Missing clinicId in token",
    });
  }
  req.inventoryClinicId = clinicId;
  return next();
}

module.exports = {
  auth,
  requireRole,
  requireClinic,
  canonicalRole,
};
