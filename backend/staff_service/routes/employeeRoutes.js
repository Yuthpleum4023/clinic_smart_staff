// ==================================================
// routes/employeeRoutes.js
// ==================================================

const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/auth");

// ✅ internal key middleware
const { requireInternalKey } = require("../middleware/internalKey");

const ctrl = require("../controllers/employeeController");

// ==================================================
// 🔒 INTERNAL ROUTES (system-to-system)
// ใช้สำหรับ auth_user_service → staff_service
// ไม่ต้องใช้ JWT ของ user
// ใช้ x-internal-key แทน
// ==================================================
router.get(
  "/internal/by-user/:userId",
  requireInternalKey,
  ctrl.getEmployeeByUserIdInternal
);

router.get(
  "/internal/by-staff/:staffId",
  requireInternalKey,
  ctrl.getEmployeeByStaffIdInternal
);

router.post(
  "/internal/create-from-user",
  requireInternalKey,
  ctrl.createEmployeeFromInternal
);

// ==================================================
// 🔒 ADMIN DROPDOWN (ต้องมาก่อน /:id กันชน)
// ==================================================
router.get(
  "/dropdown",
  auth,
  requireRole(["admin"]),
  ctrl.listForDropdown
);

// ==================================================
// FIXED PATH ROUTES (ต้องมาก่อน /:id)
// ==================================================
router.get(
  "/by-user/:userId",
  auth,
  ctrl.getEmployeeByUserId
);

router.get(
  "/by-staff/:staffId",
  auth,
  ctrl.getEmployeeByStaffId
);

// ==================================================
// CRUD
// ==================================================

// CREATE (admin only)
router.post(
  "/",
  auth,
  requireRole(["admin"]),
  ctrl.createEmployee
);

// LIST (admin only)
router.get(
  "/",
  auth,
  requireRole(["admin"]),
  ctrl.listEmployees
);

// GET BY ID
router.get(
  "/:id",
  auth,
  ctrl.getEmployeeById
);

// UPDATE (admin only)
router.put(
  "/:id",
  auth,
  requireRole(["admin"]),
  ctrl.updateEmployee
);

// DEACTIVATE (admin only)
router.delete(
  "/:id",
  auth,
  requireRole(["admin"]),
  ctrl.deactivateEmployee
);

module.exports = router;