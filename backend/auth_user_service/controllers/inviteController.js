// backend/auth_user_service/controllers/inviteController.js

const Invite = require("../models/Invite");
const { makeInviteCode } = require("../utils/id");

function normStr(v) {
  return String(v || "").trim();
}

function upper(v) {
  return normStr(v).toUpperCase();
}

function normalizeInviteRole(v) {
  const r = normStr(v).toLowerCase();
  return r === "helper" || r === "employee" ? r : "";
}

function isExpired(inv) {
  if (!inv?.expiresAt) return false;
  const t = new Date(inv.expiresAt).getTime();
  if (!Number.isFinite(t)) return false;
  return Date.now() > t;
}

function serializeInvite(inv = {}) {
  return {
    _id: inv._id,
    inviteCode: normStr(inv.inviteCode),
    clinicId: normStr(inv.clinicId),
    createdByUserId: normStr(inv.createdByUserId),
    role: normalizeInviteRole(inv.role) || "employee",
    fullName: normStr(inv.fullName),
    email: normStr(inv.email),
    phone: normStr(inv.phone),
    expiresAt: inv.expiresAt || null,
    usedAt: inv.usedAt || null,
    usedByUserId: normStr(inv.usedByUserId),
    isRevoked: !!inv.isRevoked,
    isExpired: isExpired(inv),
    createdAt: inv.createdAt || null,
    updatedAt: inv.updatedAt || null,
  };
}

async function createInvite(req, res) {
  try {
    const { clinicId, userId } = req.user || {};
    const scopedClinicId = normStr(clinicId);
    const scopedUserId = normStr(userId);

    if (!scopedClinicId) {
      return res.status(401).json({
        ok: false,
        message: "Missing clinicId in token",
      });
    }

    if (!scopedUserId) {
      return res.status(401).json({
        ok: false,
        message: "Missing userId in token",
      });
    }

    const len = parseInt(process.env.INVITE_CODE_LEN || "8", 10);
    const expiresHours = parseInt(
      process.env.INVITE_DEFAULT_EXPIRES_HOURS || "72",
      10
    );

    const { fullName = "", email = "", phone = "", role } = req.body || {};
    const inviteRole = normalizeInviteRole(role) || "employee";

    let code = "";
    for (let i = 0; i < 5; i++) {
      const c = upper(makeInviteCode(len));
      const exists = await Invite.findOne({ inviteCode: c }).lean();
      if (!exists) {
        code = c;
        break;
      }
    }

    if (!code) {
      return res.status(500).json({
        ok: false,
        message: "Failed to generate invite code",
      });
    }

    const expiresAt = new Date(Date.now() + expiresHours * 60 * 60 * 1000);

    const inv = await Invite.create({
      inviteCode: code,
      clinicId: scopedClinicId,
      createdByUserId: scopedUserId,
      role: inviteRole,
      fullName: normStr(fullName),
      email: normStr(email),
      phone: normStr(phone),
      expiresAt,
      usedAt: null,
      usedByUserId: "",
      isRevoked: false,
    });

    return res.status(201).json({
      ok: true,
      invite: serializeInvite(inv),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "createInvite failed",
      error: e.message || String(e),
    });
  }
}

async function listInvites(req, res) {
  try {
    const { clinicId } = req.user || {};
    const scopedClinicId = normStr(clinicId);

    if (!scopedClinicId) {
      return res.status(401).json({
        ok: false,
        message: "Missing clinicId in token",
      });
    }

    const invites = await Invite.find({ clinicId: scopedClinicId })
      .sort({ createdAt: -1 })
      .lean();

    return res.json({
      ok: true,
      invites: invites.map(serializeInvite),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "listInvites failed",
      error: e.message || String(e),
    });
  }
}

async function revokeInvite(req, res) {
  try {
    const { clinicId } = req.user || {};
    const scopedClinicId = normStr(clinicId);
    const code = upper(req.params?.code);

    if (!scopedClinicId) {
      return res.status(401).json({
        ok: false,
        message: "Missing clinicId in token",
      });
    }

    if (!code) {
      return res.status(400).json({
        ok: false,
        message: "Invite code is required",
      });
    }

    const inv = await Invite.findOne({
      clinicId: scopedClinicId,
      inviteCode: code,
    });

    if (!inv) {
      return res.status(404).json({
        ok: false,
        message: "Invite not found",
      });
    }

    inv.isRevoked = true;
    await inv.save();

    return res.json({
      ok: true,
      invite: serializeInvite(inv),
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "revokeInvite failed",
      error: e.message || String(e),
    });
  }
}

