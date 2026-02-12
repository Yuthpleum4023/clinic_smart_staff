// ==================================================
// routes/employeeRoutes.js
// ==================================================

const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/employeeController");

// CRUD
router.post("/", ctrl.createEmployee);
router.get("/", ctrl.listEmployees);
router.get("/:id", ctrl.getEmployeeById);
router.put("/:id", ctrl.updateEmployee);
router.delete("/:id", ctrl.deactivateEmployee);

module.exports = router;
