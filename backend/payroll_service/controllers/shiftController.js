// payroll_service/controllers/shiftController.js
const Shift = require("../models/Shift");

// -------------------- Helpers --------------------
function mustBeAdmin(req, res) {
  const role = req.user?.role;
  if (role !== "admin") {
    res.status(403).json({ message: "Forbidden (admin only)" });
    return false;
  }
  return true;
}

// -------------------- Controllers --------------------

// POST /shifts  (admin)
// สร้างกะงาน
async function createShift(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const {
      clinicId,
      staffId,
      date,
      start,
      end,
      hourlyRate = 0,
      note = "",
    } = req.body || {};

    if (!clinicId || !staffId || !date || !start || !end) {
      return res.status(400).json({
        message: "clinicId, staffId, date, start, end required",
      });
    }

    const created = await Shift.create({
      clinicId: String(clinicId).trim(),
      staffId: String(staffId).trim(),
      date,
      start,
      end,
      hourlyRate: Number(hourlyRate || 0),
      note: String(note || ""),
    });

    return res.json({ ok: true, shift: created });
  } catch (e) {
    return res.status(500).json({
      message: "createShift failed",
      error: e.message || String(e),
    });
  }
}

// GET /shifts
// list กะงาน (admin เห็นทั้งหมด / staff เห็นของตัวเอง)
async function listShifts(req, res) {
  try {
    const role = req.user?.role;
    const userStaffId = req.user?.staffId;

    const { clinicId = "", staffId = "" } = req.query || {};
    const q = {};

    if (clinicId) q.clinicId = String(clinicId).trim();

    if (role === "admin") {
      if (staffId) q.staffId = String(staffId).trim();
    } else {
      // staff เห็นเฉพาะของตัวเอง
      if (!userStaffId) {
        return res.status(403).json({ message: "staffId missing in token" });
      }
      q.staffId = String(userStaffId).trim();
    }

    const rows = await Shift.find(q)
      .sort({ date: -1, createdAt: -1 })
      .limit(200)
      .lean();

    return res.json({ ok: true, items: rows });
  } catch (e) {
    return res.status(500).json({
      message: "listShifts failed",
      error: e.message || String(e),
    });
  }
}

// PATCH /shifts/:id/status  (admin)
// เปลี่ยนสถานะกะ
async function updateShiftStatus(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const id = String(req.params.id || "").trim();
    if (!id) return res.status(400).json({ message: "id required" });

    const { status, minutesLate = 0 } = req.body || {};
    const st = String(status || "").trim().toLowerCase();
    const allowed = ["completed", "late", "cancelled", "no_show"];

    if (!allowed.includes(st)) {
      return res.status(400).json({ message: "Invalid status", allowed });
    }

    const shift = await Shift.findById(id);
    if (!shift) {
      return res.status(404).json({ message: "Shift not found" });
    }

    shift.status = st;
    shift.minutesLate = Number(minutesLate || 0);
    await shift.save();

    return res.json({ ok: true, shift });
  } catch (e) {
    return res.status(500).json({
      message: "updateShiftStatus failed",
      error: e.message || String(e),
    });
  }
}

// DELETE /shifts/:id  (admin)
async function deleteShift(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const id = String(req.params.id || "").trim();
    if (!id) return res.status(400).json({ message: "id required" });

    const deleted = await Shift.findByIdAndDelete(id);
    if (!deleted) {
      return res.status(404).json({ message: "Shift not found" });
    }

    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({
      message: "deleteShift failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  createShift,
  listShifts,
  updateShiftStatus,
  deleteShift,
};