// POST /api/invites/redeem
// ใช้ก่อนสมัคร account
// คืน clinicId + role + prefill fields
// ยังไม่ mark used ที่ endpoint นี้
// ให้ mark used ตอน register success จริง
async function redeemInvite(req, res) {
  try {
    const code = upper(req.body?.inviteCode);

    if (!code) {
      return res.status(400).json({
        ok: false,
        message: "inviteCode is required",
      });
    }

    const inv = await Invite.findOne({ inviteCode: code }).lean();

    if (!inv) {
      return res.status(404).json({
        ok: false,
        message: "Invalid invite code",
      });
    }

    if (inv.isRevoked) {
      return res.status(400).json({
        ok: false,
        message: "Invite revoked",
      });
    }

    if (inv.usedAt) {
      return res.status(400).json({
        ok: false,
        message: "Invite already used",
      });
    }

    if (isExpired(inv)) {
      return res.status(400).json({
        ok: false,
        message: "Invite expired",
      });
    }

    return res.json({
      ok: true,
      invite: {
        inviteCode: normStr(inv.inviteCode),
        clinicId: normStr(inv.clinicId),
        role: normalizeInviteRole(inv.role) || "employee",
        fullName: normStr(inv.fullName),
        email: normStr(inv.email),
        phone: normStr(inv.phone),
        expiresAt: inv.expiresAt || null,
      },
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "redeemInvite failed",
      error: e.message || String(e),
    });
  }
}

// ==================================================
// HELPER: finalize invite after register success
// IMPORTANT:
// - ใช้หลังสร้าง user สำเร็จแล้วเท่านั้น
// - auth_user_service "ไม่สร้าง employee" เอง
// - function นี้แค่ mark invite used และคืน invite payload
//   ให้ register controller เอาไปใช้ต่อ
// ==================================================
async function finalizeInviteAfterRegister(inviteCode, userId) {
  const code = upper(inviteCode);
  const uid = normStr(userId);

  if (!code) {
    throw new Error("inviteCode is required");
  }

  if (!uid) {
    throw new Error("userId is required");
  }

  const inv = await Invite.findOne({ inviteCode: code });

  if (!inv) {
    throw new Error("Invalid invite code");
  }

  if (inv.isRevoked) {
    throw new Error("Invite revoked");
  }

  if (inv.usedAt) {
    throw new Error("Invite already used");
  }

  if (isExpired(inv)) {
    throw new Error("Invite expired");
  }

  inv.usedAt = new Date();
  inv.usedByUserId = uid;

  await inv.save();

  return {
    inviteCode: normStr(inv.inviteCode),
    clinicId: normStr(inv.clinicId),
    role: normalizeInviteRole(inv.role) || "employee",
    fullName: normStr(inv.fullName),
    email: normStr(inv.email),
    phone: normStr(inv.phone),
    expiresAt: inv.expiresAt || null,
  };
}

// ==================================================
// HELPER: find valid invite by code without marking used
// useful for register flow / service logic
// ==================================================
async function getValidInviteByCode(inviteCode) {
  const code = upper(inviteCode);

  if (!code) {
    throw new Error("inviteCode is required");
  }

  const inv = await Invite.findOne({ inviteCode: code }).lean();

  if (!inv) {
    throw new Error("Invalid invite code");
  }

  if (inv.isRevoked) {
    throw new Error("Invite revoked");
  }

  if (inv.usedAt) {
    throw new Error("Invite already used");
  }

  if (isExpired(inv)) {
    throw new Error("Invite expired");
  }

  return {
    inviteCode: normStr(inv.inviteCode),
    clinicId: normStr(inv.clinicId),
    role: normalizeInviteRole(inv.role) || "employee",
    fullName: normStr(inv.fullName),
    email: normStr(inv.email),
    phone: normStr(inv.phone),
    expiresAt: inv.expiresAt || null,
  };
}

module.exports = {
  createInvite,
  listInvites,
  revokeInvite,
  redeemInvite,
  finalizeInviteAfterRegister,
  getValidInviteByCode,
};