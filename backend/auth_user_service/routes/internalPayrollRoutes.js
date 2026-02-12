const express = require("express");
const router = express.Router();

const payrollTaxController = require("../controllers/payrollTaxController");

// ✅ Internal only (ใช้ x-internal-key)
router.post("/payroll/calc-tax-ytd", payrollTaxController.calcTaxYTDInternal);

module.exports = router;
