// controllers/authController.js
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

/* ======================================================
   Helper: ensure staffId (employee only)
====================================================== */
async function ensureStaffIdIfEmployee(userDocOrLean) {
  try {
    if (!userDocOrLean) return userDocOrLean;
    if (userDocOrLean.role !== "employee") return userDocOrLean;

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

function normStr(v) {
  return String(v || "").trim();
}

function safeUser(u) {
  if (!u) return null;
  return {
    userId: u.userId,
    clinicId: u.clinicId,
    role: u.role,
    staffId: u.staffId || "",
    email: u.email || "",
    phone: u.phone || "",
    fullName: u.fullName || "",
    employeeCode: u.employeeCode || "",
    isActive: u.isActive,
  };
}

// ✅ NEW: รวม payload token ให้เหมือนกันทุก endpoint
function makeJwtPayload(user) {
  // ต้องมี _id (ObjectId) เพื่อให้ service อื่นใช้ findById ได้
  const mongoId =
    user?._id?.toString?.() || (user?._id ? String(user._id) : "");

  const payload = {
    // เดิมของระบบคุณ
    userId: normStr(user?.userId),
    clinicId: normStr(user?.clinicId),
    role: normStr(user?.role),
    staffId: normStr(user?.staffId),

    // ✅ เพิ่มเพื่อให้ service อื่น enrich ได้ทันที (เช่น payroll_service: availability)
    // ✅ ไม่ต้อง query /me ซ้ำ
    fullName: normStr(user?.fullName),
    phone: normStr(user?.phone),

    // ✅ optional แต่มีประโยชน์ในอนาคต
    email: normStr(user?.email),
  };

  // ✅ ใส่ id เฉพาะเมื่อหาได้จริง (กัน payload แปลก)
  if (mongoId && mongoId !== "undefined" && mongoId !== "null") {
    payload.id = mongoId; // ✅ Mongo ObjectId string 24 chars
  }

  return payload;
}

/* ======================================================
   LOGIN
   POST /login
   ✅ FIX: กันค้าง + log pinpoint + maxTimeMS
====================================================== */
async function login(req, res) {
  const t0 = Date.now();
  try {
    const emailOrPhone = normStr(req.body?.emailOrPhone);
    const password = normStr(req.body?.password);

    console.log("🔐 /login hit", {
      ip: req.ip,
      emailOrPhone,
      hasPw: !!password,
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

    user = await ensureStaffIdIfEmployee(user);

    // ✅ FIX: ใส่ id (ObjectId) ลง token ด้วย + ✅ fullName/phone/email
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
      role: "admin",
      staffId: "",
      email: adminEmail || "",
      phone: adminPhone || "",
      fullName: adminFullName || "",
      passwordHash,
      isActive: true,
      employeeCode: "",
    });

    // ✅ FIX: ใส่ id (ObjectId) ลง token ด้วย + ✅ fullName/phone/email
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

    // ✅ FIX: ใส่ id (ObjectId) ลง token ด้วย + ✅ fullName/phone/email
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
  registerClinicAdmin,
  registerWithInvite,
  forgotPassword,
  resetPassword,
};