#!/usr/bin/env node
"use strict";
const { buildFdReadOnlyConnectivityConfig, assertFdReadOnlyConnectivityConfig } = require("../src/connectivity/fd/fdReadOnlyConnectionConfig");
function s(value) { return String(value ?? "").trim(); }
try {
  const config = buildFdReadOnlyConnectivityConfig({ host: s(process.env.FD_SOURCE_HOST), user: s(process.env.FD_SOURCE_USER) });
  assertFdReadOnlyConnectivityConfig(config);
  process.stdout.write(JSON.stringify(config, null, 2) + "\n");
} catch (err) {
  console.error(JSON.stringify({ ok: false, code: String(err?.message || "FD_CONNECTIVITY_CONFIG_FAILED") }, null, 2));
  process.exit(1);
}
