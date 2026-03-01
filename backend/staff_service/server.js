// ==================================================
// staff_service/server.js
// PURPOSE: Staff / Employee Master Service (MVP)
// ==================================================

const path = require("path");

// ✅ FIX: บังคับให้ dotenv โหลด .env จากโฟลเดอร์เดียวกับไฟล์นี้เสมอ
require("dotenv").config({
  path: path.join(__dirname, ".env"),
});

const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");

const employeeRoutes = require("./routes/employeeRoutes");

const app = express();

// -----------------------------------------------------------------------------
// CORS
// -----------------------------------------------------------------------------
app.use(cors({ origin: "*", credentials: false }));

// -----------------------------------------------------------------------------
// ✅ BODY PARSERS (MUST be before routes)
// - กัน req.body ว่าง / undefined
// -----------------------------------------------------------------------------
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

// -----------------------------------------------------------------------------
// ✅ REQUEST LOGGER (สำคัญมากสำหรับ Render / Debug)
// -----------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();

  const ip =
    (req.headers["x-forwarded-for"] || "").toString().split(",")[0].trim() ||
    req.socket.remoteAddress;

  console.log("==========================================");
  console.log(`➡️  ${req.method} ${req.originalUrl}`, { ip });

  const ct = req.headers["content-type"];
  if (ct) console.log("   ↳ content-type:", ct);

  // log body เฉพาะ method ที่มักมี body
  if (["POST", "PUT", "PATCH"].includes(req.method)) {
    const safeBody = { ...(req.body || {}) };
    if (safeBody.password) safeBody.password = "***";
    if (safeBody.token) safeBody.token = "***";
    if (safeBody.jwt) safeBody.jwt = "***";
    console.log("   ↳ body:", safeBody);
  }

  res.on("finish", () => {
    const ms = Date.now() - start;
    console.log(`⬅️  ${req.method} ${req.originalUrl} -> ${res.statusCode} (${ms}ms)`);
    console.log("==========================================");
  });

  next();
});

// -------------------- Env / Debug --------------------
const PORT = Number(process.env.PORT || 3104); // ✅ กันชนกับ SMF
const MONGO_URI = process.env.MONGO_URI;

// ✅ ช่วย debug (ไม่โชว์ URI เต็มเพื่อความปลอดภัย)
console.log("🧪 ENV CHECK:", {
  PORT,
  MONGO_URI: MONGO_URI ? "SET" : "MISSING",
});

// ✅ ถ้าไม่มี MONGO_URI ให้ fail เร็ว (จะได้ไม่งง)
if (!MONGO_URI) {
  console.error("❌ Missing MONGO_URI in .env");
  process.exit(1);
}

// -------------------- Health --------------------
app.get("/health", (req, res) => {
  res.json({
    ok: true,
    service: "staff_service",
    port: PORT,
  });
});

// -------------------- Routes --------------------
app.use("/api/employees", employeeRoutes);

// -----------------------------------------------------------------------------
// ✅ 404 handler (เห็นชัดว่า client ยิง path อะไรมา)
// -----------------------------------------------------------------------------
app.use((req, res) => {
  res.status(404).json({
    ok: false,
    error: "NOT_FOUND",
    method: req.method,
    path: req.originalUrl,
  });
});

// -----------------------------------------------------------------------------
// ✅ error handler (กันพังเงียบ)
// -----------------------------------------------------------------------------
app.use((err, req, res, next) => {
  console.error("❌ Unhandled error:", err);
  res.status(500).json({
    ok: false,
    error: "INTERNAL_SERVER_ERROR",
    message: err?.message || "unknown",
  });
});

// -------------------- Mongo + Start --------------------
let server = null;

async function start() {
  await mongoose.connect(MONGO_URI);
  console.log("✅ MongoDB connected (staff_service)");

  server = app.listen(PORT, "0.0.0.0", () => {
    console.log(`🚀 staff_service running on port ${PORT}`);
  });

  // ✅ graceful shutdown (กัน port ค้าง)
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

async function shutdown() {
  try {
    console.log("🛑 Shutting down staff_service...");
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    await mongoose.disconnect();
  } catch (e) {
    console.error("❌ shutdown error:", e.message);
  } finally {
    process.exit(0);
  }
}

start().catch((err) => {
  console.error("❌ staff_service start failed:", err);
  process.exit(1);
});