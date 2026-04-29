// controllers/employeeController.js
// ==================================================
// PURPOSE: Employee CRUD (Staff service)
//
// ✅ PRODUCTION FULL FILE
// - Admin employee CRUD scoped by clinicId
// - Safe getters: by-user / by-staff / by-id
// - Always return staffId = String(_id)
// - Return Flutter-compatible aliases:
//   id, staffId, linkedUserId, firstName, lastName,
//   baseSalary, hourlyWage, bonus, absentDays, position
// - Save payroll-related fields to backend:
//   position, employeeCode, bonus, absentDays,
//   otherAllowance, otherDeduction
// - Safe update whitelist: no direct req.body mass assignment
// - Internal ensure route for service-to-service flow
// - Duplicate-safe / idempotent employee creation by clinicId + userId
// - Supports unlinked manual employee records when userId is empty
// ==================================================

const mongoose = require("mongoose");
const Employee = require("../schemas/Employee");

// --------------------------------------------------
// Basic helpers
// --------------------------------------------------
function s(v) {
  return String(v ?? "").trim();
}

function n(v, fallback = 0) {
  if (v === undefined || v === null || v === "") return fallback;
  const cleaned = typeof v === "string" ? v.replace(/,/g, "").trim() : v;
  const x = Number(cleaned);
  return Number.isFinite(x) ? x : fallback;
}

function i(v, fallback = 0) {
  const x = Math.floor(n(v, fallback));
  return Number.isFinite(x) ? x : fallback;
}

function min0(v, fallback = 0) {
  return Math.max(0, n(v, fallback));
}

function clamp(v, min, max, fallback = 0) {
  const x = n(v, fallback);
  return Math.max(min, Math.min(max, x));
}

function isObjectId(v) {
  return mongoose.Types.ObjectId.isValid(String(v || ""));
}

function isAdmin(req) {
  return s(req.user?.role) === "admin";
}

function pickReqId(req) {
  return s(
    req.headers["x-request-id"] ||
      req.headers["x-correlation-id"] ||
      req.headers["x-trace-id"] ||
      ""
  );
}

function safeReqMeta(req) {
  return {
    method: s(req.method),
    path: s(req.originalUrl || req.url),
    ip: s(req.headers["x-forwarded-for"] || req.ip),
    reqId: pickReqId(req),
    userId: s(req.user?.userId),
    role: s(req.user?.role),
    clinicId: s(req.user?.clinicId),
    hasInternalKey: !!s(req.headers["x-internal-key"]),
  };
}

function logEmployeeDebug(label, data = {}) {
  try {
    console.log(`[EMPLOYEE][DEBUG] ${label}`, data);
  } catch (_) {}
}

function errorShape(err) {
  return {
    name: s(err?.name),
    message: s(err?.message),
    code: err?.code ?? null,
    status: err?.status ?? null,
    errors:
      err?.errors && typeof err.errors === "object"
        ? Object.keys(err.errors)
        : [],
  };
}

function hasSchemaPath(path) {
  try {
    return !!Employee?.schema?.path(path);
  } catch (_) {
    return false;
  }
}

function hasClinicIdField() {
  return hasSchemaPath("clinicId");
}

function isDuplicateKeyError(err) {
  return !!(err && (err.code === 11000 || err.code === 11001));
}

function hasOwn(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj || {}, key);
}

function hasAny(obj, keys = []) {
  return keys.some((k) => hasOwn(obj, k));
}

function pickFirst(obj, keys = []) {
  for (const k of keys) {
    if (hasOwn(obj, k)) return obj[k];
  }
  return undefined;
}

function splitFullName(fullName) {
  const parts = s(fullName).split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { firstName: "", lastName: "" };
  if (parts.length === 1) return { firstName: parts[0], lastName: "" };

  return {
    firstName: parts[0],
    lastName: parts.slice(1).join(" "),
  };
}

function normalizeEmploymentType(v) {
  const t = s(v).toLowerCase();

  if (!t) return "fullTime";

  if (
    ["fulltime", "full_time", "full-time", "full time", "ft", "monthly"].includes(
      t
    )
  ) {
    return "fullTime";
  }

  if (
    ["parttime", "part_time", "part-time", "part time", "pt", "hourly"].includes(
      t
    )
  ) {
    return "partTime";
  }

  return t === "partTime" ? "partTime" : "fullTime";
}

