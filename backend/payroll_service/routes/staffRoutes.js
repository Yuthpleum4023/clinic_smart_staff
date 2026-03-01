// backend/payroll_service/routes/staffRoutes.js
// ======================================================
// payroll_service staff routes (proxy to staff_service)
// ======================================================

const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const { dropdown } = require("../controllers/staffController");

// ✅ Admin dropdown
// GET /staff/dropdown
router.get("/dropdown", auth, requireRole(["admin"]), dropdown);

module.exports = router;