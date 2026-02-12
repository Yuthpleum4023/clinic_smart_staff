const router = require("express").Router();
const auth = require("../middleware/auth");

router.get("/summary", auth, async (req, res) => {
  return res.json({ ok: true, message: "payroll summary: coming soon" });
});

module.exports = router;
