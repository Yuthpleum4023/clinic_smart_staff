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

  return r; // unknown -> keep
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

  // ตัด quote ครอบทั้งก้อน เช่น "aaa.bbb.ccc"
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

function extractClinicIdFromPayload(payload) {
  // 1) direct fields
  let clinicId = pickFirstNonEmpty(
    payload.clinicId,
    payload.clinic_id,
    payload.cid
  );
  if (clinicId) return clinicId;

  // 2) payload.clinic (string/object)
  const clinic = payload.clinic;
  if (typeof clinic === "string") {
    clinicId = normStr(clinic);
    if (clinicId) return clinicId;
  }
  if (clinic && typeof clinic === "object") {
    clinicId = pickFirstNonEmpty(clinic.clinicId, clinic.id, clinic._id);
    if (clinicId) return clinicId;
  }

  // 3) payload.clinics (array)
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
 * - IMPORTANT: helper อาจไม่มี staffId => "ไม่ทำให้เป็น 403 ที่นี่"
 *   แต่จะติด flag req.user.staffIdMissing = true
 */
function auth(req, res, next) {
  try {
    const token = extractToken(req);

    if (AUTH_LOG) {
      console.log("======================================");
      console.log("🔐 AUTH CHECK");
      console.log("🔐 Authorization:", req.headers.authorization ? "YES" : "NO");
      console.log("🔐 Token Preview:", String(token).slice(0, 30));
      console.log("🔐 Token Dots:", (String(token).match(/\./g) || []).length);
    }

    if (!token) {
      if (AUTH_LOG) console.log("❌ Missing token");
      return res.status(401).json({ message: "Missing token" });
    }

    // JWT ต้องมี dot อย่างน้อย 2 จุด
    const dotCount = (String(token).match(/\./g) || []).length;
    if (dotCount < 2) {
      if (AUTH_LOG) console.log("❌ JWT malformed (structure)");
      return res.status(401).json({ message: "Invalid token (malformed)" });
    }

    const payload = jwt.verify(token, process.env.JWT_SECRET);

    if (AUTH_LOG) {
      console.log("✅ JWT OK payload:", payload);
    }

    // ✅ staffId fallback (กัน payload คนละชื่อ field)
    const staffId = pickFirstNonEmpty(
      payload.staffId,
      payload.employeeId,
      payload.empId,
      payload.staff_id,
      payload.employee_id
    );

    // ✅ userId fallback (รองรับ id/_id ด้วย)
    const userId = pickFirstNonEmpty(
      payload.userId,
      payload.user_id,
      payload.uid,
      payload.id,
      payload._id
    );

    // ✅ clinicId fallback (รองรับ clinic/clinics)
    const clinicId = extractClinicIdFromPayload(payload);

    // ✅ roles: activeRole > role > roles[]
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

    // ✅ effective role priority: activeRole > role > roles[0]
    const effectiveRole = activeRole || roleCanonical || roles[0] || "";

    // ✅ IMPORTANT (durable contract):
    // principalId = staffId ถ้ามี, ถ้าไม่มีให้ fallback = userId
    // (ใช้ในอนาคตเวลาอยากทำ endpoint รองรับ helper แบบไม่ต้อง staffId)
    const principalId = staffId || userId;
    const principalType = staffId ? "staff" : "user";

    req.user = {
      userId,
      clinicId,

      // ✅ important
      role: effectiveRole,
      roles,
      activeRole: activeRole || "",

      // staffId อาจว่างได้ (โดยเฉพาะ helper)
      staffId,

      // ✅ durable flags
      staffIdMissing: !normStr(staffId),
      principalId,
      principalType,

      // meta
      fullName: normStr(payload.fullName || payload.name),
      phone: normStr(payload.phone),
      email: normStr(payload.email),

      // keep original ids too
      id: normStr(payload.id),
      _id: normStr(payload._id),
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
 * ✅ Role guard (canonical + รองรับ roles array)
 * Usage:
 *   requireRole(['admin'])
 *   requireRole(['employee'])
 *   requireRole(['admin','employee'])
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

    if (have.size === 0) return res.status(401).json({ message: "Unauthorized" });

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
 * ✅ NEW: Require staffId
 * - ใช้เฉพาะ endpoint ที่ "ต้อง" อ้างอิง staffId จริง ๆ (เช่น /shifts แบบเดิม)
 *
 * ตัวอย่าง:
 *   router.get('/shifts', auth, requireRole(['helper','employee']), requireStaffId(), ctrl.listMyShifts)
 */
function requireStaffId() {
  return (req, res, next) => {
    const staffId = normStr(req.user?.staffId);
    if (staffId) return next();

    // ✅ คง message ให้ตรงกับที่ Flutter log เจอ เพื่อดีบัก/สื่อสารชัด
    return res.status(403).json({ message: "staffId missing in token" });
  };
}

/**
 * ✅ Ensure staff self-access (employee can only act on their own staffId)
 * - employee role: staffId in req (param/body/query) must match req.user.staffId
 * - admin role: allow (if allowClinic=true)
 *
 * ✅ IMPORTANT:
 * - ถ้า client ไม่ส่ง staffId/clinicId มา -> เติมจาก token ให้ (กัน controller 400)
 *
 * NOTE:
 * - helper ไม่ควรใช้ middleware นี้ (เพราะ helper อาจไม่มี staffId)
 */
function requireSelfStaff({ allowClinic = true } = {}) {
  return (req, res, next) => {
    const role = canonicalRole(req.user?.role);
    if (!role) return res.status(401).json({ message: "Unauthorized" });

    // ✅ admin bypass (ถ้าอนุญาต)
    if (allowClinic && role === "admin") return next();

    // ✅ ถ้าไม่อนุญาต clinic -> ต้องเป็น employee เท่านั้น
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

    // ✅ เติม staffId ให้ body ถ้าไม่มี
    if (!req.body) req.body = {};
    if (!normStr(req.body.staffId) && !normStr(req.body.employeeId)) {
      req.body.staffId = tokenStaffId;
    }

    // ✅ clinicId เติมให้ด้วย (ถ้ามี) และถ้าส่งมาแล้วต้องตรง
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

module.exports = { auth, requireRole, requireStaffId, requireSelfStaff };