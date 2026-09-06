const router = require("express").Router();
const { auth, requireClinic, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/itemController");

router.use(auth, requireClinic, requireRole(["admin", "employee"]));

router.get("/low-stock", ctrl.listLowStock);
router.post("/", requireRole(["admin"]), ctrl.createItem);
router.get("/", ctrl.listItems);
router.get("/:id/card", ctrl.getStockCard);
router.patch("/:id/threshold", requireRole(["admin"]), ctrl.updateThreshold);
router.get("/:id", ctrl.getItem);
router.patch("/:id", requireRole(["admin"]), ctrl.updateItem);

module.exports = router;
