// backend/payroll_service/routes/attendanceRoutes.js
const router = require("express").Router();
const { auth, requireRole, requireSelfStaff } = require("../middleware/auth");
const ctrl = require("../controllers/attendanceController");

// ======================================
// ✅ Premium Anti-fraud: Self-attendance only
// - ไม่ให้ admin ลงเวลาแทน
// - อนุญาต employee + helper (แต่ helper ต้องมี staffId)
// - requireSelfStaff({allowClinic:false}) จะ:
//    - เติม staffId/clinicId จาก token ให้
//    - และกันไม่ให้ spoof staffId
// ======================================

const SELF_ROLES = ["employee", "helper"];

// ✅ helper ต้องมี staffId (เพราะ attendance ทุกอย่างผูก staffId)
// - employee: ต้องมี staffId อยู่แล้ว
// - helper: บางเคสอาจไม่มี staffId -> บล็อกก่อนถึง controller (ชัดเจน + กัน error)
function requireStaffId(req, res, next) {
  const staffId = String(req.user?.staffId || "").trim();
  if (!staffId) {
    return res.status(400).json({
      ok: false,
      message: "Missing staffId in token (helper must have staffId to use attendance)",
    });
  }
  return next();
}

// check-in
router.post(
  "/check-in",
  auth,
  requireRole(SELF_ROLES),
  requireStaffId,
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkIn
);

// check-out (recommended)
router.post(
  "/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireStaffId,
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkOut
);

// backward compatible (with session id)
router.post(
  "/:id/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireStaffId,
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkOut
);

// my sessions
router.get(
  "/me",
  auth,
  requireRole(SELF_ROLES),
  requireStaffId,
  requireSelfStaff({ allowClinic: false }),
  ctrl.listMySessions
);

// optional preview
router.get(
  "/me-preview",
  auth,
  requireRole(SELF_ROLES),
  requireStaffId,
  requireSelfStaff({ allowClinic: false }),
  ctrl.myDayPreview
);

// ======================================
// ✅ admin reports (admin-only จริงๆ)
// ======================================
router.get("/clinic", auth, requireRole(["admin"]), ctrl.listClinicSessions);

module.exports = router;