function clinicScopeQuery(req) {
  if (!hasClinicIdField()) return {};
  const clinicId = s(req.user?.clinicId);
  return clinicId ? { clinicId } : {};
}

function getInternalClinicId(req) {
  return (
    s(req.query?.clinicId) ||
    s(req.body?.clinicId) ||
    s(req.headers["x-clinic-id"]) ||
    ""
  );
}

// --------------------------------------------------
// Flutter-compatible output
// --------------------------------------------------
function withStaffId(emp) {
  if (!emp) return emp;

  const obj =
    typeof emp.toObject === "function"
      ? emp.toObject({ virtuals: true })
      : { ...emp };

  const id = s(obj._id || obj.id);
  const staffId = id || s(obj.staffId);

  const fullName = s(obj.fullName);
  const split = splitFullName(fullName);

  const linkedUserId = s(obj.linkedUserId || obj.linked_user_id || obj.userId);

  const employmentTypeRaw = s(obj.employmentType);
  const employmentType =
    normalizeEmploymentType(employmentTypeRaw) === "partTime"
      ? "parttime"
      : "fulltime";

  const monthlySalary = min0(
    obj.monthlySalary !== undefined ? obj.monthlySalary : obj.baseSalary,
    0
  );

  const hourlyRate = min0(
    obj.hourlyRate !== undefined ? obj.hourlyRate : obj.hourlyWage,
    0
  );

  return {
    ...obj,

    id: staffId,
    _id: obj._id,
    staffId,

    linkedUserId,
    userId: s(obj.userId || linkedUserId),

    firstName: s(obj.firstName) || split.firstName,
    lastName: s(obj.lastName) || split.lastName,
    fullName,

    employeeCode: s(obj.employeeCode),
    position: s(obj.position) || "Staff",

    employmentType,
    employmentTypeBackend: normalizeEmploymentType(obj.employmentType),

    monthlySalary,
    baseSalary: monthlySalary,

    hourlyRate,
    hourlyWage: hourlyRate,

    bonus: min0(obj.bonus, 0),
    absentDays: i(obj.absentDays, 0),

    otherAllowance: min0(obj.otherAllowance, 0),
    otherDeduction: min0(obj.otherDeduction, 0),

    active: obj.active !== false,
  };
}

// --------------------------------------------------
// Payload builders
// --------------------------------------------------
function buildFullNameFromInput(input = {}) {
  const direct = s(input.fullName || input.name);
  if (direct) return direct;

  const first = s(input.firstName);
  const last = s(input.lastName);
  return [first, last].filter(Boolean).join(" ").trim();
}

function normalizeUserLinkFields(input = {}) {
  const userId = s(
    pickFirst(input, [
      "userId",
      "linkedUserId",
      "linked_user_id",
      "authUserId",
      "auth_user_id",
    ])
  );

  const linkedUserId = s(
    pickFirst(input, [
      "linkedUserId",
      "linked_user_id",
      "userId",
      "authUserId",
      "auth_user_id",
    ])
  );

  const resolved = userId || linkedUserId;

  return {
    userId: resolved,
    linkedUserId: resolved,
  };
}

