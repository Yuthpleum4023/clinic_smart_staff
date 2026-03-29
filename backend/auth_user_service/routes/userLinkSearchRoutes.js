const express = require("express");
const router = express.Router();

// ✅ FIX: ชี้ไปไฟล์จริง
const { auth } = require("../middleware/authMiddleware");

const ctrl = require("../controllers/userLinkSearchController");

// ======================================
// Routes
// ======================================

// GET /api/users/search-for-link?q=...
router.get("/search-for-link", auth, ctrl.searchUsersForEmployeeLink);

module.exports = router;