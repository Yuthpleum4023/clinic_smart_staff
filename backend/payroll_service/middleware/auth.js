// backend/payroll_service/middleware/auth.js
const jwt = require("jsonwebtoken");

const AUTH_LOG =
  String(process.env.AUTH_LOG || "false").toLowerCase() === "true";

function normStr(v) {
  return String(v || "").trim();
}

function normLower(v) {
  return normStr(v).toLowerCase();
}

/**
 * Map role aliases -> canonical role
 * - clinic group: admin/clinic/clinic_admin
 * - employee group: employee/staff/emp
 * - helper group: helper
 */
function canonicalRole(roleRaw) {
  const r = normLower(roleRaw);

  // clinic/admin aliases
  if (
    r === "admin" ||
    r === "clinic" ||
    r === "clinic_admin" ||
    r === "clinicadmin" ||
    r === "owner"
  ) {
    return "clinic";
  }

  // employee/staff aliases
  if (r === "employee" || r === "staff" || r === "emp") {
    return "employee";
  }

  // helper
  if (r === "helper") {
    return "helper";
  }

  // unknown -> keep normalized (so requireRole can still match if caller passes exact)
  return r;
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
      console.log("✅ JWT OK payload:", payload);
    }

    // ✅ staffId fallback (กัน payload คนละชื่อ field)
    const staffId =
      normStr(payload.staffId) ||
      normStr(payload.employeeId) ||
      normStr(payload.empId) ||
      normStr(payload.staff_id) ||
      normStr(payload.employee_id) ||
      normStr(payload.id);

    // ✅ clinicId fallback
    const clinicId =
      normStr(payload.clinicId) ||
      normStr(payload.clinic_id) ||
      normStr(payload.cid);

    // ✅ userId fallback
    const userId =
      normStr(payload.userId) ||
      normStr(payload.user_id) ||
      normStr(payload.uid);

    const roleCanonical = canonicalRole(payload.role);

    // ✅ SAFE NORMALIZATION (แก้ ghost bug ว่าง)
    req.user = {
      userId,
      clinicId,
      role: roleCanonical,
      staffId,

      // meta
      fullName: normStr(payload.fullName),
      phone: normStr(payload.phone),
      email: normStr(payload.email),

      // keep original id too
      id: normStr(payload.id),
    };

    if (AUTH_LOG) {
      console.log("✅ req.user:", req.user);
    }

    return next();
  } catch (err) {
    if (AUTH_LOG) console.log("❌ JWT ERROR:", err.name, err.message);

    return res.status(401).json({
      message: "Invalid token",
      error: err.message,
    });
  }
}

/**
 * ✅ Role guard (case-insensitive + canonical)
 * Usage:
 *   requireRole(['clinic'])        // clinic/admin
 *   requireRole(['employee'])      // employee/staff
 *   requireRole(['clinic','employee'])
 */
function requireRole(roles = []) {
  const allowed = (Array.isArray(roles) ? roles : [roles])
    .map((r) => canonicalRole(r))
    .filter(Boolean);

  return (req, res, next) => {
    const role = canonicalRole(req.user?.role);
    if (!role) return res.status(401).json({ message: "Unauthorized" });

    if (!allowed.includes(role)) {
      return res.status(403).json({
        message: "Forbidden",
        role,
        allowed,
      });
    }
    return next();
  };
}

/**
 * ✅ Ensure staff self-access (employee can only act on their own staffId)
 * - employee role: staffId in req (param/body) must match req.user.staffId
 * - clinic role: allow
 *
 * You can use this in attendance routes.
 */
function requireSelfStaff({ allowClinic = true } = {}) {
  return (req, res, next) => {
    const role = canonicalRole(req.user?.role);
    if (!role) return res.status(401).json({ message: "Unauthorized" });

    if (allowClinic && role === "clinic") return next();

    // for employee/helper: enforce staffId match (if route uses staffId)
    const tokenStaffId = normStr(req.user?.staffId);

    // try read staffId from: params, body, query
    const reqStaffId =
      normStr(req.params?.staffId) ||
      normStr(req.params?.employeeId) ||
      normStr(req.body?.staffId) ||
      normStr(req.body?.employeeId) ||
      normStr(req.query?.staffId) ||
      normStr(req.query?.employeeId);

    if (!tokenStaffId) {
      return res.status(403).json({ message: "Forbidden (missing staffId)" });
    }

    if (reqStaffId && reqStaffId !== tokenStaffId) {
      return res.status(403).json({
        message: "Forbidden (staff mismatch)",
      });
    }

    return next();
  };
}

module.exports = { auth, requireRole, requireSelfStaff };