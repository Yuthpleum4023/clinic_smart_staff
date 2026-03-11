// backend/payroll_service/routes/clinicPolicyRoutes.js
const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const {
  getMyClinicPolicy,
  updateMyClinicPolicy,
} = require("../controllers/clinicPolicyController");

// ✅ รองรับทั้ง admin และ clinic_admin
const POLICY_ADMIN_ROLES = ["admin", "clinic_admin"];

// GET current clinic policy
router.get(
  "/me",
  auth,
  requireRole(POLICY_ADMIN_ROLES),
  getMyClinicPolicy
);

// PUT full update
router.put(
  "/me",
  auth,
  requireRole(POLICY_ADMIN_ROLES),
  updateMyClinicPolicy
);

// PATCH partial update (Flutter หน้าตั้งค่าใช้อันนี้)
router.patch(
  "/me",
  auth,
  requireRole(POLICY_ADMIN_ROLES),
  updateMyClinicPolicy
);

module.exports = router;