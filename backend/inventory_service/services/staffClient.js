const { s } = require("../utils/strings");

function baseUrl() {
  return s(process.env.STAFF_SERVICE_URL).replace(/\/+$/, "");
}

function internalKey() {
  return s(
    process.env.STAFF_SERVICE_INTERNAL_KEY ||
      process.env.INTERNAL_SERVICE_KEY
  );
}

function employeeBasePath() {
  return s(
    process.env.STAFF_EMPLOYEE_BASE_PATH ||
      "/api/employees"
  ).replace(/\/+$/, "");
}

async function parseJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return {};
  }
}

function pickEmployee(payload) {
  return (
    payload?.employee ||
    payload?.data?.employee ||
    payload?.data ||
    null
  );
}

async function fetchEmployee(url, headers) {
  let response;

  try {
    response = await fetch(url, {
      method: "GET",
      headers,
      signal: AbortSignal.timeout(8000),
    });
  } catch (cause) {
    const err = new Error("staff_service unavailable");
    err.status = 503;
    err.code = "STAFF_SERVICE_UNAVAILABLE";
    err.cause = cause;
    throw err;
  }

  const payload = await parseJson(response);

  if (response.status === 404) return null;

  if (!response.ok) {
    const err = new Error(
      s(payload?.message || payload?.error) ||
        `staff_service returned ${response.status}`
    );
    err.status = response.status >= 500 ? 503 : response.status;
    err.code = "STAFF_LOOKUP_FAILED";
    throw err;
  }

  return pickEmployee(payload);
}

async function getEmployeeByUserId({
  userId,
  clinicId,
  authorization = "",
}) {
  const base = baseUrl();

  if (!base) {
    const err = new Error("STAFF_SERVICE_URL is not configured");
    err.status = 503;
    err.code = "STAFF_SERVICE_NOT_CONFIGURED";
    throw err;
  }

  const path = employeeBasePath();

  if (s(authorization)) {
    const url =
      `${base}${path}/by-user/${encodeURIComponent(userId)}`;

    return fetchEmployee(url, {
      authorization: s(authorization),
      accept: "application/json",
    });
  }

  const key = internalKey();

  if (!key) {
    const err = new Error(
      "No user Authorization header and no staff internal key configured"
    );
    err.status = 503;
    err.code = "STAFF_AUTH_CONTEXT_REQUIRED";
    throw err;
  }

  const url =
    `${base}${path}/internal/by-user/${encodeURIComponent(userId)}` +
    `?clinicId=${encodeURIComponent(clinicId)}`;

  return fetchEmployee(url, {
    "x-internal-key": key,
    accept: "application/json",
  });
}

module.exports = { getEmployeeByUserId };
