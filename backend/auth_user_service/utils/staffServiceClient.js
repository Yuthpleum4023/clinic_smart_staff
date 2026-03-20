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
  if (!uid) return null;

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);

  const url = `${b}/api/employees/by-user/${encodeURIComponent(uid)}`;

  console.log("🧪 [staffClient] getEmployeeByUserId");
  console.log("   ↳ baseUrl:", b);
  console.log("   ↳ url:", url);
  console.log("   ↳ userId:", uid);
  console.log("   ↳ has internal key:", !!headers["x-internal-key"]);

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

    return employee ? normalizeEmployeePayload(employee) : null;
  } catch (e) {
    console.log("⚠️ [staffClient] getEmployeeByUserId failed:", {
      status: Number(e?.status || 0),
      message: e?.message || "",
      payload: e?.payload || {},
    });

    if ([404, 429].includes(Number(e?.status))) {
      return null;
    }
    throw e;
  }
}

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
    console.log("⚠️ [staffClient] createEmployeeFromUser skipped: invalid body", body);
    return null;
  }

  const b = baseUrl();
  const headers = buildHeaders(bearerToken);
  const url = `${b}/api/employees/internal/create-from-user`;

  console.log("🧪 [staffClient] createEmployeeFromUser");
  console.log("   ↳ baseUrl:", b);
  console.log("   ↳ url:", url);
  console.log("   ↳ has internal key:", !!headers["x-internal-key"]);
  console.log("   ↳ internal key prefix:", s(headers["x-internal-key"]).slice(0, 12));
  console.log("   ↳ body:", body);

  try {
    const data = await fetchJson(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      timeoutMs: 12000,
    });

    const employee =
      data?.employee ||
      data?.data?.employee ||
      data?.data ||
      data?.item ||
      data?.result ||
      null;

    console.log("✅ [staffClient] createEmployeeFromUser success:", {
      created: !!employee,
      staffId: s(employee?.staffId || employee?._id || employee?.id),
      userId: s(employee?.userId),
      clinicId: s(employee?.clinicId),
    });

    return employee ? normalizeEmployeePayload(employee) : null;
  } catch (e) {
    console.log("❌ [staffClient] createEmployeeFromUser failed:", {
      status: Number(e?.status || 0),
      message: e?.message || "",
      payload: e?.payload || {},
    });

    if (Number(e?.status) === 429) {
      console.log("⚠️ createEmployee skipped (429 rate limit)");
      return null;
    }

    console.log("⚠️ createEmployee failed:", e.message);
    return null;
  }
}

async function ensureEmployeeForUser(userLike, bearerToken = "") {
  try {
    const role = s(userLike?.activeRole || userLike?.role).toLowerCase();
    const roles = Array.isArray(userLike?.roles)
      ? userLike.roles.map((x) => s(x).toLowerCase())
      : [];

    const isEmployee = role === "employee" || roles.includes("employee");

    console.log("🧪 [staffClient] ensureEmployeeForUser");
    console.log("   ↳ userId:", s(userLike?.userId));
    console.log("   ↳ clinicId:", s(userLike?.clinicId));
    console.log("   ↳ role:", role);
    console.log("   ↳ roles:", roles);
    console.log("   ↳ isEmployee:", isEmployee);

    if (!isEmployee) {
      return { ok: true, skipped: true, reason: "not_employee_role" };
    }

    const userId = s(userLike?.userId);
    if (!userId) {
      return { ok: false, skipped: true, reason: "missing_userId" };
    }

    const clinicId = s(userLike?.clinicId);
    if (!clinicId) {
      return { ok: false, skipped: true, reason: "missing_clinicId" };
    }

    const existing = await getEmployeeByUserId(userId, bearerToken);
    if (existing) {
      console.log("✅ [staffClient] employee already exists:", {
        userId: existing.userId,
        staffId: existing.staffId,
        clinicId: existing.clinicId,
      });

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
      created: !!created,
      skipped: !created,
      reason: created ? "" : "create_failed_or_rate_limited",
      employee: created,
    };
  } catch (e) {
    console.log("⚠️ ensureEmployeeForUser safe fail:", e.message);

    return {
      ok: false,
      skipped: true,
      reason: "safe_fail",
    };
  }
}

module.exports = {
  getEmployeeByUserId,
  createEmployeeFromUser,
  ensureEmployeeForUser,
};