// payroll_service/server.js
require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const app = express();

// -------------------- Middlewares --------------------
app.use(cors());
app.use(express.json({ limit: "1mb" }));

// ✅ REQUEST LOGGER (DEBUG: ดูว่า request ถึง payroll_service ไหม)
app.use((req, res, next) => {
  const start = Date.now();
  const auth = req.headers.authorization;

  console.log("==========================================");
  console.log(`➡️  ${req.method} ${req.originalUrl}`);
  console.log(`   Host: ${req.headers.host || "-"}`);
  console.log(`   Authorization: ${auth ? "YES" : "NO"}`);

  res.on("finish", () => {
    console.log(`⬅️  ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - start}ms)`);
    console.log("==========================================");
  });

  next();
});

// -------------------- Health --------------------
app.get("/health", (req, res) => {
  return res.json({ ok: true, service: "payroll_service" });
});

// -------------------- Routes --------------------
app.use("/shifts", require("./routes/shiftRoutes"));
app.use("/payroll", require("./routes/payrollRoutes"));

// ✅ NEW: ShiftNeed (ประกาศงานว่าง / รับงาน / approve -> สร้าง Shift)
app.use("/shift-needs", require("./routes/shiftNeedRoutes"));

// ✅ NEW: Payroll Close (ปิดงวดจริง + YTD)
app.use("/payroll-close", require("./routes/payrollCloseRoutes"));

// -------------------- Start --------------------
const PORT = Number(process.env.PORT || 3102);

async function start() {
  if (!process.env.MONGO_URI) {
    console.error("❌ Missing MONGO_URI in .env");
    process.exit(1);
  }

  await mongoose.connect(process.env.MONGO_URI);
  console.log("✅ MongoDB connected (payroll_service)");

  const server = app.listen(PORT, () => {
    console.log(`🚀 payroll_service listening on port ${PORT}`);
  });

  // ✅ กัน port ค้างเวลา Ctrl+C
  process.on("SIGINT", () => {
    console.log("🛑 Shutting down payroll_service...");
    server.close(() => process.exit(0));
  });
}

start().catch((e) => {
  console.error("❌ payroll_service start failed:", e);
  process.exit(1);
});
