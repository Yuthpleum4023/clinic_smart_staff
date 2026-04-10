const bcrypt = require("bcryptjs");
const Clinic = require("../models/Clinic");
const User = require("../models/User");
const Invite = require("../models/Invite");
const ResetToken = require("../models/ResetToken");
const { makeId } = require("../utils/id");
const { signToken } = require("../utils/jwt");
const { ensureEmployeeForUser } = require("../utils/staffServiceClient");

const USER_PREFIX = (process.env.USER_ID_PREFIX || "usr_").toString();
const CLINIC_PREFIX = (process.env.CLINIC_ID_PREFIX || "cln_").toString();
const EMP_PREFIX = (process.env.EMPLOYEE_ID_PREFIX || "emp_").toString();

const RESET_TOKEN_TTL_MINUTES = Number(
  process.env.RESET_TOKEN_TTL_MINUTES || 10
);
const RESET_LOG =
  String(process.env.RESET_LOG || "true").toLowerCase() === "true";

const ROLE_ENUM = ["admin", "employee", "helper"];
const PLAN_ENUM = ["free", "premium"];

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
  const set = new Set(roles.map((x) => normalizeRole(x)).filter(Boolean));
  return Array.from(set);
}

function normalizePlan(v) {
  const p = normLower(v);
  return PLAN_ENUM.includes(p) ? p : "free";
}

function toDateOrNull(v) {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return Number.isFinite(d.getTime()) ? d : null;
}

function toNumOrNull(v) {
  if (v === null || v === undefined) return null;
  const x = Number(v);
  return Number.isFinite(x) ? x : null;
}

function isValidLatLng(lat, lng) {
  if (lat === null || lng === null) return false;
  if (typeof lat !== "number" || typeof lng !== "number") return false;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat < -90 || lat > 90) return false;
  if (lng < -180 || lng > 180) return false;
  return true;
}

function normalizeLocation(input) {
  const lat = toNumOrNull(input?.lat) ?? toNumOrNull(input?.latitude);
  const lng = toNumOrNull(input?.lng) ?? toNumOrNull(input?.longitude);

  const district = normStr(input?.district || input?.amphoe);
  const province = normStr(input?.province || input?.changwat);
  const address = normStr(input?.address || input?.fullAddress);

  const label = normStr(
    input?.label ||
      input?.locationLabel ||
      [district, province].filter(Boolean).join(", ") ||
      address
  );

  if (!isValidLatLng(lat, lng)) {
    return {
      lat: null,
      lng: null,
      district,
      province,
      address,
      label,
      updatedAt: null,
    };
  }

  return {
    lat,
    lng,
    district,
    province,
    address,
    label,
    updatedAt: new Date(),
  };
}

function isPremiumActive(userLike) {
  const plan = normalizePlan(userLike?.plan);
  if (plan !== "premium") return false;

  const until = toDateOrNull(userLike?.premiumUntil);
  if (!until) return false;

  return until.getTime() > Date.now();
}

function ensureRolesAndActive(userLike, desiredActiveRole) {
  const legacy = normalizeRole(userLike?.role);
  const dbRoles = normalizeRoles(userLike?.roles);

  let roles = dbRoles.length ? dbRoles : legacy ? [legacy] : [];

  const want = normalizeRole(desiredActiveRole);
  const active =
    want ||
    normalizeRole(userLike?.activeRole) ||
    legacy ||
    (roles.length ? roles[0] : "") ||
    "employee";

  if (!roles.includes(active)) roles = [...roles, active];
  roles = normalizeRoles(roles);

  return {
    roles,
    activeRole: active,
    legacyRole: active,
  };
}

function pickActiveRole(user, requested) {
  const roles = normalizeRoles(user?.roles);
  const legacy = normalizeRole(user?.role);
  const active = normalizeRole(user?.activeRole);
  const req = normalizeRole(requested);

  if (req) {
    if (roles.includes(req)) return req;
    if (legacy && legacy === req) return req;
    return "";
  }

  if (active) return active;
  if (legacy) return legacy;
  if (roles.length > 0) return roles[0];
  return "employee";
}

function isHelperUser(userLike) {
  const fixed = ensureRolesAndActive(
    userLike || {},
    userLike?.activeRole || userLike?.role
  );

  return (
    fixed.activeRole === "helper" ||
    fixed.legacyRole === "helper" ||
    fixed.roles.includes("helper")
  );
}

