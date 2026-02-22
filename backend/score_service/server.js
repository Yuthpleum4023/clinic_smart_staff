// server.js (score_service) — FULL FILE (SAFE + FIXED BODY PARSER + REQUEST/BODY LOG)
// -----------------------------------------------------------------------------
// ✅ Adds / Ensures:
// - ✅ express.json() + express.urlencoded() BEFORE routes (แก้ req.body ว่าง/400)
// - ✅ Request logger (เห็นทุก request ใน Render Live tail)
// - ✅ Body preview logger (เฉพาะ method ที่มี body)
// - ✅ /health
// - ✅ /events -> routes/eventRoutes
// - ✅ /score  -> routes/scoreRoutes
// - ✅ 404 handler (เห็น path ที่ยิงผิด)
// - ✅ Error handler (กันพังเงียบ)
// -----------------------------------------------------------------------------

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const app = express();

// -----------------------------------------------------------------------------
// CORS
// -----------------------------------------------------------------------------
app.use(cors({ origin: "*", credentials: false }));

// -----------------------------------------------------------------------------
// ✅ BODY PARSERS (MUST be before routes)
// - แก้ปัญหา req.body เป็น {} / undefined -> 400 ทันที
// -----------------------------------------------------------------------------
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

// -----------------------------------------------------------------------------
// ✅ REQUEST LOGGER (สำคัญมากสำหรับ Render Live tail)
// -----------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();

  const ip =
    (req.headers["x-forwarded-for"] || "").toString().split(",")[0].trim() ||
    req.socket.remoteAddress;

  console.log(`➡️ ${req.method} ${req.originalUrl}`, { ip });

  // ✅ Log content-type (ช่วย debug body parse)
  const ct = req.headers["content-type"];
  if (ct) console.log("   ↳ content-type:", ct);

  // ✅ Log body preview for POST/PUT/PATCH (หลัง express.json แล้ว)
  if (["POST", "PUT", "PATCH"].includes(req.method)) {
    // ระวังข้อมูลส่วนตัว: log แบบย่อ + ตัด token ออก
    const safeBody = { ...(req.body || {}) };
    if (safeBody.password) safeBody.password = "***";
    if (safeBody.token) safeBody.token = "***";
    if (safeBody.jwt) safeBody.jwt = "***";

    console.log("   ↳ body:", safeBody);
  }

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

// Score routes (และอาจมี /score/events/attendance ด้วย ขึ้นกับไฟล์ของท่าน)
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

// -----------------------------------------------------------------------------
// START
// -----------------------------------------------------------------------------
const PORT = process.env.PORT || 10000;

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