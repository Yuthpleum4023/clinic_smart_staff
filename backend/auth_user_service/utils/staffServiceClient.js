function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));
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

// ================= SAFE FETCH (NO CREATE RETRY) =================
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
        data?.message || `HTTP ${res.status}`,
        res.status,
        data
      );
    }

    return data;
  } catch (e) {
    if (e?.name === "AbortError") {
      throw makeError("staff service timeout", 504);
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

// ================= NORMALIZE =================
function normalizeEmployeePayload(employeeLike = {}) {
  const obj =
    employeeLike && typeof employeeLike === "object" ? employeeLike : {};

  return {
    staffId: s(obj.staffId || obj._id || obj.id),
    userId: s(obj.userId),
    clinicId: s(obj.clinicId),
    fullName: s(obj.fullName),
  };
}

// ================= GET =================
async function getEmployeeByUserId(userId, bearerToken = "", clinicId = "") {
  const uid = s(userId);
  const cid = s(clinicId);
  if (!uid) return null;

  const url = `${baseUrl()}/api/employees/internal/by-user/${uid}?clinicId=${cid}`;

  try {
    const data = await fetchJson(url, {
      method: "GET",
      headers: buildHeaders(bearerToken),
      timeoutMs: 10000,
    });

    const emp = data?.employee || null;
    return emp ? normalizeEmployeePayload(emp) : null;
  } catch (e) {
    if (e.status === 404) return null;
    if (e.status === 429) throw makeError("EMPLOYEE_BUSY", 429);
    throw e;
  }
}

// ================= ENSURE (NEW) =================
async function ensureEmployee(userLike, bearerToken = "") {
  const body = {
    userId: s(userLike.userId),
    clinicId: s(userLike.clinicId),
    fullName: s(userLike.fullName),
  };

  const url = `${baseUrl()}/api/employees/internal/ensure`;

  const data = await fetchJson(url, {
    method: "POST",
    headers: buildHeaders(bearerToken),
    body: JSON.stringify(body),
    timeoutMs: 15000,
  });

  return data?.employee
    ? normalizeEmployeePayload(data.employee)
    : null;
}

// ================= MAIN =================
async function ensureEmployeeForUser(userLike, bearerToken = "") {
  try {
    const userId = s(userLike?.userId);
    const clinicId = s(userLike?.clinicId);

    if (!userId || !clinicId) {
      return {
        ok: false,
        skipped: true,
        reason: "missing_data",
      };
    }

    // 1. check existing
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

    // 2. ensure (NO RETRY)
    const employee = await ensureEmployee(userLike, bearerToken);

    return {
      ok: true,
      created: true,
      skipped: false,
      employee,
    };
  } catch (e) {
    const status = Number(e?.status || 0);

    console.log("⚠️ ensureEmployeeForUser:", status, e.message);

    if (status === 429) {
      return {
        ok: true,
        skipped: true,
        reason: "employee_service_busy",
      };
    }

    return {
      ok: true,
      skipped: true,
      reason: "unknown_error",
    };
  }
}

module.exports = {
  getEmployeeByUserId,
  ensureEmployeeForUser,
};