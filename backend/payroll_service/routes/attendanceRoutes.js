const router = require("express").Router();

const {
  auth,
  requireRole,
  requireSelfAttendance,
} = require("../middleware/auth");

const ctrl = require("../controllers/attendanceController");

// ======================================
// Roles
// ======================================

const SELF_ROLES = ["employee", "helper"];
const ADMIN_ROLES = ["admin", "clinic_admin"];

// =====================================================
// SELF ATTENDANCE (employee + helper)
// =====================================================

// -------------------------------
// CHECK-IN
// -------------------------------
router.post(
  "/check-in",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.checkIn
);

// -------------------------------
// CHECK-OUT (recommended)
// -------------------------------
router.post(
  "/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.checkOut
);

// backward compatible
router.post(
  "/:id/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.checkOut
);

// =====================================================
// MANUAL ATTENDANCE REQUEST (SELF)
// =====================================================

// submit manual attendance request
router.post(
  "/manual-request",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.submitManualRequest
);

// list my manual requests
router.get(
  "/manual-request/my",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  ctrl.listMyManualRequests
);

// =====================================================
// MY ATTENDANCE
// =====================================================

// my sessions history
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
// ADMIN / CLINIC ATTENDANCE
// =====================================================

// clinic attendance sessions
router.get(
  "/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.listClinicSessions
);

// clinic manual request queue
router.get(
  "/manual-request/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.listClinicManualRequests
);

// approve manual request
router.post(
  "/manual-request/:id/approve",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.approveManualRequest
);

// reject manual request
router.post(
  "/manual-request/:id/reject",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.rejectManualRequest
);

module.exports = router;