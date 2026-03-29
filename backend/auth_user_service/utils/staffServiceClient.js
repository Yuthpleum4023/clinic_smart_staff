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
    err.payload = { message: "Missing STAFF_SERVICE_URL" };
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

function makeError(message, status = 500, payload = {}, extra = {}) {
  const err = new Error(message || "staff service error");
  err.status = status;
  err.payload = payload || {};
  Object.assign(err, extra || {});
  return err;
}

function logStaffClient(label, data = {}) {
  try {
    console.log(`[STAFF_CLIENT] ${label}`, data);
  } catch (_) {}
}

function normalizeReasonFromStatus(status, fallback = "unknown_error") {
  const code = Number(status || 0);

  if (code === 400) return "bad_request";
  if (code === 401) return "unauthorized";
  if (code === 403) return "forbidden";
  if (code === 404) return "not_found";
  if (code === 409) return "conflict";
  if (code === 429) return "employee_service_busy";
  if (code === 500) return "staff_service_500";
  if (code === 502 || code === 503 || code === 504) {
    return "staff_service_unavailable";
  }

  return fallback;
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
        data,
        { url }
      );
    }

    return data;
  } catch (e) {
    if (e?.name === "AbortError") {
      throw makeError(
        "staff service timeout",
        504,
        { message: "staff service timeout" },
        { url }
      );
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

function buildEnsureBody(userLike = {}) {
  return {
    userId: s(userLike.userId),
    clinicId: s(userLike.clinicId),
    fullName: s(userLike.fullName),
  };
}

// ================= GET =================
async function getEmployeeByUserId(userId, bearerToken = "", clinicId = "") {
  const uid = s(userId);
  const cid = s(clinicId);
  if (!uid) return null;

  const url = `${baseUrl()}/api/employees/internal/by-user/${encodeURIComponent(
    uid
  )}?clinicId=${encodeURIComponent(cid)}`;

  logStaffClient("getEmployeeByUserId.start", {
    userId: uid,
    clinicId: cid,
    url,
    hasBearer: !!s(bearerToken),
    hasInternalKey: !!internalKey(),
  });

  try {
    const data = await fetchJson(url, {
      method: "GET",
      headers: buildHeaders(bearerToken),
      timeoutMs: 10000,
    });

    const emp = data?.employee || null;
    const normalized = emp ? normalizeEmployeePayload(emp) : null;

    logStaffClient("getEmployeeByUserId.success", {
      userId: uid,
      clinicId: cid,
      found: !!normalized,
      staffId: s(normalized?.staffId),
    });

    return normalized;
  } catch (e) {
    const status = Number(e?.status || 0);

    logStaffClient("getEmployeeByUserId.failed", {
      userId: uid,
      clinicId: cid,
      status,
      reason: normalizeReasonFromStatus(status),
      message: e?.message || "",
      payload: e?.payload || {},
    });

    if (status === 404) return null;
    if (status === 429) throw makeError("EMPLOYEE_BUSY", 429, e?.payload || {});
    throw e;
  }
}

// ================= ENSURE =================
async function ensureEmployee(userLike, bearerToken = "") {
  const body = buildEnsureBody(userLike);
  const url = `${baseUrl()}/api/employees/internal/ensure`;

  logStaffClient("ensureEmployee.start", {
    userId: body.userId,
    clinicId: body.clinicId,
    fullName: body.fullName,
    url,
    hasBearer: !!s(bearerToken),
    hasInternalKey: !!internalKey(),
  });

  const data = await fetchJson(url, {
    method: "POST",
    headers: buildHeaders(bearerToken),
    body: JSON.stringify(body),
    timeoutMs: 15000,
  });

  const employee = data?.employee
    ? normalizeEmployeePayload(data.employee)
    : null;

  logStaffClient("ensureEmployee.success", {
    userId: body.userId,
    clinicId: body.clinicId,
    created: !!data?.created,
    staffId: s(employee?.staffId),
  });

  return employee;
}

// ================= MAIN =================
async function ensureEmployeeForUser(userLike, bearerToken = "") {
  const userId = s(userLike?.userId);
  const clinicId = s(userLike?.clinicId);
  const fullName = s(userLike?.fullName);

  try {
    if (!userId || !clinicId) {
      logStaffClient("ensureEmployeeForUser.skip_missing_data", {
        userId,
        clinicId,
        fullName,
      });

      return {
        ok: false,
        skipped: true,
        reason: "missing_data",
      };
    }

    if (!fullName) {
      logStaffClient("ensureEmployeeForUser.skip_missing_fullName", {
        userId,
        clinicId,
      });

      return {
        ok: false,
        skipped: true,
        reason: "missing_full_name",
      };
    }

    // 1) check existing
    const existing = await getEmployeeByUserId(userId, bearerToken, clinicId);

    if (existing) {
      logStaffClient("ensureEmployeeForUser.existing", {
        userId,
        clinicId,
        staffId: s(existing?.staffId),
      });

      return {
        ok: true,
        created: false,
        skipped: false,
        reason: "",
        employee: existing,
      };
    }

    // 2) ensure
    const employee = await ensureEmployee(userLike, bearerToken);

    if (!employee || !s(employee.staffId)) {
      logStaffClient("ensureEmployeeForUser.not_ready_after_ensure", {
        userId,
        clinicId,
      });

      return {
        ok: false,
        created: false,
        skipped: true,
        reason: "employee_not_ready",
      };
    }

    return {
      ok: true,
      created: true,
      skipped: false,
      reason: "",
      employee,
    };
  } catch (e) {
    const status = Number(e?.status || 0);
    const reason = normalizeReasonFromStatus(status);

    logStaffClient("ensureEmployeeForUser.failed", {
      userId,
      clinicId,
      fullName,
      status,
      reason,
      message: e?.message || "",
      payload: e?.payload || {},
    });

    if (status === 429) {
      return {
        ok: false,
        skipped: true,
        reason: "employee_service_busy",
      };
    }

    if (status === 400) {
      return {
        ok: false,
        skipped: true,
        reason: "bad_request",
      };
    }

    if (status === 401 || status === 403) {
      return {
        ok: false,
        skipped: true,
        reason: "auth_failed",
      };
    }

    if (status === 404) {
      return {
        ok: false,
        skipped: true,
        reason: "not_found",
      };
    }

    if (status === 500) {
      return {
        ok: false,
        skipped: true,
        reason: "staff_service_500",
      };
    }

    if (status === 502 || status === 503 || status === 504) {
      return {
        ok: false,
        skipped: true,
        reason: "staff_service_unavailable",
      };
    }

    return {
      ok: false,
      skipped: true,
      reason: "unknown_error",
    };
  }
}

module.exports = {
  getEmployeeByUserId,
  ensureEmployeeForUser,
};