function helperSafeClinicId(userLike) {
  return isHelperUser(userLike) ? "" : normStr(userLike?.clinicId);
}

function helperSafeStaffId(userLike) {
  return isHelperUser(userLike) ? "" : normStr(userLike?.staffId);
}

function isEmployeeUser(userLike) {
  const fixed = ensureRolesAndActive(
    userLike || {},
    userLike?.activeRole || userLike?.role
  );

  return (
    fixed.activeRole === "employee" ||
    fixed.legacyRole === "employee" ||
    fixed.roles.includes("employee")
  );
}

function shouldAttemptEnsureEmployee(userLike) {
  if (!userLike) return false;
  if (!isEmployeeUser(userLike)) return false;
  if (isHelperUser(userLike)) return false;

  const clinicId = normStr(userLike?.clinicId);
  if (!clinicId) return false;

  const staffId = normStr(userLike?.staffId);
  const provisionStatus = normLower(userLike?.employeeProvisionStatus);

  if (staffId) return false;
  if (provisionStatus === "ready") return false;

  return true;
}

function safeUser(u) {
  if (!u) return null;

  const fixed = ensureRolesAndActive(u, u?.activeRole || u?.role);
  const plan = normalizePlan(u?.plan);
  const premiumUntil = toDateOrNull(u?.premiumUntil);
  const premium = isPremiumActive({ plan, premiumUntil });

  return {
    userId: u.userId,
    clinicId: helperSafeClinicId({
      ...u,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    }),
    role: fixed.legacyRole,
    activeRole: fixed.activeRole,
    roles: fixed.roles,
    staffId: helperSafeStaffId({
      ...u,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    }),
    email: u.email || "",
    phone: u.phone || "",
    fullName: u.fullName || "",
    employeeCode: u.employeeCode || "",
    isActive: u.isActive,
    employeeProvisionStatus: normStr(u.employeeProvisionStatus) || "",
    location: {
      lat: u?.location?.lat ?? null,
      lng: u?.location?.lng ?? null,
      district: u?.location?.district || "",
      province: u?.location?.province || "",
      address: u?.location?.address || "",
      label: u?.location?.label || "",
      updatedAt: u?.location?.updatedAt
        ? new Date(u.location.updatedAt).toISOString()
        : null,
    },
    plan,
    premiumUntil: premiumUntil ? premiumUntil.toISOString() : null,
    isPremium: premium,
  };
}

async function buildMePayload(userLike) {
  if (!userLike) return null;

  const fixed = ensureRolesAndActive(
    userLike,
    userLike?.activeRole || userLike?.role
  );

  const normalized = {
    ...userLike,
    activeRole: fixed.activeRole,
    role: fixed.legacyRole,
    roles: fixed.roles,
  };

  const base = safeUser(normalized);
  const mongoId =
    normalized?._id?.toString?.() ||
    (normalized?._id ? String(normalized._id) : "");

  const clinicId = normStr(base?.clinicId);

  let clinicObj = null;
  let clinics = [];

  if (clinicId) {
    try {
      const clinic = await Clinic.findOne({ clinicId }).lean();

      if (clinic) {
        clinicObj = {
          id: normStr(clinic.clinicId) || clinicId,
          _id: clinic?._id?.toString?.() || "",
          clinicId: normStr(clinic.clinicId) || clinicId,
          name: normStr(clinic.name),
          phone: normStr(clinic.phone),
        };
      } else {
        clinicObj = {
          id: clinicId,
          _id: "",
          clinicId,
          name: "",
          phone: "",
        };
      }

      clinics = clinicObj ? [clinicObj] : [];
    } catch (_) {
      clinicObj = {
        id: clinicId,
        _id: "",
        clinicId,
        name: "",
        phone: "",
      };
      clinics = [clinicObj];
    }
  }

  return {
    userId: normStr(base?.userId),
    id: mongoId || normStr(base?.userId),
    _id: mongoId || normStr(base?.userId),

    clinicId,
    clinic: clinicObj,
    clinics,

    role: normStr(base?.role),
    activeRole: normStr(base?.activeRole),
    roles: Array.isArray(base?.roles) ? base.roles : [],

    staffId: normStr(base?.staffId),
    email: normStr(base?.email),
    phone: normStr(base?.phone),
    fullName: normStr(base?.fullName),
    employeeCode: normStr(base?.employeeCode),
    isActive: !!base?.isActive,
    employeeProvisionStatus: normStr(base?.employeeProvisionStatus),

    location: {
      lat: base?.location?.lat ?? null,
      lng: base?.location?.lng ?? null,
      district: normStr(base?.location?.district),
      province: normStr(base?.location?.province),
      address: normStr(base?.location?.address),
      label: normStr(base?.location?.label),
      updatedAt: base?.location?.updatedAt || null,
    },

    plan: normStr(base?.plan) || "free",
    premiumUntil: base?.premiumUntil || null,
    isPremium: !!base?.isPremium,
  };
}

