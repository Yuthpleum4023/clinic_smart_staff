// backend/auth_user_service/routes/inviteRoutes.js

const express = require("express");
const router = express.Router();

const ctrl = require("../controllers/inviteController");
const { auth, requireRole } = require("../middleware/authMiddleware");

// ==================================================
// PUBLIC ROUTES
// ==================================================
// ใช้ก่อนสมัคร account
// ไม่ต้อง auth
// ==================================================
router.post("/redeem", ctrl.redeemInvite);

// ==================================================
// ADMIN ROUTES (clinic admin เท่านั้น)
// ==================================================

// สร้าง invite (เลือก role ได้: employee / helper)
router.post(
  "/",
  auth,
  requireRole(["admin"]),
  ctrl.createInvite
);

// list invites ของ clinic
router.get(
  "/",
  auth,
  requireRole(["admin"]),
  ctrl.listInvites
);

// revoke invite
router.post(
  "/:code/revoke",
  auth,
  requireRole(["admin"]),
  ctrl.revokeInvite
);

module.exports = router;