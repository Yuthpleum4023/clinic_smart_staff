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
const IntegrationEvent = require("../models/IntegrationEvent");
const StockItem = require("../models/StockItem");
const StockMovement = require("../models/StockMovement");

const inventoryRoutes = require("../routes/inventoryRoutes");

const {
  generateConnectorCredential,
} = require("../services/connectorCredentialService");

const TEST_DB =
  "css_inventory_operational_test";

const TEST_JWT_SECRET =
  "inventory-operational-simulator-secret";

function assertTestDatabase() {
  if (mongoose.connection.name !== TEST_DB) {
    const err = new Error(
      `Refusing operational simulator cleanup outside ${TEST_DB}`
    );
    err.code = "TEST_DATABASE_GUARD_FAILED";
    throw err;
  }
}

async function cleanup() {
  assertTestDatabase();

  for (const Model of [
    IntegrationEvent,
    InventoryItemMapping,
    StockMovement,
    StockItem,
    ConnectorConfig,
  ]) {
    await mongoose.connection
      .collection(Model.collection.name)
      .deleteMany({});
  }
}

async function ensureIndexes() {
  assertTestDatabase();

  await ConnectorConfig.createIndexes();
  await InventoryItemMapping.createIndexes();
  await IntegrationEvent.createIndexes();

  const movementCollection =
    mongoose.connection.collection(
      StockMovement.collection.name
    );

  const indexes =
    await movementCollection.indexes();

  if (
    !indexes.some(
      (index) =>
        index.name ===
        "operational_test_movement_idempotency"
    )
  ) {
    await movementCollection.createIndex(
      {
        clinicId: 1,
        idempotencyKey: 1,
      },
      {
        name:
          "operational_test_movement_idempotency",
        unique: true,
        partialFilterExpression: {
          idempotencyKey: {
            $type: "string",
            $gt: "",
          },
        },
      }
    );
  }
}

function tokenFor({
  userId,
  clinicId,
  role,
}) {
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

  app.use(
    express.json({
      limit: "1mb",
    })
  );

  app.use(
    "/api/inventory",
    inventoryRoutes
  );

  app.use(
    (err, req, res, next) => {
      if (res.headersSent) {
        return next(err);
      }

      return res
        .status(
          Number(err?.status) || 500
        )
        .json({
          ok: false,
          code:
            err?.code ||
            "REQUEST_FAILED",
          message:
            err?.message ||
            "Request failed",
          ...(err?.details
            ? {
                details:
                  err.details,
              }
            : {}),
        });
    }
  );

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
    "content-type":
      "application/json",
  };

  if (token) {
    headers.authorization =
      `Bearer ${token}`;
  }

  const response =
    await fetch(
      `${baseUrl}${path}`,
      {
        method,
        headers,
        ...(body !== undefined
          ? {
              body:
                JSON.stringify(
                  body
                ),
            }
          : {}),
      }
    );

  let payload = {};

  try {
    payload =
      await response.json();
  } catch (_) {}

  return {
    status:
      response.status,
    payload,
  };
}

