// server.js (score_service) — FULL FILE
// -----------------------------------------------------------------------------
// ✅ Includes:
// - express.json() + express.urlencoded() BEFORE routes
// - Request logger
// - Body preview logger
// - /health
// - /events -> routes/eventRoutes
// - /score  -> routes/scoreRoutes
// - /      -> routes/helperRoutes        ✅ NEW (global helper trust routes)
// - /      -> routes/recommendRoutes     ✅ OPTIONAL/ENABLED
// - 404 handler
// - Error handler
// -----------------------------------------------------------------------------

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const mongoSanitize = require("express-mongo-sanitize");
const hpp = require("hpp");
const mongoose = require("mongoose");

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
  return str(process.env.SCORE_SERVICE_INTERNAL_KEY || process.env.INTERNAL_SERVICE_KEY);
}

function hasValidInternalKey(req) {
  const expected = expectedInternalKey();
  if (!expected) return false;

  const incoming =
    str(req.headers["x-internal-key"]) ||
    str(req.headers["internal_service_key"]);

  return !!incoming && incoming === expected;
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
// BODY PARSERS
// -----------------------------------------------------------------------------
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

app.use(
  mongoSanitize({
    replaceWith: "_",
  })
);

app.use(hpp());

// -----------------------------------------------------------------------------
// REQUEST LOGGER
// -----------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();

  const ip =
    (req.headers["x-forwarded-for"] || "").toString().split(",")[0].trim() ||
    req.socket.remoteAddress;

  console.log(`➡️ ${req.method} ${req.originalUrl}`, { ip });

  const ct = req.headers["content-type"];
  if (ct) console.log("   ↳ content-type:", ct);

  if (["POST", "PUT", "PATCH"].includes(req.method)) {
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
// HEALTH
// -----------------------------------------------------------------------------
app.get("/health", (req, res) => {
  res.json({ ok: true, service: "score_service" });
});

// -----------------------------------------------------------------------------
// ROUTES
// -----------------------------------------------------------------------------
const eventRoutes = require("./routes/eventRoutes");
const scoreRoutes = require("./routes/scoreRoutes");

// ✅ NEW: Global helper trust routes
const helperRoutes = require("./routes/helperRoutes");

// ✅ Existing recommendation routes
const recommendRoutes = require("./routes/recommendRoutes");

// Events: POST /events/attendance
app.use("/events", eventRoutes);

// Score routes
app.use("/score", scoreRoutes);

// ✅ Global helper search + trust score
// expected endpoints:
// - GET /helpers/search?q=...
// - GET /helpers/:userId/score
app.use("/", helperRoutes);

// ✅ Recommendation routes
// expected endpoint:
// - GET /recommendations?clinicId=...
app.use("/", recommendRoutes);

// -----------------------------------------------------------------------------
// 404 HANDLER
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
// ERROR HANDLER
// -----------------------------------------------------------------------------
app.use((err, req, res, next) => {
  console.error("❌ Unhandled error:", err);

  if (res.headersSent) return next(err);

  res.status(500).json({
    ok: false,
    error: "INTERNAL_SERVER_ERROR",
    message: IS_PROD ? "Internal Server Error" : err?.message || "unknown",
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

  mongoose.set("strictQuery", true);
  mongoose.set("sanitizeFilter", true);

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