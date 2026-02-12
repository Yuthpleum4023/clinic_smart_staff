// backend/auth_user_service/routes/payrollTaxRoutes.js
const express = require("express");
const router = express.Router();

const payrollTaxController = require("../controllers/payrollTaxController");

// ===================================================
// ✅ INTERNAL TAX (สำหรับ payroll_service ตอนปิดงวด)
// ต้องส่ง header: x-internal-key = INTERNAL_SERVICE_KEY
// ===================================================

// ✅ route หลัก (ให้ payroll_service เรียกตัวนี้)
router.post(
  "/internal/payroll/calc-tax-ytd",
  payrollTaxController.calcTaxYTDInternal
);

// ✅ fallback เผื่อบางโปรเจกต์ mount ใต้ /users (กันหลง path)
router.post(
  "/users/internal/payroll/calc-tax-ytd",
  payrollTaxController.calcTaxYTDInternal
);

// ✅ fallback เผื่อมี /api prefix (กัน gateway/compose บางแบบ)
router.post(
  "/api/internal/payroll/calc-tax-ytd",
  payrollTaxController.calcTaxYTDInternal
);

router.post(
  "/api/users/internal/payroll/calc-tax-ytd",
  payrollTaxController.calcTaxYTDInternal
);

module.exports = router;
