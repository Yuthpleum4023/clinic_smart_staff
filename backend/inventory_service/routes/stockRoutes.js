const router = require("express").Router();
const { auth, requireClinic, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/stockController");

router.use(auth, requireClinic);

router.post(
  "/in",
  requireRole(["admin", "employee"]),
  ctrl.stockIn
);

router.post(
  "/consume",
  requireRole(["admin", "employee"]),
  ctrl.consume
);

router.post(
  "/admin-adjust",
  requireRole(["admin"]),
  ctrl.adminAdjust
);

module.exports = router;
