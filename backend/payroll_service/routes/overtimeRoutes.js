// backend/payroll_service/routes/overtimeRoutes.js
const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const {
  // ✅ Staff (read-only)
  listMy,

  // ✅ Admin
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
// ✅ STAFF (READ-ONLY)
// - พนักงานดู OT ของตัวเองได้ (โปร่งใส + ช่วยขาย Premium)
// - GET /overtime/my?month=yyyy-MM&status=pending|approved|rejected|locked(optional)
// ======================================================
router.get("/my", auth, requireRole(["staff"]), listMy);

// ======================================================
// ✅ ADMIN ONLY (ตามที่เราออกแบบ)
// ======================================================

// LIST
// GET /overtime?month=yyyy-MM&staffId=...&status=pending|approved|rejected|locked(optional)
router.get("/", auth, requireRole(["admin"]), listForStaff);

// CREATE MANUAL
// POST /overtime/manual
router.post("/manual", auth, requireRole(["admin"]), createManual);

// BULK APPROVE (ต้องมาก่อน /:id เพื่อกัน route ชนกัน)
// PATCH /overtime/bulk-approve/month  { staffId, month }
router.patch("/bulk-approve/month", auth, requireRole(["admin"]), bulkApproveMonth);

// PATCH /overtime/bulk-approve/day  { staffId, workDate }
router.patch("/bulk-approve/day", auth, requireRole(["admin"]), bulkApproveDay);

// UPDATE ONE
// PATCH /overtime/:id   { minutes?, multiplier?, note? }
router.patch("/:id", auth, requireRole(["admin"]), updateOne);

// APPROVE / REJECT
// PATCH /overtime/:id/approve
router.patch("/:id/approve", auth, requireRole(["admin"]), approveOne);

// PATCH /overtime/:id/reject  { reason? }
router.patch("/:id/reject", auth, requireRole(["admin"]), rejectOne);

// DELETE (manual only in controller)
// DELETE /overtime/:id
router.delete("/:id", auth, requireRole(["admin"]), removeOne);

module.exports = router;