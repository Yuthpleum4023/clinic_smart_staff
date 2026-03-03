// backend/payroll_service/routes/attendanceRoutes.js
const router = require("express").Router();
const { auth, requireRole, requireSelfStaff } = require("../middleware/auth");
const ctrl = require("../controllers/attendanceController");

// ======================================
// ✅ Premium Anti-fraud: Self-attendance only
// - ไม่ให้ admin/clinic ลงเวลาแทน
// - อนุญาต employee + helper (ถ้า helper มี staffId)
// - requireSelfStaff({allowClinic:false}) จะ:
//    - เติม staffId/clinicId จาก token ให้
//    - และกันไม่ให้ spoof staffId
// ======================================

const SELF_ROLES = ["employee", "helper"];

// check-in
router.post(
  "/check-in",
  auth,
  requireRole(SELF_ROLES),
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkIn
);

// check-out (recommended)
router.post(
  "/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkOut
);

// backward compatible (with session id)
router.post(
  "/:id/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkOut
);

// my sessions
router.get(
  "/me",
  auth,
  requireRole(SELF_ROLES),
  requireSelfStaff({ allowClinic: false }),
  ctrl.listMySessions
);

// optional preview
router.get(
  "/me-preview",
  auth,
  requireRole(SELF_ROLES),
  requireSelfStaff({ allowClinic: false }),
  ctrl.myDayPreview
);

// ======================================
// admin reports
// NOTE: ถ้าจะให้คลินิกดูรายงาน เปิดไว้ได้
// ======================================
router.get("/clinic", auth, requireRole(["admin"]), ctrl.listClinicSessions);

module.exports = router;