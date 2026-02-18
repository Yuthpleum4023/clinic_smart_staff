const express = require("express");
const router = express.Router();

// ✅ รองรับทั้ง 2 แบบ export:
// 1) module.exports = authFunction
// 2) module.exports = { auth, requireRole }
const authMod = require("../middleware/authMiddleware");
const auth = typeof authMod === "function" ? authMod : authMod.auth;

if (typeof auth !== "function") {
  throw new Error(
    "auth middleware is not a function. Check middleware/authMiddleware.js export."
  );
}

const ctrl = require("../controllers/staffController");

// ✅ Search staff by name/phone/staffId
// GET /staff/search?q=สมชาย
// GET /staff/search?q=098
router.get("/search", auth, ctrl.searchStaff);

// (optional) get by staffId
// GET /staff/by-staffid/STF_xxx
router.get("/by-staffid/:staffId", auth, ctrl.getByStaffId);

module.exports = router;
