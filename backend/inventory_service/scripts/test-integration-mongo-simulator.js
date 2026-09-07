const assert = require("node:assert/strict");
const path = require("node:path");

require("dotenv").config({
  path: path.join(
    __dirname,
    "..",
    ".env"
  ),
});

const mongoose = require("mongoose");

const ConnectorConfig = require("../models/ConnectorConfig");
const IntegrationEvent = require("../models/IntegrationEvent");
const InventoryItemMapping = require("../models/InventoryItemMapping");
const StockItem = require("../models/StockItem");
const StockMovement = require("../models/StockMovement");

const {
  processConsumptionEvent,
} = require("../services/integrationProcessingService");

const TEST_DB =
  "css_inventory_int_test";

function expectCode(
  promiseFactory,
  expectedCode
) {
  return (async () => {
    let thrown = null;

    try {
      await promiseFactory();
    } catch (err) {
      thrown = err;
    }

    assert.ok(
      thrown,
      `Expected error code ${expectedCode}`
    );

    assert.equal(
      thrown.code,
      expectedCode
    );

    return thrown;
  })();
}

async function qtyOf(itemId) {
  const item =
    await StockItem.findById(
      itemId
    ).lean();

  return item?.currentQty;
}

async function countMovements(
  clinicId
) {
  return StockMovement.countDocuments({
    clinicId,
    type: "external_consumption",
  });
}

function assertTestDatabase() {
  if (
    mongoose.connection.name !==
    TEST_DB
  ) {
    const err = new Error(
      `Refusing simulator cleanup outside ${TEST_DB}`
    );
    err.code =
      "TEST_DATABASE_GUARD_FAILED";
    throw err;
  }
}

async function ensureSimulatorIndexes() {
  assertTestDatabase();

  // Build only indexes owned by the Phase 2 integration layer.
  // Legacy StockItem indexes are deliberately not rebuilt here.
  await Promise.all([
    ConnectorConfig.createIndexes(),
    IntegrationEvent.createIndexes(),
    InventoryItemMapping.createIndexes(),
  ]);

  // Defensive materialization idempotency for this isolated
  // simulator DB. This mirrors the production semantic key
  // without modifying the legacy StockMovement schema.
  await mongoose.connection
    .collection(StockMovement.collection.name)
    .createIndex(
      {
        clinicId: 1,
        idempotencyKey: 1,
      },
      {
        unique: true,
        name:
          "sim_clinicId_1_idempotencyKey_1",
        partialFilterExpression: {
          idempotencyKey: {
            $type: "string",
            $gt: "",
          },
        },
      }
    );
}

async function cleanupSimulatorData() {
  assertTestDatabase();

  // Dedicated simulator DB only.
  //
  // Cleanup intentionally bypasses Mongoose model middleware
  // by using the underlying Mongo collections. This is test
  // infrastructure, not a production stock mutation path.
  //
  // StockMovement itself remains immutable through the normal
  // application Model API.
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
        .collection(Model.collection.name)
        .deleteMany({})
    )
  );
}

