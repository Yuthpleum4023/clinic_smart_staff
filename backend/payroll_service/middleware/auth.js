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

function pickFirstNonEmpty(...vals) {
  for (const v of vals) {
    const s = normStr(v);
    if (s) return s;
  }
  return "";
}

/**
 * ✅ Canonical roles (ตรงกับ controller ทั้งระบบ)
 * - admin    : คลินิก admin/owner/manager ฯลฯ
 * - employee : ลูกจ้างประจำคลินิกทุกตำแหน่ง
 * - helper   : ผู้ช่วย part-time ที่วิ่งรับงาน (marketplace)
 */
function canonicalRole(roleRaw) {
  const r = normLower(roleRaw);

  // admin aliases
  if (
    r === "admin" ||
    r === "clinic" ||
    r === "clinic_admin" ||
    r === "clinicadmin" ||
    r === "owner" ||
    r === "manager"
  ) {
    return "admin";
  }

  // employee/staff aliases
  if (r === "employee" || r === "staff" || r === "emp") {
    return "employee";
  }

  // helper aliases
  if (
    r === "helper" ||
    r === "assistant" ||
    r === "dental_assistant" ||
    r === "dental assistant"
  ) {
    return "helper";
  }

  return r;
}

function canonicalRolesList(v) {
  if (Array.isArray(v)) {
    return v
      .map((x) => canonicalRole(x))
      .map((x) => normStr(x))
      .filter(Boolean);
  }
  const one = canonicalRole(v);
  return one ? [one] : [];
}

function extractToken(req) {
  const raw = normStr(req.headers.authorization);
  if (!raw) return "";

  let cleaned = raw;

  if (
    (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
    (cleaned.startsWith("'") && cleaned.endsWith("'"))
  ) {
    cleaned = normStr(cleaned.slice(1, -1));
  }

  const parts = cleaned.split(" ").filter(Boolean);

  if (parts.length >= 2 && parts[0].toLowerCase() === "bearer") {
    return normStr(parts.slice(1).join(" "));
  }

  return cleaned;
}

function extractClinicIdFromPayload(payload) {
  let clinicId = pickFirstNonEmpty(
    payload.clinicId,
    payload.clinic_id,
    payload.cid
  );
  if (clinicId) return clinicId;

  const clinic = payload.clinic;
  if (typeof clinic === "string") {
    clinicId = normStr(clinic);
    if (clinicId) return clinicId;
  }
  if (clinic && typeof clinic === "object") {
    clinicId = pickFirstNonEmpty(clinic.clinicId, clinic.id, clinic._id);
    if (clinicId) return clinicId;
  }

  const clinics = payload.clinics;
  if (Array.isArray(clinics) && clinics.length > 0) {
    const first = clinics[0];
    if (typeof first === "string") {
      clinicId = normStr(first);
      if (clinicId) return clinicId;
    }
    if (first && typeof first === "object") {
      clinicId = pickFirstNonEmpty(first.clinicId, first.id, first._id);
      if (clinicId) return clinicId;
    }
  }

  return "";
}

/**
 * ✅ AUTH middleware
 * - verify JWT
 * - normalize user ctx
 * - IMPORTANT: helper อาจไม่มี staffId / clinicId
 *   แต่จะไม่โดน block ที่นี่
 */
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
      console.log("🔐 Token Dots:", (String(token).match(/\./g) || []).length);
    }

    if (!token) {
      if (AUTH_LOG) console.log("❌ Missing token");
      return res.status(401).json({ message: "Missing token" });
    }

    const dotCount = (String(token).match(/\./g) || []).length;
    if (dotCount < 2) {
      if (AUTH_LOG) console.log("❌ JWT malformed (structure)");
      return res.status(401).json({ message: "Invalid token (malformed)" });
    }

    const payload = jwt.verify(token, process.env.JWT_SECRET);

    if (AUTH_LOG) {
      console.log("✅ JWT OK payload:", payload);
    }

    const staffId = pickFirstNonEmpty(
      payload.staffId,
      payload.employeeId,
      payload.empId,
      payload.staff_id,
      payload.employee_id
    );

    const userId = pickFirstNonEmpty(
      payload.userId,
      payload.user_id,
      payload.uid,
      payload.id,
      payload._id
    );

    const clinicId = extractClinicIdFromPayload(payload);

    const activeRoleRaw = pickFirstNonEmpty(
      payload.activeRole,
      payload.active_role
    );
    const roleRaw = pickFirstNonEmpty(payload.role, payload.userRole);

    const activeRole = canonicalRole(activeRoleRaw);
    const roleCanonical = canonicalRole(roleRaw);

    const rolesAllSet = new Set([
      ...canonicalRolesList(payload.roles),
      ...(roleCanonical ? [roleCanonical] : []),
      ...(activeRole ? [activeRole] : []),
    ]);

    const roles = Array.from(rolesAllSet).filter(Boolean);

    const effectiveRole = activeRole || roleCanonical || roles[0] || "";
    const principalId = staffId || userId;
    const principalType = staffId ? "staff" : "user";

    req.user = {
      userId,
      clinicId,

      role: effectiveRole,
      roles,
      activeRole: activeRole || "",

      staffId,
      staffIdMissing: !normStr(staffId),
      clinicIdMissing: !normStr(clinicId),

      principalId,
      principalType,

      fullName: normStr(payload.fullName || payload.name),
      phone: normStr(payload.phone),
      email: normStr(payload.email),

      id: normStr(payload.id),
      _id: normStr(payload._id),
    };

    if (AUTH_LOG) console.log("✅ req.user:", req.user);

    return next();
  } catch (err) {
    if (AUTH_LOG) console.log("❌ JWT ERROR:", err.name, err.message);
    return res
      .status(401)
      .json({ message: "Invalid token", error: err.message });
  }
}

