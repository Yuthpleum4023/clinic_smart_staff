// controllers/employeeController.js
// ==================================================
// PURPOSE: Employee CRUD (Staff service)
// + Admin dropdown list (scoped by clinicId if schema supports)
// + Safe getters: by-user / by-staff
// + HARD FIX: always return staffId = String(_id) in employee payload
// + FIX: allow non-admin to read own record by staffId
// + NEW: internal ensure route for service-to-service flow
// + NEW: duplicate-safe / idempotent employee creation
// + DEBUG LOGS: employee provisioning / internal lookup tracing
// ==================================================

const mongoose = require("mongoose");
const Employee = require("../schemas/Employee");

function s(v) {
  return String(v || "").trim();
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

/**
 * Attach staffId to payload (Flutter expects this)
 * staffId in system = Employee._id (string)
 */
function withStaffId(emp) {
  if (!emp) return emp;
  const obj = typeof emp.toObject === "function" ? emp.toObject() : emp;
  const id = s(obj._id);
  return { ...obj, staffId: id || s(obj.staffId) };
}

/**
 * Detect whether Employee schema has clinicId field.
 * If not, fallback works for single-clinic MVP only.
 */
function hasClinicIdField() {
  try {
    return !!Employee?.schema?.path("clinicId");
  } catch (_) {
    return false;
  }
}

function clinicScopeQuery(req) {
  if (!hasClinicIdField()) return {};
  const clinicId = s(req.user?.clinicId);
  return clinicId ? { clinicId } : {};
}

function normalizeEmploymentType(v) {
  const t = s(v).toLowerCase();

  if (!t) return "fullTime";
  if (["fulltime", "full_time", "full-time", "ft"].includes(t)) {
    return "fullTime";
  }
  if (["parttime", "part_time", "part-time", "pt"].includes(t)) {
    return "partTime";
  }

  return s(v) || "fullTime";
}

function buildEmployeeCreatePayload(input = {}) {
  const payload = {
    userId: s(input.userId),
    fullName: s(input.fullName || input.name),
    employmentType: normalizeEmploymentType(input.employmentType),
    active:
      input.active === undefined && input.isActive === undefined
        ? true
        : !!(input.active ?? input.isActive),
  };

  // เก็บ field เพิ่มเมื่อ schema รองรับเท่านั้น
  if (hasClinicIdField()) {
    payload.clinicId = s(input.clinicId);
  }

  if (Employee?.schema?.path("monthlySalary")) {
    payload.monthlySalary = Number(input.monthlySalary || 0) || 0;
  }

  if (Employee?.schema?.path("hourlyRate")) {
    payload.hourlyRate = Number(input.hourlyRate || 0) || 0;
  }

  if (Employee?.schema?.path("hoursPerDay")) {
    payload.hoursPerDay = Number(input.hoursPerDay || 8) || 8;
  }

  if (Employee?.schema?.path("workingDaysPerMonth")) {
    payload.workingDaysPerMonth = Number(input.workingDaysPerMonth || 26) || 26;
  }

  if (Employee?.schema?.path("otMultiplierNormal")) {
    payload.otMultiplierNormal = Number(input.otMultiplierNormal || 1.5) || 1.5;
  }

  if (Employee?.schema?.path("otMultiplierHoliday")) {
    payload.otMultiplierHoliday =
      Number(input.otMultiplierHoliday || 2.0) || 2.0;
  }

  if (Employee?.schema?.path("provisionedFrom")) {
    payload.provisionedFrom = s(input.provisionedFrom || "manual");
  }

  return payload;
}

function isDuplicateKeyError(err) {
  return !!(err && (err.code === 11000 || err.code === 11001));
}

async function findEmployeeByUserIdScoped(userId, clinicId = "") {
  const uid = s(userId);
  if (!uid) return null;

  const q = { userId: uid };
  if (hasClinicIdField() && clinicId) q.clinicId = s(clinicId);

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

function getInternalClinicId(req) {
  return (
    s(req.query?.clinicId) ||
    s(req.body?.clinicId) ||
    s(req.headers["x-clinic-id"]) ||
    ""
  );
}

async function createOrGetExistingEmployee(payload) {
  logEmployeeDebug("createOrGetExistingEmployee.start", {
    userId: s(payload.userId),
    clinicId: s(payload.clinicId),
    fullName: s(payload.fullName),
    employmentType: s(payload.employmentType),
    active: !!payload.active,
    provisionedFrom: s(payload.provisionedFrom),
  });

  const existing = await findEmployeeByUserIdScoped(
    payload.userId,
    payload.clinicId
  );

  if (existing) {
    logEmployeeDebug("createOrGetExistingEmployee.existing", {
      userId: s(payload.userId),
      clinicId: s(payload.clinicId),
      employeeId: s(existing?._id),
      staffId: s(existing?._id || existing?.staffId),
    });

    return {
      created: false,
      employee: existing,
    };
  }

  try {
    const emp = await Employee.create(payload);

    logEmployeeDebug("createOrGetExistingEmployee.created", {
      userId: s(payload.userId),
      clinicId: s(payload.clinicId),
      employeeId: s(emp?._id),
      staffId: s(emp?._id),
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

    if (isDuplicateKeyError(err)) {
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

// -------------------- CREATE (admin route should guard) --------------------
exports.createEmployee = async (req, res) => {
  try {
    const payload = buildEmployeeCreatePayload(req.body || {});

    logEmployeeDebug("createEmployee.hit", {
      ...safeReqMeta(req),
      rawBody: {
        userId: s(req.body?.userId),
        clinicId: s(req.body?.clinicId),
        fullName: s(req.body?.fullName || req.body?.name),
        employmentType: s(req.body?.employmentType),
        monthlySalary: req.body?.monthlySalary ?? null,
      },
      normalizedPayload: payload,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!payload.userId) {
      logEmployeeDebug("createEmployee.reject_missing_userId", {
        ...safeReqMeta(req),
        payload,
      });

      return res.status(400).json({ ok: false, error: "userId is required" });
    }

    if (!payload.fullName) {
      logEmployeeDebug("createEmployee.reject_missing_fullName", {
        ...safeReqMeta(req),
        payload,
      });

      return res.status(400).json({ ok: false, error: "fullName is required" });
    }

    if (hasClinicIdField()) {
      const clinicId = s(req.user?.clinicId);
      if (!clinicId) {
        logEmployeeDebug("createEmployee.reject_missing_token_clinicId", {
          ...safeReqMeta(req),
          payload,
        });

        return res
          .status(401)
          .json({ ok: false, message: "Missing clinicId in token" });
      }
      payload.clinicId = clinicId;
    }

    if (Employee?.schema?.path("provisionedFrom") && !payload.provisionedFrom) {
      payload.provisionedFrom = "manual_admin";
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

    return res.status(400).json({ ok: false, error: err.message });
  }
};

// -------------------- INTERNAL ENSURE FROM USER --------------------
// POST /api/employees/internal/ensure
async function ensureEmployeeInternalHandler(req, res) {
  try {
    const payload = buildEmployeeCreatePayload(req.body || {});

    logEmployeeDebug("internal.ensure.hit", {
      ...safeReqMeta(req),
      rawBody: {
        userId: s(req.body?.userId),
        clinicId: s(req.body?.clinicId),
        fullName: s(req.body?.fullName || req.body?.name),
        employmentType: s(req.body?.employmentType),
      },
      normalizedPayload: payload,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!payload.userId) {
      logEmployeeDebug("internal.ensure.reject_missing_userId", {
        ...safeReqMeta(req),
        payload,
      });

      return res.status(400).json({
        ok: false,
        message: "userId is required",
      });
    }

    if (!payload.fullName) {
      logEmployeeDebug("internal.ensure.reject_missing_fullName", {
        ...safeReqMeta(req),
        payload,
      });

      return res.status(400).json({
        ok: false,
        message: "fullName is required",
      });
    }

    if (hasClinicIdField() && !payload.clinicId) {
      logEmployeeDebug("internal.ensure.reject_missing_clinicId", {
        ...safeReqMeta(req),
        payload,
      });

      return res.status(400).json({
        ok: false,
        message: "clinicId is required",
      });
    }

    if (Employee?.schema?.path("provisionedFrom")) {
      payload.provisionedFrom = s(payload.provisionedFrom || "internal_ensure");
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

    return res.status(500).json({
      ok: false,
      message: err.message || "ensureEmployeeInternal failed",
    });
  }
}

// ✅ route ใหม่ที่ควรใช้
exports.ensureEmployeeInternal = ensureEmployeeInternalHandler;

// ✅ alias เก่าเพื่อ backward compatibility
// POST /api/employees/internal/create-from-user
exports.createEmployeeFromInternal = ensureEmployeeInternalHandler;

// -------------------- INTERNAL GET BY USER ID --------------------
// GET /api/employees/internal/by-user/:userId
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
      logEmployeeDebug("internal.by-user.reject_missing_clinicId", {
        ...safeReqMeta(req),
        paramUserId: userId,
      });

      return res.status(400).json({
        ok: false,
        message: "clinicId required",
      });
    }

    const emp = await findEmployeeByUserIdScoped(userId, clinicId);

    if (!emp) {
      logEmployeeDebug("internal.by-user.not_found", {
        ...safeReqMeta(req),
        userId,
        clinicId,
      });

      return res.status(404).json({
        ok: false,
        message: "Employee not found",
      });
    }

    logEmployeeDebug("internal.by-user.success", {
      ...safeReqMeta(req),
      userId,
      clinicId,
      employeeId: s(emp?._id),
      staffId: s(emp?._id || emp?.staffId),
    });

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

// -------------------- INTERNAL GET BY STAFF ID --------------------
// GET /api/employees/internal/by-staff/:staffId
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
      logEmployeeDebug("internal.by-staff.reject_invalid_staffId", {
        ...safeReqMeta(req),
        paramStaffId: staffId,
      });

      return res.status(400).json({
        ok: false,
        message: "Invalid staffId",
      });
    }

    if (hasClinicIdField() && !clinicId) {
      logEmployeeDebug("internal.by-staff.reject_missing_clinicId", {
        ...safeReqMeta(req),
        paramStaffId: staffId,
      });

      return res.status(400).json({
        ok: false,
        message: "clinicId required",
      });
    }

    const emp = await findEmployeeByStaffIdScoped(staffId, clinicId);

    if (!emp) {
      logEmployeeDebug("internal.by-staff.not_found", {
        ...safeReqMeta(req),
        staffId,
        clinicId,
      });

      return res.status(404).json({
        ok: false,
        message: "Employee not found",
      });
    }

    logEmployeeDebug("internal.by-staff.success", {
      ...safeReqMeta(req),
      staffId,
      clinicId,
      employeeId: s(emp?._id),
    });

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

// -------------------- GET BY ID --------------------
// - admin: can read within clinic (if clinicId exists)
// - non-admin: only read own record (emp.userId === token.userId)
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
      if (!tokenUserId || s(emp.userId) !== tokenUserId) {
        return res.status(403).json({ ok: false, message: "Forbidden" });
      }
    }

    logEmployeeDebug("getById.success", {
      ...safeReqMeta(req),
      employeeId: id,
      userId: s(emp?.userId),
      clinicId: s(emp?.clinicId),
    });

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

// -------------------- LIST (active=true) --------------------
// - should be admin-only by route
exports.listEmployees = async (req, res) => {
  try {
    const q = { active: true, ...clinicScopeQuery(req) };

    logEmployeeDebug("listEmployees.hit", {
      ...safeReqMeta(req),
      query: q,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!hasClinicIdField()) {
      console.log(
        "⚠️ Employee schema has NO clinicId -> listEmployees is NOT clinic-scoped (MVP only)"
      );
    } else if (!s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const list = await Employee.find(q).sort({ createdAt: -1 }).lean();

    logEmployeeDebug("listEmployees.success", {
      ...safeReqMeta(req),
      count: Array.isArray(list) ? list.length : 0,
    });

    return res.json({ ok: true, items: list.map(withStaffId) });
  } catch (err) {
    logEmployeeDebug("listEmployees.failed", {
      ...safeReqMeta(req),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- LIST FOR DROPDOWN (ADMIN) --------------------
// GET /api/employees/dropdown
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

    if (!hasClinicIdField()) {
      console.log(
        "⚠️ Employee schema has NO clinicId -> dropdown is NOT clinic-scoped (MVP only)"
      );
    }

    const list = await Employee.find(q)
      .select("_id fullName employmentType userId")
      .sort({ fullName: 1 })
      .lean();

    logEmployeeDebug("listForDropdown.success", {
      ...safeReqMeta(req),
      count: Array.isArray(list) ? list.length : 0,
    });

    return res.json({
      ok: true,
      items: list
        .map((e) => ({
          staffId: String(e._id),
          fullName: s(e.fullName),
          employmentType: s(e.employmentType),
          userId: s(e.userId),
        }))
        .filter((x) => x.staffId),
    });
  } catch (err) {
    logEmployeeDebug("listForDropdown.failed", {
      ...safeReqMeta(req),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- GET BY USER ID --------------------
// GET /api/employees/by-user/:userId
// - admin: can read within clinic (if clinicId exists)
// - non-admin: allow only if param userId == token.userId
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
      return res
        .status(400)
        .json({ ok: false, message: "userId required" });
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

    const q = { userId: paramUserId, active: true, ...clinicScopeQuery(req) };

    logEmployeeDebug("getByUserId.query", q);

    const emp = await Employee.findOne(q).lean();

    if (!emp) {
      logEmployeeDebug("getByUserId.not_found", {
        ...safeReqMeta(req),
        paramUserId,
      });

      return res
        .status(404)
        .json({ ok: false, message: "Employee not found" });
    }

    logEmployeeDebug("getByUserId.success", {
      ...safeReqMeta(req),
      paramUserId,
      employeeId: s(emp?._id),
      staffId: s(emp?._id || emp?.staffId),
    });

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    logEmployeeDebug("getByUserId.failed", {
      ...safeReqMeta(req),
      paramUserId: s(req.params?.userId),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- GET BY STAFF ID --------------------
// GET /api/employees/by-staff/:staffId
// - admin: read within clinic
// - non-admin: allow only if this employee belongs to token user / token staff
exports.getEmployeeByStaffId = async (req, res) => {
  try {
    const staffId = s(req.params.staffId);

    logEmployeeDebug("getByStaffId.hit", {
      ...safeReqMeta(req),
      paramStaffId: staffId,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(staffId)) {
      return res.status(400).json({ ok: false, message: "Invalid staffId" });
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const emp = await Employee.findById(staffId).lean();

    if (!emp) {
      logEmployeeDebug("getByStaffId.not_found", {
        ...safeReqMeta(req),
        paramStaffId: staffId,
      });

      return res
        .status(404)
        .json({ ok: false, message: "Employee not found" });
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

      const ownsByUser = !!tokenUserId && s(emp.userId) === tokenUserId;
      const ownsByStaff = !!tokenStaffId && tokenStaffId === staffId;

      if (!ownsByUser && !ownsByStaff) {
        return res.status(403).json({ ok: false, message: "Forbidden" });
      }
    }

    logEmployeeDebug("getByStaffId.success", {
      ...safeReqMeta(req),
      paramStaffId: staffId,
      employeeId: s(emp?._id),
      userId: s(emp?.userId),
    });

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    logEmployeeDebug("getByStaffId.failed", {
      ...safeReqMeta(req),
      paramStaffId: s(req.params?.staffId),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- UPDATE (admin route should guard) --------------------
exports.updateEmployee = async (req, res) => {
  try {
    const id = s(req.params.id);

    logEmployeeDebug("updateEmployee.hit", {
      ...safeReqMeta(req),
      employeeId: id,
      body: req.body || {},
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(id)) {
      return res.status(400).json({ ok: false, error: "Invalid employee id" });
    }

    if (hasClinicIdField()) {
      const clinicId = s(req.user?.clinicId);
      if (!clinicId) {
        return res
          .status(401)
          .json({ ok: false, message: "Missing clinicId in token" });
      }
      req.body.clinicId = clinicId;
    }

    const emp = await Employee.findByIdAndUpdate(id, req.body, {
      new: true,
    }).lean();

    if (!emp) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    if (hasClinicIdField()) {
      const clinicId = s(req.user?.clinicId);
      if (clinicId && s(emp.clinicId) !== clinicId) {
        return res
          .status(403)
          .json({ ok: false, message: "Forbidden (different clinic)" });
      }
    }

    logEmployeeDebug("updateEmployee.success", {
      ...safeReqMeta(req),
      employeeId: id,
      userId: s(emp?.userId),
      clinicId: s(emp?.clinicId),
    });

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    logEmployeeDebug("updateEmployee.failed", {
      ...safeReqMeta(req),
      employeeId: s(req.params?.id),
      error: errorShape(err),
      body: req.body || {},
    });

    return res.status(400).json({ ok: false, error: err.message });
  }
};

// -------------------- DEACTIVATE (admin route should guard) --------------------
exports.deactivateEmployee = async (req, res) => {
  try {
    const id = s(req.params.id);

    logEmployeeDebug("deactivateEmployee.hit", {
      ...safeReqMeta(req),
      employeeId: id,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!isObjectId(id)) {
      return res.status(400).json({ ok: false, error: "Invalid employee id" });
    }

    if (hasClinicIdField() && !s(req.user?.clinicId)) {
      return res
        .status(401)
        .json({ ok: false, message: "Missing clinicId in token" });
    }

    const emp = await Employee.findByIdAndUpdate(
      id,
      { active: false },
      { new: true }
    ).lean();

    if (!emp) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    if (hasClinicIdField()) {
      const clinicId = s(req.user?.clinicId);
      if (clinicId && s(emp.clinicId) !== clinicId) {
        return res
          .status(403)
          .json({ ok: false, message: "Forbidden (different clinic)" });
      }
    }

    logEmployeeDebug("deactivateEmployee.success", {
      ...safeReqMeta(req),
      employeeId: id,
      userId: s(emp?.userId),
      clinicId: s(emp?.clinicId),
    });

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    logEmployeeDebug("deactivateEmployee.failed", {
      ...safeReqMeta(req),
      employeeId: s(req.params?.id),
      error: errorShape(err),
    });

    return res.status(500).json({ ok: false, error: err.message });
  }
};