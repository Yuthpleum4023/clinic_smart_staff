// payroll_service/routes/shiftRoutes.js
const router = require("express").Router();
const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/shiftController");

// สร้างกะ (admin)
router.post("/", auth, requireRole(["admin"]), ctrl.createShift);

// list กะ (login ทุก role ได้)
router.get("/", auth, ctrl.listShifts);

// เปลี่ยนสถานะกะ (admin)
router.patch("/:id/status", auth, requireRole(["admin"]), ctrl.updateShiftStatus);

// ลบกะ (admin)
router.delete("/:id", auth, requireRole(["admin"]), ctrl.deleteShift);

module.exports = router;