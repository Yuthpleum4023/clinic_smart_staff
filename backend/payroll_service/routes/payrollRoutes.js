// payroll_service/routes/payrollRoutes.js
const router = require("express").Router();
const auth = require("../middleware/auth");

// GET /payroll/summary
// ขั้นต่ำ: ใช้ทดสอบ auth + route ว่ารันได้
router.get("/summary", auth, async (req, res) => {
  return res.json({
    ok: true,
    message: "payroll summary route ready",
    user: req.user || null,
  });
});

module.exports = router;
