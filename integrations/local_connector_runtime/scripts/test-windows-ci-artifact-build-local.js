"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const repo =
  path.resolve(__dirname, "..", "..", "..");

const workflow =
  fs.readFileSync(
    path.join(
      repo,
      ".github",
      "workflows",
      "build-clinic-smart-staff-connector-windows.yml"
    ),
    "utf8"
  );

assert.match(
  workflow,
  /runs-on: windows-2022/
);

assert.match(
  workflow,
  /NODE_VERSION: "22\.19\.0"/
);

assert.match(
  workflow,
  /CONNECTOR_WINSW_URL/
);

assert.match(
  workflow,
  /CONNECTOR_WINSW_SHA256/
);

assert.match(
  workflow,
  /Get-FileHash -Algorithm SHA256/
);

assert.match(
  workflow,
  /build-installer\.ps1/
);

assert.match(
  workflow,
  /ClinicSmartStaffConnectorSetup-\$\{\{ inputs\.version \}\}-x64\.exe/
);

assert.match(
  workflow,
  /SHA256SUMS\.txt/
);

assert.match(
  workflow,
  /actions\/upload-artifact@v4/
);

assert.match(
  workflow,
  /SIGNED_INSTALLER_CREATED=FALSE/
);

assert.doesNotMatch(
  workflow,
  /CLINIC_CONNECTOR_TOKEN\s*:/
);

assert.doesNotMatch(
  workflow,
  /CLINIC_SOURCE_DB_PASSWORD\s*:/
);

assert.doesNotMatch(
  workflow,
  /StockMovement/
);

console.log(
  "WINDOWS_CI_ARTIFACT_BUILD_TESTS_PASSED=TRUE"
);

console.log(
  "WINDOWS_RUNNER_PINNED=TRUE"
);

console.log(
  "NODE_VERSION_PINNED=TRUE"
);

console.log(
  "WINSW_SHA256_REQUIRED=TRUE"
);

console.log(
  "UNSIGNED_INSTALLER_ARTIFACT_UPLOAD=TRUE"
);

console.log(
  "CI_EMBEDS_CONNECTOR_SECRETS=FALSE"
);
