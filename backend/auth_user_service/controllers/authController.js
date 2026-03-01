// backend/auth_user_service/controllers/authController.js
const bcrypt = require("bcryptjs");
const Clinic = require("../models/Clinic");
const User = require("../models/User");
const Invite = require("../models/Invite");
const ResetToken = require("../models/ResetToken"); // ✅ NEW
const { makeId } = require("../utils/id");
const { signToken } = require("../utils/jwt");

const USER_PREFIX = (process.env.USER_ID_PREFIX || "usr_").toString();
const CLINIC_PREFIX = (process.env.CLINIC_ID_PREFIX || "cln_").toString();
const EMP_PREFIX = (process.env.EMPLOYEE_ID_PREFIX || "emp_").toString();
const STAFF_PREFIX = (process.env.STAFF_ID_PREFIX || "stf_").toString();

const RESET_TOKEN_TTL_MINUTES = Number(process.env.RESET_TOKEN_TTL_MINUTES || 10);
const RESET_LOG =
  String(process.env.RESET_LOG || "true").toLowerCase() === "true";

const ROLE_ENUM = ["admin", "employee", "helper"];

/* ======================================================
   Helpers
====================================================== */
function normStr(v) {
  return String(v || "").trim();
}

function normLower(v) {
  return normStr(v).toLowerCase();
}

function normalizeRole(v) {
  const r = normLower(v);
  return ROLE_ENUM.includes(r) ? r : "";
}

function normalizeRoles(arr) {
  const roles = Array.isArray(arr) ? arr : [];
  const set = new Set(
    roles.map((x) => normalizeRole(x)).filter((x) => !!x)
  );
  return Array.from(set);
}

/**
 * ✅ Ensure roles[] contains (legacy role + activeRole) and is unique
 * - Backward compatible: ถ้า roles ว่าง ให้เริ่มจาก legacy role
 * - บังคับให้ activeRole อยู่ใน roles เสมอ
 */
function ensureRolesAndActive(userLike, desiredActiveRole) {
  const legacy = normalizeRole(userLike?.role);
  const dbRoles = normalizeRoles(userLike?.roles);

  // base roles
  let roles = dbRoles.length ? dbRoles : (legacy ? [legacy] : []);

  // activeRole candidate
  const want = normalizeRole(desiredActiveRole);
  const active =
    want ||
    normalizeRole(userLike?.activeRole) ||
    legacy ||
    (roles.length ? roles[0] : "") ||
    "employee";

  // ensure active in roles
  if (!roles.includes(active)) roles = [...roles, active];

  // safety: roles must be valid enum only
  roles = normalizeRoles(roles);

  return { roles, activeRole: active, legacyRole: active };
}

function pickActiveRole(user, requested) {
  const roles = normalizeRoles(user?.roles);
  const legacy = normalizeRole(user?.role);
  const active = normalizeRole(user?.activeRole);

  const req = normalizeRole(requested);

  // ✅ If client requests role, it must be in roles (or matches legacy)
  if (req) {
    if (roles.includes(req)) return req;
    if (legacy && legacy === req) return req; // backward case: roles not backfilled yet
    return ""; // invalid request
  }

  // no request -> use activeRole first, else legacy, else first role, else employee
  if (active) return active;
  if (legacy) return legacy;
  if (roles.length > 0) return roles[0];
  return "employee";
}

function safeUser(u) {
  if (!u) return null;

  // ✅ กัน roles ว่าง (ของเก่า) ให้คืน roles ที่ถูกต้องเสมอ
  const fixed = ensureRolesAndActive(u, u?.activeRole || u?.role);

  return {
    userId: u.userId,
    clinicId: u.clinicId,

    // ✅ legacy + active
    role: fixed.legacyRole,
    activeRole: fixed.activeRole,
    roles: fixed.roles,

    staffId: u.staffId || "",
    email: u.email || "",
    phone: u.phone || "",
    fullName: u.fullName || "",
    employeeCode: u.employeeCode || "",
    isActive: u.isActive,
  };
}

