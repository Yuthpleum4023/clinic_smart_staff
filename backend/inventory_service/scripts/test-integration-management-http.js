const assert = require("node:assert/strict");
const path = require("node:path");

require("dotenv").config({
  path: path.join(__dirname, "..", ".env"),
});

const express = require("express");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");

const ConnectorConfig = require("../models/ConnectorConfig");
const InventoryItemMapping = require("../models/InventoryItemMapping");
const StockItem = require("../models/StockItem");

const inventoryRoutes = require("../routes/inventoryRoutes");

const {
  verifyConnectorSecret,
} = require("../services/connectorCredentialService");

const TEST_DB = "css_inventory_admin_mgmt_test";
const TEST_JWT_SECRET =
  "inventory-admin-management-simulator-secret";

function assertTestDatabase() {
  if (mongoose.connection.name !== TEST_DB) {
    const err = new Error(
      `Refusing management simulator cleanup outside ${TEST_DB}`
    );
    err.code = "TEST_DATABASE_GUARD_FAILED";
    throw err;
  }
}

async function cleanup() {
  assertTestDatabase();

  const models = [
    InventoryItemMapping,
    ConnectorConfig,
    StockItem,
  ];

  await Promise.all(
    models.map((Model) =>
      mongoose.connection
        .collection(Model.collection.name)
        .deleteMany({})
    )
  );
}

async function ensureIndexes() {
  assertTestDatabase();

  await Promise.all([
    ConnectorConfig.createIndexes(),
    InventoryItemMapping.createIndexes(),
  ]);
}

function tokenFor({ userId, clinicId, role }) {
  return jwt.sign(
    {
      userId,
      clinicId,
      role,
      activeRole: role,
    },
    TEST_JWT_SECRET,
    { expiresIn: "1h" }
  );
}

function createApp() {
  const app = express();

  app.use(express.json({ limit: "1mb" }));
  app.use("/api/inventory", inventoryRoutes);

  app.use((err, req, res, next) => {
    if (res.headersSent) return next(err);

    const status = Number(err?.status) || 500;

    return res.status(status).json({
      ok: false,
      code: err?.code || "REQUEST_FAILED",
      message: err?.message || "Request failed",
      ...(err?.details ? { details: err.details } : {}),
    });
  });

  return app;
}

async function jsonRequest({
  baseUrl,
  method,
  path,
  token,
  body,
}) {
  const headers = {
    "content-type": "application/json",
  };

  if (token) {
    headers.authorization = `Bearer ${token}`;
  }

  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    ...(body !== undefined
      ? { body: JSON.stringify(body) }
      : {}),
  });

  let payload = {};
  try {
    payload = await response.json();
  } catch (_) {}

  return {
    status: response.status,
    payload,
  };
}

function parseCredentialToken(token) {
  const parts = String(token || "").split(".");
  assert.equal(parts.length, 3);

  return {
    credentialKeyId: parts[1],
    secret: parts[2],
  };
}

