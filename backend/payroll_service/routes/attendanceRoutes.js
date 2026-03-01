// backend/payroll_service/routes/attendanceRoutes.js
const router = require("express").Router();
const { auth, requireRole } = require("../middleware/auth");

const ctrl = require("../controllers/attendanceController");

// staff/employee
router.post("/check-in", auth, ctrl.checkIn);
router.post("/:id/check-out", auth, ctrl.checkOut);

router.get("/me", auth, ctrl.listMySessions);

// ✅ optional: วันเดียว + ค่าจ้าง/OT preview (ดึง staff_service)
router.get("/me-preview", auth, ctrl.myDayPreview);

// admin
router.get("/clinic", auth, requireRole(["admin"]), ctrl.listClinicSessions);

module.exports = router;