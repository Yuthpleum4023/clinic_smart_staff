const router = require("express").Router();
const auth = require("../middleware/auth");

router.get("/", auth, async (req, res) => {
  return res.json({ ok: true, message: "shift routes: coming soon" });
});

module.exports = router;