function buildEmployeeCreatePayload(input = {}, opts = {}) {
  const userLink = normalizeUserLinkFields(input);

  const payload = {
    userId: userLink.userId,
    linkedUserId: userLink.linkedUserId,
    fullName: buildFullNameFromInput(input),
    position: s(input.position) || "Staff",
    employeeCode: s(input.employeeCode || input.employee_code),
    employmentType: normalizeEmploymentType(input.employmentType),
    active:
      input.active === undefined && input.isActive === undefined
        ? true
        : !!(input.active ?? input.isActive),
  };

  if (hasClinicIdField()) {
    payload.clinicId = s(opts.forceClinicId || input.clinicId);
  }

  if (hasSchemaPath("monthlySalary")) {
    payload.monthlySalary = min0(
      pickFirst(input, [
        "monthlySalary",
        "baseSalary",
        "salary",
        "grossBase",
        "grossMonthly",
      ]),
      0
    );
  }

  if (hasSchemaPath("hourlyRate")) {
    payload.hourlyRate = min0(
      pickFirst(input, ["hourlyRate", "hourlyWage", "wagePerHour"]),
      0
    );
  }

  if (hasSchemaPath("bonus")) {
    payload.bonus = min0(input.bonus, 0);
  }

  if (hasSchemaPath("absentDays")) {
    payload.absentDays = clamp(input.absentDays, 0, 31, 0);
  }

  if (hasSchemaPath("otherAllowance")) {
    payload.otherAllowance = min0(
      pickFirst(input, ["otherAllowance", "commission", "allowance"]),
      0
    );
  }

  if (hasSchemaPath("otherDeduction")) {
    payload.otherDeduction = min0(
      pickFirst(input, ["otherDeduction", "deduction"]),
      0
    );
  }

  if (hasSchemaPath("hoursPerDay")) {
    payload.hoursPerDay = min0(input.hoursPerDay, 8) || 8;
  }

  if (hasSchemaPath("workingDaysPerMonth")) {
    payload.workingDaysPerMonth =
      min0(input.workingDaysPerMonth, 26) || 26;
  }

  if (hasSchemaPath("otMultiplierNormal")) {
    payload.otMultiplierNormal =
      min0(input.otMultiplierNormal, 1.5) || 1.5;
  }

  if (hasSchemaPath("otMultiplierHoliday")) {
    payload.otMultiplierHoliday =
      min0(input.otMultiplierHoliday, 2.0) || 2.0;
  }

  if (hasSchemaPath("provisionedFrom")) {
    payload.provisionedFrom = s(
      input.provisionedFrom || opts.provisionedFrom || "manual"
    );
  }

  if (payload.employmentType === "partTime") {
    payload.monthlySalary = 0;
    payload.absentDays = 0;
  }

  if (payload.employmentType === "fullTime") {
    payload.hourlyRate = 0;
  }

  return payload;
}

function buildEmployeeUpdatePayload(input = {}, opts = {}) {
  const payload = {};

  if (hasClinicIdField() && opts.forceClinicId) {
    payload.clinicId = s(opts.forceClinicId);
  }

  if (
    hasAny(input, [
      "userId",
      "linkedUserId",
      "linked_user_id",
      "authUserId",
      "auth_user_id",
    ])
  ) {
    const userLink = normalizeUserLinkFields(input);
    payload.userId = userLink.userId;
    payload.linkedUserId = userLink.linkedUserId;
  }

  if (
    hasAny(input, ["fullName", "name", "firstName", "lastName"])
  ) {
    payload.fullName = buildFullNameFromInput(input);
  }

  if (hasOwn(input, "position")) {
    payload.position = s(input.position) || "Staff";
  }

  if (hasOwn(input, "employeeCode") || hasOwn(input, "employee_code")) {
    payload.employeeCode = s(input.employeeCode || input.employee_code);
  }

  if (hasOwn(input, "employmentType")) {
    payload.employmentType = normalizeEmploymentType(input.employmentType);
  }

  if (
    hasAny(input, [
      "monthlySalary",
      "baseSalary",
      "salary",
      "grossBase",
      "grossMonthly",
    ]) &&
    hasSchemaPath("monthlySalary")
  ) {
    payload.monthlySalary = min0(
      pickFirst(input, [
        "monthlySalary",
        "baseSalary",
        "salary",
        "grossBase",
        "grossMonthly",
      ]),
      0
    );
  }

  if (
    hasAny(input, ["hourlyRate", "hourlyWage", "wagePerHour"]) &&
    hasSchemaPath("hourlyRate")
  ) {
    payload.hourlyRate = min0(
      pickFirst(input, ["hourlyRate", "hourlyWage", "wagePerHour"]),
      0
    );
  }

  if (hasOwn(input, "bonus") && hasSchemaPath("bonus")) {
    payload.bonus = min0(input.bonus, 0);
  }

  if (hasOwn(input, "absentDays") && hasSchemaPath("absentDays")) {
    payload.absentDays = clamp(input.absentDays, 0, 31, 0);
  }

  if (
    hasAny(input, ["otherAllowance", "commission", "allowance"]) &&
    hasSchemaPath("otherAllowance")
  ) {
    payload.otherAllowance = min0(
      pickFirst(input, ["otherAllowance", "commission", "allowance"]),
      0
    );
  }

  if (
    hasAny(input, ["otherDeduction", "deduction"]) &&
    hasSchemaPath("otherDeduction")
  ) {
    payload.otherDeduction = min0(
      pickFirst(input, ["otherDeduction", "deduction"]),
      0
    );
  }

  if (hasOwn(input, "hoursPerDay") && hasSchemaPath("hoursPerDay")) {
    payload.hoursPerDay = min0(input.hoursPerDay, 8) || 8;
  }

  if (
    hasOwn(input, "workingDaysPerMonth") &&
    hasSchemaPath("workingDaysPerMonth")
  ) {
    payload.workingDaysPerMonth =
      min0(input.workingDaysPerMonth, 26) || 26;
  }

  if (
    hasOwn(input, "otMultiplierNormal") &&
    hasSchemaPath("otMultiplierNormal")
  ) {
    payload.otMultiplierNormal =
      min0(input.otMultiplierNormal, 1.5) || 1.5;
  }

  if (
    hasOwn(input, "otMultiplierHoliday") &&
    hasSchemaPath("otMultiplierHoliday")
  ) {
    payload.otMultiplierHoliday =
      min0(input.otMultiplierHoliday, 2.0) || 2.0;
  }

  if (
    (hasOwn(input, "active") || hasOwn(input, "isActive")) &&
    hasSchemaPath("active")
  ) {
    payload.active = !!(input.active ?? input.isActive);
  }

  // Normalize according to final employment type if known.
  const nextType = payload.employmentType;
  if (nextType === "partTime") {
    payload.monthlySalary = 0;
    payload.absentDays = 0;
  }

  if (nextType === "fullTime") {
    payload.hourlyRate = 0;
  }

  return payload;
}

