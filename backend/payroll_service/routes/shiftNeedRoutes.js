// payroll_service/routes/shiftNeedRoutes.js
const router = require("express").Router();
const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/shiftNeedController");

// ✅ แนะนำให้เอา /open ไว้ก่อน route ที่มี /:id กันสับสนในอนาคต

// ======================================================
// ✅ STAFF / EMPLOYEE (ต้อง login)
// ======================================================
router.get("/open", auth, ctrl.listOpenNeeds);
router.post("/:id/apply", auth, ctrl.applyNeed);

// ======================================================
// ✅ ADMIN (ต้องเป็น admin เท่านั้น)
// ======================================================
router.post("/", auth, requireRole(["admin"]), ctrl.createNeed);
router.get("/", auth, requireRole(["admin"]), ctrl.listClinicNeeds);
router.get("/:id/applicants", auth, requireRole(["admin"]), ctrl.listApplicants);
router.post("/:id/approve", auth, requireRole(["admin"]), ctrl.approveApplicant);
router.patch("/:id/cancel", auth, requireRole(["admin"]), ctrl.cancelNeed);

module.exports = router;