// backend/payroll_service/utils/staffClient.js
//
// PURPOSE: payroll_service -> staff_service client
// - getEmployeeByUserId(userId, bearerToken?)
// - getEmployeeByStaffId(staffId, bearerToken?)
// - listEmployeesDropdown(bearerToken?)
//
// PRODUCTION SAFE PATCH
// - ลด fallback candidates ให้เหลือเท่าที่จำเป็น
// - มี in-memory short cache ลด request ซ้ำ
// - stop immediately on 429 Too Many Requests
// - stop immediately on 401/403 (auth/internal key issue)
// - dedupe in-flight requests (ถ้ามี call พร้อมกัน key เดียวกัน จะใช้ promise เดียวกัน)
// - clearer error propagation + safer logs
// - FIX: null cache works correctly
// - FIX: dropdown cache key safer per bearer token key
// - FIX: user/staff lookup cache key now separated by bearer token key
// - FIX: extractEmployee supports array/list fallback better
//
// ✅ UPDATED FOR BACKEND-ONLY PAYROLL:
// - normalizeEmployee() now exposes stable payroll fields:
//   baseSalary / salary / monthlySalary / monthlyWage
//   hourlyRate / hourlyWage
//   employmentType / employeeType / workType
//   linkedUserId / userId
//

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
    headers.Authorization = t;
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

async function fetchJson(url, { headers = {}, timeoutMs = 10000 } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);

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
    clearTimeout(timer);
  }
}

function makeError(message, status = 500, payload = {}, extra = {}) {
  const err = new Error(message || "staff_service error");
  err.status = status;
  err.payload = payload || {};
  Object.assign(err, extra || {});
  return err;
}

function shouldStopImmediately(status) {
  const code = Number(status || 0);
  return code === 429 || code === 401 || code === 403;
}

