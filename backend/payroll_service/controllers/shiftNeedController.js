const ShiftNeed = require("../models/ShiftNeed");
const Shift = require("../models/Shift");

// ---------------- helpers ----------------
function normalizeRoles(r) {
  if (!r) return [];
  if (Array.isArray(r)) return r.map((x) => String(x || "").trim()).filter(Boolean);
  return [String(r || "").trim()].filter(Boolean);
}

function mustRoleAny(req, roles = []) {
  const have = normalizeRoles(req.user?.role);
  const want = (roles || []).map((x) => String(x || "").trim()).filter(Boolean);

  const ok = have.some((x) => want.includes(x));
  if (!ok) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

// keep original helper (used by admin paths)
function mustRole(req, roles = []) {
  const r = req.user?.role;
  if (!roles.includes(r)) {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

function getClinicId(req) {
  return (req.user?.clinicId || "").toString().trim();
}

function getStaffId(req) {
  // ✅ fallback: ถ้า token ยังไม่มี staffId ให้ใช้ userId แทน (admin จะมีแต่สมัครไม่ได้)
  return (
    (req.user?.staffId ||
      req.user?.userId ||
      req.user?.id ||
      req.user?._id ||
      "")
      .toString()
      .trim()
  );
}

function bad(msg, code = 400) {
  const err = new Error(msg);
  err.statusCode = code;
  throw err;
}

// ---------------- admin: create need ----------------
async function createNeed(req, res) {
  try {
    mustRole(req, ["admin"]);

    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const {
      title = "ต้องการผู้ช่วย",
      role = "ผู้ช่วย",
      date,
      start,
      end,
      hourlyRate,
      requiredCount = 1,
      note = "",
    } = req.body || {};

    if (!date || !start || !end) bad("date/start/end required");
    if (!hourlyRate || Number(hourlyRate) <= 0) bad("hourlyRate must be > 0");
    if (Number(requiredCount) <= 0) bad("requiredCount must be > 0");

    const need = await ShiftNeed.create({
      clinicId,
      title,
      role,
      date,
      start,
      end,
      hourlyRate: Number(hourlyRate),
      requiredCount: Number(requiredCount),
      note,
      status: "open",
      createdByUserId: req.user?.userId || "",
    });

    return res.status(201).json({ need });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "createNeed failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: list own clinic needs ----------------
async function listClinicNeeds(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const status = (req.query.status || "").toString().trim();
    const q = { clinicId };
    if (status) q.status = status;

    const items = await ShiftNeed.find(q).sort({ createdAt: -1 }).lean();
    return res.json({ items });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listClinicNeeds failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- public (auth): list open needs ----------------
async function listOpenNeeds(req, res) {
  try {
    // ✅ ทุก role ที่ login แล้วดูได้ (admin / employee / helper / staff)
    // ไม่บังคับ role ที่นี่

    const staffId = getStaffId(req); // อาจว่างได้ถ้าเป็น admin

    const q = { status: "open" };
    const items = await ShiftNeed.find(q).sort({ date: 1, start: 1 }).lean();

    const enriched = items.map((n) => {
      const applied =
        staffId &&
        (n.applicants || []).some(
          (a) => String(a.staffId) === String(staffId)
        );
      return { ...n, _applied: !!applied };
    });

    return res.json({ items: enriched });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listOpenNeeds failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- staff/helper: apply ----------------
async function applyNeed(req, res) {
  try {
    // ✅ สมัครได้เฉพาะ employee / helper / staff (admin สมัครไม่ได้)
    mustRoleAny(req, ["employee", "helper", "staff"]);

    const staffId = getStaffId(req);
    if (!staffId) bad("missing staffId in token (please add staffId to JWT)", 400);

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.status !== "open") bad("need is not open", 400);

    const already = (need.applicants || []).some(
      (a) => String(a.staffId) === String(staffId)
    );
    if (already) return res.json({ ok: true, message: "already applied" });

    need.applicants.push({
      staffId,
      userId: req.user?.userId || "",
      status: "pending",
      appliedAt: new Date(),
    });

    await need.save();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "applyNeed failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: list applicants ----------------
async function listApplicants(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id).lean();
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);

    return res.json({ applicants: need.applicants || [] });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "listApplicants failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: approve applicant -> create Shift ----------------
async function approveApplicant(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const id = (req.params.id || "").toString();
    const { staffId } = req.body || {};
    const staff = (staffId || "").toString().trim();
    if (!staff) bad("staffId required");

    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);
    if (need.status !== "open") bad("need is not open", 400);

    const a = (need.applicants || []).find(
      (x) => String(x.staffId) === String(staff)
    );
    if (!a) bad("applicant not found", 404);

    // mark approved + reject others (MVP)
    need.applicants = (need.applicants || []).map((x) => ({
      ...x.toObject(),
      status:
        String(x.staffId) === String(staff) ? "approved" : "rejected",
    }));

    // ✅ create real Shift
    const shift = await Shift.create({
      clinicId: need.clinicId,
      staffId: staff,
      date: need.date,
      start: need.start,
      end: need.end,
      hourlyRate: need.hourlyRate,
      note: need.note || need.title || "Shift from ShiftNeed",
      status: "scheduled",
    });

    // If requiredCount=1 -> mark filled
    if (Number(need.requiredCount || 1) <= 1) {
      need.status = "filled";
    }

    await need.save();

    return res.json({ ok: true, shift });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "approveApplicant failed",
      error: e.message || String(e),
    });
  }
}

// ---------------- admin: cancel need ----------------
async function cancelNeed(req, res) {
  try {
    mustRole(req, ["admin"]);
    const clinicId = getClinicId(req);
    if (!clinicId) bad("missing clinicId in token", 400);

    const id = (req.params.id || "").toString();
    const need = await ShiftNeed.findById(id);
    if (!need) bad("need not found", 404);
    if (need.clinicId !== clinicId) bad("forbidden", 403);

    need.status = "cancelled";
    await need.save();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(e.statusCode || 500).json({
      message: "cancelNeed failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  createNeed,
  listClinicNeeds,
  listOpenNeeds,
  applyNeed,
  listApplicants,
  approveApplicant,
  cancelNeed,
};
