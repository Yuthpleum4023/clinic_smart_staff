// ==================================================
// routes/employeeRoutes.js
// PURPOSE:
// - Employee CRUD
// - Internal ensure / lookup routes for service-to-service flow
// ==================================================

const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/auth");
const { requireInternalKey } = require("../middleware/internalKey");

const ctrl = require("../controllers/employeeController");

// ==================================================
// 🔒 INTERNAL ROUTES (system-to-system)
// ใช้สำหรับ auth_user_service → staff_service
// ไม่ต้องใช้ JWT ของ user
// ใช้ x-internal-key แทน
// ==================================================

// ✅ internal get by user
router.get(
  "/internal/by-user/:userId",
  requireInternalKey,
  ctrl.getEmployeeByUserIdInternal
);

// ✅ internal get by staff
router.get(
  "/internal/by-staff/:staffId",
  requireInternalKey,
  ctrl.getEmployeeByStaffIdInternal
);

// ✅ NEW: internal ensure employee (route ใหม่ที่ควรใช้)
router.post(
  "/internal/ensure",
  requireInternalKey,
  ctrl.ensureEmployeeInternal
);

// ✅ BACKWARD COMPAT: route เก่ายังใช้ได้
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

// GET employee by userId
router.get(
  "/by-user/:userId",
  auth,
  ctrl.getEmployeeByUserId
);

// GET employee by staffId
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