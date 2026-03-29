// server.js (CommonJS) - FINAL / DEBUG+SAFE
// AUTH + INVITES + TAX PROFILES + INTERNAL TAX + STAFF SEARCH
// + GLOBAL HELPER SEARCH + USER LINK SEARCH

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
// Request Logger
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
// Safety Timeout
// ===================================================
app.use((req, res, next) => {
  res.setTimeout(15000, () => {
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
const BOOT_AT = Date.now();

app.get("/health", (req, res) => {
  const uptimeSec = Math.floor((Date.now() - BOOT_AT) / 1000);
  res.json({
    ok: true,
    service: "auth_user_service",
    uptimeSec,
    env: process.env.NODE_ENV || "dev",
  });
});

// ===================================================
// Routes
// ===================================================
const authRoutes = require("./routes/authRoutes");
const inviteRoutes = require("./routes/inviteRoutes");
const taxProfileRoutes = require("./routes/taxProfileRoutes");

// INTERNAL TAX
const payrollTaxRoutes = require("./routes/payrollTaxRoutes");

// STAFF SEARCH (internal clinic staff)
const staffRoutes = require("./routes/staffRoutes");

// GLOBAL HELPER MARKETPLACE
const helperRoutes = require("./routes/helperRoutes");

// NEW: USER LINK SEARCH FOR EMPLOYEE LINKING
const userLinkSearchRoutes = require("./routes/userLinkSearchRoutes");

// AUTH
app.use("/", authRoutes);

// INVITES
app.use("/invites", inviteRoutes);

// TAX PROFILES
app.use("/users", taxProfileRoutes);

// INTERNAL TAX
app.use("/", payrollTaxRoutes);

// STAFF SEARCH
app.use("/staff", staffRoutes);

// GLOBAL HELPER SEARCH
app.use("/", helperRoutes);

// USER LINK SEARCH
app.use("/api/users", userLinkSearchRoutes);

// ===================================================
// Global Error Handler
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

mongoose.set("strictQuery", true);

mongoose
  .connect(MONGO_URI, {
    serverSelectionTimeoutMS: 10000,
    connectTimeoutMS: 10000,
    socketTimeoutMS: 20000,
  })
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

server.headersTimeout = 20000;
server.requestTimeout = 20000;

server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 auth_user_service listening on port ${PORT}`);
});