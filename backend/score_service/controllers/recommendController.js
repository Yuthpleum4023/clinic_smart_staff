const TrustScore = require("../models/TrustScore");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

async function getRecommendations(req, res) {
  try {
    const clinicId = s(req.query.clinicId);
    const limit = Math.max(1, Math.min(Number(req.query.limit || 10), 50));

    if (!clinicId) {
      return res.status(400).json({ message: "clinicId required" });
    }

    /**
     * ✅ เป้าหมาย:
     * - ตัดคนที่มี NO_SHOW_30D ออก
     * - พยายามรวมรายการด้วย userId/principalId ก่อน
     * - ถ้าไม่มีจริง ๆ ค่อย fallback เป็น staffId
     * - ส่ง field ที่ Flutter ใช้โชว์ชื่อกลับไปด้วย
     *
     * NOTE:
     * ถ้าเอกสาร TrustScore ยังไม่มี userId/fullName/phone
     * response ก็จะยัง fallback เป็น staffId / ชื่อว่างอยู่
     */
    const rows = await TrustScore.aggregate([
      {
        $match: {
          flags: { $nin: ["NO_SHOW_30D"] },
        },
      },
      {
        $addFields: {
          helperKey: {
            $ifNull: [
              "$userId",
              {
                $ifNull: [
                  "$principalId",
                  "$staffId",
                ],
              },
            ],
          },
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
          _id: "$helperKey",

          helperKey: { $first: "$helperKey" },

          // identity
          userId: { $first: "$userId" },
          principalId: { $first: "$principalId" },
          staffId: { $first: "$staffId" },

          // profile snapshot (ถ้ามี)
          fullName: { $first: "$fullName" },
          name: { $first: "$name" },
          phone: { $first: "$phone" },
          role: { $first: "$role" },

          // trust score
          trustScore: { $first: "$trustScore" },
          badges: { $first: "$badges" },
          flags: { $first: "$flags" },
          sourceClinicId: { $first: "$clinicId" },
          updatedAt: { $first: "$updatedAt" },
          level: { $first: "$level" },
          levelLabel: { $first: "$levelLabel" },

          // optional stats (ถ้ามีใน model)
          totalShifts: { $first: "$totalShifts" },
          completed: { $first: "$completed" },
          late: { $first: "$late" },
          noShow: { $first: "$noShow" },
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

    const recommended = rows.map((x) => {
      const trustScore = n(x.trustScore, 0);

      return {
        helperKey: s(x.helperKey),

        // ✅ identity
        userId: s(x.userId),
        principalId: s(x.principalId),
        staffId: s(x.staffId),

        // ✅ profile
        fullName: s(x.fullName),
        name: s(x.name),
        phone: s(x.phone),
        role: s(x.role) || "helper",

        // ✅ score
        trustScore,
        level: s(x.level) || "unknown",
        levelLabel: s(x.levelLabel) || "ยังไม่มีข้อมูล",
        badges: Array.isArray(x.badges) ? x.badges : [],
        flags: Array.isArray(x.flags) ? x.flags : [],
        sourceClinicId: s(x.sourceClinicId),

        // ✅ stats
        stats: {
          totalShifts: n(x.totalShifts, 0),
          completed: n(x.completed, 0),
          late: n(x.late, 0),
          noShow: n(x.noShow, 0),
        },

        // ✅ why recommended
        reason: [
          `trustScore ${trustScore}`,
          ...(Array.isArray(x.badges) ? x.badges.slice(0, 2) : []),
        ],
      };
    });

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