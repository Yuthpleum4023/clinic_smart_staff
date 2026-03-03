// backend/payroll_service/server.js
require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

// ✅ OPTIONAL: decode JWT context (ไม่บังคับ) เพื่อช่วย bootstrap/debug
let jwt = null;
try {
  jwt = require("jsonwebtoken");
} catch (_) {
  jwt = null;
}

const app = express();

// -------------------- CORS --------------------
app.use(cors({ origin: "*", credentials: false }));

// -------------------- BODY PARSERS (สำคัญมาก) --------------------
// ✅ ป้องกัน req.body ว่าง/undefined ในบางเคส
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

// -------------------- Response Helpers (LONG-TERM STABLE) --------------------
// ✅ มาตรฐาน response ให้ค่อยๆ migrate routes ทีละตัวได้
app.use((req, res, next) => {
  res.ok = (data = {}, meta = undefined) => {
    const payload = { ok: true, data };
    if (meta !== undefined) payload.meta = meta;
    return res.status(200).json(payload);
  };

  res.fail = (
    status = 400,
    message = "BAD_REQUEST",
    code = "BAD_REQUEST",
    extra = undefined
  ) => {
    const payload = { ok: false, code, message };
    if (extra !== undefined) payload.extra = extra;
    return res.status(status).json(payload);
  };

  next();
});

// -------------------- JWT Context Decoder (NO-BREAK) --------------------
// ✅ ไม่บังคับ auth แต่อ่าน token ถ้ามี เพื่อให้ routes ใช้ข้อมูลได้ (debug + bootstrap)
// - ต้องตั้ง JWT_SECRET ให้ตรงกับ auth_user_service
app.use((req, res, next) => {
  req.userCtx = null;

  const auth = req.headers.authorization || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";

  if (!token || !jwt || !process.env.JWT_SECRET) return next();

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // ปรับให้ tolerant: ชื่อ field อาจต่างกัน
    const userId = (
      decoded.userId ||
      decoded.id ||
      decoded._id ||
      decoded.sub ||
      ""
    )
      .toString()
      .trim();

    const clinicId = (decoded.clinicId || decoded.clinic || decoded.cid || "")
      .toString()
      .trim();

    const role = (decoded.activeRole || decoded.role || "").toString().trim();

    req.userCtx = {
      userId,
      clinicId,
      role,
      roles: Array.isArray(decoded.roles) ? decoded.roles : undefined,
      raw: decoded,
    };
  } catch (_) {
    // ignore (token ผิด/หมดอายุ) — routes ที่บังคับ auth จะจัดการเอง
    req.userCtx = null;
  }

  next();
});

// -------------------- REQUEST LOGGER --------------------
app.use((req, res, next) => {
  const start = Date.now();
  const auth = req.headers.authorization;

  const ip =
    (req.headers["x-forwarded-for"] || "").toString().split(",")[0].trim() ||
    req.socket.remoteAddress;

  console.log("==========================================");
  console.log(`➡️  ${req.method} ${req.originalUrl}`);
  console.log(`   IP: ${ip || "-"}`);
  console.log(`   Host: ${req.headers.host || "-"}`);
  console.log(`   Authorization: ${auth ? "YES" : "NO"}`);

  const ct = req.headers["content-type"];
  if (ct) console.log(`   Content-Type: ${ct}`);

  // ✅ Log body preview เฉพาะ method ที่มักมี body
  if (["POST", "PUT", "PATCH"].includes(req.method)) {
    const safeBody = { ...(req.body || {}) };
    if (safeBody.password) safeBody.password = "***";
    if (safeBody.token) safeBody.token = "***";
    if (safeBody.jwt) safeBody.jwt = "***";
    if (safeBody.adminPassword) safeBody.adminPassword = "***";
    if (safeBody.pin) safeBody.pin = "***";
    console.log("   Body:", safeBody);
  }

  // ✅ log decoded context (ช่วย debug role/clinic/user)
  if (req.userCtx?.userId) {
    console.log("   UserCtx:", {
      userId: req.userCtx.userId,
      clinicId: req.userCtx.clinicId,
      role: req.userCtx.role,
    });
  }

  res.on("finish", () => {
    console.log(
      `⬅️  ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - start}ms)`
    );
    console.log("==========================================");
  });

  next();
});

// -------------------- Health --------------------
app.get("/health", (req, res) => {
  return res.ok({ service: "payroll_service" });
});

// ✅ Root route (กัน 404 เวลาเปิด URL ตรง ๆ / ช่วย monitoring)
app.get("/", (req, res) => {
  return res.ok({ service: "payroll_service", status: "running" });
});

// -------------------- INTERNAL (Bootstrap for Long-term Stability) --------------------
// ✅ auth_user_service จะยิงมาสร้าง/เตรียม profile mapping ให้ payroll_service
// ✅ ใช้ secret กันคนภายนอกเรียก
// ENV ที่ต้องมี:
// - INTERNAL_BOOTSTRAP_KEY=some-strong-key
//
// ตัวอย่างเรียกจาก auth_user_service:
// POST https://payroll.../internal/bootstrap
// Headers: x-internal-key: <INTERNAL_BOOTSTRAP_KEY>
// Body: { userId, clinicId, role, fullName, phone, email }
const INTERNAL_BOOTSTRAP_KEY = (process.env.INTERNAL_BOOTSTRAP_KEY || "").trim();

function _pickStr(v) {
  const s = (v ?? "").toString().trim();
  if (!s || s === "null" || s === "undefined") return "";
  return s;
}

