const express = require("express");
const router = express.Router();

const auth = require("../middleware/authMiddleware");
const ctrl = require("../controllers/scoreController");

// ----------------------------------------------------
// helper
// ----------------------------------------------------
function validateStaffId(staffId, res) {
  const sid = String(staffId || "").trim();

  if (!sid) {
    res.status(400).json({ message: "staffId required" });
    return null;
  }

  if (!sid.startsWith("stf_")) {
    res.status(400).json({
      message: "Invalid staffId",
      hint: "staffId must start with stf_",
    });
    return null;
  }

  return sid;
}

// ----------------------------------------------------
// GET /score/staff/:staffId/score
// ----------------------------------------------------
router.get("/staff/:staffId/score", auth, (req, res, next) => {
  const sid = validateStaffId(req.params.staffId, res);
  if (!sid) return;

  req.params.staffId = sid;
  return ctrl.getStaffScore(req, res, next);
});

// ----------------------------------------------------
// Backward compatibility
// GET /score/trustscore?staffId=...
// ----------------------------------------------------
router.get("/trustscore", auth, (req, res, next) => {
  const sid = validateStaffId(req.query.staffId, res);
  if (!sid) return;

  req.params.staffId = sid;
  return ctrl.getStaffScore(req, res, next);
});

// ----------------------------------------------------
// Backward compatibility
// GET /score/trustscore/:staffId
// ----------------------------------------------------
router.get("/trustscore/:staffId", auth, (req, res, next) => {
  const sid = validateStaffId(req.params.staffId, res);
  if (!sid) return;

  req.params.staffId = sid;
  return ctrl.getStaffScore(req, res, next);
});

// ----------------------------------------------------
// POST /score/events/attendance
// ----------------------------------------------------
router.post("/events/attendance", auth, (req, res, next) => {
  const sid = validateStaffId(req.body.staffId, res);
  if (!sid) return;

  req.body.staffId = sid;
  return ctrl.postAttendanceEvent(req, res, next);
});

module.exports = router;