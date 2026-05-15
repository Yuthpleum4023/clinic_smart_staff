// backend/auth_user_service/controllers/subscriptionController.js
//
// ✅ PRODUCTION SUBSCRIPTION CONTROLLER — CLINIC LEVEL
// ------------------------------------------------------
// ✅ Core rule:
// - Premium belongs to "clinicId", NOT individual employee/helper user.
// - Clinic/admin/system activates premium for the clinic.
// - Employee uses premium through their linked clinicId.
// - Helper should use premium through the clinicId of the shift they are working on.
// - Employee/helper should NOT buy or activate premium by themselves.
//
// ✅ Supports:
// - POST /subscription/activate
// - POST /subscription/cancel
// - GET  /subscription/me
// - GET  /subscription/check?clinicId=xxx   (optional/internal use)
//
// ✅ Good for launch promotion:
// - body.months = 2
// - amount = 0
// - meta.campaign = "clinic_launch_free_60_days"
//
// IMPORTANT:
// This controller expects Subscription model to be clinic-level:
// - clinicId required + unique
// - ownerUserId optional
// - userId legacy only
//

const User = require("../models/User");
const Subscription = require("../models/Subscription");

const PLAN_ENUM = ["free", "premium"];
const ACTIVE_LIKE_STATUSES = ["active", "cancelled"];

function s(v) {
  return String(v || "").trim();
}

function lower(v) {
  return s(v).toLowerCase();
}

function normalizePlan(v) {
  const p = lower(v);
  return PLAN_ENUM.includes(p) ? p : "free";
}

function toDateOrNull(v) {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return Number.isFinite(d.getTime()) ? d : null;
}

function addMonths(date, months) {
  const d = new Date(date.getTime());
  d.setMonth(d.getMonth() + months);
  return d;
}

function daysLeftUntil(date) {
  const d = toDateOrNull(date);
  if (!d) return 0;

  const diff = d.getTime() - Date.now();
  if (diff <= 0) return 0;

  return Math.ceil(diff / (24 * 60 * 60 * 1000));
}

function getReqUserId(req) {
  return s(
    req.user?.userId ||
      req.user?.id ||
      req.user?._id ||
      req.auth?.userId ||
      ""
  );
}

function getReqClinicId(req) {
  return s(
    req.user?.clinicId ||
      req.user?.clinic?.clinicId ||
      req.user?.clinic?._id ||
      req.auth?.clinicId ||
      ""
  );
}

function getReqRole(req) {
  return lower(
    req.user?.role ||
      req.user?.userRole ||
      req.user?.type ||
      req.user?.accountType ||
      ""
  );
}

function isInternalRequest(req) {
  const expected = s(process.env.INTERNAL_SERVICE_KEY);
  if (!expected) return false;

  const k1 = s(req.headers?.["x-internal-service-key"]);
  const k2 = s(req.headers?.["x-internal-key"]);
  const k3 = s(req.headers?.["internal-service-key"]);

  return [k1, k2, k3].some((v) => v && v === expected);
}

function isPrivilegedActor(req) {
  if (isInternalRequest(req)) return true;

  const role = getReqRole(req);

  return [
    "admin",
    "super_admin",
    "system",
    "owner",
    "clinic_owner",
    "clinic_admin",
    "clinic",
  ].includes(role);
}

function isEmployeeOrHelper(req) {
  const role = getReqRole(req);

  return [
    "employee",
    "helper",
    "staff",
    "clinic_staff",
    "parttime",
    "part_time",
  ].includes(role);
}

async function findUserByUserId(userId) {
  const id = s(userId);
  if (!id) return null;

  return User.findOne({ userId: id }).lean();
}

function buildPremiumSummary(sub) {
  const now = new Date();

  const premiumUntil = toDateOrNull(sub?.premiumUntil);
  const biometricUntil = toDateOrNull(
    sub?.features?.biometricAttendance?.premiumUntil
  );

  const status = lower(sub?.status);
  const plan = normalizePlan(sub?.plan);

  const mainActive =
    plan === "premium" &&
    ACTIVE_LIKE_STATUSES.includes(status) &&
    premiumUntil &&
    premiumUntil.getTime() > now.getTime();

  // ถ้าไม่มี feature object ให้ถือว่า biometric ใช้ตาม premium หลัก
  const biometricStatus = lower(
    sub?.features?.biometricAttendance?.status || "enabled"
  );

  const biometricActive =
    !!mainActive &&
    biometricStatus === "enabled" &&
    (!biometricUntil || biometricUntil.getTime() > now.getTime());

  return {
    plan: mainActive ? "premium" : "free",
    status: s(sub?.status || "inactive"),
    isPremiumActive: !!mainActive,

    // ✅ ตัวนี้ให้ Flutter / payroll_service ใช้ตัดสิน feature สแกนนิ้ว
    biometricAttendanceEnabled: !!biometricActive,

    premiumUntil: premiumUntil ? premiumUntil.toISOString() : null,
    biometricAttendanceUntil: biometricUntil
      ? biometricUntil.toISOString()
      : premiumUntil
      ? premiumUntil.toISOString()
      : null,

    daysLeft: daysLeftUntil(premiumUntil),
  };
}