function makeJwtPayload(user) {
  const mongoId =
    user?._id?.toString?.() || (user?._id ? String(user._id) : "");

  const fixed = ensureRolesAndActive(user, user?.activeRole || user?.role);

  const plan = normalizePlan(user?.plan);
  const premiumUntil = toDateOrNull(user?.premiumUntil);
  const premium = isPremiumActive({ plan, premiumUntil });

  const normalizedForRole = {
    ...user,
    activeRole: fixed.activeRole,
    role: fixed.legacyRole,
    roles: fixed.roles,
  };

  const payload = {
    userId: normStr(user?.userId),
    clinicId: helperSafeClinicId(normalizedForRole),
    role: fixed.activeRole,
    activeRole: fixed.activeRole,
    roles: fixed.roles,
    staffId: helperSafeStaffId(normalizedForRole),
    fullName: normStr(user?.fullName),
    phone: normStr(user?.phone),
    email: normStr(user?.email),
    location: {
      lat: user?.location?.lat ?? null,
      lng: user?.location?.lng ?? null,
      district: normStr(user?.location?.district),
      province: normStr(user?.location?.province),
      label: normStr(user?.location?.label),
    },
    plan,
    premiumUntil: premiumUntil ? premiumUntil.toISOString() : null,
    isPremium: premium,
  };

  if (mongoId && mongoId !== "undefined" && mongoId !== "null") {
    payload.id = mongoId;
  }

  return payload;
}

/**
 * IMPORTANT:
 * - auth_user_service ห้าม generate staffId เอง
 * - staffId ต้องมาจาก staff_service หลัง ensure/create สำเร็จเท่านั้น
 */
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

    return userDocOrLean;
  } catch (_) {
    return userDocOrLean;
  }
}

async function syncUserStaffIdFromEnsured(userLike, ensured) {
  try {
    const currentStaffId = normStr(userLike?.staffId);
    const ensuredStaffId = normStr(ensured?.employee?.staffId);

    if (
      !userLike?.userId ||
      !ensuredStaffId ||
      ensuredStaffId === currentStaffId
    ) {
      return userLike;
    }

    await User.updateOne(
      { userId: userLike.userId },
      { $set: { staffId: ensuredStaffId } }
    );

    return {
      ...userLike,
      staffId: ensuredStaffId,
    };
  } catch (_) {
    return userLike;
  }
}

async function persistEmployeeProvisionState(
  userId,
  {
    staffId = "",
    employeeProvisionStatus = "",
  } = {}
) {
  const uid = normStr(userId);
  if (!uid) return;

  const setDoc = {};

  if (staffId !== undefined && staffId !== null) {
    setDoc.staffId = normStr(staffId);
  }

  if (employeeProvisionStatus) {
    setDoc.employeeProvisionStatus = normStr(employeeProvisionStatus);
  }

  if (!Object.keys(setDoc).length) return;

  await User.updateOne({ userId: uid }, { $set: setDoc });
}