// ✅ NEW: รวม payload token ให้เหมือนกันทุก endpoint (multi-role ready)
function makeJwtPayload(user) {
  const mongoId =
    user?._id?.toString?.() || (user?._id ? String(user._id) : "");

  // ✅ IMPORTANT: role in token = activeRole เสมอ + roles ต้องไม่ว่าง
  const fixed = ensureRolesAndActive(user, user?.activeRole || user?.role);

  const payload = {
    userId: normStr(user?.userId),
    clinicId: normStr(user?.clinicId),

    // ✅ token role ใช้ activeRole เสมอ
    role: fixed.activeRole,

    // ✅ ส่งเพิ่มเพื่ออนาคต (แอปเลือก role ได้)
    activeRole: fixed.activeRole,
    roles: fixed.roles,

    staffId: normStr(user?.staffId),

    fullName: normStr(user?.fullName),
    phone: normStr(user?.phone),
    email: normStr(user?.email),
  };

  if (mongoId && mongoId !== "undefined" && mongoId !== "null") {
    payload.id = mongoId;
  }

  return payload;
}

/* ======================================================
   Helper: ensure staffId (employee only)
   ✅ Multi-role safe:
   - ถ้ามี employee อยู่ใน roles หรือ activeRole/role เป็น employee -> ต้องมี staffId
====================================================== */
async function ensureStaffIdIfEmployee(userDocOrLean) {
  try {
    if (!userDocOrLean) return userDocOrLean;

    const legacyRole = normalizeRole(userDocOrLean.role);
    const activeRole = normalizeRole(userDocOrLean.activeRole);
    const roles = normalizeRoles(userDocOrLean.roles);

    const hasEmployee =
      legacyRole === "employee" ||
      activeRole === "employee" ||
      roles.includes("employee");

    if (!hasEmployee) return userDocOrLean;

    const staffId = String(userDocOrLean.staffId || "").trim();
    if (staffId.length > 0) return userDocOrLean;

    const newStaffId = makeId(STAFF_PREFIX, 10);

    await User.updateOne(
      { userId: userDocOrLean.userId },
      { $set: { staffId: newStaffId } }
    );

    return { ...userDocOrLean, staffId: newStaffId };
  } catch {
    return userDocOrLean;
  }
}

/* ======================================================
   LOGIN
   POST /login
   body: { emailOrPhone, password, activeRole? }
   ✅ FIX: กันค้าง + log pinpoint + maxTimeMS
   ✅ NEW: รองรับเลือก activeRole (employee/helper/admin)
====================================================== */
async function login(req, res) {
  const t0 = Date.now();
  try {
    const emailOrPhone = normStr(req.body?.emailOrPhone);
    const password = normStr(req.body?.password);
    const requestedRole = req.body?.activeRole; // optional

    console.log("🔐 /login hit", {
      ip: req.ip,
      emailOrPhone,
      hasPw: !!password,
      activeRole: requestedRole ? String(requestedRole) : "",
    });

    if (!emailOrPhone || !password) {
      return res
        .status(400)
        .json({ message: "emailOrPhone and password required" });
    }

    console.log("🔎 finding user...");
    let user = await User.findOne({
      $or: [{ email: emailOrPhone }, { phone: emailOrPhone }],
    })
      .maxTimeMS(5000)
      .lean();

    console.log("✅ findOne done", {
      found: !!user,
      ms: Date.now() - t0,
    });

    if (!user) return res.status(401).json({ message: "Invalid credentials" });
    if (!user.isActive) {
      return res.status(403).json({ message: "User disabled" });
    }

    const hash = normStr(user.passwordHash);
    if (!hash) {
      console.log("❌ passwordHash missing", { userId: user.userId });
      return res.status(500).json({ message: "passwordHash missing for user" });
    }

    console.log("🔑 bcrypt compare...");
    const ok = await bcrypt.compare(password, hash);

    console.log("✅ bcrypt done", {
      ok,
      ms: Date.now() - t0,
    });

    if (!ok) return res.status(401).json({ message: "Invalid credentials" });

    // ✅ ensure staffId if user has employee role in any form
    user = await ensureStaffIdIfEmployee(user);

    // ✅ determine activeRole to use
    const activeRole = pickActiveRole(user, requestedRole);
    if (!activeRole) {
      return res.status(403).json({
        message: "Requested role not allowed for this user",
        requestedRole: normalizeRole(requestedRole),
        roles: normalizeRoles(user?.roles),
        legacyRole: normalizeRole(user?.role),
      });
    }

    // ✅ Ensure roles[] contains activeRole + backfill legacy role
    const fixed = ensureRolesAndActive(user, activeRole);

    // ✅ persist: activeRole + legacy role + roles[]
    await User.updateOne(
      { userId: user.userId },
      {
        $set: {
          activeRole: fixed.activeRole,
          role: fixed.legacyRole, // sync legacy
          roles: fixed.roles,
        },
      }
    );

    // refresh local user object fields for response/token payload
    user = {
      ...user,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    };

    const token = signToken(makeJwtPayload(user));

    console.log("✅ login success total ms=", Date.now() - t0);
    return res.json({ user: safeUser(user), token });
  } catch (e) {
    console.error("❌ login failed", e, "ms=", Date.now() - t0);
    return res.status(500).json({ message: "login failed", error: e.message });
  }
}

