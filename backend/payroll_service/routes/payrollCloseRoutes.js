const express = require("express");
const router = express.Router();

const auth = require("../middleware/auth");   // ✅ ใส่อันนี้
const ctrl = require("../controllers/payrollCloseController");

// ✅ ต้องผ่าน JWT ก่อน
router.post("/close-month", auth, ctrl.closeMonth);

// ✅ ดูงวดที่ปิดแล้ว (ต้อง auth เช่นกัน)
router.get("/close-months/:employeeId", auth, ctrl.getClosedMonthsByEmployee);

module.exports = router;
