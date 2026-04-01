// payroll_service/routes/payrollCloseRoutes.js
const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/payrollCloseController");

// ======================================================
// ✅ ปิดงวด (admin เท่านั้น)
// Preferred:
// POST /payroll-close/close-month/:employeeId/:month
//
// Backward-compatible:
// POST /payroll-close/close-month
// ======================================================
router.post(
  "/close-month/:employeeId/:month",
  auth,
  requireRole(["admin"]),
  ctrl.closeMonth
);

router.post(
  "/close-month",
  auth,
  requireRole(["admin"]),
  ctrl.closeMonth
);

// ======================================================
// ✅ ดูงวดที่ปิดแล้ว (ทั้งหมดของ employeeId)
// GET /payroll-close/close-months/:employeeId
// - admin: ดูได้ทุกคน (แต่ controller ควรผูก clinicId กันข้ามคลินิก)
// - employee/staff: ดูได้เฉพาะของตัวเอง
// ======================================================
router.get(
  "/close-months/:employeeId",
  auth,
  ctrl.guardPayslipAccess,
  ctrl.getClosedMonthsByEmployee
);

// ======================================================
// ✅ ดึงงวดที่ปิดแล้ว "รายเดือน" สำหรับหน้า payslip
// GET /payroll-close/close-month/:employeeId/:month
// ตัวอย่าง: /payroll-close/close-month/stf_xxx/2026-03
// ======================================================
router.get(
  "/close-month/:employeeId/:month",
  auth,
  ctrl.guardPayslipAccess,
  ctrl.getClosedMonthByEmployeeAndMonth
);

module.exports = router;