async function tryEnsureEmployeeProvision(userLike, sourceLabel = "") {
  try {
    if (!userLike?.userId) {
      return {
        ok: false,
        skipped: true,
        reason: "missing_userId",
        user: userLike,
      };
    }

    if (!shouldAttemptEnsureEmployee(userLike)) {
      return {
        ok: true,
        skipped: true,
        reason: "not_needed",
        user: userLike,
      };
    }

    console.log(`🧩 ensureEmployeeForUser(${sourceLabel}) start`, {
      userId: userLike.userId,
      clinicId: normStr(userLike.clinicId),
      staffId: normStr(userLike.staffId),
      employeeProvisionStatus: normStr(userLike.employeeProvisionStatus),
      role: normStr(userLike.activeRole || userLike.role),
    });

    const ensured = await ensureEmployeeForUser(userLike, "");

    console.log(`🧩 ensureEmployeeForUser(${sourceLabel}) result`, {
      userId: userLike.userId,
      ok: !!ensured?.ok,
      created: !!ensured?.created,
      skipped: !!ensured?.skipped,
      reason: ensured?.reason || "",
      employeeStaffId: ensured?.employee?.staffId || "",
    });

    if (ensured?.ok && ensured?.employee?.staffId) {
      let nextUser = await syncUserStaffIdFromEnsured(userLike, ensured);

      await persistEmployeeProvisionState(nextUser.userId, {
        staffId: normStr(ensured.employee.staffId),
        employeeProvisionStatus: "ready",
      });

      nextUser = {
        ...nextUser,
        staffId: normStr(ensured.employee.staffId),
        employeeProvisionStatus: "ready",
      };

      return {
        ok: true,
        created: !!ensured?.created,
        skipped: false,
        reason: "",
        ensured,
        user: nextUser,
      };
    }

    await persistEmployeeProvisionState(userLike.userId, {
      employeeProvisionStatus: "pending",
    });

    return {
      ok: !!ensured?.ok,
      created: !!ensured?.created,
      skipped: !!ensured?.skipped,
      reason: ensured?.reason || "not_ready",
      ensured,
      user: {
        ...userLike,
        employeeProvisionStatus: "pending",
      },
    };
  } catch (e) {
    console.log(`⚠️ ensureEmployeeForUser(${sourceLabel}) failed`, {
      userId: normStr(userLike?.userId),
      status: e?.status || 0,
      message: e?.message || "",
    });

    await persistEmployeeProvisionState(userLike?.userId, {
      employeeProvisionStatus: "pending",
    });

    return {
      ok: false,
      skipped: true,
      reason: "ensure_exception",
      errorStatus: e?.status || 0,
      errorMessage: e?.message || "",
      user: userLike
        ? { ...userLike, employeeProvisionStatus: "pending" }
        : userLike,
    };
  }
}

/* ======================================================
   LOGIN
====================================================== */
async function login(req, res) {
  const t0 = Date.now();

  try {
    const emailOrPhone = normStr(req.body?.emailOrPhone);
    const password = normStr(req.body?.password);
    const requestedRole = req.body?.activeRole;

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

    let user = await User.findOne({
      $or: [{ email: emailOrPhone }, { phone: emailOrPhone }],
    })
      .maxTimeMS(5000)
      .lean();

    console.log("✅ findOne done", {
      found: !!user,
      ms: Date.now() - t0,
    });

    if (!user) {
      return res.status(401).json({ message: "Invalid credentials" });
    }

    if (!user.isActive) {
      return res.status(403).json({ message: "User disabled" });
    }

    const hash = normStr(user.passwordHash);
    if (!hash) {
      console.log("❌ passwordHash missing", { userId: user.userId });
      return res.status(500).json({ message: "passwordHash missing for user" });
    }

    const ok = await bcrypt.compare(password, hash);

    console.log("✅ bcrypt done", {
      ok,
      ms: Date.now() - t0,
    });

    if (!ok) {
      return res.status(401).json({ message: "Invalid credentials" });
    }

    user = await ensureStaffIdIfEmployee(user);

    const activeRole = pickActiveRole(user, requestedRole);
    if (!activeRole) {
      return res.status(403).json({
        message: "Requested role not allowed for this user",
        requestedRole: normalizeRole(requestedRole),
        roles: normalizeRoles(user?.roles),
        legacyRole: normalizeRole(user?.role),
      });
    }

    const fixed = ensureRolesAndActive(user, activeRole);

    await User.updateOne(
      { userId: user.userId },
      {
        $set: {
          activeRole: fixed.activeRole,
          role: fixed.legacyRole,
          roles: fixed.roles,
        },
      }
    );

    user = {
      ...user,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    };

    if (shouldAttemptEnsureEmployee(user)) {
      const ensuredOnLogin = await tryEnsureEmployeeProvision(user, "login");
      if (ensuredOnLogin?.user) {
        user = ensuredOnLogin.user;
      }
    } else {
      console.log("✅ skip ensureEmployeeForUser(login)", {
        userId: user.userId,
        role: normStr(user?.activeRole || user?.role),
        reason: isEmployeeUser(user)
          ? "already_ready_or_missing_context"
          : "not_employee",
        staffId: normStr(user?.staffId),
        clinicId: normStr(user?.clinicId),
        employeeProvisionStatus: normStr(user?.employeeProvisionStatus),
      });
    }

    const token = signToken(makeJwtPayload(user));
    const userPayload = await buildMePayload(user);

    console.log("✅ login success total ms=", Date.now() - t0);
    return res.json({ user: userPayload, token });
  } catch (e) {
    console.error("❌ login failed", e, "ms=", Date.now() - t0);
    return res.status(500).json({
      message: "login failed",
      error: e.message,
    });
  }
}

