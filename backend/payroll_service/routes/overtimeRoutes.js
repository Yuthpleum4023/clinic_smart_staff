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
} = require("../controllers/overtimeController");

// ======================================================
// ✅ STAFF / EMPLOYEE / HELPER (READ-ONLY)
// - ดู OT ของตัวเองได้
// - GET /overtime/my?month=yyyy-MM&status=...
// ======================================================
router.get(
  "/my",
  auth,
  requireRole(["employee", "helper", "staff"]),
  listMy
);

// ======================================================
// ✅ ADMIN ONLY
// ======================================================

// LIST
// GET /overtime?month=yyyy-MM&principalId=...&status=...
// or legacy: &staffId=...
router.get("/", auth, requireRole(["admin"]), listForStaff);

// CREATE MANUAL
router.post("/manual", auth, requireRole(["admin"]), createManual);

// BULK APPROVE
router.patch("/bulk-approve/month", auth, requireRole(["admin"]), bulkApproveMonth);
router.patch("/bulk-approve/day", auth, requireRole(["admin"]), bulkApproveDay);

// UPDATE ONE
router.patch("/:id", auth, requireRole(["admin"]), updateOne);

// APPROVE / REJECT
router.patch("/:id/approve", auth, requireRole(["admin"]), approveOne);
router.patch("/:id/reject", auth, requireRole(["admin"]), rejectOne);

// DELETE
router.delete("/:id", auth, requireRole(["admin"]), removeOne);

module.exports = router;