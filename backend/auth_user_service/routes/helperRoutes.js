const router = require("express").Router();
const { auth, requireRole } = require("../middleware/authMiddleware");
const {
  searchHelpers,
  getHelperByUserId,
} = require("../controllers/helperController");

// clinic/admin ใช้ค้น helper ทั้งระบบได้
router.get("/helpers/search", auth, requireRole(["admin", "clinic"]), searchHelpers);

// clinic/admin ใช้ดู helper ตาม userId ได้
router.get(
  "/helpers/by-userid/:userId",
  auth,
  requireRole(["admin", "clinic"]),
  getHelperByUserId
);

module.exports = router;