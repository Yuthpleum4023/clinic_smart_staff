// backend/payroll_service/routes/overtimeRoutes.js
const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const {
  listMy,
  listForStaff,
  createManual,
  updateOne,
  approveOne,
  rejectOne,
  bulkApproveMonth,
  bulkApproveDay,
  removeOne,

  // ✅ NEW: Standard user request OT
  requestOt,
} = require("../controllers/overtimeController");

// ======================================================
// ✅ STAFF / EMPLOYEE / HELPER
// ======================================================

// ------------------------------------------------------
// 1️⃣ ดู OT ของตัวเอง
// GET /overtime/my?month=yyyy-MM&status=...
// ------------------------------------------------------
router.get(
  "/my",
  auth,
  requireRole(["employee", "helper", "staff"]),
  listMy
);

// ------------------------------------------------------
// 2️⃣ NEW: STANDARD USER ส่ง OT เอง (status=pending)
// POST /overtime/request
// body: {
//   workDate: "yyyy-MM-dd",
//   start: "HH:mm",
//   end: "HH:mm",
//   multiplier?: number,
//   note?: string
// }
// ------------------------------------------------------
router.post(
  "/request",
  auth,
  requireRole(["employee", "helper", "staff"]),
  requestOt
);

// ======================================================
// ✅ ADMIN ONLY
// ======================================================

// ------------------------------------------------------
// LIST
// GET /overtime?month=yyyy-MM&principalId=...&status=...
// or legacy: &staffId=...
// ------------------------------------------------------
router.get(
  "/",
  auth,
  requireRole(["admin"]),
  listForStaff
);

// ------------------------------------------------------
// CREATE MANUAL (admin creates OT for someone)
// ------------------------------------------------------
router.post(
  "/manual",
  auth,
  requireRole(["admin"]),
  createManual
);

// ------------------------------------------------------
// BULK APPROVE
// ------------------------------------------------------
router.patch(
  "/bulk-approve/month",
  auth,
  requireRole(["admin"]),
  bulkApproveMonth
);

router.patch(
  "/bulk-approve/day",
  auth,
  requireRole(["admin"]),
  bulkApproveDay
);

// ------------------------------------------------------
// UPDATE ONE
// ------------------------------------------------------
router.patch(
  "/:id",
  auth,
  requireRole(["admin"]),
  updateOne
);

// ------------------------------------------------------
// APPROVE / REJECT
// ------------------------------------------------------
router.patch(
  "/:id/approve",
  auth,
  requireRole(["admin"]),
  approveOne
);

router.patch(
  "/:id/reject",
  auth,
  requireRole(["admin"]),
  rejectOne
);

// ------------------------------------------------------
// DELETE
// ------------------------------------------------------
router.delete(
  "/:id",
  auth,
  requireRole(["admin"]),
  removeOne
);

module.exports = router;