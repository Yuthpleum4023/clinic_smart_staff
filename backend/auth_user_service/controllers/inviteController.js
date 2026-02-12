const Invite = require("../models/Invite");
const { makeInviteCode } = require("../utils/id");

async function createInvite(req, res) {
  try {
    const { clinicId, userId } = req.user || {};
    const len = parseInt(process.env.INVITE_CODE_LEN || "8", 10);
    const expiresHours = parseInt(process.env.INVITE_DEFAULT_EXPIRES_HOURS || "72", 10);

    const { fullName = "", email = "", phone = "" } = req.body || {};

    // generate unique code (retry a few times)
    let code = "";
    for (let i = 0; i < 5; i++) {
      const c = makeInviteCode(len);
      const exists = await Invite.findOne({ inviteCode: c }).lean();
      if (!exists) {
        code = c;
        break;
      }
    }
    if (!code) return res.status(500).json({ message: "Failed to generate invite code" });

    const expiresAt = new Date(Date.now() + expiresHours * 60 * 60 * 1000);

    const inv = await Invite.create({
      inviteCode: code,
      clinicId,
      createdByUserId: userId,
      role: "employee",
      fullName,
      email,
      phone,
      expiresAt,
      usedAt: null,
      usedByUserId: "",
      isRevoked: false,
    });

    return res.json({ invite: inv });
  } catch (e) {
    return res.status(500).json({ message: "createInvite failed", error: e.message || String(e) });
  }
}

async function listInvites(req, res) {
  const { clinicId } = req.user || {};
  const invites = await Invite.find({ clinicId }).sort({ createdAt: -1 }).lean();
  return res.json({ invites });
}

async function revokeInvite(req, res) {
  const { clinicId } = req.user || {};
  const { code } = req.params;

  const inv = await Invite.findOne({ clinicId, inviteCode: code.toUpperCase() });
  if (!inv) return res.status(404).json({ message: "Invite not found" });

  inv.isRevoked = true;
  await inv.save();
  return res.json({ ok: true });
}

module.exports = { createInvite, listInvites, revokeInvite };
