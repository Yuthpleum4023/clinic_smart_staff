const router = require("express").Router();

const auth = require("../middleware/authMiddleware");
const { postAttendanceEvent } = require("../controllers/eventController");

router.post("/attendance", auth, postAttendanceEvent);

module.exports = router;
