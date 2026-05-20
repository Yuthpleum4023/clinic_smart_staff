const express = require("express");
const router = express.Router();

const { auth, requireRole } = require("../middleware/authMiddleware");
const ctrl = require("../controllers/clinicSecurityController");

// Login users in a clinic can see whether PIN exists.
router.get("/pin/status", auth, ctrl.getPinStatus);

// Admin/clinic_admin only. authMiddleware maps clinic_admin aliases to admin.
router.post("/pin/set", auth, requireRole(["admin"]), ctrl.setClinicPin);

// Login users in the same clinic can verify the clinic PIN.
router.post("/pin/verify", auth, ctrl.verifyClinicPin);

module.exports = router;