function validateCreatePayload(payload, { internal = false } = {}) {
  if (hasClinicIdField() && !s(payload.clinicId)) {
    return "clinicId is required";
  }

  if (internal && !s(payload.userId)) {
    return "userId is required";
  }

  if (!s(payload.fullName)) {
    return "fullName is required";
  }

  if (payload.employmentType === "fullTime") {
    if (min0(payload.monthlySalary, 0) <= 0 && !internal) {
      return "monthlySalary/baseSalary must be greater than 0 for full-time employee";
    }
  }

  if (payload.employmentType === "partTime") {
    if (min0(payload.hourlyRate, 0) <= 0 && !internal) {
      return "hourlyRate/hourlyWage must be greater than 0 for part-time employee";
    }
  }

  return "";
}

// --------------------------------------------------
// Find helpers
// --------------------------------------------------
async function findEmployeeByUserIdScoped(userId, clinicId = "") {
  const uid = s(userId);
  if (!uid) return null;

  const q = {
    $or: [{ userId: uid }],
  };

  if (hasSchemaPath("linkedUserId")) {
    q.$or.push({ linkedUserId: uid });
  }

  if (hasClinicIdField() && clinicId) {
    q.clinicId = s(clinicId);
  }

  logEmployeeDebug("findEmployeeByUserIdScoped.query", q);

  const emp = await Employee.findOne(q).lean();

  logEmployeeDebug("findEmployeeByUserIdScoped.result", {
    userId: uid,
    clinicId: s(clinicId),
    found: !!emp,
    employeeId: s(emp?._id),
    staffId: s(emp?._id || emp?.staffId),
  });

  return emp;
}

async function findEmployeeByStaffIdScoped(staffId, clinicId = "") {
  const sid = s(staffId);

  if (!isObjectId(sid)) {
    logEmployeeDebug("findEmployeeByStaffIdScoped.invalid", {
      staffId: sid,
      clinicId: s(clinicId),
    });
    return null;
  }

  const emp = await Employee.findById(sid).lean();

  logEmployeeDebug("findEmployeeByStaffIdScoped.byId", {
    staffId: sid,
    clinicId: s(clinicId),
    found: !!emp,
    employeeClinicId: s(emp?.clinicId),
  });

  if (!emp) return null;

  if (hasClinicIdField() && clinicId && s(emp.clinicId) !== s(clinicId)) {
    logEmployeeDebug("findEmployeeByStaffIdScoped.clinic_mismatch", {
      staffId: sid,
      wantedClinicId: s(clinicId),
      employeeClinicId: s(emp.clinicId),
    });
    return null;
  }

  return emp;
}

