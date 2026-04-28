// payroll_service/routes/payrollCloseRoutes.js
const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/payrollCloseController");

// ======================================================
// ✅ Payroll Preview (admin เท่านั้น)
//
// ใช้สำหรับ Flutter แสดงตัวเลขจาก backend เท่านั้น
// Flutter ห้ามคำนวณเงินเดือนเอง
//
// Preferred:
// POST /payroll-close/preview/:employeeId/:month
//
// body optional:
// {
//   "clinicId": "cln_xxx",
//   "bonus": 0,
//   "otherAllowance": 0,
//   "otherDeduction": 0,
//   "pvdEmployeeMonthly": 0,
//   "taxMode": "WITHHOLDING",
//   "employeeUserId": "usr_xxx",
//
//   // สำหรับ part-time ในอนาคต ถ้ามี
//   "regularWorkHours": 80,
//   "regularWorkMinutes": 4800,
//   "workItems": []
// }
//
// Backend จะคำนวณ:
// - salary/grossBase
// - OT จาก approved OT
// - SSO
// - tax
// - netPay
// ======================================================
router.post(
  "/preview/:employeeId/:month",
  auth,
  requireRole(["admin"]),
  ctrl.previewMonth
);

// Backward-compatible preview route
router.post(
  "/preview",
  auth,
  requireRole(["admin"]),
  ctrl.previewMonth
);

// ======================================================
// ✅ ปิดงวด (admin เท่านั้น)
// Preferred:
// POST /payroll-close/close-month/:employeeId/:month
//
// Backward-compatible:
// POST /payroll-close/close-month
//
// หมายเหตุ production:
// - Flutter ส่ง input ได้ เช่น bonus / allowance / deduction / taxMode
// - Backend เป็นคนคำนวณยอดเงินจริงทั้งหมด
// - Backend ไม่เชื่อ otPay / ssoEmployeeMonthly / netPay จาก Flutter
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