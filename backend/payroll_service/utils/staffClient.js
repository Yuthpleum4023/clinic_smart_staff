// backend/payroll_service/utils/staffClient.js
//
// PURPOSE: payroll_service -> staff_service client
// - getEmployeeByUserId(userId, bearerToken?)
// - getEmployeeByStaffId(staffId, bearerToken?)          ✅ NEW
// - listEmployeesDropdown(bearerToken?)                  ✅ NEW (admin dropdown)
//
// NOTE:
// staff_service ของท่านใช้: app.use("/api/employees", employeeRoutes)
// ดังนั้น path หลักคือ /api/employees/...
// แต่ใส่ fallback candidates เผื่อบางเครื่องยังเป็น /employees/...

function s(v) {
  return String(v || "").trim();
}

function baseUrl() {
  const u = s(process.env.STAFF_SERVICE_URL);
  if (!u) throw new Error("Missing STAFF_SERVICE_URL");
  return u.replace(/\/+$/, "");
}

function buildHeaders(bearerToken = "") {
  const headers = {};
  const t = s(bearerToken);
  if (t) headers["Authorization"] = t; // ส่งต่อ token เดิม (ถ้า staff_service มี auth)
  return headers;
}

async function fetchJson(url, { headers = {}, timeoutMs = 15000 } = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);

  try {
    const r = await fetch(url, {
      method: "GET",
      headers,
      signal: ctrl.signal,
    });

    const data = await r.json().catch(() => ({}));
    return { ok: r.ok, status: r.status, data };
  } finally {
    clearTimeout(t);
  }
}

// helper: try multiple candidate URLs (compat)
async function getFirstOk(candidates, headers) {
  let last = null;

  for (const url of candidates) {
    const res = await fetchJson(url, { headers });

    if (res.ok) return res;

    // เก็บ error ล่าสุดไว้
    last = res;
  }

  const msg =
    last?.data?.message ||
    last?.data?.error ||
    `staff_service error (${last?.status || "unknown"})`;

  const err = new Error(msg);
  err.status = last?.status || 500;
  err.payload = last?.data || {};
  err.tried = candidates;
  throw err;
}

// ======================================================
// ดึง employee โดย userId
// ======================================================
async function getEmployeeByUserId(userId, bearerToken = "") {
  const u = s(userId);
  if (!u) throw new Error("Missing userId");

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const candidates = [
    `${b}/api/employees/by-user/${encodeURIComponent(u)}`, // ✅ correct for your staff_service
    `${b}/employees/by-user/${encodeURIComponent(u)}`, // fallback
  ];

  const r = await getFirstOk(candidates, headers);

  // รองรับทั้งแบบ {ok:true, employee:{...}} หรือส่ง employee ตรง ๆ
  return r.data?.employee || r.data || null;
}

// ======================================================
// ✅ NEW: ดึง employee โดย staffId (ซึ่งเท่ากับ Employee _id ใน staff_service)
// ======================================================
async function getEmployeeByStaffId(staffId, bearerToken = "") {
  const id = s(staffId);
  if (!id) throw new Error("Missing staffId");

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const candidates = [
    `${b}/api/employees/by-staff/${encodeURIComponent(id)}`, // ✅ correct
    `${b}/employees/by-staff/${encodeURIComponent(id)}`, // fallback
    `${b}/api/employees/${encodeURIComponent(id)}`, // fallback (CRUD by id)
    `${b}/employees/${encodeURIComponent(id)}`, // fallback
  ];

  const r = await getFirstOk(candidates, headers);
  return r.data?.employee || r.data || null;
}

// ======================================================
// ✅ NEW: dropdown list สำหรับ admin
// - expected from staff_service: { ok:true, items:[{staffId, fullName, employmentType, userId}] }
// - fallback: ถ้า staff_service ยังไม่มี /dropdown จะ fallback ไป list แล้ว map ให้
// ======================================================
async function listEmployeesDropdown(bearerToken = "") {
  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  // 1) try dropdown endpoint first
  const dropdownCandidates = [
    `${b}/api/employees/dropdown`, // ✅ correct
    `${b}/employees/dropdown`, // fallback
  ];

  try {
    const r = await getFirstOk(dropdownCandidates, headers);
    const items = r.data?.items;
    if (Array.isArray(items)) return items;
    // ถ้า payload ไม่ตรงก็ไป fallback list
  } catch (_) {
    // ignore -> fallback list
  }

  // 2) fallback: list employees แล้ว map ให้เป็น dropdown format
  const listCandidates = [
    `${b}/api/employees`, // ✅ correct
    `${b}/employees`, // fallback
  ];

  const r2 = await getFirstOk(listCandidates, headers);

  // รองรับทั้งแบบ {ok:true, items:[...]} หรือเป็น array ตรง ๆ
  const rawList = Array.isArray(r2.data) ? r2.data : r2.data?.items;
  const list = Array.isArray(rawList) ? rawList : [];

  return list
    .filter((e) => e && (e.active === undefined || e.active === true))
    .map((e) => ({
      staffId: String(e._id || ""),
      fullName: s(e.fullName),
      employmentType: s(e.employmentType),
      userId: s(e.userId),
    }))
    .filter((x) => x.staffId);
}

module.exports = {
  getEmployeeByUserId,
  getEmployeeByStaffId,
  listEmployeesDropdown,
};