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

  // ✅ Standard user request OT
  requestOt,
} = require("../controllers/overtimeController");

// ======================================================
// Roles
// ======================================================

const SELF_ROLES = ["employee", "helper", "staff", "admin", "clinic_admin"];
const ADMIN_ROLES = ["admin", "clinic_admin"];

// ======================================================
// SELF VIEW / SELF REQUEST
// ======================================================

// ------------------------------------------------------
// 1) ดู OT ของตัวเอง
// GET /overtime/my?month=yyyy-MM&status=...
// ------------------------------------------------------
router.get("/my", auth, requireRole(SELF_ROLES), listMy);

// ------------------------------------------------------
// 2) STANDARD USER ส่ง OT เอง (status=pending)
// POST /overtime/request
// ------------------------------------------------------
router.post("/request", auth, requireRole(SELF_ROLES), requestOt);

// ======================================================
// ADMIN / CLINIC ADMIN
// ======================================================

// ------------------------------------------------------
// LIST
// GET /overtime?month=yyyy-MM&principalId=...&status=...
// or legacy: &staffId=...
// ------------------------------------------------------
router.get("/", auth, requireRole(ADMIN_ROLES), listForStaff);

// ------------------------------------------------------
// CREATE MANUAL (admin creates OT for someone)
// ------------------------------------------------------
router.post("/manual", auth, requireRole(ADMIN_ROLES), createManual);

// ------------------------------------------------------
// BULK APPROVE
// ------------------------------------------------------
router.patch(
  "/bulk-approve/month",
  auth,
  requireRole(ADMIN_ROLES),
  bulkApproveMonth
);

router.patch(
  "/bulk-approve/day",
  auth,
  requireRole(ADMIN_ROLES),
  bulkApproveDay
);

// ------------------------------------------------------
// UPDATE ONE
// ------------------------------------------------------
router.patch("/:id", auth, requireRole(ADMIN_ROLES), updateOne);

// ------------------------------------------------------
// APPROVE / REJECT
// ------------------------------------------------------
router.patch("/:id/approve", auth, requireRole(ADMIN_ROLES), approveOne);
router.patch("/:id/reject", auth, requireRole(ADMIN_ROLES), rejectOne);

// ------------------------------------------------------
// DELETE
// ------------------------------------------------------
router.delete("/:id", auth, requireRole(ADMIN_ROLES), removeOne);

module.exports = router;