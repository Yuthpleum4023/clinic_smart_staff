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

function scoreMatch(user, qLower) {
  const fullName = s(user.fullName).toLowerCase();
  const firstName = s(user.firstName).toLowerCase();
  const lastName = s(user.lastName).toLowerCase();
  const phone = s(user.phone).toLowerCase();
  const email = s(user.email).toLowerCase();
  const userId = s(user.userId).toLowerCase();
  const role = normalizeRole(user.role);

  let score = 0;

  if (fullName === qLower) score += 1000;
  if (`${firstName} ${lastName}`.trim() === qLower) score += 950;
  if (phone === qLower) score += 900;
  if (userId === qLower) score += 850;
  if (email === qLower) score += 800;

  if (fullName.startsWith(qLower)) score += 300;
  if (firstName.startsWith(qLower)) score += 260;
  if (lastName.startsWith(qLower)) score += 240;
  if (phone.startsWith(qLower)) score += 220;
  if (userId.startsWith(qLower)) score += 200;

  if (fullName.includes(qLower)) score += 140;
  if (firstName.includes(qLower)) score += 120;
  if (lastName.includes(qLower)) score += 110;
  if (phone.includes(qLower)) score += 100;
  if (userId.includes(qLower)) score += 90;
  if (email.includes(qLower)) score += 80;

  // ดัน helper/employee ขึ้น แต่ไม่เอา admin-like
  if (role === "helper") score += 30;
  if (role === "employee") score += 20;

  // มีชื่อจริงให้ขึ้นก่อน account ว่าง ๆ
  if (fullName) score += 15;
  if (phone) score += 10;

  return score;
}

function toSearchItems(docs = []) {
  return docs
    .filter((u) => u && typeof u === "object")
    .map((u) => {
      const fullName = s(u.fullName);
      const derivedName = splitThaiOrGenericName(fullName);

      const firstName = s(u.firstName) || derivedName.firstName;
      const lastName = s(u.lastName) || derivedName.lastName;

      return {
        userId: s(u.userId),
        fullName,
        firstName,
        lastName,
        phone: s(u.phone),
        email: s(u.email),
        role: s(u.activeRole || u.role),
        clinicId: s(u.clinicId),
        firstClinicId: s(u.firstClinicId),
        staffId: s(u.staffId),
        employeeProvisionStatus: s(u.employeeProvisionStatus),
        isActive: !!u.isActive,
        createdAt: u.createdAt || null,
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
    const qLower = q.toLowerCase();

    const limitRaw = parseInt(String(req.query?.limit || "20"), 10);
    const limit = Math.min(
      Math.max(Number.isFinite(limitRaw) ? limitRaw : 20, 1),
      50
    );

    const keywordQuery = {
      $or: [
        { fullName: rx },
        { firstName: rx },
        { lastName: rx },
        { phone: rx },
        { email: rx },
        { userId: rx },
      ],
    };

    const mongoQuery = {
      isActive: true,
      $and: [
        keywordQuery,
        {
          $or: [
            // คนที่อยู่คลินิกเดียวกับ admin
            { clinicId },
            { firstClinicId: clinicId },

            // helper กลางที่ยังไม่ได้ผูก clinic
            {
              $and: [
                {
                  $or: [{ role: "helper" }, { activeRole: "helper" }],
                },
                {
                  $or: [
                    { clinicId: { $exists: false } },
                    { clinicId: "" },
                    { clinicId: null },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    const docs = await User.find(mongoQuery)
      .select(
        "userId fullName firstName lastName phone email role activeRole roles clinicId firstClinicId staffId employeeProvisionStatus isActive createdAt"
      )
      .limit(200)
      .lean();

    const items = toSearchItems(docs)
      .filter((u) => !isAdminLikeRole(u.role))
      .sort((a, b) => {
        const scoreA = scoreMatch(a, qLower);
        const scoreB = scoreMatch(b, qLower);
        if (scoreB !== scoreA) return scoreB - scoreA;

        const nameA = s(a.fullName);
        const nameB = s(b.fullName);
        const byName = nameA.localeCompare(nameB, "th");
        if (byName !== 0) return byName;

        const timeA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
        const timeB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
        return timeB - timeA;
      })
      .slice(0, limit);

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