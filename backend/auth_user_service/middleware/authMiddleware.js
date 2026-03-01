// backend/auth_user_service/middleware/authMiddleware.js
const { verifyToken } = require("../utils/jwt");

// ---------------- helpers ----------------
function normStr(v) {
  return String(v || "").trim();
}

function normLower(v) {
  return normStr(v).toLowerCase();
}

/**
 * Map role aliases -> canonical role (ตาม auth_user_service)
 * - admin/clinic aliases -> admin
 * - employee/staff/emp -> employee
 * - helper -> helper
 */
function canonicalRole(roleRaw) {
  const r = normLower(roleRaw);

  // admin/clinic aliases
  if (
    r === "admin" ||
    r === "clinic" ||
    r === "clinic_admin" ||
    r === "clinicadmin" ||
    r === "owner"
  ) {
    return "admin";
  }

  // employee/staff aliases
  if (r === "employee" || r === "staff" || r === "emp") {
    return "employee";
  }

  // helper
  if (r === "helper") {
    return "helper";
  }

  return r;
}

function cleanQuoted(s) {
  const v = normStr(s);
  if (!v) return "";
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    return normStr(v.slice(1, -1));
  }
  return v;
}

function extractToken(req) {
  const raw = cleanQuoted(req.headers.authorization || "");
  if (!raw) return "";

  // Bearer <token> (case-insensitive) + รองรับหลายช่องว่าง
  const parts = raw.split(" ").filter(Boolean);
  if (parts.length >= 2 && parts[0].toLowerCase() === "bearer") {
    return cleanQuoted(parts.slice(1).join(" "));
  }

  // เผื่อส่ง token ตรง ๆ
  return raw;
}

// ---------------- middleware ----------------
function auth(req, res, next) {
  try {
    const token = extractToken(req);
    if (!token) return res.status(401).json({ message: "Missing token" });

    const decoded = verifyToken(token) || {};
    // decoded ควรเป็น { userId, clinicId, role, staffId?, roles?, activeRole?, ... }

    // ✅ Multi-role normalize
    const activeRole = canonicalRole(decoded.activeRole || "");
    const roleFromToken = canonicalRole(decoded.role || "");

    const rolesArr = Array.isArray(decoded.roles)
      ? decoded.roles.map(canonicalRole).filter(Boolean)
      : [];

    // ✅ effectiveRole priority: activeRole > role
    const effectiveRole = activeRole || roleFromToken;

    // ✅ ensure effectiveRole อยู่ใน roles[]
    const roleSet = new Set(rolesArr);
    if (effectiveRole) roleSet.add(effectiveRole);

    req.user = {
      ...decoded,

      // normalize key fields
      userId: normStr(decoded.userId),
      clinicId: normStr(decoded.clinicId),
      staffId: normStr(decoded.staffId),

      // canonical + multi-role
      role: effectiveRole, // downstream ใช้ field เดิมนี้
      activeRole: effectiveRole,
      roles: Array.from(roleSet),
    };

    return next();
  } catch (e) {
    console.log(
      "❌ auth_user_service auth failed:",
      e?.name || "",
      e?.message || e
    );
    return res.status(401).json({ message: "Invalid token" });
  }
}

/**
 * ✅ Role guard (รองรับ multi-role)
 * - ผ่านถ้า role ที่ active อยู่ตรง allowed
 * - หรือ roles[] มี role ที่ allowed
 */
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
      return res.status(401).json({ message: "Unauthorized" });
    }

    if (effective && allowed.includes(effective)) return next();
    if (allRoles.some((r) => allowed.includes(r))) return next();

    return res.status(403).json({
      message: "Forbidden",
      role: effective || "",
      roles: allRoles,
      allowed,
    });
  };
}

// alias (optional)
const requireAnyRole = requireRole;

module.exports = { auth, requireRole, requireAnyRole };