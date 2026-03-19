// backend/payroll_service/utils/staffClient.js
//
// PURPOSE: payroll_service -> staff_service client
// - getEmployeeByUserId(userId, bearerToken?)
// - getEmployeeByStaffId(staffId, bearerToken?)
// - listEmployeesDropdown(bearerToken?)
//
// NOTE:
// staff_service ของท่านใช้: app.use("/api/employees", employeeRoutes)
// ดังนั้น path หลักคือ /api/employees/...
// แต่ใส่ fallback candidates เผื่อบางเครื่องยังเป็น /employees/...
//
// PATCH:
// - ✅ send x-internal-key for internal calls
// - ✅ stop fallback immediately on 429 Too Many Requests
// - ✅ clearer error propagation

function s(v) {
  return String(v || "").trim();
}

function baseUrl() {
  const u = s(process.env.STAFF_SERVICE_URL);
  if (!u) {
    const err = new Error("Missing STAFF_SERVICE_URL");
    err.status = 503;
    err.payload = { message: "Missing STAFF_SERVICE_URL" };
    throw err;
  }
  return u.replace(/\/+$/, "");
}

function buildHeaders(bearerToken = "") {
  const headers = {
    Accept: "application/json",
  };

  const t = s(bearerToken);
  if (t) {
    headers["Authorization"] = t;
  }

  const internalKey = s(
    process.env.STAFF_SERVICE_INTERNAL_KEY || process.env.INTERNAL_SERVICE_KEY
  );
  if (internalKey) {
    headers["x-internal-key"] = internalKey;
  }

  return headers;
}

async function readResponseBodySafe(response) {
  const raw = await response.text().catch(() => "");

  if (!raw) {
    return { raw: "", data: {} };
  }

  try {
    return { raw, data: JSON.parse(raw) };
  } catch (_) {
    return {
      raw,
      data: {
        message: raw,
      },
    };
  }
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

    const { raw, data } = await readResponseBodySafe(r);

    return {
      ok: r.ok,
      status: r.status,
      data,
      raw,
      url,
    };
  } catch (e) {
    if (e?.name === "AbortError") {
      const err = new Error(`staff_service timeout after ${timeoutMs}ms`);
      err.status = 504;
      err.payload = { message: err.message };
      err.url = url;
      throw err;
    }

    const err = new Error(e?.message || "staff_service request failed");
    err.status = 503;
    err.payload = { message: err.message };
    err.url = url;
    throw err;
  } finally {
    clearTimeout(t);
  }
}

function extractEmployee(payload) {
  if (!payload || typeof payload !== "object") return null;

  if (payload.employee && typeof payload.employee === "object") {
    return payload.employee;
  }

  if (
    payload.data &&
    typeof payload.data === "object" &&
    !Array.isArray(payload.data)
  ) {
    if (payload.data.employee && typeof payload.data.employee === "object") {
      return payload.data.employee;
    }
    return payload.data;
  }

  if (payload.item && typeof payload.item === "object") {
    return payload.item;
  }

  if (
    payload.result &&
    typeof payload.result === "object" &&
    !Array.isArray(payload.result)
  ) {
    return payload.result;
  }

  if (Array.isArray(payload.items) && payload.items.length === 1) {
    return payload.items[0];
  }

  if (
    payload._id ||
    payload.id ||
    payload.staffId ||
    payload.userId ||
    payload.fullName
  ) {
    return payload;
  }

  return null;
}

function extractList(payload) {
  if (Array.isArray(payload)) return payload;
  if (!payload || typeof payload !== "object") return [];

  if (Array.isArray(payload.items)) return payload.items;
  if (Array.isArray(payload.data)) return payload.data;
  if (Array.isArray(payload.results)) return payload.results;
  if (Array.isArray(payload.employees)) return payload.employees;

  if (
    payload.data &&
    typeof payload.data === "object" &&
    Array.isArray(payload.data.items)
  ) {
    return payload.data.items;
  }

  return [];
}