function emptyPremiumSummary() {
  return {
    plan: "free",
    status: "inactive",
    isPremiumActive: false,
    biometricAttendanceEnabled: false,
    premiumUntil: null,
    biometricAttendanceUntil: null,
    daysLeft: 0,
  };
}

async function resolveClinicContext(req, options = {}) {
  const {
    allowBodyClinicId = false,
    allowQueryClinicId = false,
    allowUserFallback = true,
  } = options;

  const tokenUserId = getReqUserId(req);
  const tokenClinicId = getReqClinicId(req);

  const bodyClinicId = allowBodyClinicId ? s(req.body?.clinicId) : "";
  const queryClinicId = allowQueryClinicId ? s(req.query?.clinicId) : "";

  const bodyUserId = s(req.body?.userId);
  const ownerUserIdFromBody = s(req.body?.ownerUserId);

  let clinicId = bodyClinicId || queryClinicId || tokenClinicId;
  let ownerUserId = ownerUserIdFromBody || bodyUserId || tokenUserId;
  let user = null;

  // Legacy fallback:
  // ถ้าระบบเก่าส่ง userId มา แต่ยังไม่ส่ง clinicId ให้หา clinicId จาก User
  if (!clinicId && allowUserFallback && bodyUserId) {
    user = await findUserByUserId(bodyUserId);
    clinicId = s(user?.clinicId);
    ownerUserId = ownerUserId || s(user?.userId);
  }

  // Fallback สำหรับ /subscription/me:
  // token มี userId แต่ไม่มี clinicId
  if (!clinicId && allowUserFallback && tokenUserId) {
    user = await findUserByUserId(tokenUserId);
    clinicId = s(user?.clinicId);
    ownerUserId = ownerUserId || s(user?.userId);
  }

  return {
    clinicId,
    ownerUserId,
    tokenUserId,
    user,
  };
}

async function maybeMarkExpired(sub) {
  if (!sub) return sub;

  const premiumUntil = toDateOrNull(sub.premiumUntil);
  const status = lower(sub.status);

  if (
    premiumUntil &&
    premiumUntil.getTime() <= Date.now() &&
    ["active", "cancelled"].includes(status)
  ) {
    sub.status = "expired";
    sub.plan = "free";
    sub.updatedBy = "system";

    sub.events = Array.isArray(sub.events) ? sub.events : [];
    sub.events.push({
      type: "expire",
      at: new Date(),
      ref: "",
      amount: 0,
      meta: {
        reason: "premiumUntil passed",
        scope: "clinic",
        clinicId: s(sub.clinicId),
      },
    });

    await sub.save();
  }

  return sub;
}

/**
 * POST /subscription/activate
 *
 * ใช้สำหรับ admin/system เรียกเปิด Premium ให้ "คลินิก"
 *
 * body:
 * {
 *   clinicId,          // ✅ preferred
 *   userId?,           // legacy fallback: ใช้หา clinicId จาก user
 *   ownerUserId?,
 *   months: 2,
 *   externalRef?,
 *   amount?,
 *   meta?
 * }
 */
