// controllers/scoreController.js
//
// ✅ FULL FILE (UPDATED)
// - ✅ ของเดิมครบ: getStaffScore / postAttendanceEvent
// - ✅ เพิ่ม searchStaff: GET /staff/search?q=...  (ค้นชื่อ/เบอร์/รหัส)
// - ✅ SAFE: ถ้า score_service ยังไม่มี models/User.js จะไม่ล้ม -> ตอบ 501 บอกให้เพิ่มโมเดลก่อน

const TrustScore = require("../models/TrustScore");
const AttendanceEvent = require("../models/AttendanceEvent");

const BASE_SCORE = 80;

// ✅ key มาตรฐาน
const SCORE_RULES = {
  completed: +1,
  late: -2,
  cancelled_early: -5,
  no_show: -25,
};

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

function normalizeStatus(status) {
  let st = String(status || "").trim().toLowerCase();

  // ✅ backward compat: ถ้ามี client ส่ง cancelled มา ให้ map เป็น cancelled_early
  if (st === "cancelled") st = "cancelled_early";

  return st;
}

// --------------------------------------
// ✅ helpers for search
// --------------------------------------
function _cleanQuery(q) {
  return String(q || "").trim();
}

function _digitsOnly(s) {
  return String(s || "").replace(/\D/g, "");
}

function _safeRegexContains(q) {
  // escape regex special chars
  const esc = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(esc, "i");
}

// --------------------------------------
// GET /staff/:staffId/score
// --------------------------------------
async function getStaffScore(req, res) {
  try {
    const staffId = (req.params.staffId || "").trim();
    if (!staffId) return res.status(400).json({ message: "staffId is required" });

    let doc = await TrustScore.findOne({ staffId }).lean();

    if (!doc) {
      const created = await TrustScore.create({ staffId, trustScore: BASE_SCORE });
      doc = created.toObject();
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
        cancelled: doc.cancelled || 0, // ✅ คงชื่อเดิมให้ UI ใช้ได้เลย
      },
    });
  } catch (e) {
    return res.status(500).json({
      message: "getStaffScore failed",
      error: e.message || String(e),
    });
  }
}

// --------------------------------------
// ✅ GET /staff/search?q=...&limit=20
// ใช้สำหรับค้นหา "ชื่อ/เบอร์" แล้วคืน staffId (กันผู้ใช้ต้องจำ id)
// --------------------------------------
async function searchStaff(req, res) {
  try {
    const q = _cleanQuery(req.query.q);
    const limit = Math.max(1, Math.min(Number(req.query.limit || 20), 50));

    if (!q) {
      return res.status(400).json({ message: "q is required" });
    }

    // ✅ score_service อาจยังไม่มี User model
    let User;
    try {
      User = require("../models/User");
    } catch (_) {
      return res.status(501).json({
        message:
          "searchStaff not available: score_service has no models/User.js yet",
        hint:
          "ให้เพิ่ม models/User.js (schema ผู้ใช้) มาไว้ใน score_service หรือทำ route นี้เป็น proxy ไป auth_user_service",
      });
    }

    const rx = _safeRegexContains(q);
    const digits = _digitsOnly(q);
    const phoneRx = digits ? _safeRegexContains(digits) : null;

    // ค้นจาก: fullName, phone, staffId, employeeCode, userId, email
    const or = [
      { fullName: rx },
      { staffId: rx },
      { employeeCode: rx },
      { userId: rx },
      { email: rx },
    ];
    if (phoneRx) {
      // phone เก็บทั้งแบบมีขีด/เว้นวรรคได้ -> เทียบแบบ contains digits ก็พอ
      or.push({ phone: phoneRx });
    } else {
      or.push({ phone: rx });
    }

    const users = await User.find({ $or: or })
      .select("staffId fullName phone userId clinicId role employeeCode email")
      .limit(limit)
      .lean();

    // ✅ เติม trustScore แบบเบา ๆ ให้ UI เลือกคนได้ง่ายขึ้น
    const staffIds = users
      .map((u) => String(u.staffId || "").trim())
      .filter((x) => x);

    const scoreDocs = staffIds.length
      ? await TrustScore.find({ staffId: { $in: staffIds } })
          .select("staffId trustScore totalShifts completed late noShow cancelled flags badges")
          .lean()
      : [];

    const scoreMap = new Map(scoreDocs.map((d) => [d.staffId, d]));

    const results = users.map((u) => {
      const sid = String(u.staffId || "").trim();
      const sc = sid ? scoreMap.get(sid) : null;

      return {
        staffId: sid || "",
        fullName: u.fullName || "",
        phone: u.phone || "",
        userId: u.userId || "",
        clinicId: u.clinicId || "",
        role: u.role || "",
        employeeCode: u.employeeCode || "",
        email: u.email || "",

        // score summary (optional)
        trustScore: sc ? sc.trustScore : null,
        stats: sc
          ? {
              totalShifts: sc.totalShifts || 0,
              completed: sc.completed || 0,
              late: sc.late || 0,
              noShow: sc.noShow || 0,
              cancelled: sc.cancelled || 0,
            }
          : null,
      };
    });

    return res.json({
      ok: true,
      q,
      count: results.length,
      results,
    });
  } catch (e) {
    return res.status(500).json({
      message: "searchStaff failed",
      error: e.message || String(e),
    });
  }
}

