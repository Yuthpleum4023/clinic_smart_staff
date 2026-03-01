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
// ✅ ดูงวดที่ปิดแล้ว (ทั้งหมดของ employeeId)
// GET /payroll-close/close-months/:employeeId
// - admin: ดูได้ทุกคนในคลินิก
// - staff: (ถ้าจะเปิดให้ดู) ต้องเป็นของตัวเองเท่านั้น -> ไปเช็คใน controller
// ======================================================
router.get("/close-months/:employeeId", auth, ctrl.getClosedMonthsByEmployee);

// ======================================================
// ✅ NEW: ดึงงวดที่ปิดแล้ว "รายเดือน" สำหรับหน้า payslip (แนะนำมาก)
// GET /payroll-close/close-month/:employeeId/:month
// ตัวอย่าง: /payroll-close/close-month/EMP001/2026-03
// ======================================================
router.get("/close-month/:employeeId/:month", auth, ctrl.getClosedMonthByEmployeeAndMonth);

module.exports = router;