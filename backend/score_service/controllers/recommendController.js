const TrustScore = require("../models/TrustScore");

async function getRecommendations(req, res) {
  try {
    const clinicId = String(req.query.clinicId || "").trim();
    const limit = Math.max(1, Math.min(Number(req.query.limit || 10), 50));

    if (!clinicId) {
      return res.status(400).json({ message: "clinicId required" });
    }

    // ✅ SaaS-safe:
    // - ตัดคนที่มี NO_SHOW_30D ออก
    // - รวมหลาย clinic ให้เหลือ 1 staffId ต่อ 1 รายการ
    // - ใช้ score สูงสุดของคนนั้นเป็นตัวแทนชั่วคราวสำหรับ recommendation
    const rows = await TrustScore.aggregate([
      {
        $match: {
          flags: { $nin: ["NO_SHOW_30D"] },
        },
      },
      {
        $sort: {
          trustScore: -1,
          updatedAt: -1,
        },
      },
      {
        $group: {
          _id: "$staffId",
          staffId: { $first: "$staffId" },
          trustScore: { $first: "$trustScore" },
          badges: { $first: "$badges" },
          flags: { $first: "$flags" },
          sourceClinicId: { $first: "$clinicId" },
          updatedAt: { $first: "$updatedAt" },
          level: { $first: "$level" },
          levelLabel: { $first: "$levelLabel" },
        },
      },
      {
        $sort: {
          trustScore: -1,
          updatedAt: -1,
        },
      },
      {
        $limit: limit,
      },
    ]);

    const recommended = rows.map((x) => ({
      staffId: x.staffId,
      trustScore: Number(x.trustScore || 0),
      level: x.level || "unknown",
      levelLabel: x.levelLabel || "ยังไม่มีข้อมูล",
      badges: Array.isArray(x.badges) ? x.badges : [],
      flags: Array.isArray(x.flags) ? x.flags : [],
      sourceClinicId: x.sourceClinicId || "",
      reason: [
        `trustScore ${Number(x.trustScore || 0)}`,
        ...(Array.isArray(x.badges) ? x.badges.slice(0, 2) : []),
      ],
    }));

    return res.json({
      clinicId,
      count: recommended.length,
      recommended,
    });
  } catch (e) {
    return res.status(500).json({
      message: "getRecommendations failed",
      error: e.message || String(e),
    });
  }
}

module.exports = { getRecommendations };