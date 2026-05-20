// server.js (CommonJS) - FINAL / DEBUG+SAFE
// AUTH + INVITES + TAX PROFILES + INTERNAL TAX + STAFF SEARCH
// + GLOBAL HELPER SEARCH + USER LINK SEARCH

const express = require("express");
const mongoose = require("mongoose");
const dotenv = require("dotenv");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const mongoSanitize = require("express-mongo-sanitize");
const hpp = require("hpp");
const http = require("http");

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3101;
const IS_PROD = process.env.NODE_ENV === "production";

app.set("trust proxy", 1);
app.disable("x-powered-by");

function parseCorsOrigins(value) {
  return String(value || "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
}

const allowedCorsOrigins = parseCorsOrigins(process.env.CORS_ORIGIN);
const allowAllCorsInDev = !IS_PROD && allowedCorsOrigins.length === 0;

// ===================================================
// Security + Middlewares
// ===================================================
app.use(
  helmet({
    crossOriginResourcePolicy: false,
  })
);

const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: Number(process.env.RATE_LIMIT_MAX || 300),
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === "/health",
  message: {
    ok: false,
    code: "RATE_LIMITED",
    message: "Too many requests, please try again later.",
  },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: Number(process.env.AUTH_RATE_LIMIT_MAX || 50),
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.method === "GET",
  message: {
    ok: false,
    code: "AUTH_RATE_LIMITED",
    message: "Too many authentication attempts, please try again later.",
  },
});

app.use(generalLimiter);

app.use(
  cors({
    origin(origin, callback) {
      // Flutter mobile / server-to-server มักไม่มี Origin header
      if (!origin) return callback(null, true);

      if (allowAllCorsInDev) return callback(null, true);

      if (allowedCorsOrigins.includes(origin)) {
        return callback(null, true);
      }

      return callback(new Error("Not allowed by CORS"));
    },
    credentials: false,
    optionsSuccessStatus: 204,
  })
);

// จำกัด brute-force เฉพาะ endpoint auth ที่พบบ่อย โดยไม่กระทบ health/route อื่น
app.use(
  [
    "/login",
    "/register",
    "/forgot-password",
    "/reset-password",
    "/verify",
    "/otp",
    "/api/login",
    "/api/register",
    "/api/forgot-password",
    "/api/reset-password",
    "/api/verify",
    "/api/otp",
    "/clinic-security/pin/set",
    "/clinic-security/pin/verify",
    "/api/clinic-security/pin/set",
    "/api/clinic-security/pin/verify",
  ],
  authLimiter
);

app.use(express.json({ limit: "2mb" }));
app.use(express.urlencoded({ extended: true, limit: "2mb" }));

app.use(
  mongoSanitize({
    replaceWith: "_",
  })
);

app.use(hpp());

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
      console.log(`⏱️ [${req._rid}] TIMEOUT ${req.method} ${req.originalUrl}`);
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

// USER LINK SEARCH
const userLinkSearchRoutes = require("./routes/userLinkSearchRoutes");

// CLINIC SECURITY / PIN
const clinicSecurityRoutes = require("./routes/clinicSecurityRoutes");

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

// CLINIC SECURITY / PIN
app.use("/clinic-security", clinicSecurityRoutes);
app.use("/api/clinic-security", clinicSecurityRoutes);

// ===================================================
// 404 Handler
// ===================================================
app.use((req, res) => {
  res.status(404).json({
    message: "Route not found",
    method: req.method,
    path: req.originalUrl,
  });
});

// ===================================================
// Global Error Handler
// ===================================================
app.use((err, req, res, next) => {
  console.error(`❌ [${req._rid || "noid"}] ERROR:`, err);
  if (res.headersSent) return next(err);

  res.status(500).json({
    message: IS_PROD ? "Internal Server Error" : err.message || "Internal Server Error",
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
mongoose.set("sanitizeFilter", true);

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