async function run() {
  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required for the Mongo simulator"
    );
  }

  await mongoose.connect(
    process.env.MONGO_URI,
    {
      dbName: TEST_DB,

      // The production StockItem / StockMovement models contain
      // legacy index definitions that are outside this Phase 2
      // simulator's ownership. Do not rebuild those indexes here.
      autoIndex: false,
    }
  );

  assert.equal(
    mongoose.connection.name,
    TEST_DB
  );

  await cleanupSimulatorData();
  await ensureSimulatorIndexes();

  const clinicA =
    "integration-sim-clinic-a";
  const clinicB =
    "integration-sim-clinic-b";

  const connectorA =
    await ConnectorConfig.create({
      clinicId: clinicA,
      connectorKey:
        "simulator-a",
      externalSystem:
        "simulator_vendor",
      connectorType:
        "simulator",
      displayName:
        "Simulator A",
      enabled: true,
    });

  const connectorB =
    await ConnectorConfig.create({
      clinicId: clinicB,
      connectorKey:
        "simulator-b",
      externalSystem:
        "simulator_vendor",
      connectorType:
        "simulator",
      displayName:
        "Simulator B",
      enabled: true,
    });

  const itemA =
    await StockItem.create({
      clinicId: clinicA,
      name:
        "Simulator Item A",
      sku:
        "SIM-A-INV-000001",
      category:
        "simulator",
      unit:
        "piece",
      currentQty: 10,
      minimumQty: 2,
      lowStockAlertEnabled:
        true,
      lowStockActive:
        false,
      active: true,
    });

  const inactiveItem =
    await StockItem.create({
      clinicId: clinicA,
      name:
        "Simulator Inactive Item",
      sku:
        "SIM-A-INV-000002",
      category:
        "simulator",
      unit:
        "piece",
      currentQty: 5,
      minimumQty: 0,
      lowStockAlertEnabled:
        false,
      lowStockActive:
        false,
      active: false,
    });

  const conversionItem =
    await StockItem.create({
      clinicId: clinicA,
      name:
        "Simulator Conversion Item",
      sku:
        "SIM-A-INV-000003",
      category:
        "simulator",
      unit:
        "piece",
      currentQty: 1000,
      minimumQty: 0,
      lowStockAlertEnabled:
        false,
      lowStockActive:
        false,
      active: true,
    });

  const recoveryItem =
    await StockItem.create({
      clinicId: clinicA,
      name:
        "Simulator Recovery Item",
      sku:
        "SIM-A-INV-000004",
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

  const clinicBItem =
    await StockItem.create({
      clinicId: clinicB,
      name:
        "Simulator Clinic B Item",
      sku:
        "SIM-B-INV-000001",
      category:
        "simulator",
      unit:
        "piece",
      currentQty: 30,
      minimumQty: 0,
      lowStockAlertEnabled:
        false,
      lowStockActive:
        false,
      active: true,
    });

  await InventoryItemMapping.create({
    clinicId: clinicA,
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

  await InventoryItemMapping.create({
    clinicId: clinicA,
    connectorId:
      connectorA._id,
    externalItemId:
      "MED-INACTIVE",
    externalUnit:
      "piece",
    stockItemId:
      inactiveItem._id,
    inventoryUnit:
      "piece",
    conversionNumerator: 1,
    conversionDenominator: 1,
    active: true,
  });

  await InventoryItemMapping.create({
    clinicId: clinicA,
    connectorId:
      connectorA._id,
    externalItemId:
      "MED-BOX",
    externalUnit:
      "box",
    stockItemId:
      conversionItem._id,
    inventoryUnit:
      "piece",
    conversionNumerator: 100,
    conversionDenominator: 1,
    active: true,
  });

  const baseEvent = {
    externalEventId:
      "EVENT-001",
    externalLineId: "1",
    externalItemId:
      "MED001",
    quantity: 2,
    unit: "piece",
    eventType:
      "dispensed",
    occurredAt:
      "2026-09-07T10:32:00+07:00",
    referenceType:
      "patient_dispense",
    referenceNo:
      "VISIT-1001",
  };

  const first =
    await processConsumptionEvent({
      connectorId:
        connectorA._id,
      input: baseEvent,
    });

  assert.equal(
    first.idempotentReplay,
    false
  );

  assert.equal(
    await qtyOf(itemA._id),
    8
  );

  assert.equal(
    await countMovements(clinicA),
    1
  );

  const replay =
    await processConsumptionEvent({
      connectorId:
        connectorA._id,
      input: {
        ...baseEvent,
        metadata: {
          retry: true,
          transportAttempt: 2,
        },
      },
    });

  assert.equal(
    replay.idempotentReplay,
    true
  );

  assert.equal(
    await qtyOf(itemA._id),
    8
  );

  assert.equal(
    await countMovements(clinicA),
    1
  );

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input: {
          ...baseEvent,
          quantity: 3,
        },
      }),
    "EXTERNAL_EVENT_CONFLICT"
  );

  assert.equal(
    await qtyOf(itemA._id),
    8
  );

  const concurrentEvent = {
    ...baseEvent,
    externalEventId:
      "EVENT-002",
    quantity: 1,
    referenceNo:
      "VISIT-1002",
  };

  const concurrent =
    await Promise.allSettled([
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input:
          concurrentEvent,
      }),
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input:
          concurrentEvent,
      }),
    ]);

  const rejectedConcurrent =
    concurrent.filter(
      (entry) =>
        entry.status ===
        "rejected"
    );

  if (
    rejectedConcurrent.length > 0
  ) {
    console.error(
      "CONCURRENT_RESULTS=",
      concurrent
    );
  }

  assert.equal(
    rejectedConcurrent.length,
    0
  );

  assert.equal(
    await qtyOf(itemA._id),
    7
  );

  assert.equal(
    await countMovements(clinicA),
    2
  );

  assert.equal(
    await IntegrationEvent.countDocuments({
      clinicId: clinicA,
      connectorId:
        connectorA._id,
      externalEventId:
        "EVENT-002",
      externalLineId:
        "1",
    }),
    1
  );

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input: {
          ...baseEvent,
          externalEventId:
            "EVENT-003",
          externalItemId:
            "UNMAPPED",
          quantity: 1,
        },
      }),
    "ITEM_MAPPING_NOT_FOUND"
  );

  assert.equal(
    await qtyOf(itemA._id),
    7
  );

  const blockedUnmapped =
    await IntegrationEvent.findOne({
      clinicId: clinicA,
      connectorId:
        connectorA._id,
      externalEventId:
        "EVENT-003",
    }).lean();

  assert.equal(
    blockedUnmapped.status,
    "blocked"
  );

  assert.equal(
    blockedUnmapped.errorCode,
    "ITEM_MAPPING_NOT_FOUND"
  );

  // Fix the missing mapping after the original event
  // has already been durably recorded as blocked.
  await InventoryItemMapping.create({
    clinicId: clinicA,
    connectorId:
      connectorA._id,
    externalItemId:
      "UNMAPPED",
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

  const recovered =
    await processConsumptionEvent({
      connectorId:
        connectorA._id,
      input: {
        ...baseEvent,
        externalEventId:
          "EVENT-003",
        externalItemId:
          "UNMAPPED",
        quantity: 1,
      },
      reprocessBlocked: true,
    });

  assert.equal(
    recovered.idempotentReplay,
    false
  );

  assert.equal(
    await qtyOf(
      recoveryItem._id
    ),
    9
  );

  const recoveredEvent =
    await IntegrationEvent.findOne({
      clinicId: clinicA,
      connectorId:
        connectorA._id,
      externalEventId:
        "EVENT-003",
      externalLineId:
        "1",
    }).lean();

  assert.equal(
    recoveredEvent.status,
    "applied"
  );

  assert.ok(
    recoveredEvent.stockMovementId
  );

  const recoveredReplay =
    await processConsumptionEvent({
      connectorId:
        connectorA._id,
      input: {
        ...baseEvent,
        externalEventId:
          "EVENT-003",
        externalItemId:
          "UNMAPPED",
        quantity: 1,
      },
    });

  assert.equal(
    recoveredReplay.idempotentReplay,
    true
  );

  assert.equal(
    await qtyOf(
      recoveryItem._id
    ),
    9
  );

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input: {
          ...baseEvent,
          externalEventId:
            "EVENT-004",
          externalItemId:
            "MED-INACTIVE",
          quantity: 1,
        },
      }),
    "STOCK_ITEM_INACTIVE"
  );

  assert.equal(
    await qtyOf(
      inactiveItem._id
    ),
    5
  );

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input: {
          ...baseEvent,
          externalEventId:
            "EVENT-005",
          quantity: 100,
        },
      }),
    "INSUFFICIENT_STOCK"
  );

  assert.equal(
    await qtyOf(itemA._id),
    7
  );

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorB._id,
        input: {
          ...baseEvent,
          externalEventId:
            "EVENT-B-001",
          quantity: 1,
        },
      }),
    "ITEM_MAPPING_NOT_FOUND"
  );

  assert.equal(
    await qtyOf(
      clinicBItem._id
    ),
    30
  );

  assert.equal(
    await qtyOf(itemA._id),
    7
  );

  const conversion =
    await processConsumptionEvent({
      connectorId:
        connectorA._id,
      input: {
        ...baseEvent,
        externalEventId:
          "EVENT-006",
        externalItemId:
          "MED-BOX",
        unit: "box",
        quantity: 2,
        referenceNo:
          "VISIT-1006",
      },
    });

  assert.equal(
    conversion.movement
      .quantityDelta,
    -200
  );

  assert.equal(
    await qtyOf(
      conversionItem._id
    ),
    800
  );

  const beforeInvalidCount =
    await IntegrationEvent.countDocuments();

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input: {
          ...baseEvent,
          externalEventId: "",
        },
      }),
    "EXTERNAL_EVENT_ID_REQUIRED"
  );

  await expectCode(
    () =>
      processConsumptionEvent({
        connectorId:
          connectorA._id,
        input: {
          ...baseEvent,
          externalEventId:
            "EVENT-BAD-QTY",
          quantity: 0,
        },
      }),
    "INVALID_QUANTITY"
  );

  assert.equal(
    await IntegrationEvent.countDocuments(),
    beforeInvalidCount
  );

  const externalMovements =
    await StockMovement.find({
      clinicId: clinicA,
      type:
        "external_consumption",
    }).lean();

  assert.equal(
    externalMovements.length,
    4
  );

  assert.ok(
    externalMovements.every(
      (movement) =>
        movement.sourceType ===
        "connector"
    )
  );

  assert.equal(
    await qtyOf(itemA._id),
    7
  );

  console.log(
    "MONGO_SIMULATOR_PASSED=TRUE"
  );
  console.log(
    "VALID_EVENT_10_TO_8=PASS"
  );
  console.log(
    "DUPLICATE_EVENT_8_TO_8=PASS"
  );
  console.log(
    "CONFLICT_EVENT_NO_STOCK_CHANGE=PASS"
  );
  console.log(
    "CONCURRENT_DUPLICATE_SINGLE_MOVEMENT=PASS"
  );
  console.log(
    "UNMAPPED_EVENT_BLOCKED=PASS"
  );
  console.log(
    "BLOCKED_EVENT_REPROCESS_AFTER_MAPPING_FIX=PASS"
  );
  console.log(
    "BLOCKED_EVENT_REPROCESS_RETRY_IDEMPOTENT=PASS"
  );
  console.log(
    "INACTIVE_ITEM_BLOCKED=PASS"
  );
  console.log(
    "INSUFFICIENT_STOCK_BLOCKED=PASS"
  );
  console.log(
    "CLINIC_ISOLATION=PASS"
  );
  console.log(
    "UNIT_CONVERSION=PASS"
  );
  console.log(
    "MALFORMED_EVENT_NO_INTEGRATION_RECORD=PASS"
  );
  console.log(
    "ROUTES_EXPOSED=FALSE"
  );
  console.log(
    "CONNECTOR_AUTH_ENABLED=FALSE"
  );
  console.log(
    "TEST_DATABASE=" +
      TEST_DB
  );
}

(async () => {
  try {
    await run();
  } finally {
    if (
      mongoose.connection.readyState !==
      0
    ) {
      try {
        if (
          mongoose.connection.name ===
          TEST_DB
        ) {
          await cleanupSimulatorData();
        }
      } finally {
        await mongoose.disconnect();
      }
    }
  }
})().catch((err) => {
  console.error(
    "MONGO_SIMULATOR_FAILED=TRUE"
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
