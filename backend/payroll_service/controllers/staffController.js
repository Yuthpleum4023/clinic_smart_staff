// backend/payroll_service/controllers/staffController.js
// ======================================================
// PURPOSE: payroll_service as "gateway/proxy" for staff_service
// - ✅ Admin can call payroll_service only (no need to call staff_service directly)
// - GET /staff/dropdown  -> fetch from staff_service and return simplified list
// ======================================================

const { listEmployeesDropdown } = require("../utils/staffClient");

function s(v) {
  return String(v || "").trim();
}

// ======================================================
// GET /staff/dropdown
// - admin only (middleware should enforce already)
// - forwards Authorization header to staff_service (if staff_service uses auth)
// ======================================================
async function dropdown(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const bearer = s(req.headers.authorization); // "Bearer xxx"
    const data = await listEmployeesDropdown({ bearerToken: bearer });

    return res.json({
      ok: true,
      source: "staff_service",
      items: Array.isArray(data?.items) ? data.items : [],
    });
  } catch (e) {
    return res.status(e.status || 500).json({
      ok: false,
      message: "staff dropdown failed",
      error: e.message,
      detail: e.payload || null,
    });
  }
}

module.exports = { dropdown };