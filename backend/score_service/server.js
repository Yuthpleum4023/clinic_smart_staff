// server.js (score_service) — FULL FILE (SAFE + FIXED MOUNT)
require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const app = express();
app.use(cors({ origin: "*", credentials: false }));
app.use(express.json({ limit: "1mb" }));

// health
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