function extractEmployee(payload) {
  if (!payload) return null;

  if (Array.isArray(payload) && payload.length === 1) {
    return payload[0];
  }

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

    if (Array.isArray(payload.data.items) && payload.data.items.length === 1) {
      return payload.data.items[0];
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

  if (Array.isArray(payload.results) && payload.results.length === 1) {
    return payload.results[0];
  }

  if (Array.isArray(payload.employees) && payload.employees.length === 1) {
    return payload.employees[0];
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

function normalizeEmployee(employee) {
  if (!employee || typeof employee !== "object") return null;

  const monthlySalary = n(
    employee.baseSalary ??
      employee.salary ??
      employee.monthlySalary ??
      employee.monthlyWage ??
      employee.grossBase ??
      employee.grossMonthly ??
      employee.fixedSalary ??
      employee.defaultSalary ??
      employee.payroll?.baseSalary ??
      employee.payroll?.monthlySalary ??
      employee.payroll?.salary ??
      0
  );

  const hourlyRate = n(
    employee.hourlyRate ??
      employee.hourlyWage ??
      employee.hourly_salary ??
      employee.hourly_salary_rate ??
      employee.wagePerHour ??
      employee.ratePerHour ??
      employee.payroll?.hourlyRate ??
      employee.payroll?.hourlyWage ??
      0
  );

  const employmentType = s(
    employee.employmentType ||
      employee.employeeType ||
      employee.workType ||
      employee.payroll?.employmentType ||
      ""
  );

  const userId = s(
    employee.userId ||
      employee.linkedUserId ||
      employee.linked_user_id ||
      employee.accountUserId ||
      employee.user?._id ||
      employee.user?.id ||
      ""
  );

  const staffId = s(
    employee.staffId ||
      employee.employeeCode ||
      employee.code ||
      employee._id ||
      employee.id ||
      ""
  );

  return {
    ...employee,

    _id: s(employee._id || employee.id || staffId || ""),
    id: s(employee.id || employee._id || staffId || ""),

    staffId,

    userId,
    linkedUserId: s(
      employee.linkedUserId ||
        employee.linked_user_id ||
        userId ||
        employee.accountUserId ||
        employee.user?._id ||
        employee.user?.id ||
        ""
    ),

    fullName: s(employee.fullName || employee.name || ""),
    name: s(employee.name || employee.fullName || ""),

    clinicId: s(
      employee.clinicId ||
        employee.clinic?._id ||
        employee.clinic?.id ||
        employee.clinic?.clinicId ||
        ""
    ),

    employmentType,
    employeeType: s(employee.employeeType || employmentType),
    workType: s(employee.workType || employmentType),

    // ✅ Stable payroll fields for payroll_service
    baseSalary: monthlySalary,
    salary: monthlySalary,
    monthlySalary,
    monthlyWage: monthlySalary,

    hourlyRate,
    hourlyWage: hourlyRate,

    status: s(employee.status || employee.employeeStatus || ""),
  };
}

// ======================================================
// SHORT CACHE + IN-FLIGHT DEDUPE
// ======================================================
const RESPONSE_CACHE = new Map();
const INFLIGHT = new Map();

const DEFAULT_TTL_MS = n(process.env.STAFF_CLIENT_CACHE_TTL_MS, 5000);
const NULL_TTL_MS = n(process.env.STAFF_CLIENT_NULL_CACHE_TTL_MS, 2000);

const CACHE_MISS = Symbol("CACHE_MISS");

function nowMs() {
  return Date.now();
}

function getCache(cacheKey) {
  const item = RESPONSE_CACHE.get(cacheKey);
  if (!item) return CACHE_MISS;

  if (item.expireAt <= nowMs()) {
    RESPONSE_CACHE.delete(cacheKey);
    return CACHE_MISS;
  }

  return item.value;
}

function setCache(cacheKey, value, ttlMs = DEFAULT_TTL_MS) {
  RESPONSE_CACHE.set(cacheKey, {
    value,
    expireAt: nowMs() + Math.max(500, ttlMs),
  });
}

function deleteCache(cacheKey) {
  RESPONSE_CACHE.delete(cacheKey);
}

async function withInflight(cacheKey, fn) {
  if (INFLIGHT.has(cacheKey)) {
    return INFLIGHT.get(cacheKey);
  }

  const promise = (async () => {
    try {
      return await fn();
    } finally {
      INFLIGHT.delete(cacheKey);
    }
  })();

  INFLIGHT.set(cacheKey, promise);
  return promise;
}

function tokenCacheKeyPart(bearerToken = "") {
  const t = s(bearerToken);
  if (!t) return "anon";

  let h = 0;
  for (let i = 0; i < t.length; i++) {
    h = (h * 31 + t.charCodeAt(i)) >>> 0;
  }

  return `tok:${h.toString(16)}`;
}

// ======================================================
// CORE CANDIDATE FETCHER
// ======================================================
async function getFirstOk(candidates, headers, options = {}) {
  const allow404 = !!options.allow404;
  const timeoutMs = n(options.timeoutMs, 10000);
  let last = null;

  for (const url of candidates) {
    try {
      const res = await fetchJson(url, { headers, timeoutMs });

      if (res.ok) {
        return res;
      }

      const msg =
        res?.data?.message ||
        res?.data?.error ||
        res?.raw ||
        `staff_service error (${res.status || "unknown"})`;

      if (shouldStopImmediately(res.status)) {
        throw makeError(msg, res.status, res.data || {}, { url });
      }

      if (allow404 && res.status === 404) {
        last = res;
        continue;
      }

      last = res;
    } catch (e) {
      const status = Number(e?.status || 0);

      if (shouldStopImmediately(status)) {
        throw e;
      }

      last = {
        ok: false,
        status: status || 503,
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

  throw makeError(msg, last?.status || 500, last?.data || {}, {
    tried: candidates,
  });
}

// ======================================================
// LOOKUP BY USER ID
// ใช้เท่าที่จำเป็น: endpoint หลัก + fallback query
// ======================================================
async function getEmployeeByUserId(userId, bearerToken = "") {
  const u = s(userId);
  if (!u) {
    throw makeError("Missing userId", 400, { message: "Missing userId" });
  }

  const tokenPart = tokenCacheKeyPart(bearerToken);
  const cacheKey = `user:${u}:${tokenPart}`;
  const cached = getCache(cacheKey);
  if (cached !== CACHE_MISS) return cached;

  return withInflight(cacheKey, async () => {
    const cachedAgain = getCache(cacheKey);
    if (cachedAgain !== CACHE_MISS) return cachedAgain;

    const b = baseUrl();
    const headers = buildHeaders(bearerToken);

    const candidates = [
      `${b}/api/employees/by-user/${encodeURIComponent(u)}`,
      `${b}/api/employees?userId=${encodeURIComponent(u)}`,
    ];

    const r = await getFirstOk(candidates, headers, {
      allow404: true,
      timeoutMs: 10000,
    });

    if (!r.ok && r.status === 404) {
      setCache(cacheKey, null, NULL_TTL_MS);
      return null;
    }

    const employee =
      normalizeEmployee(extractEmployee(r.data)) ||
      normalizeEmployee(extractList(r.data)[0]);

    if (!employee) {
      setCache(cacheKey, null, NULL_TTL_MS);
      return null;
    }

    setCache(cacheKey, employee, DEFAULT_TTL_MS);

    if (employee.staffId) {
      setCache(`staff:${employee.staffId}:${tokenPart}`, employee, DEFAULT_TTL_MS);
    }

    if (employee.userId) {
      setCache(`user:${employee.userId}:${tokenPart}`, employee, DEFAULT_TTL_MS);
    }

    return employee;
  });
}

// ======================================================
// LOOKUP BY STAFF ID
// ใช้เท่าที่จำเป็น: endpoint หลัก + fallback by id
// ======================================================
async function getEmployeeByStaffId(staffId, bearerToken = "") {
  const id = s(staffId);
  if (!id) {
    throw makeError("Missing staffId", 400, { message: "Missing staffId" });
  }

  const tokenPart = tokenCacheKeyPart(bearerToken);
  const cacheKey = `staff:${id}:${tokenPart}`;
  const cached = getCache(cacheKey);
  if (cached !== CACHE_MISS) return cached;

  return withInflight(cacheKey, async () => {
    const cachedAgain = getCache(cacheKey);
    if (cachedAgain !== CACHE_MISS) return cachedAgain;

    const b = baseUrl();
    const headers = buildHeaders(bearerToken);

    const candidates = [
      `${b}/api/employees/by-staff/${encodeURIComponent(id)}`,
      `${b}/api/employees/${encodeURIComponent(id)}`,
    ];

    const r = await getFirstOk(candidates, headers, {
      allow404: true,
      timeoutMs: 10000,
    });

    if (!r.ok && r.status === 404) {
      setCache(cacheKey, null, NULL_TTL_MS);
      return null;
    }

    const employee =
      normalizeEmployee(extractEmployee(r.data)) ||
      normalizeEmployee(extractList(r.data)[0]);

    if (!employee) {
      setCache(cacheKey, null, NULL_TTL_MS);
      return null;
    }

    setCache(cacheKey, employee, DEFAULT_TTL_MS);

    if (employee.staffId) {
      setCache(`staff:${employee.staffId}:${tokenPart}`, employee, DEFAULT_TTL_MS);
    }

    if (employee.userId) {
      setCache(`user:${employee.userId}:${tokenPart}`, employee, DEFAULT_TTL_MS);
    }

    return employee;
  });
}

// ======================================================
// DROPDOWN LIST FOR ADMIN
// try dropdown endpoint first, then fallback to full list
// ======================================================
async function listEmployeesDropdown(bearerToken = "") {
  const cacheKey = `dropdown:employees:${tokenCacheKeyPart(bearerToken)}`;
  const cached = getCache(cacheKey);
  if (cached !== CACHE_MISS) return cached;

  return withInflight(cacheKey, async () => {
    const cachedAgain = getCache(cacheKey);
    if (cachedAgain !== CACHE_MISS) return cachedAgain;

    const b = baseUrl();
    const headers = buildHeaders(bearerToken);

    const dropdownCandidates = [
      `${b}/api/employees/dropdown`,
      `${b}/api/employees`,
    ];

    const r = await getFirstOk(dropdownCandidates, headers, {
      allow404: true,
      timeoutMs: 12000,
    });

    const items = extractList(r.data);

    const normalized = (Array.isArray(items) ? items : [])
      .filter((e) => e && typeof e === "object")
      .filter((e) => {
        const status = s(e.status || e.employeeStatus).toLowerCase();
        const activeFlag =
          e.active === undefined && e.isActive === undefined
            ? null
            : !!(e.active ?? e.isActive);

        const deleted =
          !!e.deleted || !!e.isDeleted || !!e.archived || !!e.isArchived;

        const inactive =
          activeFlag === false ||
          ["inactive", "terminated", "deleted", "archived"].includes(status);

        return !deleted && !inactive;
      })
      .map((e) => {
        const emp = normalizeEmployee(e);

        return {
          staffId: s(emp?.staffId || emp?._id || emp?.id),
          fullName: s(emp?.fullName || emp?.name),
          employmentType: s(emp?.employmentType),
          userId: s(emp?.userId || emp?.linkedUserId),

          // ✅ optional payroll fields for dropdown consumers
          baseSalary: n(emp?.baseSalary),
          monthlySalary: n(emp?.monthlySalary),
          hourlyRate: n(emp?.hourlyRate),
          hourlyWage: n(emp?.hourlyWage),
        };
      })
      .filter((x) => x.staffId);

    setCache(cacheKey, normalized, DEFAULT_TTL_MS);

    return normalized;
  });
}

// ======================================================
// OPTIONAL HELPERS (debug/admin use)
// ======================================================
function clearStaffClientCache() {
  RESPONSE_CACHE.clear();
  INFLIGHT.clear();
}

function getStaffClientCacheStats() {
  return {
    responseCacheSize: RESPONSE_CACHE.size,
    inflightSize: INFLIGHT.size,
    defaultTtlMs: DEFAULT_TTL_MS,
    nullTtlMs: NULL_TTL_MS,
  };
}

module.exports = {
  getEmployeeByUserId,
  getEmployeeByStaffId,
  listEmployeesDropdown,
  clearStaffClientCache,
  getStaffClientCacheStats,
};