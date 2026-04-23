const router = require("express").Router();

const {
  auth,
  requireRole,
  requireSelfAttendance,
} = require("../middleware/auth");

const ctrl = require("../controllers/attendanceController");
const analytics = require("../controllers/attendanceAnalyticsController");

// ======================================
// Roles
// ======================================

// ✅ production-safe:
// attendanceController รองรับ employee / staff / helper
// route จึงควรปล่อย staff ผ่านด้วย
const SELF_ROLES = ["employee", "staff", "helper"];
const ADMIN_ROLES = ["admin", "clinic_admin"];

// ======================================
// Safe handler helpers
// ======================================

function notImplemented(name) {
  return (req, res) => {
    return res.status(501).json({
      ok: false,
      code: "NOT_IMPLEMENTED",
      message: `${name} is not implemented in attendanceController`,
    });
  };
}

function useHandler(handler, name) {
  return typeof handler === "function" ? handler : notImplemented(name);
}

// backward-compatible aliases
const listMySessions =
  typeof ctrl.listMySessions === "function"
    ? ctrl.listMySessions
    : typeof ctrl.listAttendance === "function"
    ? ctrl.listAttendance
    : notImplemented("listMySessions/listAttendance");

const myDayPreview =
  typeof ctrl.myDayPreview === "function"
    ? ctrl.myDayPreview
    : notImplemented("myDayPreview");

const listClinicSessions =
  typeof ctrl.listClinicSessions === "function"
    ? ctrl.listClinicSessions
    : notImplemented("listClinicSessions");

const rejectManualRequest =
  typeof ctrl.rejectManualRequest === "function"
    ? ctrl.rejectManualRequest
    : typeof ctrl.approveManualRequest === "function"
    ? (req, res, next) => {
        req.body = {
          ...(req.body || {}),
          action: "reject",
        };
        return ctrl.approveManualRequest(req, res, next);
      }
    : notImplemented("rejectManualRequest/approveManualRequest");

// =====================================================
// SELF ATTENDANCE (employee + staff + helper)
// =====================================================

// CHECK-IN
router.post(
  "/check-in",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  useHandler(ctrl.checkIn, "checkIn")
);

// CHECK-OUT
router.post(
  "/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  useHandler(ctrl.checkOut, "checkOut")
);

// backward compatible
router.post(
  "/:id/check-out",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  useHandler(ctrl.checkOut, "checkOut")
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
  useHandler(ctrl.submitManualRequest, "submitManualRequest")
);

// list my manual requests
router.get(
  "/manual-request/my",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  useHandler(ctrl.listMyManualRequests, "listMyManualRequests")
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
  listMySessions
);

// today preview
router.get(
  "/me-preview",
  auth,
  requireRole(SELF_ROLES),
  requireSelfAttendance(),
  myDayPreview
);

// =====================================================
// ADMIN / CLINIC ATTENDANCE
// =====================================================

// clinic attendance sessions
router.get(
  "/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  listClinicSessions
);

// clinic manual request queue
router.get(
  "/manual-request/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  useHandler(ctrl.listClinicManualRequests, "listClinicManualRequests")
);

// approve manual request
router.post(
  "/manual-request/:id/approve",
  auth,
  requireRole(ADMIN_ROLES),
  useHandler(ctrl.approveManualRequest, "approveManualRequest")
);

// reject manual request
router.post(
  "/manual-request/:id/reject",
  auth,
  requireRole(ADMIN_ROLES),
  rejectManualRequest
);

// =====================================================
// ATTENDANCE ANALYTICS (ADMIN / HR DASHBOARD)
// =====================================================

// clinic attendance analytics
router.get(
  "/analytics/clinic",
  auth,
  requireRole(ADMIN_ROLES),
  useHandler(analytics?.clinicAnalytics, "analytics.clinicAnalytics")
);

// staff attendance analytics
router.get(
  "/analytics/staff/:principalId",
  auth,
  requireRole(ADMIN_ROLES),
  useHandler(analytics?.staffAnalytics, "analytics.staffAnalytics")
);

module.exports = router;