async function activate(req, res) {
  try {
    // ✅ พนักงาน/helper ห้ามเปิดสิทธิ์เอง
    if (isEmployeeOrHelper(req) && !isInternalRequest(req)) {
      return res.status(403).json({
        message: "Employee/helper cannot activate clinic premium",
      });
    }

    // ✅ ต้องเป็น admin/clinic owner/system/internal เท่านั้น
    if (!isPrivilegedActor(req)) {
      return res.status(403).json({
        message: "Only clinic owner/admin/system can activate subscription",
      });
    }

    const actor = getReqUserId(req) || "system";

    const { clinicId, ownerUserId } = await resolveClinicContext(req, {
      allowBodyClinicId: true,
      allowQueryClinicId: false,
      allowUserFallback: true,
    });

    const months = Number(req.body?.months || 1);
    const externalRef = s(req.body?.externalRef);
    const amount = Number(req.body?.amount || 0);
    const meta = req.body?.meta && typeof req.body.meta === "object" ? req.body.meta : {};

    if (!clinicId) {
      return res.status(400).json({
        message: "clinicId required",
      });
    }

    if (!Number.isFinite(months) || months <= 0) {
      return res.status(400).json({
        message: "months must be > 0",
      });
    }

    // ✅ กัน payment/webhook/admin action ref เดียวกันถูกใช้กับคลินิกอื่น
    if (externalRef) {
      const existingByRef = await Subscription.findOne({
        "events.ref": externalRef,
      });

      if (existingByRef) {
        const existingClinicId = s(existingByRef.clinicId);

        if (existingClinicId && existingClinicId !== clinicId) {
          return res.status(409).json({
            ok: false,
            message: "externalRef already used by another clinic",
            clinicId: existingClinicId,
          });
        }

        return res.json({
          ok: true,
          message: "Already processed",
          clinicId,
          premium: buildPremiumSummary(existingByRef),
          subscription: existingByRef,
        });
      }
    }

    let sub = await Subscription.findOne({ clinicId });

    if (!sub) {
      sub = await Subscription.create({
        clinicId,
        ownerUserId: ownerUserId || actor,
        userId: ownerUserId || actor, // legacy only
        plan: "free",
        status: "inactive",
        startedAt: null,
        premiumUntil: null,
        features: {
          biometricAttendance: {
            status: "enabled",
            startedAt: null,
            premiumUntil: null,
          },
        },
        externalRef: "",
        events: [],
        updatedBy: actor,
      });
    }

    const now = new Date();
    const currentUntil = toDateOrNull(sub.premiumUntil);
    const base =
      currentUntil && currentUntil.getTime() > now.getTime()
        ? currentUntil
        : now;

    const newUntil = addMonths(base, months);

    sub.clinicId = clinicId;
    sub.ownerUserId = sub.ownerUserId || ownerUserId || actor;
    sub.userId = sub.userId || ownerUserId || actor; // legacy only

    sub.plan = "premium";
    sub.status = "active";
    sub.startedAt = sub.startedAt || now;
    sub.premiumUntil = newUntil;
    sub.externalRef = externalRef || sub.externalRef;
    sub.updatedBy = actor;

    sub.features = sub.features || {};
    sub.features.biometricAttendance = {
      status: "enabled",
      startedAt:
        sub.features?.biometricAttendance?.startedAt ||
        sub.startedAt ||
        now,
      premiumUntil: newUntil,
    };

    sub.events = Array.isArray(sub.events) ? sub.events : [];
    sub.events.push({
      type: "activate",
      at: now,
      ref: externalRef,
      amount: Number.isFinite(amount) ? amount : 0,
      meta: {
        ...meta,
        scope: "clinic",
        clinicId,
        feature: meta.feature || "biometric_attendance",
      },
    });

    await sub.save();

    // ✅ legacy sync เพื่อให้ user ในคลินิกมีข้อมูลประกอบ
    // แต่ "ห้าม" ใช้ user.plan เป็นตัวตัดสินสิทธิ์หลักอีกต่อไป
    await User.updateMany(
      { clinicId },
      {
        $set: {
          clinicPlan: "premium",
          clinicPremiumUntil: newUntil,
          planUpdatedAt: now,
        },
      }
    ).catch(() => null);

    return res.json({
      ok: true,
      scope: "clinic",
      clinicId,
      ownerUserId: sub.ownerUserId,
      premiumUntil: newUntil.toISOString(),
      premium: buildPremiumSummary(sub),
      subscription: sub,
    });
  } catch (e) {
    return res.status(500).json({
      message: "activate failed",
      error: e.message,
    });
  }
}

/**
 * POST /subscription/cancel
 *
 * body:
 * {
 *   clinicId,          // ✅ preferred
 *   userId?,           // legacy fallback
 *   reason?,
 *   immediate?: true   // true = ตัดสิทธิ์ทันที, ไม่ส่ง = ใช้ได้จนหมดอายุ
 * }
 */