function _normRole(v) {
  const r = _pickStr(v).toLowerCase();
  if (r === "helper") return "helper";
  if (r === "employee") return "employee";
  if (r === "admin") return "admin";
  return r;
}

// ✅ IMPORTANT: ประกาศ model/schema ครั้งเดียว (กัน index ซ้ำ/เตือนซ้ำ)
const BootstrapSchema =
  mongoose.models.UserBootstrap?.schema ||
  new mongoose.Schema(
    {
      userId: { type: String, required: true, index: true },
      clinicId: { type: String, default: "" },
      role: { type: String, default: "" },
      fullName: { type: String, default: "" },
      email: { type: String, default: "" },
      phone: { type: String, default: "" },
      updatedAt: { type: Date, default: Date.now },
      createdAt: { type: Date, default: Date.now },
    },
    { collection: "user_bootstraps" }
  );

// unique index (ทำครั้งเดียวพอ)
BootstrapSchema.index({ userId: 1 }, { unique: true });

const UserBootstrap =
  mongoose.models.UserBootstrap || mongoose.model("UserBootstrap", BootstrapSchema);

// ✅ ตรงนี้เป็น “hook ระยะยาว”
async function ensureBootstrapRecord(payload) {
  const now = new Date();
  const update = {
    clinicId: payload.clinicId || "",
    role: payload.role || "",
    fullName: payload.fullName || "",
    email: payload.email || "",
    phone: payload.phone || "",
    updatedAt: now,
  };

  await UserBootstrap.updateOne(
    { userId: payload.userId },
    { $set: update, $setOnInsert: { createdAt: now, userId: payload.userId } },
    { upsert: true }
  );

  return true;
}

app.post("/internal/bootstrap", async (req, res) => {
  try {
    if (!INTERNAL_BOOTSTRAP_KEY) {
      return res.fail(
        500,
        "INTERNAL_BOOTSTRAP_KEY missing on payroll_service",
        "CONFIG_MISSING"
      );
    }

    const key = _pickStr(req.headers["x-internal-key"]);
    if (!key || key !== INTERNAL_BOOTSTRAP_KEY) {
      return res.fail(403, "Forbidden", "FORBIDDEN");
    }

    const userId = _pickStr(req.body?.userId);
    const clinicId = _pickStr(req.body?.clinicId);
    const role = _normRole(req.body?.role);
    const fullName = _pickStr(req.body?.fullName);
    const email = _pickStr(req.body?.email);
    const phone = _pickStr(req.body?.phone);

    if (!userId) {
      return res.fail(400, "userId is required", "VALIDATION_ERROR");
    }

    await ensureBootstrapRecord({ userId, clinicId, role, fullName, email, phone });

    return res.ok({ bootstrapped: true, userId, clinicId, role });
  } catch (e) {
    console.error("❌ internal/bootstrap error:", e);
    return res.fail(500, e?.message || "internal error", "INTERNAL_ERROR");
  }
});

// -------------------- Routes --------------------
app.use("/shifts", require("./routes/shiftRoutes"));
app.use("/payroll", require("./routes/payrollRoutes"));

// ✅ ShiftNeed (ประกาศงานว่าง / รับงาน / approve -> สร้าง Shift)
app.use("/shift-needs", require("./routes/shiftNeedRoutes"));

// ✅ Payroll Close (ปิดงวดจริง + YTD)
app.use("/payroll-close", require("./routes/payrollCloseRoutes"));

// ✅ Clinics (location for navigation)
app.use("/clinics", require("./routes/clinicRoutes"));

// ✅ Clinic Policy (OT / Attendance Policy per clinic)
app.use("/clinic-policy", require("./routes/clinicPolicyRoutes"));

// ✅ Attendance (check-in/out)
app.use("/attendance", require("./routes/attendanceRoutes"));

// ✅ Availabilities (ตารางว่างผู้ช่วย -> ให้คลินิกเห็น)
app.use("/availabilities", require("./routes/availabilityRoutes"));

// ✅ Overtime (pending/approved/rejected/locked)
app.use("/overtime", require("./routes/overtimeRoutes"));

// ✅ Staff Proxy (dropdown จาก staff_service ผ่าน payroll_service)
app.use("/staff", require("./routes/staffRoutes"));

// -------------------- 404 handler --------------------
app.use((req, res) => {
  return res.status(404).json({
    ok: false,
    code: "NOT_FOUND",
    message: "Not Found",
    method: req.method,
    path: req.originalUrl,
  });
});

// -------------------- Error handler --------------------
app.use((err, req, res, next) => {
  console.error("❌ Unhandled error:", err);
  return res.status(500).json({
    ok: false,
    code: "INTERNAL_SERVER_ERROR",
    message: err?.message || "unknown",
  });
});

// -------------------- Start --------------------
const PORT = Number(process.env.PORT || 3102);

async function start() {
  if (!process.env.MONGO_URI) {
    console.error("❌ Missing MONGO_URI in .env");
    process.exit(1);
  }

  await mongoose.connect(process.env.MONGO_URI);
  console.log("✅ MongoDB connected (payroll_service)");

  const server = app.listen(PORT, () => {
    console.log(`🚀 payroll_service listening on port ${PORT}`);
  });

  // ✅ กัน port ค้างเวลา Ctrl+C
  process.on("SIGINT", () => {
    console.log("🛑 Shutting down payroll_service...");
    server.close(() => process.exit(0));
  });
}

start().catch((e) => {
  console.error("❌ payroll_service start failed:", e);
  process.exit(1);
});