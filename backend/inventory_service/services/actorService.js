const { s } = require("../utils/strings");
const { canonicalRole } = require("../middleware/auth");
const { getEmployeeByUserId } = require("./staffClient");

async function resolveInventoryActor(req) {
  const effectiveRole = canonicalRole(req.user?.role);

  const roleSet = new Set(
    [
      effectiveRole,
      ...(Array.isArray(req.user?.roles)
        ? req.user.roles.map(canonicalRole)
        : []),
    ].filter(Boolean)
  );

  const clinicId = s(req.inventoryClinicId || req.user?.clinicId);
  const userId = s(req.user?.userId);

  if (!clinicId || !userId) {
    const err = new Error("Missing userId or clinicId in token");
    err.status = 401;
    err.code = "IDENTITY_SCOPE_REQUIRED";
    throw err;
  }

  const hasAdmin = roleSet.has("admin");
  const hasEmployee = roleSet.has("employee");

  // Inventory policy:
  // - Helper is explicitly excluded.
  // - Admin/clinic owner is trusted from authenticated clinic authority.
  // - Every other clinic role must prove active Staff membership.
  //
  // We intentionally do not whitelist position/role names here.
  const isHelper =
    effectiveRole === "helper" ||
    (!effectiveRole && roleSet.has("helper"));

  if (isHelper) {
    const err = new Error(
      "Helper role cannot access clinic inventory"
    );
    err.status = 403;
    err.code = "INVENTORY_HELPER_FORBIDDEN";
    throw err;
  }

  let staffId = s(req.user?.staffId);
  let displayName = s(
    req.user?.fullName ||
      req.user?.name ||
      req.user?.displayName ||
      req.user?.email
  );

  if (!hasAdmin) {
    const employee = await getEmployeeByUserId({
      userId,
      clinicId,
      authorization: req.headers.authorization,
    });

    if (!employee) {
      const err = new Error(
        "Staff membership not found for this clinic"
      );
      err.status = 403;
      err.code = "STAFF_MEMBERSHIP_NOT_FOUND";
      throw err;
    }

    if (employee.active === false) {
      const err = new Error("Staff membership is inactive");
      err.status = 403;
      err.code = "STAFF_MEMBERSHIP_INACTIVE";
      throw err;
    }

    const employeeClinicId = s(employee.clinicId);

    if (employeeClinicId && employeeClinicId !== clinicId) {
      const err = new Error("Staff membership clinic mismatch");
      err.status = 403;
      err.code = "STAFF_CLINIC_MISMATCH";
      throw err;
    }

    staffId = s(employee.staffId || employee._id || staffId);

    displayName = s(
      employee.fullName ||
        employee.name ||
        displayName
    );
  }

  return {
    userId,
    clinicId,
    role: effectiveRole,
    roles: Array.from(roleSet),
    hasAdmin,
    hasEmployee,
    staffId,
    displayName,
  };
}

module.exports = { resolveInventoryActor };
