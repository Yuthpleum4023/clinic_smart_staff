const router = require("express").Router();
const auth = require("../middleware/auth");
const {
  getStaffScore,
  listStaff,
} = require("../controllers/staffController");

// =====================================================
// GET /staff
// - admin ใช้ list ผู้ช่วย
// - รองรับ query ?role=helper
// =====================================================
router.get("/", auth, listStaff);

// =====================================================
// GET /staff/:staffId/score
// =====================================================
router.get("/:staffId/score", auth, getStaffScore);

module.exports = router;
