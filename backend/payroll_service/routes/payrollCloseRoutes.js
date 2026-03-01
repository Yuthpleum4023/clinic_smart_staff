// payroll_service/routes/payrollCloseRoutes.js
const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/payrollCloseController");

// ======================================================
// ✅ ปิดงวด (admin เท่านั้น)
// POST /payroll-close/close-month
// ======================================================
router.post("/close-month", auth, requireRole(["admin"]), ctrl.closeMonth);

// ======================================================
// ✅ ดูงวดที่ปิดแล้ว
// GET /payroll-close/close-months/:employeeId
// ======================================================
router.get("/close-months/:employeeId", auth, ctrl.getClosedMonthsByEmployee);

module.exports = router;