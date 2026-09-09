const assert = require(
  "node:assert/strict"
);
const path = require(
  "node:path"
);

require("dotenv").config({
  path: path.join(
    __dirname,
    "..",
    ".env"
  ),
});

const express = require(
  "express"
);
const mongoose = require(
  "mongoose"
);

const ConnectorConfig = require(
  "../models/ConnectorConfig"
);
const IntegrationEvent = require(
  "../models/IntegrationEvent"
);
const InventoryItemMapping = require(
  "../models/InventoryItemMapping"
);
const StockItem = require(
  "../models/StockItem"
);
const StockMovement = require(
  "../models/StockMovement"
);

const inventoryRoutes = require(
  "../routes/inventoryRoutes"
);

const {
  generateConnectorCredential,
} = require(
  "../services/connectorCredentialService"
);

const TEST_DB =
  "css_inventory_ingress_test";

function assertTestDatabase() {
  if (
    mongoose.connection.name !==
    TEST_DB
  ) {
    const err = new Error(
      `Refusing ingress simulator cleanup outside ${TEST_DB}`
    );
    err.code =
      "TEST_DATABASE_GUARD_FAILED";
    throw err;
  }
}

async function cleanup() {
  assertTestDatabase();

  const models = [
    IntegrationEvent,
    InventoryItemMapping,
    StockMovement,
    StockItem,
    ConnectorConfig,
  ];

  await Promise.all(
    models.map((Model) =>
      mongoose.connection
        .collection(
          Model.collection.name
        )
        .deleteMany({})
    )
  );
}

