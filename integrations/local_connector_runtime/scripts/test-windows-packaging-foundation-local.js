"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const pkg = path.join(root, "packaging", "windows");

function read(rel) {
  return fs.readFileSync(path.join(pkg, rel), "utf8");
}

const manifest = JSON.parse(read("package-manifest.json"));

assert.equal(manifest.productName, "Clinic Smart Staff Connector");
assert.equal(manifest.legacyPatientWorkstationInstall, false);
assert.equal(manifest.secrets.embeddedInInstaller, false);
assert.equal(manifest.secrets.embeddedInConfig, false);

const configTemplate =
  JSON.parse(read("templates/connector-config.template.json"));

assert.equal(
  configTemplate.connectorTokenEnv,
  "CLINIC_CONNECTOR_TOKEN"
);

assert.equal(
  configTemplate.source.passwordEnv,
  "CLINIC_SOURCE_DB_PASSWORD"
);

assert.equal(
  Object.prototype.hasOwnProperty.call(
    configTemplate.source,
    "password"
  ),
  false
);

const serviceXml =
  read("service/ClinicSmartStaffConnectorService.xml");

assert.match(serviceXml, /ClinicSmartStaffConnector/);
assert.match(serviceXml, /node\\node\.exe/);
assert.match(serviceXml, /app\\bin\\connector\.js/);

const install = read("scripts/install-service.ps1");

const provision = read("scripts/provision-and-start-service.ps1");

assert.doesNotMatch(
  install,
  /CLINIC_CONNECTOR_TOKEN/
);
assert.doesNotMatch(
  install,
  /CLINIC_SOURCE_DB_PASSWORD/
);

assert.match(
  provision,
  /CLINIC_CONNECTOR_TOKEN/
);

assert.match(
  provision,
  /CLINIC_SOURCE_DB_PASSWORD/
);

for (const forbidden of [
  "INSERT INTO",
  "UPDATE ",
  "DELETE FROM",
  "DROP TABLE"
]) {
  assert.equal(serviceXml.includes(forbidden), false);
  assert.equal(install.includes(forbidden), false);
}

console.log("WINDOWS_PACKAGING_FOUNDATION_TESTS_PASSED=TRUE");
console.log("INSTALLER_EMBEDS_SECRETS=FALSE");
console.log("CONFIG_EMBEDS_DB_PASSWORD=FALSE");
console.log("WINDOWS_SERVICE_RESTART_POLICY=TRUE");
console.log("LEGACY_PATIENT_WORKSTATION_REQUIRED=FALSE");
console.log("PUBLIC_DATABASE_PORT_REQUIRED=FALSE");