// --------------------------------------
// POST /events/attendance
// --------------------------------------
async function postAttendanceEvent(req, res) {
  try {
    const { clinicId = "", staffId = "", shiftId = "", status, minutesLate = 0 } = req.body || {};

    const sId = String(staffId || "").trim();
    if (!sId) return res.status(400).json({ message: "staffId is required" });

    const st = normalizeStatus(status);
    if (!Object.prototype.hasOwnProperty.call(SCORE_RULES, st)) {
      return res.status(400).json({
        message: "Invalid status",
        allowed: Object.keys(SCORE_RULES),
      });
    }

    // 1) log event
    await AttendanceEvent.create({
      clinicId,
      staffId: sId,
      shiftId,
      status: st,
      minutesLate: Number(minutesLate || 0),
      occurredAt: new Date(),
    });

    // 2) load/create TrustScore
    let doc = await TrustScore.findOne({ staffId: sId });
    if (!doc) doc = await TrustScore.create({ staffId: sId, trustScore: BASE_SCORE });

    // 3) apply score
    const delta = SCORE_RULES[st];
    doc.trustScore = clamp((doc.trustScore ?? BASE_SCORE) + delta, 0, 100);

    // 4) counters
    doc.totalShifts = (doc.totalShifts || 0) + 1;

    if (st === "completed") doc.completed = (doc.completed || 0) + 1;
    if (st === "late") doc.late = (doc.late || 0) + 1;

    if (st === "no_show") {
      doc.noShow = (doc.noShow || 0) + 1;
      doc.lastNoShowAt = new Date();
      if (!doc.flags.includes("NO_SHOW_30D")) doc.flags.push("NO_SHOW_30D");
    }

    if (st === "cancelled_early") {
      doc.cancelled = (doc.cancelled || 0) + 1;
    }

    await doc.save();

    return res.json({
      ok: true,
      staffId: doc.staffId,
      applied: { status: st, delta },
      trustScore: doc.trustScore,
      stats: {
        totalShifts: doc.totalShifts,
        completed: doc.completed,
        late: doc.late,
        noShow: doc.noShow,
        cancelled: doc.cancelled,
      },
      flags: doc.flags,
      badges: doc.badges || [],
    });
  } catch (e) {
    return res.status(500).json({
      message: "postAttendanceEvent failed",
      error: e.message || String(e),
    });
  }
}

module.exports = { getStaffScore, postAttendanceEvent, searchStaff };