async function ensureIndexes() {
  assertTestDatabase();

  await Promise.all([
    ConnectorConfig.createIndexes(),
    IntegrationEvent.createIndexes(),
    InventoryItemMapping.createIndexes(),
  ]);

  await mongoose.connection
    .collection(
      StockMovement.collection.name
    )
    .createIndex(
      {
        clinicId: 1,
        idempotencyKey: 1,
      },
      {
        unique: true,
        name:
          "sim_ingress_clinic_idempotency",
        partialFilterExpression: {
          idempotencyKey: {
            $type: "string",
            $gt: "",
          },
        },
      }
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

      const status =
        Number(err?.status) ||
        500;

      return res
        .status(status)
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

async function postJson({
  baseUrl,
  token = "",
  body,
  path = "/consumption",
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
      `${baseUrl}/api/inventory/integrations${path}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify(
          body
        ),
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

async function qtyOf(id) {
  const item =
    await StockItem.findById(
      id
    ).lean();

  return Number(
    item?.currentQty
  );
}

async function run() {
  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required for ingestion HTTP simulator"
    );
  }

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

  const credentialA =
    generateConnectorCredential();

  const connectorA =
    await ConnectorConfig.create({
      clinicId:
        "ingress-clinic-a",
      connectorKey:
        "ingress-a",
      externalSystem:
        "generic_simulator",
      connectorType:
        "simulator",
      displayName:
        "Ingress Simulator A",
      enabled: true,
      credentialKeyId:
        credentialA.credentialKeyId,
      credentialHash:
        credentialA.credentialHash,
      credentialVersion:
        credentialA.credentialVersion,
    });

  const credentialB =
    generateConnectorCredential();

  const connectorB =
    await ConnectorConfig.create({
      clinicId:
        "ingress-clinic-b",
      connectorKey:
        "ingress-b",
      externalSystem:
        "generic_simulator",
      connectorType:
        "simulator",
      displayName:
        "Ingress Simulator B",
      enabled: true,
      credentialKeyId:
        credentialB.credentialKeyId,
      credentialHash:
        credentialB.credentialHash,
      credentialVersion:
        credentialB.credentialVersion,
    });

  const itemA =
    await StockItem.create({
      clinicId:
        "ingress-clinic-a",
      name:
        "HTTP Simulator Medicine",
      sku:
        "HTTP-SIM-INV-000001",
      category:
        "simulator",
      unit:
        "piece",
      currentQty: 10,
      minimumQty: 0,
      lowStockAlertEnabled:
        false,
      lowStockActive:
        false,
      active: true,
    });

  const recoveryItem =
    await StockItem.create({
      clinicId:
        "ingress-clinic-a",
      name:
        "HTTP Recovery Item",
      sku:
        "HTTP-SIM-INV-000002",
      category:
        "simulator",
      unit:
        "piece",
      currentQty: 10,
      minimumQty: 0,
      lowStockAlertEnabled:
        false,
      lowStockActive:
        false,
      active: true,
    });

  await InventoryItemMapping.create({
    clinicId:
      "ingress-clinic-a",
    connectorId:
      connectorA._id,
    externalItemId:
      "MED001",
    externalUnit:
      "piece",
    stockItemId:
      itemA._id,
    inventoryUnit:
      "piece",
    conversionNumerator: 1,
    conversionDenominator: 1,
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
              resolve(
                listener
              )
          );
      }
    );

  try {
    const address =
      server.address();

    const baseUrl =
      `http://127.0.0.1:${address.port}`;

    const baseEvent = {
      externalEventId:
        "HTTP-EVENT-001",
      externalLineId:
        "1",
      externalItemId:
        "MED001",
      quantity: 2,
      unit:
        "piece",
      eventType:
        "dispensed",
      occurredAt:
        "2026-09-07T01:00:00.000Z",

      clinicId:
        "attacker-clinic",
      connectorId:
        String(
          connectorB._id
        ),
      externalSystem:
        "attacker-system",
      reprocessBlocked: true,
    };

    const first =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        body:
          baseEvent,
      });

    assert.equal(
      first.status,
      201
    );

    assert.equal(
      first.payload?.ok,
      true
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    const event =
      await IntegrationEvent.findOne({
        externalEventId:
          "HTTP-EVENT-001",
      }).lean();

    assert.ok(event);

    assert.equal(
      event.clinicId,
      "ingress-clinic-a"
    );

    assert.equal(
      String(event.connectorId),
      String(connectorA._id)
    );

    assert.equal(
      event.externalSystem,
      "generic_simulator"
    );

    const movement =
      await StockMovement.findOne({
        clinicId:
          "ingress-clinic-a",
        type:
          "external_consumption",
      }).lean();

    assert.ok(movement);

    assert.equal(
      movement.balanceBefore,
      10
    );

    assert.equal(
      movement.balanceAfter,
      8
    );

    const replay =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        body:
          baseEvent,
      });

    assert.equal(
      replay.status,
      200
    );

    assert.equal(
      replay.payload?.ok,
      true
    );

    assert.equal(
      replay.payload?.data
        ?.idempotentReplay,
      true
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    const movementCount =
      await StockMovement.countDocuments({
        clinicId:
          "ingress-clinic-a",
        type:
          "external_consumption",
      });

    assert.equal(
      movementCount,
      1
    );

    const eventCountBeforeLegacyMovement =
      await IntegrationEvent
        .countDocuments();

    const legacyMovementAttempt =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        path:
          "/consumption",
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-LEGACY-MOVE-IN",
          externalLineId:
            "1",
          quantity: 3,
          eventType:
            "inventory_in",
        },
      });

    assert.equal(
      legacyMovementAttempt.status,
      400
    );

    assert.equal(
      legacyMovementAttempt
        .payload?.code,
      "UNSUPPORTED_CONSUMPTION_EVENT_TYPE"
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    assert.equal(
      await IntegrationEvent
        .countDocuments(),
      eventCountBeforeLegacyMovement
    );

    const movementIn =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        path:
          "/movements",
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-MOVE-IN",
          externalLineId:
            "1",
          quantity: 3,
          eventType:
            "inventory_in",
        },
      });

    assert.equal(
      movementIn.status,
      201
    );

    assert.equal(
      movementIn.payload?.ok,
      true
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      11
    );

    const movementOut =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        path:
          "/movements",
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-MOVE-OUT",
          externalLineId:
            "1",
          quantity: 3,
          eventType:
            "inventory_out",
        },
      });

    assert.equal(
      movementOut.status,
      201
    );

    assert.equal(
      movementOut.payload?.ok,
      true
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    const inboundMovement =
      await StockMovement.findOne({
        clinicId:
          "ingress-clinic-a",
        type:
          "external_stock_in",
      }).lean();

    assert.ok(
      inboundMovement
    );

    assert.equal(
      inboundMovement
        .quantityDelta,
      3
    );

    const movementInReplay =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        path:
          "/movements",
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-MOVE-IN",
          externalLineId:
            "1",
          quantity: 3,
          eventType:
            "inventory_in",
        },
      });

    assert.equal(
      movementInReplay.status,
      200
    );

    assert.equal(
      movementInReplay.payload
        ?.data
        ?.idempotentReplay,
      true
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    const inboundMovementCount =
      await StockMovement
        .countDocuments({
          clinicId:
            "ingress-clinic-a",
          type:
            "external_stock_in",
        });

    assert.equal(
      inboundMovementCount,
      1
    );

    const missingToken =
      await postJson({
        baseUrl,
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-002",
        },
      });

    assert.equal(
      missingToken.status,
      401
    );

    assert.equal(
      missingToken.payload?.code,
      "MISSING_CONNECTOR_TOKEN"
    );

    const wrongSecret =
      [
        "cssinv1",
        credentialA
          .credentialKeyId,
        "wrong-secret",
      ].join(".");

    const invalidToken =
      await postJson({
        baseUrl,
        token:
          wrongSecret,
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-003",
        },
      });

    assert.equal(
      invalidToken.status,
      401
    );

    assert.equal(
      invalidToken.payload?.code,
      "INVALID_CONNECTOR_TOKEN"
    );

    const malformed =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        body: {
          externalEventId:
            "HTTP-EVENT-004",
          externalItemId:
            "MED001",
          quantity: 0,
          unit:
            "piece",
          eventType:
            "dispensed",
          occurredAt:
            "2026-09-07T01:00:00.000Z",
        },
      });

    assert.equal(
      malformed.status,
      400
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    const blockedBody = {
      externalEventId:
        "HTTP-EVENT-005",
      externalLineId:
        "1",
      externalItemId:
        "RECOVERY",
      quantity: 1,
      unit:
        "piece",
      eventType:
        "dispensed",
      occurredAt:
        "2026-09-07T01:10:00.000Z",
    };

    const blocked =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        body:
          blockedBody,
      });

    assert.equal(
      blocked.status,
      409
    );

    assert.equal(
      blocked.payload?.code,
      "ITEM_MAPPING_NOT_FOUND"
    );

    assert.equal(
      await qtyOf(
        recoveryItem._id
      ),
      10
    );

    await InventoryItemMapping.create({
      clinicId:
        "ingress-clinic-a",
      connectorId:
        connectorA._id,
      externalItemId:
        "RECOVERY",
      externalUnit:
        "piece",
      stockItemId:
        recoveryItem._id,
      inventoryUnit:
        "piece",
      conversionNumerator: 1,
      conversionDenominator: 1,
      active: true,
    });

    const externalReprocessAttempt =
      await postJson({
        baseUrl,
        token:
          credentialA.token,
        body: {
          ...blockedBody,
          reprocessBlocked:
            true,
        },
      });

    assert.equal(
      externalReprocessAttempt.status,
      409
    );

    assert.equal(
      externalReprocessAttempt
        .payload?.code,
      "ITEM_MAPPING_NOT_FOUND"
    );

    assert.equal(
      await qtyOf(
        recoveryItem._id
      ),
      10
    );

    const blockedEvent =
      await IntegrationEvent.findOne({
        externalEventId:
          "HTTP-EVENT-005",
      }).lean();

    assert.equal(
      blockedEvent.status,
      "blocked"
    );

    const eventCountBeforeCross =
      await IntegrationEvent.countDocuments();

    const crossClinicAttempt =
      await postJson({
        baseUrl,
        token:
          credentialB.token,
        body: {
          ...baseEvent,
          externalEventId:
            "HTTP-EVENT-006",
          clinicId:
            "ingress-clinic-a",
          connectorId:
            String(
              connectorA._id
            ),
        },
      });

    assert.equal(
      crossClinicAttempt.status,
      409
    );

    assert.equal(
      crossClinicAttempt
        .payload?.code,
      "ITEM_MAPPING_NOT_FOUND"
    );

    assert.equal(
      await qtyOf(
        itemA._id
      ),
      8
    );

    const crossEvent =
      await IntegrationEvent.findOne({
        externalEventId:
          "HTTP-EVENT-006",
      }).lean();

    assert.ok(crossEvent);

    assert.equal(
      crossEvent.clinicId,
      "ingress-clinic-b"
    );

    assert.equal(
      String(
        crossEvent.connectorId
      ),
      String(connectorB._id)
    );

    assert.equal(
      await IntegrationEvent.countDocuments(),
      eventCountBeforeCross + 1
    );

    console.log(
      "GENERIC_INGESTION_HTTP_SIMULATOR_PASSED=TRUE"
    );
    console.log(
      "AUTHENTICATED_EVENT_10_TO_8=PASS"
    );
    console.log(
      "HTTP_DUPLICATE_IDEMPOTENT=PASS"
    );
    console.log(
      "HTTP_SINGLE_STOCK_MOVEMENT=PASS"
    );
    console.log(
      "LEGACY_CONSUMPTION_ENDPOINT_MOVEMENT_REJECTED=PASS"
    );
    console.log(
      "GENERIC_MOVEMENT_INBOUND_8_TO_11=PASS"
    );
    console.log(
      "GENERIC_MOVEMENT_OUTBOUND_11_TO_8=PASS"
    );
    console.log(
      "GENERIC_MOVEMENT_REPLAY_IDEMPOTENT=PASS"
    );
    console.log(
      "SERVER_SCOPE_OVERRIDES_BODY_SCOPE=PASS"
    );
    console.log(
      "MISSING_CONNECTOR_TOKEN_401=PASS"
    );
    console.log(
      "INVALID_CONNECTOR_TOKEN_401=PASS"
    );
    console.log(
      "MALFORMED_EVENT_REJECTED=PASS"
    );
    console.log(
      "UNMAPPED_EVENT_BLOCKED=PASS"
    );
    console.log(
      "EXTERNAL_REPROCESS_BLOCKED=PASS"
    );
    console.log(
      "CROSS_CLINIC_SCOPE_ISOLATED=PASS"
    );
    console.log(
      "USER_JWT_REQUIRED=FALSE"
    );
    console.log(
      "INTERNAL_SERVICE_KEY_REQUIRED=FALSE"
    );
    console.log(
      "VENDOR_SPECIFIC_LOGIC=FALSE"
    );
    console.log(
      "TEST_DATABASE=" +
        TEST_DB
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
    "GENERIC_INGESTION_HTTP_SIMULATOR_FAILED=TRUE"
  );
  console.error(
    "CODE=" +
      String(err?.code || "")
  );
  console.error(
    err?.stack || err
  );
  process.exit(1);
});