// helper: try multiple candidate URLs (compat)
async function getFirstOk(candidates, headers, options = {}) {
  const allow404 = !!options.allow404;
  let last = null;

  for (const url of candidates) {
    try {
      const res = await fetchJson(url, { headers });

      if (res.ok) return res;

      // ✅ ถ้าโดน rate limit ให้หยุดเลย ห้าม fallback ต่อ
      if (res.status === 429) {
        const msg =
          res?.data?.message ||
          res?.data?.error ||
          res?.raw ||
          "staff_service rate limited (429)";
        const err = new Error(msg);
        err.status = 429;
        err.payload = res.data || { message: msg };
        err.url = url;
        throw err;
      }

      if (allow404 && res.status === 404) {
        last = res;
        continue;
      }

      last = res;
    } catch (e) {
      // ✅ ถ้า 429 ให้โยนขึ้นทันที ห้ามไป candidate ถัดไป
      if (Number(e?.status || 0) === 429) {
        throw e;
      }

      last = {
        ok: false,
        status: e?.status || 503,
        data: e?.payload || {
          message: e?.message || "staff_service request failed",
        },
        raw: "",
        url,
      };
    }
  }

  if (allow404 && last?.status === 404) {
    return last;
  }

  const msg =
    last?.data?.message ||
    last?.data?.error ||
    last?.raw ||
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
    `${b}/api/employees/by-user/${encodeURIComponent(u)}`,
    `${b}/employees/by-user/${encodeURIComponent(u)}`,
    `${b}/api/employees?userId=${encodeURIComponent(u)}`,
    `${b}/employees?userId=${encodeURIComponent(u)}`,
  ];

  const r = await getFirstOk(candidates, headers, { allow404: true });

  if (!r.ok && r.status === 404) return null;

  const employee = extractEmployee(r.data);
  return employee || null;
}

// ======================================================
// ดึง employee โดย staffId (ซึ่งเท่ากับ Employee _id ใน staff_service)
// ======================================================
async function getEmployeeByStaffId(staffId, bearerToken = "") {
  const id = s(staffId);
  if (!id) throw new Error("Missing staffId");

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const candidates = [
    `${b}/api/employees/by-staff/${encodeURIComponent(id)}`,
    `${b}/employees/by-staff/${encodeURIComponent(id)}`,
    `${b}/api/employees/${encodeURIComponent(id)}`,
    `${b}/employees/${encodeURIComponent(id)}`,
    `${b}/api/employees?staffId=${encodeURIComponent(id)}`,
    `${b}/employees?staffId=${encodeURIComponent(id)}`,
  ];

  const r = await getFirstOk(candidates, headers, { allow404: true });

  if (!r.ok && r.status === 404) return null;

  const employee = extractEmployee(r.data);
  return employee || null;
}

// ======================================================
// dropdown list สำหรับ admin
// - expected from staff_service: { ok:true, items:[{staffId, fullName, employmentType, userId}] }
// - fallback: ถ้า staff_service ยังไม่มี /dropdown จะ fallback ไป list แล้ว map ให้
// ======================================================
async function listEmployeesDropdown(bearerToken = "") {
  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  // 1) try dropdown endpoint first
  const dropdownCandidates = [
    `${b}/api/employees/dropdown`,
    `${b}/employees/dropdown`,
  ];

  try {
    const r = await getFirstOk(dropdownCandidates, headers, { allow404: true });
    const items = extractList(r.data);
    if (Array.isArray(items) && items.length) {
      return items
        .filter((e) => e && typeof e === "object")
        .map((e) => ({
          staffId: s(e.staffId || e._id || e.id),
          fullName: s(e.fullName || e.name),
          employmentType: s(e.employmentType),
          userId: s(e.userId || e.linkedUserId),
        }))
        .filter((x) => x.staffId);
    }
  } catch (e) {
    if (Number(e?.status || 0) === 429) {
      throw e;
    }
    // ignore -> fallback list
  }

  // 2) fallback: list employees แล้ว map ให้เป็น dropdown format
  const listCandidates = [
    `${b}/api/employees`,
    `${b}/employees`,
  ];

  const r2 = await getFirstOk(listCandidates, headers);
  const list = extractList(r2.data);

  return list
    .filter((e) => {
      if (!e || typeof e !== "object") return false;

      const status = s(e.status || e.employeeStatus).toLowerCase();
      const activeFlag = e.active;

      if (activeFlag === false) return false;
      if (["inactive", "terminated", "deleted", "archived"].includes(status)) {
        return false;
      }

      return true;
    })
    .map((e) => ({
      staffId: s(e.staffId || e._id || e.id),
      fullName: s(e.fullName || e.name),
      employmentType: s(e.employmentType),
      userId: s(e.userId || e.linkedUserId),
    }))
    .filter((x) => x.staffId);
}

module.exports = {
  getEmployeeByUserId,
  getEmployeeByStaffId,
  listEmployeesDropdown,
};