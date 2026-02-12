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

// -------------------- Middleware --------------------
app.use(cors());
app.use(express.json());

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
    status: "ok",
    service: "staff_service",
    port: PORT,
  });
});

// -------------------- Routes --------------------
app.use("/api/employees", employeeRoutes);

// -------------------- Mongo + Start --------------------
// ✅ แนะนำ: ค่อย start server หลัง connect Mongo สำเร็จ
mongoose
  .connect(MONGO_URI)
  .then(() => {
    console.log("✅ MongoDB connected (staff_service)");
    app.listen(PORT, "0.0.0.0", () =>
      console.log(`🚀 staff_service running on port ${PORT}`)
    );
  })
  .catch((err) => {
    console.error("❌ MongoDB error:", err.message);
    process.exit(1);
  });
