const express = require("express");
const router = express.Router();

const { auth } = require("../middleware/auth");
const ctrl = require("../controllers/userLinkSearchController");

// GET /api/users/search-for-link?q=...
router.get("/search-for-link", auth, ctrl.searchUsersForEmployeeLink);

module.exports = router;