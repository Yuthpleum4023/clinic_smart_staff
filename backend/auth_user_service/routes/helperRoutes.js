// backend/auth_user_service/routes/helperRoutes.js
const router = require("express").Router();
const auth = require("../middleware/auth");
const {
  searchHelpers,
  getHelperByUserId,
} = require("../controllers/helperController");

// =====================================================
// ✅ GET /helpers/search?q=...
// =====================================================
router.get("/helpers/search", auth, searchHelpers);

// =====================================================
// ✅ GET /helpers/by-userid/:userId
// =====================================================
router.get("/helpers/by-userid/:userId", auth, getHelperByUserId);

module.exports = router;