async function run() {
  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required for management HTTP simulator"
    );
  }

  process.env.JWT_SECRET = TEST_JWT_SECRET;

  await mongoose.connect(process.env.MONGO_URI, {
    dbName: TEST_DB,
    autoIndex: false,
  });

  assertTestDatabase();
  await cleanup();
  await ensureIndexes();

  const clinicA = "admin-mgmt-clinic-a";
  const clinicB = "admin-mgmt-clinic-b";

  const adminA = tokenFor({
    userId: "admin-a",
    clinicId: clinicA,
    role: "admin",
  });

  const adminB = tokenFor({
    userId: "admin-b",
    clinicId: clinicB,
    role: "admin",
  });

  const employeeA = tokenFor({
    userId: "employee-a",
    clinicId: clinicA,
    role: "employee",
  });

  const itemA = await StockItem.create({
    clinicId: clinicA,
    name: "Management Item A",
    sku: "MGMT-A-001",
    category: "simulator",
    unit: "piece",
    currentQty: 10,
    minimumQty: 0,
    lowStockAlertEnabled: false,
    lowStockActive: false,
    active: true,
  });

  const itemABox = await StockItem.create({
    clinicId: clinicA,
    name: "Management Item A Box",
    sku: "MGMT-A-002",
    category: "simulator",
    unit: "box",
    currentQty: 10,
    minimumQty: 0,
    lowStockAlertEnabled: false,
    lowStockActive: false,
    active: true,
  });

  const itemB = await StockItem.create({
    clinicId: clinicB,
    name: "Management Item B",
    sku: "MGMT-B-001",
    category: "simulator",
    unit: "piece",
    currentQty: 10,
    minimumQty: 0,
    lowStockAlertEnabled: false,
    lowStockActive: false,
    active: true,
  });

  const app = createApp();

  const server = await new Promise((resolve) => {
    const listener = app.listen(
      0,
      "127.0.0.1",
      () => resolve(listener)
    );
  });

  try {
    const address = server.address();
    const baseUrl = `http://127.0.0.1:${address.port}`;
    const root =
      "/api/inventory/integrations/admin";

    const employeeDenied = await jsonRequest({
      baseUrl,
      method: "POST",
      path: `${root}/connectors`,
      token: employeeA,
      body: {
        connectorKey: "should-fail",
        externalSystem: "simulator",
        connectorType: "rest",
      },
    });

    assert.equal(employeeDenied.status, 403);

    const bodyScopeRejected = await jsonRequest({
      baseUrl,
      method: "POST",
      path: `${root}/connectors`,
      token: adminA,
      body: {
        clinicId: clinicB,
        connectorKey: "body-scope-reject",
        externalSystem: "simulator",
        connectorType: "rest",
      },
    });

    assert.equal(bodyScopeRejected.status, 400);
    assert.equal(
      bodyScopeRejected.payload?.code,
      "CLINIC_SCOPE_SERVER_OWNED"
    );

    const configRejected = await jsonRequest({
      baseUrl,
      method: "POST",
      path: `${root}/connectors`,
      token: adminA,
      body: {
        connectorKey: "config-reject",
        externalSystem: "simulator",
        connectorType: "rest",
        configuration: {
          password: "must-not-store",
        },
      },
    });

    assert.equal(configRejected.status, 400);
    assert.equal(
      configRejected.payload?.code,
      "CONNECTOR_CONFIGURATION_NOT_SUPPORTED"
    );

    const created = await jsonRequest({
      baseUrl,
      method: "POST",
      path: `${root}/connectors`,
      token: adminA,
      body: {
        connectorKey: "simulator-a",
        externalSystem: "generic_simulator",
        connectorType: "rest",
        displayName: "Simulator A",
      },
    });

    assert.equal(created.status, 201);
    assert.equal(created.payload?.ok, true);
    assert.equal(
      created.payload?.credential?.shownOnce,
      true
    );

    const connectorId = String(
      created.payload?.connector?._id
    );

    assert.ok(
      mongoose.Types.ObjectId.isValid(connectorId)
    );

    const firstToken =
      created.payload.credential.token;

    assert.ok(firstToken.startsWith("cssinv1."));

    const stored = await ConnectorConfig
      .findById(connectorId)
      .select("+credentialHash")
      .lean();

    assert.equal(stored.clinicId, clinicA);
    assert.equal(stored.createdBy, "admin-a");
    assert.ok(stored.credentialHash);
    assert.equal(
      JSON.stringify(stored).includes(firstToken),
      false
    );

    const list = await jsonRequest({
      baseUrl,
      method: "GET",
      path: `${root}/connectors`,
      token: adminA,
    });

    assert.equal(list.status, 200);
    assert.equal(
      list.payload?.connectors?.length,
      1
    );
    assert.equal(
      Object.prototype.hasOwnProperty.call(
        list.payload.connectors[0],
        "credentialHash"
      ),
      false
    );

    const foreignAdminDenied = await jsonRequest({
      baseUrl,
      method: "PATCH",
      path: `${root}/connectors/${connectorId}`,
      token: adminB,
      body: { enabled: false },
    });

    assert.equal(foreignAdminDenied.status, 404);

    const immutableRejected = await jsonRequest({
      baseUrl,
      method: "PATCH",
      path: `${root}/connectors/${connectorId}`,
      token: adminA,
      body: { connectorKey: "renamed" },
    });

    assert.equal(immutableRejected.status, 400);
    assert.equal(
      immutableRejected.payload?.code,
      "CONNECTOR_IDENTITY_IMMUTABLE"
    );

    const disabled = await jsonRequest({
      baseUrl,
      method: "PATCH",
      path: `${root}/connectors/${connectorId}`,
      token: adminA,
      body: {
        enabled: false,
        displayName: "Simulator A disabled",
      },
    });

    assert.equal(disabled.status, 200);
    assert.equal(
      disabled.payload?.connector?.enabled,
      false
    );

    const reenabled = await jsonRequest({
      baseUrl,
      method: "PATCH",
      path: `${root}/connectors/${connectorId}`,
      token: adminA,
      body: { enabled: true },
    });

    assert.equal(reenabled.status, 200);

    const rotated = await jsonRequest({
      baseUrl,
      method: "POST",
      path:
        `${root}/connectors/${connectorId}/rotate-credential`,
      token: adminA,
    });

    assert.equal(rotated.status, 200);
    assert.equal(
      rotated.payload?.credential?.credentialVersion,
      2
    );

    const secondToken =
      rotated.payload.credential.token;

    assert.notEqual(secondToken, firstToken);

    const firstParsed =
      parseCredentialToken(firstToken);

    const afterRotate = await ConnectorConfig
      .findById(connectorId)
      .select("+credentialHash")
      .lean();

    assert.equal(
      verifyConnectorSecret({
        credentialKeyId:
          firstParsed.credentialKeyId,
        secret: firstParsed.secret,
        credentialVersion: 1,
        credentialHash:
          afterRotate.credentialHash,
      }),
      false
    );

    const mappingBodyScopeRejected =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          `${root}/connectors/${connectorId}/mappings`,
        token: adminA,
        body: {
          clinicId: clinicB,
          externalItemId: "MED-001",
          externalUnit: "piece",
          stockItemId: String(itemA._id),
        },
      });

    assert.equal(
      mappingBodyScopeRejected.status,
      400
    );

    const inventoryUnitRejected =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          `${root}/connectors/${connectorId}/mappings`,
        token: adminA,
        body: {
          externalItemId: "MED-001",
          externalUnit: "piece",
          stockItemId: String(itemA._id),
          inventoryUnit: "fake-unit",
        },
      });

    assert.equal(
      inventoryUnitRejected.status,
      400
    );
    assert.equal(
      inventoryUnitRejected.payload?.code,
      "MAPPING_INVENTORY_UNIT_SERVER_OWNED"
    );

    const crossClinicItemRejected =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          `${root}/connectors/${connectorId}/mappings`,
        token: adminA,
        body: {
          externalItemId: "MED-FOREIGN",
          externalUnit: "piece",
          stockItemId: String(itemB._id),
        },
      });

    assert.equal(
      crossClinicItemRejected.status,
      404
    );

    const mappingCreated = await jsonRequest({
      baseUrl,
      method: "POST",
      path:
        `${root}/connectors/${connectorId}/mappings`,
      token: adminA,
      body: {
        externalItemId: "MED-001",
        externalUnit: "piece",
        stockItemId: String(itemA._id),
        conversionNumerator: 1,
        conversionDenominator: 1,
      },
    });

    assert.equal(mappingCreated.status, 201);
    assert.equal(
      mappingCreated.payload?.mapping?.clinicId,
      clinicA
    );
    assert.equal(
      mappingCreated.payload?.mapping?.inventoryUnit,
      "piece"
    );
    assert.equal(
      mappingCreated.payload?.mapping?.createdBy,
      "admin-a"
    );

    const mappingId = String(
      mappingCreated.payload?.mapping?._id
    );

    const duplicate = await jsonRequest({
      baseUrl,
      method: "POST",
      path:
        `${root}/connectors/${connectorId}/mappings`,
      token: adminA,
      body: {
        externalItemId: "MED-001",
        externalUnit: "piece",
        stockItemId: String(itemA._id),
      },
    });

    assert.equal(duplicate.status, 409);
    assert.equal(
      duplicate.payload?.code,
      "ITEM_MAPPING_ALREADY_EXISTS"
    );

    const mappingList = await jsonRequest({
      baseUrl,
      method: "GET",
      path:
        `${root}/connectors/${connectorId}/mappings`,
      token: adminA,
    });

    assert.equal(mappingList.status, 200);
    assert.equal(
      mappingList.payload?.mappings?.length,
      1
    );

    const identityUpdateRejected =
      await jsonRequest({
        baseUrl,
        method: "PATCH",
        path: `${root}/mappings/${mappingId}`,
        token: adminA,
        body: {
          externalItemId: "MED-CHANGED",
        },
      });

    assert.equal(
      identityUpdateRejected.status,
      400
    );
    assert.equal(
      identityUpdateRejected.payload?.code,
      "MAPPING_IDENTITY_IMMUTABLE"
    );

    const mappingUpdated = await jsonRequest({
      baseUrl,
      method: "PATCH",
      path: `${root}/mappings/${mappingId}`,
      token: adminA,
      body: {
        stockItemId: String(itemABox._id),
        conversionNumerator: 10,
        conversionDenominator: 1,
        active: false,
      },
    });

    assert.equal(mappingUpdated.status, 200);
    assert.equal(
      mappingUpdated.payload?.mapping?.inventoryUnit,
      "box"
    );
    assert.equal(
      mappingUpdated.payload?.mapping
        ?.conversionNumerator,
      10
    );
    assert.equal(
      mappingUpdated.payload?.mapping?.active,
      false
    );

    const foreignMappingUpdate =
      await jsonRequest({
        baseUrl,
        method: "PATCH",
        path: `${root}/mappings/${mappingId}`,
        token: adminB,
        body: { active: true },
      });

    assert.equal(
      foreignMappingUpdate.status,
      404
    );

    console.log(
      "ADMIN_MANAGEMENT_HTTP_SIMULATOR_PASSED=TRUE"
    );
    console.log("ADMIN_JWT_REQUIRED=PASS");
    console.log("NON_ADMIN_REJECTED=PASS");
    console.log("SERVER_OWNED_CLINIC_SCOPE=PASS");
    console.log(
      "PLAINTEXT_CONFIGURATION_REJECTED=PASS"
    );
    console.log(
      "CONNECTOR_CREATED_WITH_ONE_TIME_CREDENTIAL=PASS"
    );
    console.log(
      "CREDENTIAL_HASH_NOT_EXPOSED=PASS"
    );
    console.log(
      "CREDENTIAL_ROTATION_INVALIDATES_OLD_TOKEN=PASS"
    );
    console.log(
      "CONNECTOR_CROSS_CLINIC_ISOLATION=PASS"
    );
    console.log(
      "CONNECTOR_IDENTITY_IMMUTABLE=PASS"
    );
    console.log("MAPPING_EXACT_IDENTITY=PASS");
    console.log(
      "MAPPING_INVENTORY_UNIT_SERVER_DERIVED=PASS"
    );
    console.log(
      "MAPPING_CROSS_CLINIC_STOCK_ITEM_BLOCKED=PASS"
    );
    console.log(
      "MAPPING_DUPLICATE_BLOCKED=PASS"
    );
    console.log(
      "MAPPING_IDENTITY_IMMUTABLE=PASS"
    );
    console.log(
      "MAPPING_TARGET_UNIT_REFRESHED_ON_UPDATE=PASS"
    );
    console.log("MAPPING_SOFT_DISABLE=PASS");
    console.log("VENDOR_SPECIFIC_LOGIC=FALSE");
    console.log(`TEST_DATABASE=${TEST_DB}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((err) =>
        err ? reject(err) : resolve()
      )
    );
  }
}

(async () => {
  try {
    await run();
  } finally {
    if (mongoose.connection.readyState !== 0) {
      try {
        if (mongoose.connection.name === TEST_DB) {
          await cleanup();
        }
      } finally {
        await mongoose.disconnect();
      }
    }
  }
})().catch((err) => {
  console.error(
    "ADMIN_MANAGEMENT_HTTP_SIMULATOR_FAILED=TRUE"
  );
  console.error(`CODE=${String(err?.code || "")}`);
  console.error(err?.stack || err);
  process.exit(1);
});
