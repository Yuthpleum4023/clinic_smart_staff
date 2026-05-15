// backend/auth_user_service/routes/subscriptionRoutes.js
//
// ✅ PRODUCTION SUBSCRIPTION ROUTES — CLINIC LEVEL
// ------------------------------------------------------
// ✅ Premium belongs to clinicId, not employee/helper user.
// ✅ Controller handles role/security checks internally.
// ✅ This route supports:
//    - Authenticated user checking own clinic subscription
//    - Admin/clinic owner/system activating/cancelling
//    - Internal service checking subscription by clinicId
//
// Routes:
// GET  /subscription/me
// GET  /subscription/check?clinicId=cln_xxx
// POST /subscription/activate
// POST /subscription/cancel
//

const router = require("express").Router();
const ctrl = require("../controllers/subscriptionController");

const { auth } = require("../middleware/auth");

function s(v) {
  return String(v || "").trim();
}

function isInternalRequest(req) {
  const expected = s(process.env.INTERNAL_SERVICE_KEY);
  if (!expected) return false;

  const k1 = s(req.headers?.["x-internal-service-key"]);
  const k2 = s(req.headers?.["x-internal-key"]);
  const k3 = s(req.headers?.["internal-service-key"]);

  return [k1, k2, k3].some((v) => v && v === expected);
}

// ✅ Allow either:
// - normal authenticated user via JWT
// - internal service via INTERNAL_SERVICE_KEY
function authOrInternal(req, res, next) {
  if (isInternalRequest(req)) {
    req.user = {
      userId: "system",
      role: "system",
    };
    return next();
  }

  return auth(req, res, next);
}

// ✅ ดู subscription ของคลินิกตัวเอง
// employee/admin ที่ผูก clinicId จะเห็นสถานะของ clinic นั้น
// helper ที่ไม่มี clinicId ถาวรอาจได้ free/null
router.get("/me", auth, ctrl.me);

// ✅ internal/admin check by clinicId
// ใช้สำหรับ payroll_service / attendanceController / helper shift context
router.get("/check", authOrInternal, ctrl.check);

// ✅ เปิด Premium ให้คลินิก
// body preferred:
// {
//   clinicId,
//   months,
//   externalRef,
//   amount,
//   meta
// }
//
// หมายเหตุ:
// ไม่ใส่ requireRole ตรง route เพื่อไม่ให้ role clinic_owner/clinic_admin ถูกบล็อกผิด
// controller จะเป็นคนเช็กสิทธิ์ละเอียดเอง
router.post("/activate", authOrInternal, ctrl.activate);

// ✅ ยกเลิก Premium ของคลินิก
router.post("/cancel", authOrInternal, ctrl.cancel);

module.exports = router;