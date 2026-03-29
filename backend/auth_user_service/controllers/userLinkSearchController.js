const User = require("../models/User");

function s(v) {
  return String(v || "").trim();
}

function escapeRegex(v) {
  return s(v).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeRole(v) {
  return s(v).toLowerCase();
}

function isAdminLikeRole(role) {
  const r = normalizeRole(role);
  return r === "admin" || r === "clinic_admin" || r === "clinic";
}

function splitThaiOrGenericName(fullName) {
  const text = s(fullName);
  if (!text) {
    return {
      firstName: "",
      lastName: "",
    };
  }

  const parts = text.split(/\s+/).filter(Boolean);
  if (!parts.length) {
    return {
      firstName: "",
      lastName: "",
    };
  }

  return {
    firstName: s(parts[0]),
    lastName: s(parts.slice(1).join(" ")),
  };
}

function toSearchItems(docs = []) {
  return docs
    .filter((u) => u && typeof u === "object")
    .map((u) => {
      const fullName = s(u.fullName);
      const nameParts = splitThaiOrGenericName(fullName);

      return {
        userId: s(u.userId),
        fullName,
        firstName: nameParts.firstName,
        lastName: nameParts.lastName,
        phone: s(u.phone),
        email: s(u.email),
        role: s(u.activeRole || u.role),
        clinicId: s(u.clinicId),
        staffId: s(u.staffId),
        employeeProvisionStatus: s(u.employeeProvisionStatus),
        isActive: !!u.isActive,
      };
    });
}

exports.searchUsersForEmployeeLink = async (req, res) => {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = normalizeRole(req.user?.role);
    const q = s(req.query?.q);

    if (!req.user?.userId) {
      return res.status(401).json({
        ok: false,
        message: "Unauthorized",
      });
    }

    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        message: "Missing clinicId in token",
      });
    }

    if (!isAdminLikeRole(role)) {
      return res.status(403).json({
        ok: false,
        message: "Forbidden",
      });
    }

    if (!q) {
      return res.json({
        ok: true,
        items: [],
      });
    }

    const safe = escapeRegex(q);
    const rx = new RegExp(safe, "i");

    const limitRaw = parseInt(String(req.query?.limit || "20"), 10);
    const limit = Math.min(
      Math.max(Number.isFinite(limitRaw) ? limitRaw : 20, 1),
      50
    );

    const mongoQuery = {
      clinicId,
      isActive: true,
      $or: [
        { fullName: rx },
        { phone: rx },
        { email: rx },
        { userId: rx },
      ],
    };

    const docs = await User.find(mongoQuery)
      .select(
        "userId fullName phone email role activeRole roles clinicId staffId employeeProvisionStatus isActive"
      )
      .sort({ fullName: 1, createdAt: -1 })
      .limit(limit)
      .lean();

    const items = toSearchItems(docs).filter(
      (u) => !isAdminLikeRole(u.role)
    );

    return res.json({
      ok: true,
      items,
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      message: "searchUsersForEmployeeLink failed",
      error: e.message || String(e),
    });
  }
};