/* ======================================================
   ME
====================================================== */
async function me(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: "Missing token payload" });
    }

    console.log(
      "📘 /me req.user =",
      JSON.stringify(
        {
          userId: req.user?.userId || "",
          role: req.user?.role || "",
          activeRole: req.user?.activeRole || "",
          clinicId: req.user?.clinicId || "",
          staffId: req.user?.staffId || "",
          roles: Array.isArray(req.user?.roles) ? req.user.roles : [],
        },
        null,
        2
      )
    );

    let user = await User.findOne({ userId }).select("-passwordHash").lean();
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    user = await ensureStaffIdIfEmployee(user);

    const requestedOrTokenRole =
      req.user?.activeRole || req.user?.role || user?.activeRole || user?.role;

    const fixed = ensureRolesAndActive(user, requestedOrTokenRole);

    if (
      user.activeRole !== fixed.activeRole ||
      user.role !== fixed.legacyRole ||
      JSON.stringify(normalizeRoles(user.roles)) !== JSON.stringify(fixed.roles)
    ) {
      await User.updateOne(
        { userId: user.userId },
        {
          $set: {
            activeRole: fixed.activeRole,
            role: fixed.legacyRole,
            roles: fixed.roles,
          },
        }
      );
    }

    user = {
      ...user,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    };

    if (shouldAttemptEnsureEmployee(user)) {
      const ensuredOnMe = await tryEnsureEmployeeProvision(user, "me");
      if (ensuredOnMe?.user) {
        user = ensuredOnMe.user;
      }
    }

    const userPayload = await buildMePayload(user);

    console.log(
      "📘 /me response body =",
      JSON.stringify(
        {
          userId: userPayload?.userId || "",
          id: userPayload?.id || "",
          role: userPayload?.role || "",
          activeRole: userPayload?.activeRole || "",
          clinicId: userPayload?.clinicId || "",
          staffId: userPayload?.staffId || "",
          roles: Array.isArray(userPayload?.roles) ? userPayload.roles : [],
          employeeProvisionStatus: userPayload?.employeeProvisionStatus || "",
        },
        null,
        2
      )
    );

    return res.json({ user: userPayload });
  } catch (e) {
    console.log("❌ /me failed:", e?.message || e);
    return res.status(500).json({
      message: "me failed",
      error: e.message,
    });
  }
}

/* ======================================================
   UPDATE MY LOCATION
====================================================== */
async function updateMyLocation(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: "Missing token payload" });
    }

    const location = normalizeLocation(req.body || {});
    if (!isValidLatLng(location.lat, location.lng)) {
      return res.status(400).json({
        message: "lat/lng required and must be valid coordinates",
      });
    }

    const updated = await User.findOneAndUpdate(
      { userId },
      {
        $set: {
          location: {
            lat: location.lat,
            lng: location.lng,
            district: location.district || "",
            province: location.province || "",
            address: location.address || "",
            label: location.label || "",
            updatedAt: new Date(),
          },
        },
      },
      {
        new: true,
        projection: { passwordHash: 0 },
      }
    ).lean();

    if (!updated) {
      return res.status(404).json({ message: "User not found" });
    }

    return res.json({
      ok: true,
      user: safeUser(updated),
      location: {
        lat: updated?.location?.lat ?? null,
        lng: updated?.location?.lng ?? null,
        district: updated?.location?.district || "",
        province: updated?.location?.province || "",
        address: updated?.location?.address || "",
        label: updated?.location?.label || "",
        updatedAt: updated?.location?.updatedAt
          ? new Date(updated.location.updatedAt).toISOString()
          : null,
      },
    });
  } catch (e) {
    return res.status(500).json({
      message: "updateMyLocation failed",
      error: e.message,
    });
  }
}