/**
 * ✅ Role guard (canonical + รองรับ roles array)
 */
function requireRole(roles = []) {
  const allowed = (Array.isArray(roles) ? roles : [roles])
    .map((r) => canonicalRole(r))
    .filter(Boolean);

  return (req, res, next) => {
    const effective = canonicalRole(req.user?.role);
    const roleList = Array.isArray(req.user?.roles)
      ? req.user.roles.map(canonicalRole)
      : [];
    const have = new Set([effective, ...roleList].filter(Boolean));

    if (have.size === 0) {
      return res.status(401).json({ message: "Unauthorized" });
    }

    const ok = allowed.some((r) => have.has(r));
    if (!ok) {
      return res.status(403).json({
        message: "Forbidden",
        role: effective,
        roles: Array.from(have),
        allowed,
      });
    }
    return next();
  };
}

/**
 * ✅ Require staffId (ใช้เฉพาะ endpoint ที่ต้อง staffId จริง ๆ)
 */
function requireStaffId() {
  return (req, res, next) => {
    const staffId = normStr(req.user?.staffId);
    if (staffId) return next();
    return res.status(403).json({ message: "staffId missing in token" });
  };
}

/**
 * ✅ Ensure staff self-access (เดิม)
 * NOTE: helper ไม่ควรใช้ middleware นี้
 */
function requireSelfStaff({ allowClinic = true } = {}) {
  return (req, res, next) => {
    const role = canonicalRole(req.user?.role);
    if (!role) return res.status(401).json({ message: "Unauthorized" });

    if (allowClinic && role === "admin") return next();

    if (!allowClinic && role !== "employee") {
      return res.status(403).json({ message: "Forbidden" });
    }

    const tokenStaffId = normStr(req.user?.staffId);
    const tokenClinicId = normStr(req.user?.clinicId);

    if (!tokenStaffId) {
      return res.status(403).json({ message: "Forbidden (missing staffId)" });
    }

    const reqStaffId =
      normStr(req.params?.staffId) ||
      normStr(req.params?.employeeId) ||
      normStr(req.body?.staffId) ||
      normStr(req.body?.employeeId) ||
      normStr(req.query?.staffId) ||
      normStr(req.query?.employeeId);

    if (reqStaffId && reqStaffId !== tokenStaffId) {
      return res.status(403).json({ message: "Forbidden (staff mismatch)" });
    }

    if (!req.body) req.body = {};
    if (!normStr(req.body.staffId) && !normStr(req.body.employeeId)) {
      req.body.staffId = tokenStaffId;
    }

    const reqClinicId =
      normStr(req.body?.clinicId) ||
      normStr(req.body?.clinic_id) ||
      normStr(req.query?.clinicId) ||
      normStr(req.query?.clinic_id);

    if (reqClinicId && tokenClinicId && reqClinicId !== tokenClinicId) {
      return res.status(403).json({ message: "Forbidden (clinic mismatch)" });
    }

    if (!normStr(req.body.clinicId) && tokenClinicId) {
      req.body.clinicId = tokenClinicId;
    }

    return next();
  };
}

