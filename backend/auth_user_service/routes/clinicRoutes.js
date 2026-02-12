const express = require("express");
const router = express.Router();

const ctrl = require("../controllers/clinicController");
const { auth } = require("../middleware/authMiddleware");

router.get("/me", auth, ctrl.getMyClinic);

module.exports = router;
