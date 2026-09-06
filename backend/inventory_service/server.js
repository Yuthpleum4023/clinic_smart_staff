require("dotenv").config();

const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const helmet = require("helmet");
const hpp = require("hpp");
const mongoSanitize = require("express-mongo-sanitize");
const rateLimit = require("express-rate-limit");

const inventoryRoutes = require("./routes/inventoryRoutes");

const app = express();
app.disable("x-powered-by");

app.use(helmet());

const allowedOrigins = String(process.env.CORS_ORIGINS || "")
  .split(",")
  .map((x) => x.trim())
  .filter(Boolean);

app.use(
  cors({
    origin(origin, callback) {
      if (!origin) return callback(null, true);
      if (process.env.NODE_ENV !== "production" && allowedOrigins.length === 0) {
        return callback(null, true);
      }
      if (allowedOrigins.includes(origin)) return callback(null, true);
      return callback(new Error("CORS origin not allowed"));
    },
    credentials: false,
  })
);

app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));
app.use(mongoSanitize({ replaceWith: "_" }));
app.use(hpp());

app.use(
  rateLimit({
    windowMs: 60 * 1000,
    max: 300,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.use((req, res, next) => {
  const incoming =
    String(req.headers["x-request-id"] || "").trim() ||
    `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  req.requestId = incoming;
  res.setHeader("x-request-id", incoming);
  next();
});

app.get("/health", (req, res) => {
  res.json({
    ok: true,
    service: "inventory_service",
    storage: mongoose.connection.readyState === 1 ? "mongodb" : "disconnected",
  });
});

app.use("/inventory", inventoryRoutes);
app.use("/api/inventory", inventoryRoutes);

app.use((req, res) => {
  res.status(404).json({
    ok: false,
    code: "NOT_FOUND",
    method: req.method,
    path: req.originalUrl,
  });
});

app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);

  const status = Number(err?.status) || 500;
  const isProd = process.env.NODE_ENV === "production";

  if (status >= 500) {
    console.error("inventory_service error", {
      requestId: req.requestId,
      code: err?.code || "INTERNAL_SERVER_ERROR",
      message: err?.message,
    });
  }

  return res.status(status).json({
    ok: false,
    code: err?.code || (status >= 500 ? "INTERNAL_SERVER_ERROR" : "REQUEST_FAILED"),
    message:
      status >= 500 && isProd
        ? "Internal server error"
        : err?.message || "Request failed",
    ...(err?.details ? { details: err.details } : {}),
    requestId: req.requestId,
  });
});

const PORT = Number(process.env.PORT || 3105);

async function start() {
  if (!process.env.MONGO_URI) {
    throw new Error("Missing MONGO_URI");
  }

  mongoose.set("strictQuery", true);
  await mongoose.connect(process.env.MONGO_URI);

  console.log("MongoDB connected (inventory_service)");

  app.listen(PORT, () => {
    console.log(`inventory_service listening on port ${PORT}`);
  });
}

start().catch((err) => {
  console.error("inventory_service start failed:", err);
  process.exit(1);
});
