const TrustScore = require("../models/TrustScore");

// =====================================================
// GET /staff
// - list ผู้ช่วยทั้งหมด (สำหรับ admin)
// - รองรับ query ?role=helper
// =====================================================
async function listStaff(req, res) {
  try {
    const { role } = req.query;

    // ดึงจาก TrustScore เพื่อให้แน่ใจว่ามี staffId จริง
    // (ถ้าคุณมี collection staff/users แยก บอกผม เดี๋ยวปรับให้)
    const q = {};
    if (role) q.role = role;

    const docs = await TrustScore.find(q)
      .select("staffId fullName role")
      .lean();

    return res.json({
      items: docs.map((d) => ({
        staffId: d.staffId,
        fullName: d.fullName || "",
        role: d.role || "",
      })),
    });
  } catch (e) {
    console.error("listStaff failed:", e);
    return res.status(500).json({
      message: "listStaff failed",
      error: e.message || String(e),
    });
  }
}

// =====================================================
// GET /staff/:staffId/score
// =====================================================
async function getStaffScore(req, res) {
  try {
    const { staffId } = req.params;

    const doc = await TrustScore.findOne({ staffId }).lean();

    // default (ยังไม่มี record)
    if (!doc) {
      return res.json({
        staffId,
        trustScore: 80,
        flags: [],
        badges: [],
        stats: {
          totalShifts: 0,
          completed: 0,
          late: 0,
          noShow: 0,
          cancelled: 0,
        },
      });
    }

    return res.json({
      staffId: doc.staffId,
      trustScore: doc.trustScore,
      flags: doc.flags || [],
      badges: doc.badges || [],
      stats: {
        totalShifts: doc.totalShifts || 0,
        completed: doc.completed || 0,
        late: doc.late || 0,
        noShow: doc.noShow || 0,
        cancelled: doc.cancelled || 0,
      },
      lastNoShowAt: doc.lastNoShowAt,
      updatedAt: doc.updatedAt,
    });
  } catch (e) {
    return res.status(500).json({
      message: "getStaffScore failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  listStaff,
  getStaffScore,
};
