const router = require("express").Router();

const itemRoutes = require("./itemRoutes");
const stockRoutes = require("./stockRoutes");
const adjustmentRoutes = require("./adjustmentRoutes");
const integrationRoutes = require("./integrationRoutes");

router.use("/items", itemRoutes);
router.use("/stock", stockRoutes);
router.use("/adjustments", adjustmentRoutes);
router.use("/integrations", integrationRoutes);

module.exports = router;
