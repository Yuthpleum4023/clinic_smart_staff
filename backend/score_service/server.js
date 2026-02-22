// server.js (score_service) — FULL FILE (SAFE + FIXED MOUNT + REQUEST LOG)
// -----------------------------------------------------------------------------
// ✅ Adds:
// - ✅ Request log middleware (Render Live tail must show every request)
// - ✅ 404 handler (เห็น path ที่ยิงผิดชัด ๆ)
// - ✅ Error handler (กันพังเงียบ)
// ✅ Keeps:
// - /health
// - /events -> routes/eventRoutes
// - /score  -> routes/scoreRoutes
// -----------------------------------------------------------------------------

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const app = express();

// CORS / body
app.use(cors({ origin: "*", credentials: false }));
app.use(express.json({ limit: "1mb" }));

// -----------------------------------------------------------------------------
// ✅ REQUEST LOGGER (สำคัญมากสำหรับ Render Live tail)
// - ต่อให้ route ไม่แมตช์ (404) ก็จะเห็น log
// - ช่วยจับว่า Flutter ยิงเข้ามาที่ service นี้จริงไหม
// -----------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();

  const ip =
    (req.headers["x-forwarded-for"] || "").toString().split(",")[0].trim() ||
    req.socket.remoteAddress;

  console.log(`➡️ ${req.method} ${req.originalUrl}`, { ip });

  res.on("finish", () => {
    const ms = Date.now() - start;
    console.log(`✅ ${res.statusCode} ${req.method} ${req.originalUrl} (${ms}ms)`);
  });

  next();
});

// -----------------------------------------------------------------------------
// health
// -----------------------------------------------------------------------------
app.get("/health", (req, res) => {
  res.json({ ok: true, service: "score_service" });
});

// -----------------------------------------------------------------------------
// ✅ routes
// -----------------------------------------------------------------------------
// Events: POST /events/attendance
app.use("/events", require("./routes/eventRoutes"));

// ✅ Score + TrustScore alias อยู่ใน scoreRoutes
// - GET  /score/staff/:staffId/score
// - GET  /score/trustscore?staffId=xxx
// - GET  /score/trustscore/:staffId
// - POST /score/events/attendance  (ถ้าคุณยัง mount ไว้แบบนี้ใน scoreRoutes)
app.use("/score", require("./routes/scoreRoutes"));

// ❗ ถ้าโปรเจกต์คุณ “ไม่มีไฟล์” 2 อันนี้ ให้ปิดไว้ก่อน ไม่งั้น service จะล้ม
// app.use("/staff", require("./routes/staffRoutes"));
// app.use("/", require("./routes/recommendRoutes"));

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

const PORT = process.env.PORT || 3103;

async function start() {
  if (!process.env.MONGO_URI) {
    throw new Error("Missing MONGO_URI");
  }

  await mongoose.connect(process.env.MONGO_URI);
  console.log("✅ MongoDB connected (score_service)");

  app.listen(PORT, () => {
    console.log(`🚀 score_service listening on port ${PORT}`);
  });
}

start().catch((e) => {
  console.error("❌ score_service start failed:", e);
  process.exit(1);
});