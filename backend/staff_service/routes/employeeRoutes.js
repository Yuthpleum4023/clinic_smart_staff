// ==================================================
// routes/employeeRoutes.js
// ==================================================

const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/employeeController");

// ==================================================
// 🔒 ADMIN DROPDOWN (ต้องมาก่อน /:id กันชน)
// GET /employees/dropdown
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

// CREATE
router.post(
  "/",
  auth,
  requireRole(["admin"]),
  ctrl.createEmployee
);

// LIST (active employees)
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

// UPDATE
router.put(
  "/:id",
  auth,
  requireRole(["admin"]),
  ctrl.updateEmployee
);

// DEACTIVATE
router.delete(
  "/:id",
  auth,
  requireRole(["admin"]),
  ctrl.deactivateEmployee
);

module.exports = router;