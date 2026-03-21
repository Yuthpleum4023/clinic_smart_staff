// controllers/employeeController.js
// ==================================================
// PURPOSE: Employee CRUD (Staff service)
// + Admin dropdown list (scoped by clinicId if schema supports)
// + Safe getters: by-user / by-staff
// + HARD FIX: always return staffId = String(_id) in employee payload
// + FIX: allow non-admin to read own record by staffId
// + NEW: internal ensure route for service-to-service flow
// + NEW: duplicate-safe / idempotent employee creation
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

  return Employee.findOne(q).lean();
}

async function findEmployeeByStaffIdScoped(staffId, clinicId = "") {
  const sid = s(staffId);
  if (!isObjectId(sid)) return null;

  const emp = await Employee.findById(sid).lean();
  if (!emp) return null;

  if (hasClinicIdField() && clinicId && s(emp.clinicId) !== s(clinicId)) {
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
  const existing = await findEmployeeByUserIdScoped(
    payload.userId,
    payload.clinicId
  );

  if (existing) {
    return {
      created: false,
      employee: existing,
    };
  }

  try {
    const emp = await Employee.create(payload);
    return {
      created: true,
      employee: emp,
    };
  } catch (err) {
    if (isDuplicateKeyError(err)) {
      const existingAfterConflict = await findEmployeeByUserIdScoped(
        payload.userId,
        payload.clinicId
      );

      if (existingAfterConflict) {
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

    if (!payload.userId) {
      return res.status(400).json({ ok: false, error: "userId is required" });
    }

    if (!payload.fullName) {
      return res.status(400).json({ ok: false, error: "fullName is required" });
    }

    if (hasClinicIdField()) {
      const clinicId = s(req.user?.clinicId);
      if (!clinicId) {
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

    return res.status(result.created ? 201 : 200).json({
      ok: true,
      existed: !result.created,
      created: result.created,
      employee: withStaffId(result.employee),
    });
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
};

// -------------------- INTERNAL ENSURE FROM USER --------------------
// POST /api/employees/internal/ensure
// NOTE:
// - idempotent
// - if exists -> return existing
// - if duplicate race -> fallback find existing
async function ensureEmployeeInternalHandler(req, res) {
  try {
    const payload = buildEmployeeCreatePayload(req.body || {});

    console.log("🔥 INTERNAL ensure HIT", {
      userId: payload.userId,
      clinicId: payload.clinicId,
      hasClinicIdField: hasClinicIdField(),
    });

    if (!payload.userId) {
      return res.status(400).json({
        ok: false,
        message: "userId is required",
      });
    }

    if (!payload.fullName) {
      return res.status(400).json({
        ok: false,
        message: "fullName is required",
      });
    }

    if (hasClinicIdField() && !payload.clinicId) {
      return res.status(400).json({
        ok: false,
        message: "clinicId is required",
      });
    }

    if (Employee?.schema?.path("provisionedFrom")) {
      payload.provisionedFrom = s(payload.provisionedFrom || "internal_ensure");
    }

    const result = await createOrGetExistingEmployee(payload);

    return res.status(result.created ? 201 : 200).json({
      ok: true,
      created: result.created,
      employee: withStaffId(result.employee),
    });
  } catch (err) {
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

    console.log("🔥 INTERNAL by-user HIT", {
      userId,
      clinicId,
      hasClinicIdField: hasClinicIdField(),
      hasInternalKey: !!s(req.headers["x-internal-key"]),
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

    console.log("🔥 INTERNAL by-staff HIT", {
      staffId,
      clinicId,
      hasClinicIdField: hasClinicIdField(),
      hasInternalKey: !!s(req.headers["x-internal-key"]),
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

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- LIST (active=true) --------------------
// - should be admin-only by route
exports.listEmployees = async (req, res) => {
  try {
    const q = { active: true, ...clinicScopeQuery(req) };

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
    return res.json({ ok: true, items: list.map(withStaffId) });
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- LIST FOR DROPDOWN (ADMIN) --------------------
// GET /api/employees/dropdown
exports.listForDropdown = async (req, res) => {
  try {
    const role = s(req.user?.role);
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
    if (!paramUserId) {
      return res
        .status(400)
        .json({ ok: false, message: "userId required" });
    }

    const tokenUserId = s(req.user?.userId);

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

    const emp = await Employee.findOne(q).lean();
    if (!emp) {
      return res
        .status(404)
        .json({ ok: false, message: "Employee not found" });
    }

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
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

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }
};

// -------------------- UPDATE (admin route should guard) --------------------
exports.updateEmployee = async (req, res) => {
  try {
    const id = s(req.params.id);
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

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
};

// -------------------- DEACTIVATE (admin route should guard) --------------------
exports.deactivateEmployee = async (req, res) => {
  try {
    const id = s(req.params.id);
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

    return res.json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }
};