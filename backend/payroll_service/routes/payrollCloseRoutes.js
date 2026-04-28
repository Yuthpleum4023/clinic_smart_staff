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
// ✅ คำนวณงวดที่ปิดแล้วใหม่ / Re-close month (admin เท่านั้น)
//
// ใช้กรณี:
// - admin เผลอปิดงวดก่อนสิ้นเดือน
// - มี attendance / OT / deduction / allowance เปลี่ยนหลังปิดงวด
//
// POST /payroll-close/recalculate/:employeeId/:month
//
// body optional:
// {
//   "grossBase": 16000,
//   "bonus": 0,
//   "otherAllowance": 0,
//   "otherDeduction": 0,
//   "pvdEmployeeMonthly": 0,
//   "taxMode": "WITHHOLDING"
// }
//
// ถ้าไม่ส่ง body บางค่า ระบบจะใช้ค่าจาก PayrollClose เดิม
// และคำนวณ OT ใหม่จาก approved OT ล่าสุด
// ======================================================
router.post(
  "/recalculate/:employeeId/:month",
  auth,
  requireRole(["admin"]),
  ctrl.recalculateClosedMonth
);

// ======================================================
// ✅ ดูงวดที่ปิดแล้ว (ทั้งหมดของ employeeId)
// GET /payroll-close/close-months/:employeeId
// - admin: ดูได้ทุกคนใน clinic
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