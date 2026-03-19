// controllers/employeeController.js
// ==================================================
// PURPOSE: Employee CRUD (Staff service)
// + ✅ Admin dropdown list (scoped by clinicId if schema supports)
// + ✅ Safe getters: by-user / by-staff
// + ✅ HARD FIX: always return staffId = String(_id) in employee payload
// + ✅ FIX: allow non-admin to read own record by staffId
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
 * ✅ Attach staffId to payload (Flutter expects this)
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

// -------------------- CREATE (admin route should guard) --------------------
exports.createEmployee = async (req, res) => {
  try {
    if (hasClinicIdField()) {
      const clinicId = s(req.user?.clinicId);
      if (clinicId) req.body.clinicId = clinicId;
    }

    const emp = await Employee.create(req.body);
    return res.status(201).json({ ok: true, employee: withStaffId(emp) });
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
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