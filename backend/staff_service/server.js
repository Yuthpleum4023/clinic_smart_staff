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
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");

const employeeRoutes = require("./routes/employeeRoutes");

const app = express();

const IS_PROD = process.env.NODE_ENV === "production";

app.set("trust proxy", 1);
app.disable("x-powered-by");

function str(v) {
  return String(v || "").trim();
}

function parseCorsOrigins(value) {
  return String(value || "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
}

const allowedCorsOrigins = parseCorsOrigins(process.env.CORS_ORIGIN);
const allowAllCorsInDev = !IS_PROD && allowedCorsOrigins.length === 0;

function expectedInternalKey() {
  return str(process.env.STAFF_SERVICE_INTERNAL_KEY || process.env.INTERNAL_SERVICE_KEY);
}

function hasValidInternalKey(req) {
  const expected = expectedInternalKey();
  if (!expected) return false;

  const incoming =
    str(req.headers["x-internal-key"]) ||
    str(req.headers["internal_service_key"]);

  return !!incoming && incoming === expected;
}

function findDangerousKey(value, path = "") {
  if (!value || typeof value !== "object") return "";

  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i += 1) {
      const found = findDangerousKey(value[i], `${path}[${i}]`);
      if (found) return found;
    }
    return "";
  }

  for (const key of Object.keys(value)) {
    const lower = String(key).toLowerCase();

    if (
      key.startsWith("$") ||
      key.includes(".") ||
      lower === "__proto__" ||
      lower === "prototype" ||
      lower === "constructor"
    ) {
      return path ? `${path}.${key}` : key;
    }

    const found = findDangerousKey(value[key], path ? `${path}.${key}` : key);
    if (found) return found;
  }

  return "";
}

function findDuplicateQueryArray(value, path = "") {
  if (!value || typeof value !== "object") return "";

  for (const key of Object.keys(value)) {
    const nextPath = path ? `${path}.${key}` : key;
    const current = value[key];

    if (Array.isArray(current)) {
      return nextPath;
    }

    if (current && typeof current === "object") {
      const found = findDuplicateQueryArray(current, nextPath);
      if (found) return found;
    }
  }

  return "";
}

// -----------------------------------------------------------------------------
// Security + CORS
// -----------------------------------------------------------------------------
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
  skip: (req) => req.path === "/health" || hasValidInternalKey(req),
  message: {
    ok: false,
    code: "RATE_LIMITED",
    message: "Too many requests, please try again later.",
  },
});

app.use(generalLimiter);

app.use(
  cors({
    origin(origin, callback) {
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

// -----------------------------------------------------------------------------
// ✅ BODY PARSERS (MUST be before routes)
// - กัน req.body ว่าง / undefined
// -----------------------------------------------------------------------------
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

// -----------------------------------------------------------------------------
// Express 5-safe input guard
// - ไม่ mutate req.query โดยตรง
// - reject key แปลก ๆ เช่น $ne, user.name, __proto__
// - reject duplicate query เช่น ?role=a&role=b
// -----------------------------------------------------------------------------
app.use((req, res, next) => {
  const duplicateQueryPath = findDuplicateQueryArray(req.query);
  if (duplicateQueryPath) {
    return res.status(400).json({
      ok: false,
      code: "DUPLICATE_QUERY_PARAM",
      message: "Duplicate query parameters are not allowed",
      field: duplicateQueryPath,
    });
  }

  const dangerousPath =
    findDangerousKey(req.query, "query") ||
    findDangerousKey(req.body, "body") ||
    findDangerousKey(req.params, "params");

  if (dangerousPath) {
    return res.status(400).json({
      ok: false,
      code: "INVALID_INPUT_KEY",
      message: "Invalid input key",
      field: dangerousPath,
    });
  }

  return next();
});

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
    message: IS_PROD ? "Internal Server Error" : err?.message || "unknown",
  });
});

// -------------------- Mongo + Start --------------------
let server = null;

async function start() {
  mongoose.set("strictQuery", true);
  mongoose.set("sanitizeFilter", true);

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