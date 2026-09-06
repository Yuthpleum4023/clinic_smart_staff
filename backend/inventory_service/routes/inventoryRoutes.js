const router = require("express").Router();

const itemRoutes = require("./itemRoutes");
const stockRoutes = require("./stockRoutes");
const adjustmentRoutes = require("./adjustmentRoutes");

router.use("/items", itemRoutes);
router.use("/stock", stockRoutes);
router.use("/adjustments", adjustmentRoutes);

module.exports = router;
