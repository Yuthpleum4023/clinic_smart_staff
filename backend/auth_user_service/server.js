// server.js (CommonJS) - FINAL / DEBUG+SAFE (AUTH + INVITES + TAX PROFILES + INTERNAL TAX)

const express = require("express");
const mongoose = require("mongoose");
const dotenv = require("dotenv");
const cors = require("cors");
const http = require("http");

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3101;

// ===================================================
// Middlewares
// ===================================================
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "2mb" }));
app.use(express.urlencoded({ extended: true }));

// ===================================================
// Request Logger (ดูได้ทันทีว่า request ค้างตรงไหน)
// ===================================================
app.use((req, res, next) => {
  const start = Date.now();
  const rid = Math.random().toString(36).slice(2, 8);
  req._rid = rid;

  console.log(`➡️ [${rid}] ${req.method} ${req.originalUrl}`);

  res.on("finish", () => {
    const ms = Date.now() - start;
    console.log(
      `✅ [${rid}] ${res.statusCode} ${req.method} ${req.originalUrl} (${ms}ms)`
    );
  });

  res.on("close", () => {
    const ms = Date.now() - start;
    if (!res.writableEnded) {
      console.log(
        `⚠️ [${rid}] CLOSED before response (${ms}ms) ${req.method} ${req.originalUrl}`
      );
    }
  });

  next();
});

// ===================================================
// Safety Timeout (กัน request หมุนค้าง)
// ===================================================
app.use((req, res, next) => {
  res.setTimeout(10000, () => {
    if (!res.headersSent) {
      console.log(
        `⏱️ [${req._rid}] TIMEOUT ${req.method} ${req.originalUrl}`
      );
      res.status(504).json({ message: "Request timeout" });
    }
  });
  next();
});

// ===================================================
// Health Check
// ===================================================
app.get("/health", (req, res) => {
  res.json({ ok: true, service: "auth_user_service" });
});

// ===================================================
// Routes
// ===================================================
const authRoutes = require("./routes/authRoutes");
const inviteRoutes = require("./routes/inviteRoutes");
const taxProfileRoutes = require("./routes/taxProfileRoutes");

// ✅ NEW: INTERNAL TAX ROUTES (🔥 ตัวฆ่า 500 ตอนปิดงวด)
const payrollTaxRoutes = require("./routes/payrollTaxRoutes");

// AUTH (no prefix)
app.use("/", authRoutes);

// INVITES
app.use("/invites", inviteRoutes);

// TAX PROFILES / PREVIEW TAX
app.use("/users", taxProfileRoutes);

// ✅ INTERNAL TAX (สำคัญมาก)
app.use("/", payrollTaxRoutes);

// ===================================================
// Global Error Handler (กัน throw แล้วค้าง)
// ===================================================
app.use((err, req, res, next) => {
  console.error(`❌ [${req._rid || "noid"}] ERROR:`, err);
  if (res.headersSent) return next(err);
  res.status(500).json({
    message: err.message || "Internal Server Error",
  });
});

// ===================================================
// MongoDB
// ===================================================
const MONGO_URI = process.env.MONGO_URI;
if (!MONGO_URI) {
  console.error("❌ MONGO_URI is missing in .env");
  process.exit(1);
}

mongoose
  .connect(MONGO_URI)
  .then(() => {
    console.log("✅ MongoDB connected (auth_user_service)");
  })
  .catch((err) => {
    console.error("❌ MongoDB connection error:", err.message || err);
    process.exit(1);
  });

// ===================================================
// Process-level error hooks
// ===================================================
process.on("unhandledRejection", (reason) => {
  console.error("❌ unhandledRejection:", reason);
});

process.on("uncaughtException", (err) => {
  console.error("❌ uncaughtException:", err);
});

// ===================================================
// Start Server
// ===================================================
const server = http.createServer(app);

server.headersTimeout = 15000;
server.requestTimeout = 15000;

server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 auth_user_service listening on port ${PORT}`);
});
