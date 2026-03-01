// backend/payroll_service/routes/clinicPolicyRoutes.js
const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const {
  getMyClinicPolicy,
  updateMyClinicPolicy,
} = require("../controllers/clinicPolicyController");

// ✅ Admin only
router.get("/me", auth, requireRole(["admin"]), getMyClinicPolicy);
router.put("/me", auth, requireRole(["admin"]), updateMyClinicPolicy);

module.exports = router;