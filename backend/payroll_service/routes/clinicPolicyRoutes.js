// backend/payroll_service/routes/clinicPolicyRoutes.js
const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const {
  getMyClinicPolicy,
  updateMyClinicPolicy,
} = require("../controllers/clinicPolicyController");

// ✅ Policy read/write split for production safety.
// - GET /me: clinic members may read their clinic policy for attendance UI.
// - PUT/PATCH /me: only clinic admins may update policy settings.
const POLICY_READ_ROLES = ["admin", "clinic_admin", "employee", "staff", "helper"];
const POLICY_WRITE_ROLES = ["admin", "clinic_admin"];

// GET current clinic policy
router.get(
  "/me",
  auth,
  requireRole(POLICY_READ_ROLES),
  getMyClinicPolicy
);

// PUT full update
router.put(
  "/me",
  auth,
  requireRole(POLICY_WRITE_ROLES),
  updateMyClinicPolicy
);

// PATCH partial update (Flutter หน้าตั้งค่าใช้อันนี้)
router.patch(
  "/me",
  auth,
  requireRole(POLICY_WRITE_ROLES),
  updateMyClinicPolicy
);

module.exports = router;