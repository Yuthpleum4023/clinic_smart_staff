// payroll_service/routes/payrollRoutes.js
const router = require("express").Router();
const { auth } = require("../middleware/auth");
const { getEmployeeByUserId } = require("../utils/staffClient");

// GET /payroll/summary (test auth)
router.get("/summary", auth, async (req, res) => {
  return res.json({
    ok: true,
    message: "payroll summary route ready",
    user: req.user || null,
  });
});

// ✅ NEW: test fetch employee from staff_service by userId (from JWT)
router.get("/me-employee", auth, async (req, res) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(400).json({ ok: false, message: "Missing userId in token" });
    }

    const employee = await getEmployeeByUserId(userId);
    return res.json({ ok: true, employee });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "fetch employee failed",
      error: e.message,
      status: e.status || 500,
      payload: e.payload || null,
    });
  }
});

module.exports = router;