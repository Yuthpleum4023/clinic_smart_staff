"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const pipeline =
  path.join(root, "packaging", "windows", "build_pipeline");
const installer =
  path.join(root, "packaging", "windows", "installer");

function read(file) {
  return fs.readFileSync(file, "utf8");
}

const releaseManifest =
  JSON.parse(
    read(
      path.join(
        pipeline,
        "release-manifest.json"
      )
    )
  );

assert.equal(
  releaseManifest.productName,
  "Clinic Smart Staff Connector"
);

assert.equal(
  releaseManifest.architecture,
  "x64"
);

assert.equal(
  releaseManifest.signed,
  false
);

assert.equal(
  releaseManifest.serviceWrapper,
  "winsw"
);

const iss =
  read(
    path.join(
      installer,
      "ClinicSmartStaffConnector.iss"
    )
  );

assert.match(
  iss,
  /PrivilegesRequired=admin/
);

assert.match(
  iss,
  /ArchitecturesAllowed=x64compatible/
);

assert.match(
  iss,
  /install-service\.ps1/
);

assert.match(
  iss,
  /uninstall-service\.ps1/
);

const buildLayout =
  read(
    path.join(
      pipeline,
      "build-layout.ps1"
    )
  );

assert.match(
  buildLayout,
  /Pinned Node runtime input missing/
);

assert.match(
  buildLayout,
  /Pinned WinSW input missing/
);

const verify =
  read(
    path.join(
      pipeline,
      "verify-build-layout.ps1"
    )
  );

assert.match(
  verify,
  /Plaintext database password found/
);

const checksum =
  read(
    path.join(
      pipeline,
      "write-checksums.ps1"
    )
  );

assert.match(
  checksum,
  /SHA256/
);


assert.match(
  checksum,
  /\$Lines -join "`n"/
);

assert.match(
  checksum,
  /WriteAllText/
);

assert.doesNotMatch(
  checksum,
  /Set-Content[\s\S]*-Value \$Lines/
);

const allText =
  [
    releaseManifest,
    iss,
    buildLayout,
    verify,
    checksum,
    read(
      path.join(
        pipeline,
        "build-installer.ps1"
      )
    )
  ]
    .map((v) =>
      typeof v === "string"
        ? v
        : JSON.stringify(v)
    )
    .join("\n");

for (const forbidden of [
  "INSERT INTO",
  "DELETE FROM",
  "DROP TABLE"
]) {
  assert.equal(
    allText.includes(forbidden),
    false
  );
}


const buildInstaller =
  read(
    path.join(
      pipeline,
      "build-installer.ps1"
    )
  );

for (const [name, script] of [
  ["build-installer.ps1", buildInstaller],
  ["build-layout.ps1", buildLayout],
  ["verify-build-layout.ps1", verify],
  ["write-checksums.ps1", checksum]
]) {
  const firstStatement =
    script
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find(Boolean);

  assert.equal(
    firstStatement,
    "param(",
    `${name} must declare param before executable statements`
  );

  assert.ok(
    script.indexOf("param(") <
      script.indexOf('$ErrorActionPreference = "Stop"'),
    `${name} parameter binding must precede ErrorActionPreference`
  );
}

assert.doesNotMatch(
  buildInstaller,
  /build_pipeline_pipeline/
);

assert.match(
  buildInstaller,
  /packaging\\windows\\build_pipeline"/
);

assert.equal(
  /CLINIC_CONNECTOR_TOKEN\s*=\s*["'][^"']+/.test(
    allText
  ),
  false
);

assert.equal(
  /CLINIC_SOURCE_DB_PASSWORD\s*=\s*["'][^"']+/.test(
    allText
  ),
  false
);

console.log(
  "WINDOWS_INSTALLER_PIPELINE_TESTS_PASSED=TRUE"
);
console.log(
  "PINNED_EXTERNAL_BUILD_INPUTS_REQUIRED=TRUE"
);
console.log(
  "INNO_SETUP_DEFINITION=TRUE"
);
console.log(
  "SHA256_MANIFEST=TRUE"
);
console.log(
  "INSTALLER_EMBEDS_SECRETS=FALSE"
);
console.log(
  "SIGNED_INSTALLER_CREATED=FALSE"
);
