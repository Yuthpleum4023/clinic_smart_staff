const mongoose = require("mongoose");
const TrustScore = require("../models/TrustScore");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function arr(v) {
  return Array.isArray(v) ? v : [];
}

function getUsersCollection() {
  try {
    return mongoose.connection.db.collection("users");
  } catch (_) {
    return null;
  }
}

function pickLocation(raw = {}) {
  const location = raw && typeof raw === "object" ? raw : {};

  const lat = Number(
    location.lat ??
      location.latitude ??
      location?.coordinates?.lat ??
      location?.coordinates?.latitude
  );

  const lng = Number(
    location.lng ??
      location.lon ??
      location.long ??
      location.longitude ??
      location?.coordinates?.lng ??
      location?.coordinates?.lon ??
      location?.coordinates?.long ??
      location?.coordinates?.longitude
  );

  return {
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    district: s(location.district),
    province: s(location.province),
    address: s(location.address),
    label: s(location.label),
  };
}

function chooseBetterProfile(scoreDoc = {}, userDoc = {}) {
  const userLocation = pickLocation(userDoc.location || {});
  const scoreLocation = pickLocation(scoreDoc.location || {});

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
    location: {
      lat: scoreLocation.lat ?? userLocation.lat,
      lng: scoreLocation.lng ?? userLocation.lng,
      district: scoreLocation.district || userLocation.district,
      province: scoreLocation.province || userLocation.province,
      address: scoreLocation.address || userLocation.address,
      label: scoreLocation.label || userLocation.label,
    },
  };
}

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const a1 = Number(lat1);
  const o1 = Number(lng1);
  const a2 = Number(lat2);
  const o2 = Number(lng2);

  if (
    !Number.isFinite(a1) ||
    !Number.isFinite(o1) ||
    !Number.isFinite(a2) ||
    !Number.isFinite(o2)
  ) {
    return null;
  }

  const R = 6371;
  const dLat = toRad(a2 - a1);
  const dLng = toRad(o2 - o1);

  const q =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(a1)) *
      Math.cos(toRad(a2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(q), Math.sqrt(1 - q));
  return Math.round(R * c * 100) / 100;
}

function formatDistanceText(distanceKm) {
  if (!Number.isFinite(distanceKm)) return "";
  if (distanceKm < 1) {
    return `${Math.round(distanceKm * 1000)} ม.`;
  }
  return `${distanceKm.toFixed(distanceKm < 10 ? 1 : 0)} กม.`;
}

function buildAreaText(location = {}) {
  const district = s(location.district);
  const province = s(location.province);

  if (district && province) return `${district}, ${province}`;
  if (province) return province;
  if (district) return district;
  if (s(location.label)) return s(location.label);
  if (s(location.address)) return s(location.address);

  return "";
}

function parseClinicLocation(req) {
  const queryLat = Number(req.query.clinicLat ?? req.query.lat);
  const queryLng = Number(req.query.clinicLng ?? req.query.lng);

  const userLat = Number(
    req.user?.location?.lat ??
      req.user?.location?.latitude ??
      req.user?.clinicLocation?.lat ??
      req.user?.clinicLocation?.latitude
  );

  const userLng = Number(
    req.user?.location?.lng ??
      req.user?.location?.lon ??
      req.user?.location?.long ??
      req.user?.location?.longitude ??
      req.user?.clinicLocation?.lng ??
      req.user?.clinicLocation?.lon ??
      req.user?.clinicLocation?.long ??
      req.user?.clinicLocation?.longitude
  );

  return {
    lat: Number.isFinite(queryLat)
      ? queryLat
      : Number.isFinite(userLat)
      ? userLat
      : null,
    lng: Number.isFinite(queryLng)
      ? queryLng
      : Number.isFinite(userLng)
      ? userLng
      : null,
  };
}

async function getRecommendations(req, res) {
  try {
    const clinicId = s(req.query.clinicId);
    const limit = Math.max(1, Math.min(Number(req.query.limit || 10), 50));
    const clinicLocation = parseClinicLocation(req);

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

          // optional location snapshot if future schema supports it
          location: { $first: "$location" },

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

    const usersCollection = getUsersCollection();

    let byStaffId = new Map();
    let byUserId = new Map();

    if (usersCollection) {
      const staffIds = rows.map((x) => s(x.staffId)).filter(Boolean);
      const userIds = rows
        .flatMap((x) => [s(x.userId), s(x.principalId)])
        .filter(Boolean);

      const orQuery = [];
      if (staffIds.length > 0) {
        orQuery.push({ staffId: { $in: staffIds } });
      }
      if (userIds.length > 0) {
        orQuery.push({ userId: { $in: userIds } });
      }

      const userDocs =
        orQuery.length > 0
          ? await usersCollection
              .find({ $or: orQuery })
              .project({
                userId: 1,
                staffId: 1,
                fullName: 1,
                phone: 1,
                role: 1,
                activeRole: 1,
                location: 1,
              })
              .toArray()
          : [];

      byStaffId = new Map(
        userDocs
          .map((u) => [s(u.staffId), u])
          .filter(([k]) => Boolean(k))
      );

      byUserId = new Map(
        userDocs
          .map((u) => [s(u.userId), u])
          .filter(([k]) => Boolean(k))
      );
    }

    const recommended = rows
      .map((x) => {
        const trustScore = n(x.trustScore, 0);

        const matchedUser =
          byUserId.get(s(x.userId)) ||
          byUserId.get(s(x.principalId)) ||
          byStaffId.get(s(x.staffId)) ||
          null;

        const profile = chooseBetterProfile(x, matchedUser || {});
        const helperLocation = pickLocation(profile.location || {});
        const distanceKm = haversineKm(
          clinicLocation.lat,
          clinicLocation.lng,
          helperLocation.lat,
          helperLocation.lng
        );
        const areaText = buildAreaText(helperLocation);

        const badges = arr(x.badges).map((b) => s(b)).filter(Boolean);
        const flags = arr(x.flags).map((f) => s(f)).filter(Boolean);

        if (Number.isFinite(distanceKm) && distanceKm <= 10) {
          if (!badges.includes("NEAR_CLINIC")) {
            badges.push("NEAR_CLINIC");
          }
        }

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

          // location
          location: {
            lat: helperLocation.lat,
            lng: helperLocation.lng,
            district: helperLocation.district,
            province: helperLocation.province,
            address: helperLocation.address,
            label: helperLocation.label,
          },
          areaText,
          distanceKm,
          distanceText: formatDistanceText(distanceKm),
          nearClinic: Number.isFinite(distanceKm) ? distanceKm <= 10 : false,

          // score
          trustScore,
          level: s(x.level) || "unknown",
          levelLabel: s(x.levelLabel) || "ยังไม่มีข้อมูล",
          badges,
          flags,
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
            ...(badges.slice(0, 2)),
            ...(Number.isFinite(distanceKm)
              ? [`distance ${formatDistanceText(distanceKm)}`]
              : []),
          ],
        };
      })
      .sort((a, b) => {
        const aHasDistance = Number.isFinite(a.distanceKm);
        const bHasDistance = Number.isFinite(b.distanceKm);

        if (aHasDistance && bHasDistance && a.distanceKm !== b.distanceKm) {
          return a.distanceKm - b.distanceKm;
        }

        if (b.trustScore !== a.trustScore) {
          return b.trustScore - a.trustScore;
        }

        return s(b.fullName).localeCompare(s(a.fullName));
      });

    return res.json({
      clinicId,
      clinicLocation,
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