/**
 * ✅ NEW: Self-attendance guard (รองรับ employee + helper)
 * - กัน spoof clinicId/staffId/userId
 * - employee: ยังบังคับ clinicId ใน token
 * - helper: ไม่บังคับ clinicId ใน token (resolve จาก shiftId ใน controller)
 * - เติม staffId ให้ถ้ามี
 * - ไม่บังคับ staffId
 */
function requireSelfAttendance() {
  return (req, res, next) => {
    const role = canonicalRole(req.user?.role);
    if (!role) return res.status(401).json({ message: "Unauthorized" });

    if (role !== "employee" && role !== "helper") {
      return res.status(403).json({ message: "Forbidden" });
    }

    const tokenClinicId = normStr(req.user?.clinicId);
    const tokenStaffId = normStr(req.user?.staffId);
    const tokenUserId = normStr(req.user?.userId);

    if (!req.body) req.body = {};

    // =====================================================
    // ✅ HELPER FLOW
    // - helper อาจไม่มี clinicId ใน token ได้
    // - ห้าม user spoof clinicId/userId/staffId
    // - ถ้ามี staffId ใน token ค่อย enforce
    // - clinic จะไป resolve ใน controller จาก shiftId
    // =====================================================
    if (role === "helper") {
      const reqClinicId =
        normStr(req.body?.clinicId) ||
        normStr(req.body?.clinic_id) ||
        normStr(req.query?.clinicId) ||
        normStr(req.query?.clinic_id);

      if (reqClinicId && tokenClinicId && reqClinicId !== tokenClinicId) {
        return res.status(403).json({ message: "Forbidden (clinic mismatch)" });
      }

      const reqStaffId =
        normStr(req.params?.staffId) ||
        normStr(req.params?.employeeId) ||
        normStr(req.body?.staffId) ||
        normStr(req.body?.employeeId) ||
        normStr(req.query?.staffId) ||
        normStr(req.query?.employeeId);

      if (reqStaffId && tokenStaffId && reqStaffId !== tokenStaffId) {
        return res.status(403).json({ message: "Forbidden (staff mismatch)" });
      }

      if (!reqStaffId && tokenStaffId) {
        req.body.staffId = tokenStaffId;
      }

      const reqUserId =
        normStr(req.body?.userId) ||
        normStr(req.body?.user_id) ||
        normStr(req.query?.userId) ||
        normStr(req.query?.user_id);

      if (reqUserId && tokenUserId && reqUserId !== tokenUserId) {
        return res.status(403).json({ message: "Forbidden (user mismatch)" });
      }

      return next();
    }

    // =====================================================
    // ✅ EMPLOYEE FLOW
    // - employee ยังต้องมี clinicId ใน token
    // - guard เดิมคงไว้
    // =====================================================
    if (!tokenClinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    const reqClinicId =
      normStr(req.body?.clinicId) ||
      normStr(req.body?.clinic_id) ||
      normStr(req.query?.clinicId) ||
      normStr(req.query?.clinic_id);

    if (reqClinicId && reqClinicId !== tokenClinicId) {
      return res.status(403).json({ message: "Forbidden (clinic mismatch)" });
    }

    if (!normStr(req.body.clinicId)) {
      req.body.clinicId = tokenClinicId;
    }

    const reqStaffId =
      normStr(req.params?.staffId) ||
      normStr(req.params?.employeeId) ||
      normStr(req.body?.staffId) ||
      normStr(req.body?.employeeId) ||
      normStr(req.query?.staffId) ||
      normStr(req.query?.employeeId);

    if (reqStaffId && tokenStaffId && reqStaffId !== tokenStaffId) {
      return res.status(403).json({ message: "Forbidden (staff mismatch)" });
    }

    if (!reqStaffId && tokenStaffId) {
      req.body.staffId = tokenStaffId;
    }

    const reqUserId =
      normStr(req.body?.userId) ||
      normStr(req.body?.user_id) ||
      normStr(req.query?.userId) ||
      normStr(req.query?.user_id);

    if (reqUserId && tokenUserId && reqUserId !== tokenUserId) {
      return res.status(403).json({ message: "Forbidden (user mismatch)" });
    }

    return next();
  };
}

module.exports = {
  auth,
  requireRole,
  requireStaffId,
  requireSelfStaff,
  requireSelfAttendance,
};