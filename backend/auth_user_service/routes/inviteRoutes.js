const express = require("express");
const router = express.Router();

const ctrl = require("../controllers/inviteController");
const { auth, requireRole } = require("../middleware/authMiddleware");

// Admin only
router.post("/", auth, requireRole(["admin"]), ctrl.createInvite);
router.get("/", auth, requireRole(["admin"]), ctrl.listInvites);
router.post("/:code/revoke", auth, requireRole(["admin"]), ctrl.revokeInvite);

module.exports = router;