/* ======================================================
   ME
   GET /me (auth required)
====================================================== */
async function me(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: "Missing token payload" });
    }

    let user = await User.findOne({ userId }).select("-passwordHash").lean();
    if (!user) return res.status(404).json({ message: "User not found" });

    user = await ensureStaffIdIfEmployee(user);

    return res.json({ user: safeUser(user) });
  } catch (e) {
    return res.status(500).json({ message: "me failed", error: e.message });
  }
}

/* ======================================================
   ✅ NEW: SWITCH ROLE (หลัง login)
   POST /switch-role
   body: { activeRole }
   - ต้อง auth ก่อน (req.user.userId มี)
   - ตรวจว่า activeRole อยู่ใน user.roles
   - ออก token ใหม่ role=activeRole
====================================================== */
async function switchRole(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: "Missing token payload" });
    }

    const requestedRole = req.body?.activeRole;
    const want = normalizeRole(requestedRole);
    if (!want) {
      return res.status(400).json({ message: "activeRole is required" });
    }

    let user = await User.findOne({ userId }).select("-passwordHash").lean();
    if (!user) return res.status(404).json({ message: "User not found" });
    if (!user.isActive) return res.status(403).json({ message: "User disabled" });

    user = await ensureStaffIdIfEmployee(user);

    const roles = normalizeRoles(user?.roles);
    const legacy = normalizeRole(user?.role);

    // allow if roles include it OR legacy matches it (for old docs)
    const allowed = roles.includes(want) || (legacy && legacy === want);
    if (!allowed) {
      return res.status(403).json({
        message: "Role not allowed for this user",
        requestedRole: want,
        roles,
        legacyRole: legacy,
      });
    }

    // ✅ Ensure roles[] contains want
    const fixed = ensureRolesAndActive(user, want);

    await User.updateOne(
      { userId },
      { $set: { activeRole: fixed.activeRole, role: fixed.legacyRole, roles: fixed.roles } }
    );

    user = {
      ...user,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    };

    const token = signToken(makeJwtPayload(user));
    return res.json({ user: safeUser(user), token });
  } catch (e) {
    return res.status(500).json({ message: "switchRole failed", error: e.message });
  }
}

/* ======================================================
   REGISTER CLINIC ADMIN
   POST /register-clinic-admin
====================================================== */
async function registerClinicAdmin(req, res) {
  try {
    const clinicName = normStr(req.body?.clinicName);
    const adminPassword = normStr(req.body?.adminPassword);

    const adminFullName = normStr(req.body?.adminFullName);
    const adminEmail = normStr(req.body?.adminEmail).toLowerCase();
    const adminPhone = normStr(req.body?.adminPhone);

    if (!clinicName || !adminPassword) {
      return res
        .status(400)
        .json({ message: "clinicName and adminPassword required" });
    }

    const clinicId = makeId(CLINIC_PREFIX, 10);
    const userId = makeId(USER_PREFIX, 10);

    const passwordHash = await bcrypt.hash(adminPassword, 10);

    const clinic = await Clinic.create({
      clinicId,
      name: clinicName,
      ownerUserId: userId,
      phone: adminPhone || "",
    });

    const user = await User.create({
      userId,
      clinicId,

      // ✅ multi-role defaults
      roles: ["admin"],
      activeRole: "admin",

      // ✅ legacy
      role: "admin",

      staffId: "",
      email: adminEmail || "",
      phone: adminPhone || "",
      fullName: adminFullName || "",
      passwordHash,
      isActive: true,
      employeeCode: "",
    });

    const token = signToken(
      makeJwtPayload(user.toObject ? user.toObject() : user)
    );

    return res.json({
      clinic: { clinicId: clinic.clinicId, name: clinic.name },
      user: safeUser(user.toObject ? user.toObject() : user),
      token,
    });
  } catch (e) {
    return res
      .status(500)
      .json({ message: "registerClinicAdmin failed", error: e.message });
  }
}

