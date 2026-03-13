const router = require("express").Router();

// ✅ ใช้ middleware ตัวเดียวกับ service อื่น
const auth = require("../middleware/authMiddleware");

const { getRecommendations } = require("../controllers/recommendController");

// =====================================================
// GET /recommendations
// - แนะนำ helper จาก trustScore สูงสุด
// - ใช้ในหน้า marketplace / helper suggestion
// =====================================================
router.get("/recommendations", auth, getRecommendations);

module.exports = router;