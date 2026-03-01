// routes/availabilityRoutes.js
const express = require("express");
const router = express.Router();

const { auth } = require("../middleware/auth");

const {
  createAvailability,
  listMyAvailabilities,
  cancelAvailability,
  listOpenAvailabilities,
  listBookedAvailabilities, // ✅ NEW
  clearBookedAvailability,  // ✅ NEW
  bookAvailability,
} = require("../controllers/availabilityController");

// ======================================================
// ✅ CLINIC ADMIN / STAFF (ต้อง login)
// ======================================================

// browse ตารางว่างผู้ช่วย
router.get("/open", auth, listOpenAvailabilities);

// ✅ NEW: list booked (ค้างไว้หลังจอง)
router.get("/booked", auth, listBookedAvailabilities);

// ✅ NEW — clear booked item (ทำให้หายจากหน้า booked)
router.post("/:id/clear", auth, clearBookedAvailability);

// ✅ BOOK AVAILABILITY → CREATE SHIFT
router.post("/:id/book", auth, bookAvailability);

// ======================================================
// ✅ STAFF / HELPER
// ======================================================

router.get("/me", auth, listMyAvailabilities);
router.post("/", auth, createAvailability);
router.patch("/:id/cancel", auth, cancelAvailability);

module.exports = router;