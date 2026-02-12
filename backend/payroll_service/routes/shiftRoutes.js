// payroll_service/routes/shiftRoutes.js
const router = require("express").Router();
const auth = require("../middleware/auth");
const ctrl = require("../controllers/shiftController");

// สร้างกะ (admin)
router.post("/", auth, ctrl.createShift);

// list กะ
router.get("/", auth, ctrl.listShifts);

// เปลี่ยนสถานะกะ (admin)
router.patch("/:id/status", auth, ctrl.updateShiftStatus);

// ลบกะ (admin)
router.delete("/:id", auth, ctrl.deleteShift);

module.exports = router;