/* ======================================================
   REGISTER WITH INVITE (EMPLOYEE)
   POST /register-with-invite
====================================================== */
async function registerWithInvite(req, res) {
  try {
    const inviteCode = normStr(req.body?.inviteCode).toUpperCase();
    const password = normStr(req.body?.password);

    const fullName = normStr(req.body?.fullName);
    const email = normStr(req.body?.email).toLowerCase();
    const phone = normStr(req.body?.phone);

    if (!inviteCode || !password) {
      return res
        .status(400)
        .json({ message: "inviteCode and password required" });
    }

    const inv = await Invite.findOne({ inviteCode });
    if (!inv) return res.status(404).json({ message: "Invite not found" });
    if (inv.isRevoked) return res.status(403).json({ message: "Invite revoked" });
    if (inv.usedAt) return res.status(403).json({ message: "Invite already used" });
    if (inv.expiresAt && inv.expiresAt.getTime() < Date.now()) {
      return res.status(403).json({ message: "Invite expired" });
    }

    const userId = makeId(USER_PREFIX, 10);
    const employeeCode = makeId(EMP_PREFIX, 10);
    const staffId = makeId(STAFF_PREFIX, 10);
    const passwordHash = await bcrypt.hash(password, 10);

    const user = await User.create({
      userId,
      clinicId: inv.clinicId,

      // ✅ multi-role defaults
      roles: ["employee"],
      activeRole: "employee",

      // ✅ legacy
      role: "employee",

      staffId,
      email: email || inv.email || "",
      phone: phone || inv.phone || "",
      fullName: fullName || inv.fullName || "",
      employeeCode,
      passwordHash,
      isActive: true,
    });

    inv.usedAt = new Date();
    inv.usedByUserId = userId;
    await inv.save();

    const token = signToken(
      makeJwtPayload(user.toObject ? user.toObject() : user)
    );

    return res.json({
      user: safeUser(user.toObject ? user.toObject() : user),
      token,
    });
  } catch (e) {
    return res
      .status(500)
      .json({ message: "registerWithInvite failed", error: e.message });
  }
}

/* ======================================================
   🔐 FORGOT PASSWORD
   POST /forgot-password
   body: { emailOrPhone }
====================================================== */
async function forgotPassword(req, res) {
  try {
    const emailOrPhone = normStr(req.body?.emailOrPhone);
    if (!emailOrPhone) {
      return res.status(400).json({ message: "emailOrPhone required" });
    }

    const user = await User.findOne({
      $or: [{ email: emailOrPhone }, { phone: emailOrPhone }],
    }).lean();

    if (!user) return res.json({ ok: true });
    if (user.isActive === false) return res.json({ ok: true });

    await ResetToken.deleteMany({ userId: user.userId });

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + RESET_TOKEN_TTL_MINUTES * 60 * 1000);

    await ResetToken.create({
      userId: user.userId,
      code,
      expiresAt,
    });

    if (RESET_LOG) {
      console.log("🔐 RESET OTP:", code, "userId:", user.userId);
    }

    return res.json({ ok: true });
  } catch (e) {
    return res
      .status(500)
      .json({ message: "forgotPassword failed", error: e.message });
  }
}

/* ======================================================
   🔁 RESET PASSWORD
   POST /reset-password
   body: { emailOrPhone, code, newPassword }
====================================================== */
async function resetPassword(req, res) {
  try {
    const emailOrPhone = normStr(req.body?.emailOrPhone);
    const code = normStr(req.body?.code);
    const newPassword = normStr(req.body?.newPassword);

    if (!emailOrPhone || !code || !newPassword) {
      return res.status(400).json({ message: "invalid payload" });
    }
    if (newPassword.length < 6) {
      return res.status(400).json({ message: "newPassword too short (>=6)" });
    }

    const user = await User.findOne({
      $or: [{ email: emailOrPhone }, { phone: emailOrPhone }],
    });

    if (!user) return res.status(400).json({ message: "invalid code" });
    if (!user.isActive) return res.status(403).json({ message: "User disabled" });

    const token = await ResetToken.findOne({
      userId: user.userId,
      code,
      expiresAt: { $gt: new Date() },
    });

    if (!token) {
      return res.status(400).json({ message: "invalid or expired code" });
    }

    user.passwordHash = await bcrypt.hash(newPassword, 10);
    await user.save();

    await ResetToken.deleteMany({ userId: user.userId });

    return res.json({ ok: true });
  } catch (e) {
    return res
      .status(500)
      .json({ message: "resetPassword failed", error: e.message });
  }
}

module.exports = {
  login,
  me,
  switchRole, // ✅ NEW
  registerClinicAdmin,
  registerWithInvite,
  forgotPassword,
  resetPassword,
};