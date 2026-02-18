// routes/scoreRoutes.js
//
// ✅ FULL FILE (UPDATED)
// - ✅ ของเดิมครบ: staff score / trustscore alias / attendance
// - ✅ เพิ่มค้นหา staff: GET /staff/search?q=...&limit=20
//   (ต้องวางก่อน /staff/:staffId/score เพื่อไม่ให้ชนกัน)

const express = require("express");
const router = express.Router();

const auth = require("../middleware/authMiddleware");
const ctrl = require("../controllers/scoreController");

// ✅ NEW: GET /staff/search?q=...&limit=20
// ต้องมาก่อน /staff/:staffId/score ไม่งั้น "search" จะกลายเป็น staffId
router.get("/staff/search", auth, ctrl.searchStaff);

// GET /staff/:staffId/score
router.get("/staff/:staffId/score", auth, ctrl.getStaffScore);

// GET /trustscore?staffId=xxx
router.get("/trustscore", auth, (req, res, next) => {
  const staffId = (req.query.staffId || "").trim();
  if (!staffId) return res.status(400).json({ message: "staffId required" });
  req.params.staffId = staffId;
  return ctrl.getStaffScore(req, res, next);
});

// GET /trustscore/:staffId
router.get("/trustscore/:staffId", auth, ctrl.getStaffScore);

// POST /events/attendance
router.post("/events/attendance", auth, ctrl.postAttendanceEvent);

module.exports = router;
