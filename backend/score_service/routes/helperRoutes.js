// backend/score_service/routes/helperRoutes.js
const router = require("express").Router();
const auth = require("../middleware/authMiddleware");
const {
  searchHelpers,
  getHelperScoreByUserId,
} = require("../controllers/helperController");

// =====================================================
// ✅ GET /helpers/search?q=...
// - proxy auth_user_service + enrich trust score
// =====================================================
router.get("/helpers/search", auth, searchHelpers);

// =====================================================
// ✅ GET /helpers/:userId/score
// =====================================================
router.get("/helpers/:userId/score", auth, getHelperScoreByUserId);

module.exports = router;