async function cancel(req, res) {
  try {
    // ✅ พนักงาน/helper ห้าม cancel เอง
    if (isEmployeeOrHelper(req) && !isInternalRequest(req)) {
      return res.status(403).json({
        message: "Employee/helper cannot cancel clinic premium",
      });
    }

    if (!isPrivilegedActor(req)) {
      return res.status(403).json({
        message: "Only clinic owner/admin/system can cancel subscription",
      });
    }

    const actor = getReqUserId(req) || "system";

    const { clinicId } = await resolveClinicContext(req, {
      allowBodyClinicId: true,
      allowQueryClinicId: false,
      allowUserFallback: true,
    });

    const reason = s(req.body?.reason);
    const immediate = req.body?.immediate === true;

    if (!clinicId) {
      return res.status(400).json({
        message: "clinicId required",
      });
    }

    let sub = await Subscription.findOne({ clinicId });

    if (!sub) {
      sub = await Subscription.create({
        clinicId,
        ownerUserId: actor,
        userId: actor, // legacy only
        plan: "free",
        status: "inactive",
        startedAt: null,
        premiumUntil: null,
        features: {
          biometricAttendance: {
            status: "disabled",
            startedAt: null,
            premiumUntil: null,
          },
        },
        externalRef: "",
        events: [],
        updatedBy: actor,
      });
    }

    const now = new Date();

    sub.status = "cancelled";
    sub.updatedBy = actor;

    // default: cancel แล้วให้ใช้ต่อจนหมดอายุ
    // immediate=true: ตัดสิทธิ์ทันที
    if (immediate) {
      sub.plan = "free";
      sub.premiumUntil = now;

      sub.features = sub.features || {};
      sub.features.biometricAttendance = {
        status: "disabled",
        startedAt: sub.features?.biometricAttendance?.startedAt || null,
        premiumUntil: now,
      };
    }

    sub.events = Array.isArray(sub.events) ? sub.events : [];
    sub.events.push({
      type: "cancel",
      at: now,
      ref: "",
      amount: 0,
      meta: {
        reason,
        immediate,
        scope: "clinic",
        clinicId,
      },
    });

    await sub.save();

    if (immediate) {
      await User.updateMany(
        { clinicId },
        {
          $set: {
            clinicPlan: "free",
            clinicPremiumUntil: now,
            planUpdatedAt: now,
          },
        }
      ).catch(() => null);
    }

    return res.json({
      ok: true,
      scope: "clinic",
      clinicId,
      premium: buildPremiumSummary(sub),
      subscription: sub,
    });
  } catch (e) {
    return res.status(500).json({
      message: "cancel failed",
      error: e.message,
    });
  }
}

/**
 * GET /subscription/me
 *
 * ใช้กับ user ที่ login อยู่
 * - admin/employee ที่มี clinicId ใน token/user จะได้สถานะของคลินิกตัวเอง
 * - helper ถ้าไม่มี clinicId ถาวร จะได้ free/null
 *
 * หมายเหตุ:
 * - helper ที่รับ shift ของคลินิก ต้องให้ payroll/shift service เช็กจาก shift.clinicId
 *   แล้วเรียก /subscription/check?clinicId=xxx ด้วย internal key
 */
async function me(req, res) {
  try {
    const userId = getReqUserId(req);

    if (!userId) {
      return res.status(401).json({
        message: "Unauthorized",
      });
    }

    const { clinicId } = await resolveClinicContext(req, {
      allowBodyClinicId: false,
      allowQueryClinicId: false,
      allowUserFallback: true,
    });

    if (!clinicId) {
      return res.json({
        ok: true,
        scope: "clinic",
        clinicId: "",
        subscription: null,
        premium: emptyPremiumSummary(),
      });
    }

    let sub = await Subscription.findOne({ clinicId });

    if (sub) {
      sub = await maybeMarkExpired(sub);
    }

    const leanSub = sub ? sub.toObject() : null;

    return res.json({
      ok: true,
      scope: "clinic",
      clinicId,
      subscription: leanSub,
      premium: buildPremiumSummary(leanSub),
    });
  } catch (e) {
    return res.status(500).json({
      message: "me failed",
      error: e.message,
    });
  }
}

/**
 * GET /subscription/check?clinicId=xxx
 *
 * ใช้สำหรับ service อื่น เช่น payroll_service / attendanceController
 * โดยเฉพาะกรณี helper:
 * - payroll_service รู้ shiftId
 * - payroll_service หา shift.clinicId
 * - payroll_service เรียก endpoint นี้ด้วย INTERNAL_SERVICE_KEY
 *
 * ไม่ควรให้ employee/helper เรียกเช็ก clinicId อื่นเอง
 */
async function check(req, res) {
  try {
    if (!isInternalRequest(req) && !isPrivilegedActor(req)) {
      return res.status(403).json({
        message: "Internal/admin only",
      });
    }

    const clinicId = s(req.query?.clinicId || req.params?.clinicId);

    if (!clinicId) {
      return res.status(400).json({
        message: "clinicId required",
      });
    }

    let sub = await Subscription.findOne({ clinicId });

    if (sub) {
      sub = await maybeMarkExpired(sub);
    }

    const leanSub = sub ? sub.toObject() : null;

    return res.json({
      ok: true,
      scope: "clinic",
      clinicId,
      subscription: leanSub,
      premium: buildPremiumSummary(leanSub),
    });
  } catch (e) {
    return res.status(500).json({
      message: "check failed",
      error: e.message,
    });
  }
}

module.exports = {
  activate,
  cancel,
  me,
  check,
};