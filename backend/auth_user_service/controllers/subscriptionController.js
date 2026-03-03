// backend/auth_user_service/controllers/subscriptionController.js
const User = require("../models/User");
const Subscription = require("../models/Subscription");

const PLAN_ENUM = ["free", "premium"];

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

// ใช้สำหรับ admin/system เรียก "เปิด premium" ให้ user หลังรับชำระเงิน
// POST /subscription/activate
// body: { userId, months=1, externalRef?, amount?, meta? }
async function activate(req, res) {
  try {
    // ✅ ปลอดภัย: ให้ admin เรียก หรือใช้ internal key ก็ได้ (แล้วแต่ท่าน)
    const actor = s(req.user?.userId || "system");

    const userId = s(req.body?.userId);
    const months = Number(req.body?.months || 1);
    const externalRef = s(req.body?.externalRef);
    const amount = Number(req.body?.amount || 0);
    const meta = req.body?.meta || {};

    if (!userId) return res.status(400).json({ message: "userId required" });
    if (!Number.isFinite(months) || months <= 0) {
      return res.status(400).json({ message: "months must be > 0" });
    }

    const user = await User.findOne({ userId }).lean();
    if (!user) return res.status(404).json({ message: "User not found" });

    // กัน activate ซ้ำด้วย externalRef (ถ้ามี)
    let sub = await Subscription.findOne({ userId });
    if (!sub) {
      sub = await Subscription.create({
        userId,
        clinicId: s(user.clinicId),
        plan: "free",
        status: "inactive",
        startedAt: null,
        premiumUntil: null,
        externalRef: "",
        events: [],
        updatedBy: actor,
      });
    }

    if (externalRef) {
      const duplicated = (sub.events || []).some((e) => s(e.ref) === externalRef);
      if (duplicated) {
        // idempotent
        return res.json({ ok: true, message: "Already processed", subscription: sub });
      }
    }

    const now = new Date();
    const currentUntil = toDateOrNull(sub.premiumUntil);
    const base = currentUntil && currentUntil.getTime() > now.getTime() ? currentUntil : now;

    const newUntil = addMonths(base, months);

    sub.plan = "premium";
    sub.status = "active";
    sub.startedAt = sub.startedAt || now;
    sub.premiumUntil = newUntil;
    sub.externalRef = externalRef || sub.externalRef;
    sub.updatedBy = actor;

    sub.events = Array.isArray(sub.events) ? sub.events : [];
    sub.events.push({
      type: "activate",
      at: now,
      ref: externalRef,
      amount,
      meta,
    });

    await sub.save();

    // ✅ sync เข้า user ด้วย (ให้ token ส่ง isPremium ได้)
    await User.updateOne(
      { userId },
      {
        $set: {
          plan: "premium",
          premiumUntil: newUntil,
          planUpdatedAt: now,
        },
      }
    );

    return res.json({
      ok: true,
      userId,
      premiumUntil: newUntil.toISOString(),
      subscription: sub,
    });
  } catch (e) {
    return res.status(500).json({ message: "activate failed", error: e.message });
  }
}

// POST /subscription/cancel
// body: { userId?, reason? }   (ถ้าไม่ส่ง userId => cancel ของตัวเอง)
async function cancel(req, res) {
  try {
    const actor = s(req.user?.userId || "system");

    const userId = s(req.body?.userId) || s(req.user?.userId);
    const reason = s(req.body?.reason);

    if (!userId) return res.status(400).json({ message: "userId required" });

    let sub = await Subscription.findOne({ userId });
    if (!sub) {
      sub = await Subscription.create({
        userId,
        clinicId: "",
        plan: "free",
        status: "inactive",
        startedAt: null,
        premiumUntil: null,
        externalRef: "",
        events: [],
        updatedBy: actor,
      });
    }

    sub.status = "cancelled";
    sub.updatedBy = actor;
    sub.events = Array.isArray(sub.events) ? sub.events : [];
    sub.events.push({ type: "cancel", at: new Date(), ref: "", amount: 0, meta: { reason } });

    await sub.save();

    // ✅ หมายเหตุ: cancel อาจ “ไม่ตัดสิทธิ์ทันที” (ให้หมดอายุเอง)
    return res.json({ ok: true, subscription: sub });
  } catch (e) {
    return res.status(500).json({ message: "cancel failed", error: e.message });
  }
}

// GET /subscription/me
async function me(req, res) {
  try {
    const userId = s(req.user?.userId);
    if (!userId) return res.status(401).json({ message: "Unauthorized" });

    const sub = await Subscription.findOne({ userId }).lean();
    return res.json({ ok: true, subscription: sub || null });
  } catch (e) {
    return res.status(500).json({ message: "me failed", error: e.message });
  }
}

module.exports = { activate, cancel, me };