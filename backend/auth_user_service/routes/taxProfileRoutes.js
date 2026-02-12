// backend/auth_user_service/routes/taxProfileRoutes.js

const express = require("express");
const router = express.Router();

const { auth } = require("../middleware/authMiddleware");

const {
  getMyTaxProfile,
  upsertMyTaxProfile,
} = require("../controllers/taxProfileController");

const payrollTaxController = require("../controllers/payrollTaxController");

// ✅ GUARD กัน callback undefined (🔥 สำคัญมากใน production)
function safeHandler(fnName) {
  const fn = payrollTaxController[fnName];

  if (!fn) {
    console.error(`❌ MISSING CONTROLLER: ${fnName}`);

    return (req, res) => {
      return res.status(500).json({
        message: `Controller ${fnName} not implemented`,
      });
    };
  }

  return fn;
}

// ===================================================
// Tax Profile (ลดหย่อนภาษีรายปี)
// ===================================================

// GET /users/me/tax-profile?year=2026
router.get("/me/tax-profile", auth, getMyTaxProfile);

// PUT /users/me/tax-profile?year=2026
router.put("/me/tax-profile", auth, upsertMyTaxProfile);

// ===================================================
// Payroll / Tax Calculation (ประมาณการ)
// ===================================================

// POST /users/me/payroll/calc-tax?year=2026
router.post(
  "/me/payroll/calc-tax",
  auth,
  safeHandler("calcMyMonthlyTaxFromProfile") // ✅ ไม่มีทาง undefined
);

module.exports = router;
