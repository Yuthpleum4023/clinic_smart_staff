function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function baseUrl() {
  const u = s(process.env.STAFF_SERVICE_URL);
  if (!u) {
    const err = new Error("Missing STAFF_SERVICE_URL");
    err.status = 503;
    throw err;
  }
  return u.replace(/\/+$/, "");
}

function internalKey() {
  return s(
    process.env.STAFF_SERVICE_INTERNAL_KEY || process.env.INTERNAL_SERVICE_KEY
  );
}

function buildHeaders(bearerToken = "") {
  const headers = {
    Accept: "application/json",
    "Content-Type": "application/json",
  };

  const t = s(bearerToken);
  if (t) {
    headers.Authorization = t.startsWith("Bearer ") ? t : `Bearer ${t}`;
  }

  const key = internalKey();
  if (key) {
    headers["x-internal-key"] = key;
    headers["internal_service_key"] = key;
  }

  return headers;
}

async function readJsonSafe(res) {
  const raw = await res.text().catch(() => "");
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (_) {
    return { message: raw };
  }
}

function makeError(message, status = 500, payload = {}) {
  const err = new Error(message || "staff service error");
  err.status = status;
  err.payload = payload || {};
  return err;
}

async function fetchJson(url, options = {}) {
  const timeoutMs = n(options.timeoutMs, 15000);
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method: options.method || "GET",
      headers: options.headers || {},
      body: options.body,
      signal: ctrl.signal,
    });

    const data = await readJsonSafe(res);

    if (!res.ok) {
      throw makeError(
        data?.message || data?.error || `HTTP ${res.status}`,
        res.status,
        data
      );
    }

    return data;
  } catch (e) {
    if (e?.name === "AbortError") {
      throw makeError(`staff service timeout after ${timeoutMs}ms`, 504);
    }
    if (e?.status) throw e;
    throw makeError(e?.message || "staff service request failed", 503);
  } finally {
    clearTimeout(timer);
  }
}

function normalizeEmployeePayload(employeeLike = {}) {
  const obj =
    employeeLike && typeof employeeLike === "object" ? employeeLike : {};

  return {
    staffId: s(obj.staffId || obj._id || obj.id),
    userId: s(obj.userId),
    clinicId: s(obj.clinicId),
    employeeCode: s(obj.employeeCode),
    fullName: s(obj.fullName || obj.name),
    name: s(obj.name || obj.fullName),
    employmentType: s(obj.employmentType),
    phone: s(obj.phone),
    email: s(obj.email),
    active:
      obj.active === undefined && obj.isActive === undefined
        ? true
        : !!(obj.active ?? obj.isActive),
  };
}

async function getEmployeeByUserId(userId, bearerToken = "") {
  const uid = s(userId);
  if (!uid) {
    throw makeError("Missing userId", 400, { message: "Missing userId" });
  }

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const candidates = [
    `${b}/api/employees/by-user/${encodeURIComponent(uid)}`,
    `${b}/api/employees?userId=${encodeURIComponent(uid)}`,
  ];

  let last404 = null;

  for (const url of candidates) {
    try {
      const data = await fetchJson(url, {
        method: "GET",
        headers,
        timeoutMs: 12000,
      });

      const employee =
        data?.employee ||
        data?.data?.employee ||
        data?.data ||
        data?.item ||
        data?.result ||
        (Array.isArray(data?.items) ? data.items[0] : null) ||
        null;

      return employee ? normalizeEmployeePayload(employee) : null;
    } catch (e) {
      if (Number(e?.status || 0) === 404) {
        last404 = e;
        continue;
      }
      throw e;
    }
  }

  if (last404) return null;
  return null;
}

async function getEmployeeByStaffId(staffId, bearerToken = "") {
  const sid = s(staffId);
  if (!sid) {
    throw makeError("Missing staffId", 400, { message: "Missing staffId" });
  }

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const candidates = [
    `${b}/api/employees/by-staff/${encodeURIComponent(sid)}`,
    `${b}/api/employees/${encodeURIComponent(sid)}`,
  ];

  let last404 = null;

  for (const url of candidates) {
    try {
      const data = await fetchJson(url, {
        method: "GET",
        headers,
        timeoutMs: 12000,
      });

      const employee =
        data?.employee ||
        data?.data?.employee ||
        data?.data ||
        data?.item ||
        data?.result ||
        null;

      return employee ? normalizeEmployeePayload(employee) : null;
    } catch (e) {
      if (Number(e?.status || 0) === 404) {
        last404 = e;
        continue;
      }
      throw e;
    }
  }

  if (last404) return null;
  return null;
}

function buildCreateEmployeeBody(userLike = {}) {
  const userId = s(userLike.userId);
  const clinicId = s(userLike.clinicId);
  const fullName = s(userLike.fullName || userLike.name);
  const phone = s(userLike.phone);
  const email = s(userLike.email);
  const employmentType = s(userLike.employmentType || "fullTime");
  const employeeCode = s(userLike.employeeCode);

  return {
    userId,
    clinicId,
    fullName,
    employmentType: employmentType || "fullTime",
    phone,
    email,
    employeeCode,
    active: true,
  };
}

async function createEmployeeFromUser(userLike, bearerToken = "") {
  const body = buildCreateEmployeeBody(userLike);

  if (!body.userId) {
    throw makeError("Missing userId for employee creation", 400);
  }
  if (!body.fullName) {
    throw makeError("Missing fullName for employee creation", 400);
  }
  if (!body.clinicId) {
    throw makeError("Missing clinicId for employee creation", 400);
  }

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  // ✅ IMPORTANT:
  // ใช้ internal route ใหม่
  const data = await fetchJson(
    `${b}/api/employees/internal/create-from-user`,
    {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      timeoutMs: 15000,
    }
  );

  const employee =
    data?.employee ||
    data?.data?.employee ||
    data?.data ||
    data?.item ||
    data?.result ||
    null;

  return employee ? normalizeEmployeePayload(employee) : null;
}

async function ensureEmployeeForUser(userLike, bearerToken = "") {
  const role = s(userLike?.activeRole || userLike?.role).toLowerCase();
  const roles = Array.isArray(userLike?.roles)
    ? userLike.roles.map((x) => s(x).toLowerCase()).filter(Boolean)
    : [];

  const isEmployee = role === "employee" || roles.includes("employee");
  if (!isEmployee) {
    return {
      ok: true,
      skipped: true,
      reason: "not_employee_role",
      employee: null,
    };
  }

  const userId = s(userLike?.userId);
  if (!userId) {
    return {
      ok: false,
      skipped: true,
      reason: "missing_userId",
      employee: null,
    };
  }

  const existing = await getEmployeeByUserId(userId, bearerToken);
  if (existing) {
    return {
      ok: true,
      created: false,
      skipped: false,
      employee: existing,
    };
  }

  const created = await createEmployeeFromUser(userLike, bearerToken);

  return {
    ok: true,
    created: true,
    skipped: false,
    employee: created,
  };
}

module.exports = {
  getEmployeeByUserId,
  getEmployeeByStaffId,
  createEmployeeFromUser,
  ensureEmployeeForUser,
};