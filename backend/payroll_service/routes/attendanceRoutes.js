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

// =====================================================
// ✅ Self manual request flow
// =====================================================

// submit manual attendance request
router.post(
  "/manual-request",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.submitManualRequest
);

// list my manual attendance requests
router.get(
  "/manual-request/my",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.listMyManualRequests
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
// ✅ Admin report / manual approval flow
// =====================================================

// attendance sessions report
router.get(
  "/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.listClinicSessions
);

// list clinic manual attendance queue
router.get(
  "/manual-request/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.listClinicManualRequests
);

// approve manual attendance request
router.post(
  "/manual-request/:id/approve",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.approveManualRequest
);

// reject manual attendance request
router.post(
  "/manual-request/:id/reject",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.rejectManualRequest
);

module.exports = router;