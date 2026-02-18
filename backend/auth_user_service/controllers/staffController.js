const User = require("../models/User");

// ---------------- helpers ----------------
function norm(s) {
  return String(s || "").trim();
}

function escapeRegex(s) {
  const v = String(s || "");
  return v.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function getClinicId(req) {
  // middleware/auth.js ใส่ req.user แล้ว
  return norm(req.user?.clinicId);
}

function mustLogin(req) {
  if (!req.user) {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    throw err;
  }
}

function mustAdmin(req) {
  // ✅ ปลอดภัย: ถ้าไม่ใช่ admin ให้ block (รวมถึง role ว่าง/ไม่มี)
  const role = norm(req.user?.role).toLowerCase();
  if (role !== "admin") {
    const err = new Error("forbidden");
    err.statusCode = 403;
    throw err;
  }
}

// =====================================================
// GET /staff/search?q=...
// - ค้นจาก fullName / phone / staffId
// - จำกัดเฉพาะ clinic เดียวกับคนที่ login (กันข้ามคลินิก)
// - คืนรายการที่มี staffId เท่านั้น (เพราะ score_service ใช้ staffId)
// =====================================================
async function searchStaff(req, res) {
  try {
    mustLogin(req);
    mustAdmin(req); // ✅ ถ้าไม่อยากจำกัด admin ให้ลบบรรทัดนี้

    const clinicId = getClinicId(req);
    if (!clinicId) {
      return res.status(400).json({ message: "missing clinicId in token" });
    }

    const q = norm(req.query.q);
    if (!q) return res.json({ items: [] });

    const limitRaw = parseInt(req.query.limit || "20", 10);
    const limit = Math.min(Math.max(Number.isFinite(limitRaw) ? limitRaw : 20, 1), 50);

    const isDigits = /^\d+$/.test(q);
    const safe = escapeRegex(q);
    const rx = new RegExp(safe, "i");

    // ถ้าเป็นตัวเลขล้วน ให้ค้น phone แบบ contains ตัวเลข (แต่ยัง escape)
    const phoneRx = isDigits ? new RegExp(escapeRegex(q), "i") : rx;

    const mongoQuery = {
      clinicId,
      isActive: true,
      staffId: { $exists: true, $ne: "" },
      $or: [
        { fullName: rx },
        { staffId: rx },
        { phone: phoneRx },
      ],
    };

    const docs = await User.find(mongoQuery)
      .select("staffId fullName phone role userId clinicId")
      .sort({ fullName: 1, phone: 1 })
      .limit(limit)
      .lean();

    return res.json({
      items: docs.map((d) => ({
        staffId: d.staffId || "",
        fullName: d.fullName || "",
        phone: d.phone || "",
        role: d.role || "",
        userId: d.userId || "",
        clinicId: d.clinicId || "",
      })),
    });
  } catch (e) {
    const code = e.statusCode || 500;
    return res.status(code).json({
      message: "searchStaff failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// GET /staff/by-staffid/:staffId
// =====================================================
async function getByStaffId(req, res) {
  try {
    mustLogin(req);
    mustAdmin(req); // ✅ ถ้าไม่อยากจำกัด admin ให้ลบบรรทัดนี้

    const clinicId = getClinicId(req);
    if (!clinicId) {
      return res.status(400).json({ message: "missing clinicId in token" });
    }

    const staffId = norm(req.params.staffId);
    if (!staffId) return res.status(400).json({ message: "staffId is required" });

    const doc = await User.findOne({
      clinicId,
      staffId,
      isActive: true,
    })
      .select("staffId fullName phone role userId clinicId")
      .lean();

    if (!doc) return res.status(404).json({ message: "staff not found" });

    return res.json({
      staffId: doc.staffId || "",
      fullName: doc.fullName || "",
      phone: doc.phone || "",
      role: doc.role || "",
      userId: doc.userId || "",
      clinicId: doc.clinicId || "",
    });
  } catch (e) {
    const code = e.statusCode || 500;
    return res.status(code).json({
      message: "getByStaffId failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  searchStaff,
  getByStaffId,
};