async function createOrGetExistingEmployee(payload) {
  logEmployeeDebug("createOrGetExistingEmployee.start", {
    userId: s(payload.userId),
    linkedUserId: s(payload.linkedUserId),
    clinicId: s(payload.clinicId),
    fullName: s(payload.fullName),
    employmentType: s(payload.employmentType),
    active: !!payload.active,
    provisionedFrom: s(payload.provisionedFrom),
  });

  // Idempotency only applies when linked to a user.
  if (s(payload.userId)) {
    const existing = await findEmployeeByUserIdScoped(
      payload.userId,
      payload.clinicId
    );

    if (existing) {
      logEmployeeDebug("createOrGetExistingEmployee.existing", {
        userId: s(payload.userId),
        clinicId: s(payload.clinicId),
        employeeId: s(existing?._id),
      });

      return {
        created: false,
        employee: existing,
      };
    }
  }

  try {
    const emp = await Employee.create(payload);

    logEmployeeDebug("createOrGetExistingEmployee.created", {
      userId: s(payload.userId),
      clinicId: s(payload.clinicId),
      employeeId: s(emp?._id),
    });

    return {
      created: true,
      employee: emp,
    };
  } catch (err) {
    logEmployeeDebug("createOrGetExistingEmployee.create_error", {
      payload: {
        userId: s(payload.userId),
        clinicId: s(payload.clinicId),
        fullName: s(payload.fullName),
        employmentType: s(payload.employmentType),
      },
      error: errorShape(err),
    });

    if (isDuplicateKeyError(err) && s(payload.userId)) {
      const existingAfterConflict = await findEmployeeByUserIdScoped(
        payload.userId,
        payload.clinicId
      );

      if (existingAfterConflict) {
        logEmployeeDebug("createOrGetExistingEmployee.duplicate_existing", {
          userId: s(payload.userId),
          clinicId: s(payload.clinicId),
          employeeId: s(existingAfterConflict?._id),
        });

        return {
          created: false,
          employee: existingAfterConflict,
        };
      }
    }

    throw err;
  }
}

// --------------------------------------------------
// CREATE
// Route should guard admin
// --------------------------------------------------
exports.createEmployee = async (req, res) => {
  try {
    const forceClinicId = hasClinicIdField() ? s(req.user?.clinicId) : "";

    logEmployeeDebug("createEmployee.hit", {
      ...safeReqMeta(req),
      rawBody: req.body || {},
      hasClinicIdField: hasClinicIdField(),
    });

    if (hasClinicIdField() && !forceClinicId) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const payload = buildEmployeeCreatePayload(req.body || {}, {
      forceClinicId,
      provisionedFrom: "manual_admin",
    });

    const validationError = validateCreatePayload(payload, { internal: false });
    if (validationError) {
      return res.status(400).json({
        ok: false,
        message: validationError,
        error: validationError,
      });
    }

    const result = await createOrGetExistingEmployee(payload);

    logEmployeeDebug("createEmployee.success", {
      ...safeReqMeta(req),
      created: !!result.created,
      employeeId: s(result?.employee?._id),
      staffId: s(result?.employee?._id || result?.employee?.staffId),
      userId: s(result?.employee?.userId),
      clinicId: s(result?.employee?.clinicId),
    });

    return res.status(result.created ? 201 : 200).json({
      ok: true,
      existed: !result.created,
      created: result.created,
      employee: withStaffId(result.employee),
    });
  } catch (err) {
    logEmployeeDebug("createEmployee.failed", {
      ...safeReqMeta(req),
      error: errorShape(err),
      rawBody: req.body || {},
    });

    const status = isDuplicateKeyError(err) ? 409 : 400;
    return res.status(status).json({
      ok: false,
      message: isDuplicateKeyError(err)
        ? "Employee already exists for this user in this clinic"
        : err.message,
      error: err.message,
    });
  }
};

// --------------------------------------------------
// INTERNAL ENSURE FROM USER
// POST /api/employees/internal/ensure
// --------------------------------------------------
async function ensureEmployeeInternalHandler(req, res) {
  try {
    logEmployeeDebug("internal.ensure.hit", {
      ...safeReqMeta(req),
      rawBody: req.body || {},
      hasClinicIdField: hasClinicIdField(),
    });

    const payload = buildEmployeeCreatePayload(req.body || {}, {
      provisionedFrom: "internal_ensure",
    });

    const validationError = validateCreatePayload(payload, { internal: true });
    if (validationError) {
      return res.status(400).json({
        ok: false,
        message: validationError,
      });
    }

    const result = await createOrGetExistingEmployee(payload);

    logEmployeeDebug("internal.ensure.success", {
      ...safeReqMeta(req),
      created: !!result.created,
      employeeId: s(result?.employee?._id),
      staffId: s(result?.employee?._id || result?.employee?.staffId),
      userId: s(result?.employee?.userId),
      clinicId: s(result?.employee?.clinicId),
    });

    return res.status(result.created ? 201 : 200).json({
      ok: true,
      created: result.created,
      employee: withStaffId(result.employee),
    });
  } catch (err) {
    logEmployeeDebug("internal.ensure.failed", {
      ...safeReqMeta(req),
      error: errorShape(err),
      rawBody: req.body || {},
    });

    console.error("❌ ensureEmployeeInternal failed:", err);

    const status = isDuplicateKeyError(err) ? 409 : 500;
    return res.status(status).json({
      ok: false,
      message: err.message || "ensureEmployeeInternal failed",
    });
  }
}

