const TrustScore = require("../models/TrustScore");

async function getRecommendations(req, res) {
  try {
    const { clinicId } = req.query;
    if (!clinicId) return res.status(400).json({ message: "clinicId required" });

    // MVP: แนะนำจาก trustScore สูงสุด และตัดคนมี flag NO_SHOW_30D ออก
    const list = await TrustScore.find({
      $or: [{ flags: { $exists: false } }, { flags: { $ne: "NO_SHOW_30D" } }],
    })
      .sort({ trustScore: -1, updatedAt: -1 })
      .limit(10)
      .lean();

    const recommended = list.map((x) => ({
      staffId: x.staffId,
      trustScore: x.trustScore,
      badges: x.badges || [],
      flags: x.flags || [],
      reason: [
        `trustScore ${x.trustScore}`,
        ...(x.badges || []).slice(0, 2),
      ],
    }));

    return res.json({ clinicId, recommended });
  } catch (e) {
    return res.status(500).json({ message: "getRecommendations failed", error: e.message || String(e) });
  }
}

module.exports = { getRecommendations };
