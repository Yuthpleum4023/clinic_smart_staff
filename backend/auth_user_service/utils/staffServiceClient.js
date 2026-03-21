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
    headers.Authorization = t.startsWith("Bearer ")
      ? t
      : `Bearer ${t}`;
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
    employeeLike && typeof employeeLike === "object"
      ? employeeLike
      : {};

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

function shouldUseInternalLookup(bearerToken = "") {
  return !s(bearerToken) && !!internalKey();
}

// ================= GET BY USER =================
async function getEmployeeByUserId(
  userId,
  bearerToken = "",
  clinicId = ""
) {
  const uid = s(userId);
  const cid = s(clinicId);
  if (!uid) return null;

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const internal = shouldUseInternalLookup(bearerToken);

  const basePath = internal
    ? `/api/employees/internal/by-user/${encodeURIComponent(uid)}`
    : `/api/employees/by-user/${encodeURIComponent(uid)}`;

  const qs =
    internal && cid
      ? `?clinicId=${encodeURIComponent(cid)}`
      : "";

  const url = `${b}${basePath}${qs}`;

  console.log("🧪 getEmployeeByUserId:", {
    url,
    internal,
    userId: uid,
    clinicId: cid,
    hasBearer: !!s(bearerToken),
    hasInternalKey: !!headers["x-internal-key"],
  });

  try {
    const data = await fetchJson(url, {
      method: "GET",
      headers,
      timeoutMs: 8000,
    });

    const employee =
      data?.employee ||
      data?.data?.employee ||
      data?.data ||
      data?.item ||
      data?.result ||
      null;

    return employee
      ? normalizeEmployeePayload(employee)
      : null;
  } catch (e) {
    const status = Number(e?.status || 0);

    console.log("⚠️ getEmployeeByUserId error:", status, e.message);

    if (status === 404) return null;

    if (status === 429) {
      throw makeError("EMPLOYEE_SERVICE_BUSY", 429);
    }

    throw e;
  }
}

// ================= CREATE =================
function buildCreateEmployeeBody(userLike = {}) {
  return {
    userId: s(userLike.userId),
    clinicId: s(userLike.clinicId),
    fullName: s(userLike.fullName || userLike.name),
    employmentType: "fullTime",
    phone: s(userLike.phone),
    email: s(userLike.email),
    employeeCode: s(userLike.employeeCode),
    active: true,
  };
}

async function createEmployeeFromUser(userLike, bearerToken = "") {
  const body = buildCreateEmployeeBody(userLike);

  if (!body.userId || !body.fullName || !body.clinicId) {
    throw makeError("Invalid employee body", 400);
  }

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const url = `${b}/api/employees/internal/create-from-user`;

  console.log("🧪 createEmployeeFromUser:", {
    url,
    body,
  });

  try {
    const data = await fetchJson(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      timeoutMs: 12000,
    });

    const employee =
      data?.employee ||
      data?.data ||
      null;

    return employee
      ? normalizeEmployeePayload(employee)
      : null;
  } catch (e) {
    const status = Number(e?.status || 0);

    console.log("❌ createEmployeeFromUser error:", status);

    if (status === 429) {
      throw makeError("EMPLOYEE_CREATE_RATE_LIMIT", 429);
    }

    throw e;
  }
}

// ================= ENSURE (⭐ FIX ตรงนี้) =================
async function ensureEmployeeForUser(userLike, bearerToken = "") {
  try {
    const userId = s(userLike?.userId);
    const clinicId = s(userLike?.clinicId);

    if (!userId || !clinicId) {
      return {
        ok: false,
        created: false,
        skipped: false,
        reason: "missing_data",
        employee: null,
      };
    }

    const existing = await getEmployeeByUserId(
      userId,
      bearerToken,
      clinicId
    );

    if (existing) {
      return {
        ok: true,
        created: false,
        skipped: false,
        employee: existing,
      };
    }

    const created = await createEmployeeFromUser(
      userLike,
      bearerToken
    );

    return {
      ok: true,
      created: !!created,
      skipped: false,
      employee: created,
    };
  } catch (e) {
    const status = Number(e?.status || 0);

    console.log("⚠️ ensureEmployeeForUser fail:", status, e.message);

    // ⭐ FIX: กัน 429 ไม่ให้พัง flow
    if (status === 429) {
      return {
        ok: true,          // ⭐ สำคัญ
        created: false,
        skipped: true,
        reason: "employee_service_busy",
        employee: null,
      };
    }

    // ⭐ FIX: กัน unknown error ไม่ให้ล้ม register
    return {
      ok: true,
      created: false,
      skipped: true,
      reason: "unknown_error",
      employee: null,
    };
  }
}

module.exports = {
  getEmployeeByUserId,
  createEmployeeFromUser,
  ensureEmployeeForUser,
};