exports.ensureEmployeeInternal = ensureEmployeeInternalHandler;
exports.createEmployeeFromInternal = ensureEmployeeInternalHandler;

// --------------------------------------------------
// INTERNAL GET BY USER ID
// GET /api/employees/internal/by-user/:userId
// --------------------------------------------------
exports.getEmployeeByUserIdInternal = async (req, res) => {
  try {
    const userId = s(req.params.userId);
    const clinicId = getInternalClinicId(req);

    logEmployeeDebug("internal.by-user.hit", {
      ...safeReqMeta(req),
      paramUserId: userId,
      clinicIdFromResolver: clinicId,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!userId) {
      return res.status(400).json({
        ok: false,
        message: "userId required",
      });
    }

    if (hasClinicIdField() && !clinicId) {
      return res.status(400).json({
        ok: false,
        message: "clinicId required",
      });
    }

    const emp = await findEmployeeByUserIdScoped(userId, clinicId);

    if (!emp) {
      return res.status(404).json({
        ok: false,
        message: "Employee not found",
      });
    }

    return res.json({
      ok: true,
      employee: withStaffId(emp),
    });
  } catch (err) {
    logEmployeeDebug("internal.by-user.failed", {
      ...safeReqMeta(req),
      paramUserId: s(req.params?.userId),
      clinicId: getInternalClinicId(req),
      error: errorShape(err),
    });

    return res.status(500).json({
      ok: false,
      error: err.message,
    });
  }
};

// --------------------------------------------------
// INTERNAL GET BY STAFF ID
// GET /api/employees/internal/by-staff/:staffId
// --------------------------------------------------
exports.getEmployeeByStaffIdInternal = async (req, res) => {
  try {
    const staffId = s(req.params.staffId);
    const clinicId = getInternalClinicId(req);

    logEmployeeDebug("internal.by-staff.hit", {
      ...safeReqMeta(req),
      paramStaffId: staffId,
      clinicIdFromResolver: clinicId,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(staffId)) {
      return res.status(400).json({
        ok: false,
        message: "Invalid staffId",
      });
    }

    if (hasClinicIdField() && !clinicId) {
      return res.status(400).json({
        ok: false,
        message: "clinicId required",
      });
    }

    const emp = await findEmployeeByStaffIdScoped(staffId, clinicId);

    if (!emp) {
      return res.status(404).json({
        ok: false,
        message: "Employee not found",
      });
    }

    return res.json({
      ok: true,
      employee: withStaffId(emp),
    });
  } catch (err) {
    logEmployeeDebug("internal.by-staff.failed", {
      ...safeReqMeta(req),
      paramStaffId: s(req.params?.staffId),
      clinicId: getInternalClinicId(req),
      error: errorShape(err),
    });

    return res.status(500).json({
      ok: false,
      error: err.message,
    });
  }
};

// --------------------------------------------------
// GET BY ID
// - admin: can read within clinic
// - non-admin: only own record
// --------------------------------------------------
exports.getEmployeeById = async (req, res) => {
  try {
    const id = s(req.params.id);

    logEmployeeDebug("getById.hit", {
      ...safeReqMeta(req),
      employeeId: id,
    });

    if (!isObjectId(id)) {
      return res.status(400).json({ ok: false, error: "Invalid employee id" });
    }

    const emp = await Employee.findById(id).lean();

    if (!emp) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    if (hasClinicIdField()) {
      const tokenClinicId = s(req.user?.clinicId);
      if (!tokenClinicId) {
        return res
          .status(401)
          .json({ ok: false, message: "Missing clinicId in token" });
      }

      if (s(emp.clinicId) !== tokenClinicId) {
        return res
          .status(403)
          .json({ ok: false, message: "Forbidden (different clinic)" });
      }
    }

    if (!isAdmin(req)) {
      const tokenUserId = s(req.user?.userId);
      const tokenStaffId = s(req.user?.staffId);

      const ownsByUser =
        !!tokenUserId &&
        (s(emp.userId) === tokenUserId || s(emp.linkedUserId) === tokenUserId);
      const ownsByStaff = !!tokenStaffId && tokenStaffId === id;

      if (!ownsByUser && !ownsByStaff) {
        return res.status(403).json({ ok: false, message: "Forbidden" });
      }
    }

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    logEmployeeDebug("getById.failed", {
      ...safeReqMeta(req),
      employeeId: s(req.params?.id),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// --------------------------------------------------
// LIST EMPLOYEES
// Route should be admin-only
// --------------------------------------------------
exports.listEmployees = async (req, res) => {
  try {
    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const q = { active: true, ...clinicScopeQuery(req) };

    logEmployeeDebug("listEmployees.hit", {
      ...safeReqMeta(req),
      query: q,
      hasClinicIdField: hasClinicIdField(),
    });

    const list = await Employee.find(q).sort({ createdAt: -1 }).lean();

    return res.json({
      ok: true,
      items: list.map(withStaffId),
    });
  } catch (err) {
    logEmployeeDebug("listEmployees.failed", {
      ...safeReqMeta(req),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// --------------------------------------------------
// LIST FOR DROPDOWN
// GET /api/employees/dropdown
// --------------------------------------------------
exports.listForDropdown = async (req, res) => {
  try {
    const role = s(req.user?.role);

    logEmployeeDebug("listForDropdown.hit", {
      ...safeReqMeta(req),
      role,
      hasClinicIdField: hasClinicIdField(),
    });

    if (role !== "admin") {
      return res
        .status(403)
        .json({ ok: false, message: "Forbidden (admin only)" });
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const q = { active: true, ...clinicScopeQuery(req) };

    const list = await Employee.find(q)
      .select(
        "_id clinicId userId linkedUserId fullName employeeCode position employmentType monthlySalary hourlyRate bonus absentDays active"
      )
      .sort({ fullName: 1 })
      .lean();

    return res.json({
      ok: true,
      items: list.map(withStaffId).filter((x) => x.staffId),
    });
  } catch (err) {
    logEmployeeDebug("listForDropdown.failed", {
      ...safeReqMeta(req),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// --------------------------------------------------
// GET BY USER ID
// GET /api/employees/by-user/:userId
// --------------------------------------------------
exports.getEmployeeByUserId = async (req, res) => {
  try {
    const paramUserId = s(req.params.userId);
    const tokenUserId = s(req.user?.userId);

    logEmployeeDebug("getByUserId.hit", {
      ...safeReqMeta(req),
      paramUserId,
      tokenUserId,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!paramUserId) {
      return res.status(400).json({
        ok: false,
        message: "userId required",
      });
    }

    if (!isAdmin(req)) {
      if (!tokenUserId || tokenUserId !== paramUserId) {
        return res.status(403).json({ ok: false, message: "Forbidden" });
      }
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const emp = await findEmployeeByUserIdScoped(
      paramUserId,
      s(req.user?.clinicId)
    );

    if (!emp || emp.active === false) {
      return res.status(404).json({
        ok: false,
        message: "Employee not found",
      });
    }

    return res.json({
      ok: true,
      employee: withStaffId(emp),
    });
  } catch (err) {
    logEmployeeDebug("getByUserId.failed", {
      ...safeReqMeta(req),
      paramUserId: s(req.params?.userId),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// --------------------------------------------------
// GET BY STAFF ID
// GET /api/employees/by-staff/:staffId
// --------------------------------------------------
exports.getEmployeeByStaffId = async (req, res) => {
  try {
    const staffId = s(req.params.staffId);

    logEmployeeDebug("getByStaffId.hit", {
      ...safeReqMeta(req),
      paramStaffId: staffId,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(staffId)) {
      return res.status(400).json({
        ok: false,
        message: "Invalid staffId",
      });
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const emp = await Employee.findById(staffId).lean();

    if (!emp || emp.active === false) {
      return res.status(404).json({
        ok: false,
        message: "Employee not found",
      });
    }

    if (hasClinicIdField()) {
      const tokenClinicId = s(req.user?.clinicId);
      if (s(emp.clinicId) !== tokenClinicId) {
        return res
          .status(403)
          .json({ ok: false, message: "Forbidden (different clinic)" });
      }
    }

    if (!isAdmin(req)) {
      const tokenUserId = s(req.user?.userId);
      const tokenStaffId = s(req.user?.staffId);

      const ownsByUser =
        !!tokenUserId &&
        (s(emp.userId) === tokenUserId || s(emp.linkedUserId) === tokenUserId);
      const ownsByStaff = !!tokenStaffId && tokenStaffId === staffId;

      if (!ownsByUser && !ownsByStaff) {
        return res.status(403).json({ ok: false, message: "Forbidden" });
      }
    }

    return res.json({
      ok: true,
      employee: withStaffId(emp),
    });
  } catch (err) {
    logEmployeeDebug("getByStaffId.failed", {
      ...safeReqMeta(req),
      paramStaffId: s(req.params?.staffId),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// --------------------------------------------------
// UPDATE EMPLOYEE
// Route should guard admin
// --------------------------------------------------
exports.updateEmployee = async (req, res) => {
  try {
    const id = s(req.params.id);

    logEmployeeDebug("updateEmployee.hit", {
      ...safeReqMeta(req),
      employeeId: id,
      rawBody: req.body || {},
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(id)) {
      return res.status(400).json({
        ok: false,
        error: "Invalid employee id",
      });
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const existing = await Employee.findById(id).lean();

    if (!existing) {
      return res.status(404).json({
        ok: false,
        error: "Employee not found",
      });
    }

    if (hasClinicIdField()) {
      const tokenClinicId = s(req.user?.clinicId);
      if (s(existing.clinicId) !== tokenClinicId) {
        return res
          .status(403)
          .json({ ok: false, message: "Forbidden (different clinic)" });
      }
    }

    const update = buildEmployeeUpdatePayload(req.body || {}, {
      forceClinicId: hasClinicIdField() ? s(req.user?.clinicId) : "",
    });

    if (Object.keys(update).length === 0) {
      return res.status(400).json({
        ok: false,
        message: "No valid fields to update",
      });
    }

    logEmployeeDebug("updateEmployee.normalizedUpdate", {
      ...safeReqMeta(req),
      employeeId: id,
      update,
    });

    const emp = await Employee.findByIdAndUpdate(
      id,
      { $set: update },
      {
        new: true,
        runValidators: true,
        context: "query",
      }
    ).lean();

    if (!emp) {
      return res.status(404).json({
        ok: false,
        error: "Employee not found",
      });
    }

    logEmployeeDebug("updateEmployee.success", {
      ...safeReqMeta(req),
      employeeId: id,
      userId: s(emp?.userId),
      linkedUserId: s(emp?.linkedUserId),
      clinicId: s(emp?.clinicId),
      bonus: emp?.bonus,
      absentDays: emp?.absentDays,
      position: s(emp?.position),
    });

    return res.json({
      ok: true,
      employee: withStaffId(emp),
    });
  } catch (err) {
    logEmployeeDebug("updateEmployee.failed", {
      ...safeReqMeta(req),
      employeeId: s(req.params?.id),
      error: errorShape(err),
      rawBody: req.body || {},
    });

    const status = isDuplicateKeyError(err) ? 409 : 400;
    return res.status(status).json({
      ok: false,
      message: isDuplicateKeyError(err)
        ? "Employee already exists for this user in this clinic"
        : err.message,
      error: err.message,
    });
  }
};

// --------------------------------------------------
// DEACTIVATE EMPLOYEE
// Route should guard admin
// --------------------------------------------------
exports.deactivateEmployee = async (req, res) => {
  try {
    const id = s(req.params.id);

    logEmployeeDebug("deactivateEmployee.hit", {
      ...safeReqMeta(req),
      employeeId: id,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(id)) {
      return res.status(400).json({
        ok: false,
        error: "Invalid employee id",
      });
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const existing = await Employee.findById(id).lean();

    if (!existing) {
      return res.status(404).json({
        ok: false,
        error: "Employee not found",
      });
    }

    if (hasClinicIdField()) {
      const tokenClinicId = s(req.user?.clinicId);
      if (s(existing.clinicId) !== tokenClinicId) {
        return res
          .status(403)
          .json({ ok: false, message: "Forbidden (different clinic)" });
      }
    }

    const emp = await Employee.findByIdAndUpdate(
      id,
      { $set: { active: false } },
      { new: true, runValidators: true }
    ).lean();

    return res.json({
      ok: true,
      employee: withStaffId(emp),
    });
  } catch (err) {
    logEmployeeDebug("deactivateEmployee.failed", {
      ...safeReqMeta(req),
      employeeId: s(req.params?.id),
      error: errorShape(err),
    });

    return res.status(500).json({
      ok: false,
      error: err.message,
    });
  }
};