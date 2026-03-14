const mongoose = require("mongoose");
const TrustScore = require("../models/TrustScore");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function getUsersCollection() {
  try {
    return mongoose.connection.db.collection("users");
  } catch (_) {
    return null;
  }
}

function chooseBetterProfile(scoreDoc = {}, userDoc = {}) {
  return {
    userId: s(scoreDoc.userId) || s(userDoc.userId),
    principalId: s(scoreDoc.principalId) || s(userDoc.userId),
    staffId: s(scoreDoc.staffId) || s(userDoc.staffId),
    fullName: s(scoreDoc.fullName) || s(userDoc.fullName),
    name: s(scoreDoc.name) || s(userDoc.fullName),
    phone: s(scoreDoc.phone) || s(userDoc.phone),
    role:
      s(scoreDoc.role) ||
      s(userDoc.activeRole) ||
      s(userDoc.role) ||
      "helper",
  };
}

async function getRecommendations(req, res) {
  try {
    const clinicId = s(req.query.clinicId);
    const limit = Math.max(1, Math.min(Number(req.query.limit || 10), 50));

    if (!clinicId) {
      return res.status(400).json({ message: "clinicId required" });
    }

    const rows = await TrustScore.aggregate([
      {
        $match: {
          flags: { $nin: ["NO_SHOW_30D"] },
        },
      },
      {
        $addFields: {
          helperKey: {
            $cond: [
              { $gt: [{ $strLenCP: { $ifNull: ["$userId", ""] } }, 0] },
              "$userId",
              {
                $cond: [
                  {
                    $gt: [{ $strLenCP: { $ifNull: ["$principalId", ""] } }, 0],
                  },
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

          // profile snapshot
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

          // stats
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

    // --------------------------------------------
    // Enrich from users collection
    // --------------------------------------------
    const usersCollection = getUsersCollection();

    let byStaffId = new Map();
    let byUserId = new Map();

    if (usersCollection) {
      const staffIds = rows.map((x) => s(x.staffId)).filter(Boolean);
      const userIds = rows
        .flatMap((x) => [s(x.userId), s(x.principalId)])
        .filter(Boolean);

      const userDocs = await usersCollection
        .find({
          $or: [
            ...(staffIds.length > 0 ? [{ staffId: { $in: staffIds } }] : []),
            ...(userIds.length > 0 ? [{ userId: { $in: userIds } }] : []),
          ],
        })
        .project({
          userId: 1,
          staffId: 1,
          fullName: 1,
          phone: 1,
          role: 1,
          activeRole: 1,
        })
        .toArray();

      byStaffId = new Map(
        userDocs
          .map((u) => [s(u.staffId), u])
          .filter(([k]) => k.isNotEmpty),
      );

      byUserId = new Map(
        userDocs
          .map((u) => [s(u.userId), u])
          .filter(([k]) => k.isNotEmpty),
      );
    }

    const recommended = rows.map((x) => {
      const trustScore = n(x.trustScore, 0);

      const matchedUser =
        byUserId.get(s(x.userId)) ||
        byUserId.get(s(x.principalId)) ||
        byStaffId.get(s(x.staffId)) ||
        null;

      const profile = chooseBetterProfile(x, matchedUser || {});

      return {
        helperKey: s(x.helperKey),

        // identity
        userId: profile.userId,
        principalId: profile.principalId,
        staffId: profile.staffId,

        // profile
        fullName: profile.fullName,
        name: profile.name,
        phone: profile.phone,
        role: profile.role,

        // score
        trustScore,
        level: s(x.level) || "unknown",
        levelLabel: s(x.levelLabel) || "ยังไม่มีข้อมูล",
        badges: Array.isArray(x.badges) ? x.badges : [],
        flags: Array.isArray(x.flags) ? x.flags : [],
        sourceClinicId: s(x.sourceClinicId),

        // stats
        stats: {
          totalShifts: n(x.totalShifts, 0),
          completed: n(x.completed, 0),
          late: n(x.late, 0),
          noShow: n(x.noShow, 0),
        },

        // why recommended
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