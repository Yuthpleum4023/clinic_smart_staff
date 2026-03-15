const express = require("express");
const router = express.Router();

const ctrl = require("../controllers/authController");
const { auth } = require("../middleware/authMiddleware");

// ================= Public =================
router.post("/login", ctrl.login);

router.post("/register-clinic-admin", ctrl.registerClinicAdmin);
router.post("/register-with-invite", ctrl.registerWithInvite);

router.post("/forgot-password", ctrl.forgotPassword);
router.post("/reset-password", ctrl.resetPassword);

// ================= Protected =================
router.get("/me", auth, ctrl.me);

// ✅ NEW: update my location
router.patch("/users/me/location", auth, ctrl.updateMyLocation);

// ✅ NEW: Multi-role switch (ออก token ใหม่ตาม activeRole)
router.post("/switch-role", auth, ctrl.switchRole);

module.exports = router;