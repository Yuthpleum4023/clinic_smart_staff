// routes/availabilityRoutes.js
const express = require("express");
const router = express.Router();

const {
  createAvailability,
  listMyAvailabilities,
  cancelAvailability,
  listOpenAvailabilities,
  listBookedAvailabilities, // ✅ NEW
  clearBookedAvailability, // ✅ NEW
  bookAvailability,
} = require("../controllers/availabilityController");

let requireAuth = null;
try {
  requireAuth = require("../middleware/auth");
} catch (_) {
  requireAuth = (req, res, next) => next();
}

// ======================================================
// ✅ CLINIC ADMIN
// ======================================================

// browse ตารางว่างผู้ช่วย
router.get("/open", requireAuth, listOpenAvailabilities);

// ✅ NEW: list booked (ค้างไว้หลังจอง)
router.get("/booked", requireAuth, listBookedAvailabilities);

// ✅ NEW — clear booked item (ทำให้หายจากหน้า booked)
router.post("/:id/clear", requireAuth, clearBookedAvailability);

// ✅ BOOK AVAILABILITY → CREATE SHIFT
router.post("/:id/book", requireAuth, bookAvailability);

// ======================================================
// ✅ STAFF / HELPER
// ======================================================

router.get("/me", requireAuth, listMyAvailabilities);
router.post("/", requireAuth, createAvailability);
router.patch("/:id/cancel", requireAuth, cancelAvailability);

module.exports = router;