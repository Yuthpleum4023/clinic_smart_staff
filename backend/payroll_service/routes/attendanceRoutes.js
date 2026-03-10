// backend/payroll_service/routes/attendanceRoutes.js
const router = require("express").Router();
const {
  auth,
  requireRole,
  requireSelfAttendance,
} = require("../middleware/auth");
const ctrl = require("../controllers/attendanceController");

// ======================================
// ✅ Self-attendance (employee + helper)
// - ห้าม admin ลงเวลาแทน
// - กัน spoof clinicId/staffId/userId
// - เติม clinicId ให้เสมอ
// - เติม staffId ให้ถ้ามี (employee มักมี, helper อาจมี/ไม่มี)
// ======================================

const SELF_ROLES = ["employee", "helper"];
const ADMIN_ROLES = ["admin", "clinic_admin"];

// =====================================================
// ✅ Self attendance
// =====================================================

// check-in
router.post(
  "/check-in",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.checkIn
);

// check-out (recommended)
router.post(
  "/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.checkOut
);

// backward compatible (with session id)
router.post(
  "/:id/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.checkOut
);

// my sessions
router.get(
  "/me",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.listMySessions
);

// today preview
router.get(
  "/me-preview",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.myDayPreview
);

// =====================================================
// ✅ Admin report
// =====================================================
router.get(
  "/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.listClinicSessions
);

module.exports = router;