/* ======================================================
   SWITCH ROLE
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
    const allowed = roles.includes(want) || (legacy && legacy === want);

    if (!allowed) {
      return res.status(403).json({
        message: "Role not allowed for this user",
        requestedRole: want,
        roles,
        legacyRole: legacy,
      });
    }

    const fixed = ensureRolesAndActive(user, want);

    await User.updateOne(
      { userId },
      {
        $set: {
          activeRole: fixed.activeRole,
          role: fixed.legacyRole,
          roles: fixed.roles,
        },
      }
    );

    user = {
      ...user,
      activeRole: fixed.activeRole,
      role: fixed.legacyRole,
      roles: fixed.roles,
    };

    if (shouldAttemptEnsureEmployee(user)) {
      const ensuredOnSwitch = await tryEnsureEmployeeProvision(
        user,
        "switchRole"
      );
      if (ensuredOnSwitch?.user) {
        user = ensuredOnSwitch.user;
      }
    }

    const token = signToken(makeJwtPayload(user));
    const userPayload = await buildMePayload(user);

    return res.json({ user: userPayload, token });
  } catch (e) {
    return res.status(500).json({
      message: "switchRole failed",
      error: e.message,
    });
  }
}

/* ======================================================
   REGISTER CLINIC ADMIN
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
      roles: ["admin"],
      activeRole: "admin",
      role: "admin",
      staffId: "",
      email: adminEmail || "",
      phone: adminPhone || "",
      fullName: adminFullName || "",
      passwordHash,
      isActive: true,
      employeeCode: "",
      plan: "free",
      premiumUntil: null,
      planUpdatedAt: null,
      employeeProvisionStatus: "not_applicable",
    });

    const plain = user.toObject ? user.toObject() : user;
    const token = signToken(makeJwtPayload(plain));
    const userPayload = await buildMePayload(plain);

    return res.json({
      clinic: { clinicId: clinic.clinicId, name: clinic.name },
      user: userPayload,
      token,
    });
  } catch (e) {
    return res.status(500).json({
      message: "registerClinicAdmin failed",
      error: e.message,
    });
  }
}

/* ======================================================
   REGISTER WITH INVITE
   - employee: ผูก clinicId ถาวร + ensure employee (non-blocking)
   - helper: สมัครด้วย invite ได้ แต่ไม่ผูก clinicId ถาวร
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
    if (inv.isRevoked) {
      return res.status(403).json({ message: "Invite revoked" });
    }
    if (inv.usedAt) {
      return res.status(403).json({ message: "Invite already used" });
    }
    if (inv.expiresAt && inv.expiresAt.getTime() < Date.now()) {
      return res.status(403).json({ message: "Invite expired" });
    }

    const invRole = normalizeRole(inv.role) || "employee";

    const finalEmail = email || normStr(inv.email).toLowerCase() || "";
    const finalPhone = phone || normStr(inv.phone) || "";

    if (finalPhone) {
      const existed = await User.findOne({ phone: finalPhone }).lean();
      if (existed) {
        return res.status(409).json({ message: "Phone already registered" });
      }
    }

    if (finalEmail) {
      const existed = await User.findOne({ email: finalEmail }).lean();
      if (existed) {
        return res.status(409).json({ message: "Email already registered" });
      }
    }

    const userId = makeId(USER_PREFIX, 10);

    const isEmployeeInvite = invRole === "employee";
    const boundClinicId = isEmployeeInvite ? normStr(inv.clinicId) : "";

    if (isEmployeeInvite && !boundClinicId) {
      return res.status(400).json({
        message: "Invite missing clinicId for employee",
      });
    }

    const employeeCode = isEmployeeInvite ? makeId(EMP_PREFIX, 10) : "";
    const passwordHash = await bcrypt.hash(password, 10);

    const createdUser = await User.create({
      userId,
      clinicId: boundClinicId,
      roles: [invRole],
      activeRole: invRole,
      role: invRole,
      staffId: "",
      email: finalEmail,
      phone: finalPhone,
      fullName: fullName || normStr(inv.fullName) || "",
      employeeCode,
      passwordHash,
      isActive: true,
      plan: "free",
      premiumUntil: null,
      planUpdatedAt: null,
      employeeProvisionStatus: isEmployeeInvite ? "pending" : "not_applicable",
    });

    let userPlain = createdUser.toObject ? createdUser.toObject() : createdUser;

    if (isEmployeeInvite) {
      const ensuredOnRegister = await tryEnsureEmployeeProvision(
        userPlain,
        "registerWithInvite"
      );

      if (ensuredOnRegister?.user) {
        userPlain = ensuredOnRegister.user;
      }

      if (
        !normStr(userPlain?.staffId) &&
        normLower(userPlain?.employeeProvisionStatus) !== "ready"
      ) {
        console.log("⚠️ employee not ready yet, allow register", {
          userId: userPlain.userId,
          reason: ensuredOnRegister?.reason || "",
          skipped: !!ensuredOnRegister?.skipped,
        });
      }
    } else {
      console.log("✅ skip ensureEmployeeForUser(registerWithInvite)", {
        userId: userPlain.userId,
        role: invRole,
        reason: "not_employee",
      });
    }

    inv.usedAt = new Date();
    inv.usedByUserId = userId;
    await inv.save();

    const token = signToken(makeJwtPayload(userPlain));
    const userPayload = await buildMePayload(userPlain);

    return res.json({
      user: userPayload,
      token,
    });
  } catch (e) {
    return res.status(500).json({
      message: "registerWithInvite failed",
      error: e.message,
    });
  }
}

/* ======================================================
   RECONCILE EMPLOYEE (SELF HEAL)
====================================================== */
async function reconcileEmployeeSelf(req, res) {
  try {
    const userId = req.user?.userId;
    const clinicId = req.user?.clinicId;

    if (!userId) {
      return res.status(401).json({ message: "Missing token payload" });
    }

    let user = await User.findOne({ userId }).lean();
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const roles = normalizeRoles(user?.roles);
    const legacyRole = normalizeRole(user?.role);
    const activeRole = normalizeRole(user?.activeRole);

    const isEmployeeRole =
      roles.includes("employee") ||
      legacyRole === "employee" ||
      activeRole === "employee";

    if (!isEmployeeRole) {
      return res.json({
        ok: true,
        skipped: true,
        reason: "not_employee_role",
      });
    }

    if (normStr(user.staffId)) {
      return res.json({
        ok: true,
        skipped: true,
        reason: "already_has_staff",
        staffId: user.staffId,
      });
    }

    console.log("🧪 reconcileEmployeeSelf start:", {
      userId,
      clinicId,
    });

    const ensured = await tryEnsureEmployeeProvision(
      user,
      "reconcileEmployeeSelf"
    );

    if (ensured?.user) {
      user = ensured.user;
    }

    console.log("🧩 reconcileEmployeeSelf result:", {
      userId,
      ok: !!ensured?.ok,
      created: !!ensured?.created,
      skipped: !!ensured?.skipped,
      reason: ensured?.reason || "",
      employeeStaffId: ensured?.user?.staffId || "",
    });

    if (normStr(user?.staffId)) {
      return res.json({
        ok: true,
        created: true,
        staffId: user.staffId,
      });
    }

    return res.json({
      ok: !!ensured?.ok,
      created: false,
      skipped: true,
      reason: ensured?.reason || "not_ready",
    });
  } catch (e) {
    console.log("❌ reconcileEmployeeSelf error:", e.message);

    return res.status(500).json({
      ok: false,
      message: "reconcile failed",
      error: e.message,
    });
  }
}

/* ======================================================
   FORGOT PASSWORD
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
    const expiresAt = new Date(
      Date.now() + RESET_TOKEN_TTL_MINUTES * 60 * 1000
    );

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
    return res.status(500).json({
      message: "forgotPassword failed",
      error: e.message,
    });
  }
}

/* ======================================================
   RESET PASSWORD
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
      return res.status(400).json({
        message: "newPassword too short (>=6)",
      });
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
    return res.status(500).json({
      message: "resetPassword failed",
      error: e.message,
    });
  }
}

module.exports = {
  login,
  me,
  updateMyLocation,
  switchRole,
  registerClinicAdmin,
  registerWithInvite,
  reconcileEmployeeSelf,
  forgotPassword,
  resetPassword,
};