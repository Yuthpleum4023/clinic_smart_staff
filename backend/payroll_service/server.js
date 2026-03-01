// backend/payroll_service/server.js
require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const app = express();

// -------------------- CORS --------------------
app.use(cors({ origin: "*", credentials: false }));

// -------------------- BODY PARSERS (สำคัญมาก) --------------------
// ✅ ป้องกัน req.body ว่าง/undefined ในบางเคส
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

// -------------------- REQUEST LOGGER --------------------
app.use((req, res, next) => {
  const start = Date.now();
  const auth = req.headers.authorization;

  const ip =
    (req.headers["x-forwarded-for"] || "").toString().split(",")[0].trim() ||
    req.socket.remoteAddress;

  console.log("==========================================");
  console.log(`➡️  ${req.method} ${req.originalUrl}`);
  console.log(`   IP: ${ip || "-"}`);
  console.log(`   Host: ${req.headers.host || "-"}`);
  console.log(`   Authorization: ${auth ? "YES" : "NO"}`);

  const ct = req.headers["content-type"];
  if (ct) console.log(`   Content-Type: ${ct}`);

  // ✅ Log body preview เฉพาะ method ที่มักมี body
  if (["POST", "PUT", "PATCH"].includes(req.method)) {
    const safeBody = { ...(req.body || {}) };
    if (safeBody.password) safeBody.password = "***";
    if (safeBody.token) safeBody.token = "***";
    if (safeBody.jwt) safeBody.jwt = "***";
    console.log("   Body:", safeBody);
  }

  res.on("finish", () => {
    console.log(
      `⬅️  ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - start}ms)`
    );
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

// ✅ ShiftNeed (ประกาศงานว่าง / รับงาน / approve -> สร้าง Shift)
app.use("/shift-needs", require("./routes/shiftNeedRoutes"));

// ✅ Payroll Close (ปิดงวดจริง + YTD)
app.use("/payroll-close", require("./routes/payrollCloseRoutes"));

// ✅ Clinics (location for navigation)
app.use("/clinics", require("./routes/clinicRoutes"));

// ✅ Clinic Policy (OT / Attendance Policy per clinic)
app.use("/clinic-policy", require("./routes/clinicPolicyRoutes"));

// ✅ Attendance (check-in/out)
app.use("/attendance", require("./routes/attendanceRoutes"));

// ✅ Availabilities (ตารางว่างผู้ช่วย -> ให้คลินิกเห็น)
app.use("/availabilities", require("./routes/availabilityRoutes"));

// ✅ Overtime (pending/approved/rejected/locked)
app.use("/overtime", require("./routes/overtimeRoutes"));

// ✅ Staff Proxy (dropdown จาก staff_service ผ่าน payroll_service)
app.use("/staff", require("./routes/staffRoutes"));

// -------------------- 404 handler --------------------
app.use((req, res) => {
  return res.status(404).json({
    ok: false,
    error: "NOT_FOUND",
    method: req.method,
    path: req.originalUrl,
  });
});

// -------------------- Error handler --------------------
app.use((err, req, res, next) => {
  console.error("❌ Unhandled error:", err);
  return res.status(500).json({
    ok: false,
    error: "INTERNAL_SERVER_ERROR",
    message: err?.message || "unknown",
  });
});

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