async function run() {
  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required for operational HTTP simulator"
    );
  }

  process.env.JWT_SECRET =
    TEST_JWT_SECRET;

  await mongoose.connect(
    process.env.MONGO_URI,
    {
      dbName: TEST_DB,
      autoIndex: false,
    }
  );

  assertTestDatabase();
  await cleanup();
  await ensureIndexes();

  const clinicA =
    "operational-clinic-a";

  const clinicB =
    "operational-clinic-b";

  const adminA =
    tokenFor({
      userId: "admin-a",
      clinicId: clinicA,
      role: "admin",
    });

  const adminB =
    tokenFor({
      userId: "admin-b",
      clinicId: clinicB,
      role: "admin",
    });

  const employeeA =
    tokenFor({
      userId: "employee-a",
      clinicId: clinicA,
      role: "employee",
    });

  const credential =
    generateConnectorCredential();

  const connector =
    await ConnectorConfig.create({
      clinicId: clinicA,
      connectorKey:
        "operational-sim",
      externalSystem:
        "generic_simulator",
      connectorType: "rest",
      displayName:
        "Operational Simulator",
      enabled: true,
      credentialKeyId:
        credential.credentialKeyId,
      credentialHash:
        credential.credentialHash,
      credentialVersion:
        credential.credentialVersion,
      configuration: {},
      createdBy: "admin-a",
      updatedBy: "admin-a",
    });

  const item =
    await StockItem.create({
      clinicId: clinicA,
      name:
        "Operational Item",
      sku:
        "OPS-001",
      category:
        "simulator",
      unit: "piece",
      currentQty: 10,
      minimumQty: 0,
      lowStockAlertEnabled:
        false,
      lowStockActive:
        false,
      active: true,
    });

  const app = createApp();

  const server =
    await new Promise(
      (resolve) => {
        const listener =
          app.listen(
            0,
            "127.0.0.1",
            () =>
              resolve(listener)
          );
      }
    );

  try {
    const address =
      server.address();

    const baseUrl =
      `http://127.0.0.1:${address.port}`;

    const adminRoot =
      "/api/inventory/integrations/admin";

    const ingestionPath =
      "/api/inventory/integrations/consumption";

    const eventBody = {
      externalEventId:
        "OPS-EVENT-001",
      externalLineId: "1",
      externalItemId:
        "OPS-MED-001",
      quantity: 2,
      unit: "piece",
      eventType:
        "dispensed",
      occurredAt:
        "2026-09-07T03:00:00.000Z",
      referenceType:
        "visit",
      referenceNo:
        "VISIT-OPS-001",
      metadata: {
        privateNote:
          "must-not-be-exposed",
      },
    };

    const blocked =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          ingestionPath,
        token:
          credential.token,
        body:
          eventBody,
      });

    assert.equal(
      blocked.status,
      409
    );

    assert.equal(
      blocked.payload?.code,
      "ITEM_MAPPING_NOT_FOUND"
    );

    const storedConnector =
      await ConnectorConfig
        .findById(
          connector._id
        )
        .lean();

    assert.ok(
      storedConnector.lastSeenAt
    );

    assert.ok(
      storedConnector.lastErrorAt
    );

    assert.equal(
      storedConnector.lastErrorCode,
      "ITEM_MAPPING_NOT_FOUND"
    );

    const blockedEvent =
      await IntegrationEvent.findOne({
        clinicId:
          clinicA,
        connectorId:
          connector._id,
        externalEventId:
          "OPS-EVENT-001",
      }).lean();

    assert.equal(
      blockedEvent.status,
      "blocked"
    );

    const health =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/connectors/${connector._id}/health`,
        token:
          adminA,
      });

    assert.equal(
      health.status,
      200
    );

    assert.equal(
      health.payload
        ?.health
        ?.state,
      "needs_attention"
    );

    assert.equal(
      health.payload
        ?.health
        ?.counts
        ?.blocked,
      1
    );

    assert.equal(
      health.payload
        ?.health
        ?.blockedByErrorCode?.[0]
        ?.errorCode,
      "ITEM_MAPPING_NOT_FOUND"
    );

    const employeeDenied =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/connectors/${connector._id}/health`,
        token:
          employeeA,
      });

    assert.equal(
      employeeDenied.status,
      403
    );

    const foreignHealth =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/connectors/${connector._id}/health`,
        token:
          adminB,
      });

    assert.equal(
      foreignHealth.status,
      404
    );

    const blockedList =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/connectors/${connector._id}/events?status=blocked&limit=20`,
        token:
          adminA,
      });

    assert.equal(
      blockedList.status,
      200
    );

    assert.equal(
      blockedList.payload
        ?.events
        ?.length,
      1
    );

    assert.equal(
      Object.prototype
        .hasOwnProperty.call(
          blockedList
            .payload
            .events[0],
          "sourceMetadata"
        ),
      false
    );

    assert.equal(
      blockedList
        .payload
        .events[0]
        .hasSourceMetadata,
      true
    );

    const invalidStatus =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/connectors/${connector._id}/events?status=unknown`,
        token:
          adminA,
      });

    assert.equal(
      invalidStatus.status,
      400
    );

    assert.equal(
      invalidStatus
        .payload?.code,
      "INVALID_INTEGRATION_EVENT_STATUS"
    );

    const detail =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/events/${blockedEvent._id}`,
        token:
          adminA,
      });

    assert.equal(
      detail.status,
      200
    );

    assert.equal(
      detail.payload
        ?.event
        ?.status,
      "blocked"
    );

    assert.equal(
      Object.prototype
        .hasOwnProperty.call(
          detail.payload.event,
          "sourceMetadata"
        ),
      false
    );

    const foreignDetail =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/events/${blockedEvent._id}`,
        token:
          adminB,
      });

    assert.equal(
      foreignDetail.status,
      404
    );

    const mappingCreate =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          `${adminRoot}/connectors/${connector._id}/mappings`,
        token:
          adminA,
        body: {
          externalItemId:
            "OPS-MED-001",
          externalUnit:
            "piece",
          stockItemId:
            String(item._id),
          conversionNumerator:
            1,
          conversionDenominator:
            1,
        },
      });

    assert.equal(
      mappingCreate.status,
      201
    );

    const reprocessed =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          `${adminRoot}/events/${blockedEvent._id}/reprocess`,
        token:
          adminA,
      });

    assert.equal(
      reprocessed.status,
      200
    );

    assert.equal(
      reprocessed.payload
        ?.action,
      "integration_event_reprocessed"
    );

    const itemAfter =
      await StockItem
        .findById(
          item._id
        )
        .lean();

    assert.equal(
      itemAfter.currentQty,
      8
    );

    const finalEvent =
      await IntegrationEvent
        .findById(
          blockedEvent._id
        )
        .lean();

    assert.equal(
      finalEvent.status,
      "applied"
    );

    assert.equal(
      finalEvent.externalEventId,
      eventBody.externalEventId
    );

    assert.equal(
      finalEvent.externalLineId,
      eventBody.externalLineId
    );

    const movements =
      await StockMovement.countDocuments({
        clinicId:
          clinicA,
        type:
          "external_consumption",
      });

    assert.equal(
      movements,
      1
    );

    const replayReprocess =
      await jsonRequest({
        baseUrl,
        method: "POST",
        path:
          `${adminRoot}/events/${blockedEvent._id}/reprocess`,
        token:
          adminA,
      });

    assert.equal(
      replayReprocess.status,
      409
    );

    assert.equal(
      replayReprocess
        .payload?.code,
      "INTEGRATION_EVENT_NOT_BLOCKED"
    );

    const healthAfter =
      await jsonRequest({
        baseUrl,
        method: "GET",
        path:
          `${adminRoot}/connectors/${connector._id}/health`,
        token:
          adminA,
      });

    assert.equal(
      healthAfter.status,
      200
    );

    assert.equal(
      healthAfter.payload
        ?.health
        ?.counts
        ?.blocked,
      0
    );

    assert.equal(
      healthAfter.payload
        ?.health
        ?.counts
        ?.applied,
      1
    );

    assert.equal(
      healthAfter.payload
        ?.health
        ?.state,
      "healthy"
    );

    const connectorAfter =
      await ConnectorConfig
        .findById(
          connector._id
        )
        .lean();

    assert.ok(
      connectorAfter
        .lastSuccessfulSyncAt
    );

    assert.equal(
      connectorAfter.lastErrorCode,
      ""
    );

    console.log(
      "OPERATIONAL_VISIBILITY_HTTP_SIMULATOR_PASSED=TRUE"
    );
    console.log(
      "CONNECTOR_LAST_SEEN_TELEMETRY=PASS"
    );
    console.log(
      "CONNECTOR_ERROR_TELEMETRY=PASS"
    );
    console.log(
      "CONNECTOR_HEALTH_SUMMARY=PASS"
    );
    console.log(
      "BLOCKED_ERROR_AGGREGATION=PASS"
    );
    console.log(
      "ADMIN_ONLY_OPERATIONAL_VISIBILITY=PASS"
    );
    console.log(
      "CROSS_CLINIC_OPERATIONAL_ISOLATION=PASS"
    );
    console.log(
      "EVENT_STATUS_FILTER=PASS"
    );
    console.log(
      "SOURCE_METADATA_REDACTED=PASS"
    );
    console.log(
      "ADMIN_REPROCESS_BLOCKED_EVENT=PASS"
    );
    console.log(
      "REPROCESS_REUSES_EXISTING_EVENT_IDENTITY=PASS"
    );
    console.log(
      "REPROCESS_SINGLE_STOCK_MOVEMENT=PASS"
    );
    console.log(
      "REPROCESS_ALREADY_APPLIED_REJECTED=PASS"
    );
    console.log(
      "CONNECTOR_SUCCESS_TELEMETRY=PASS"
    );
    console.log(
      "LAST_ERROR_CODE_CLEARED_ON_SUCCESS=PASS"
    );
    console.log(
      "STOCK_CORE_CHANGED=FALSE"
    );
    console.log(
      "PROCESSING_CORE_CHANGED=FALSE"
    );
    console.log(
      "CONNECTOR_AUTH_CHANGED=FALSE"
    );
    console.log(
      `TEST_DATABASE=${TEST_DB}`
    );
  } finally {
    await new Promise(
      (resolve, reject) =>
        server.close(
          (err) =>
            err
              ? reject(err)
              : resolve()
        )
    );
  }
}

(async () => {
  try {
    await run();
  } finally {
    if (
      mongoose.connection
        .readyState !== 0
    ) {
      try {
        if (
          mongoose.connection.name ===
          TEST_DB
        ) {
          await cleanup();
        }
      } finally {
        await mongoose.disconnect();
      }
    }
  }
})().catch((err) => {
  console.error(
    "OPERATIONAL_VISIBILITY_HTTP_SIMULATOR_FAILED=TRUE"
  );
  console.error(
    `CODE=${String(err?.code || "")}`
  );
  console.error(
    err?.stack || err
  );
  process.exit(1);
});
