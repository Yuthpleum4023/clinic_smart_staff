const router = require("express").Router();
const auth = require("../middleware/auth");
const { getRecommendations } = require("../controllers/recommendController");

router.get("/recommendations", auth, getRecommendations);

module.exports = router;
