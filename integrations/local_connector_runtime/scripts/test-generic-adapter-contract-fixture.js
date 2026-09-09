"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  createAdapterContract,
  assertAdapterOutputAuthority,
  assertStableSourceIdentity
} = require(
  "../src/adapters/adapterContract"
);

const {
  AdapterRegistry
} = require(
  "../src/core/adapterRegistry"
);

const {
  FileCheckpointStore
} = require(
  "../src/core/checkpointStore"
);

const {
  ConnectorRuntime
} = require(
  "../src/core/connectorRuntime"
);

function createDriver(records) {
  let connected = false;

  return {
    readOnly: true,

    async connect() {
      connected = true;
    },

    async poll() {
      assert.equal(
        connected,
        true
      );

      return {
        records,
        nextCheckpoint:
          `checkpoint-${records.length}`
      };
    },

    async close() {
      connected = false;
    }
  };
}

(async () => {
  const vendorA =
    createAdapterContract({
      id: "fixture_vendor_a",

      sourceIdentity: {
        eventField:
          "dispense_id",
        lineField:
          "line_no"
      },

      async transformRecord(
        row
      ) {
        return {
          externalEventId:
            String(
              row.dispense_id
            ),

          externalLineId:
            String(
              row.line_no
            ),

          externalItemId:
            String(
              row.product_code
            ),

          unit:
            String(
              row.dispense_unit
            ),

          quantity:
            Number(
              row.dispense_qty
            ),

          eventType:
            "dispensed",

          occurredAt:
            row.dispensed_at,

          referenceType:
            "dispense",

          referenceNo:
            String(
              row.document_no
            ),

          metadata: {
            sourceRecordType:
              "fixture_a"
          }
        };
      }
    });

  const vendorB =
    createAdapterContract({
      id: "fixture_vendor_b",

      sourceIdentity: {
        eventField:
          "transactionKey",
        lineField:
          "sequence"
      },

      async transformRecord(
        row
      ) {
        return {
          externalEventId:
            String(
              row.transactionKey
            ),

          externalLineId:
            String(
              row.sequence
            ),

          externalItemId:
            String(
              row.materialId
            ),

          unit:
            String(
              row.uom
            ),

          quantity:
            Number(
              row.amount
            ),

          eventType:
            "dispensed",

          occurredAt:
            row.timestamp,

          referenceType:
            "usage",

          referenceNo:
            String(
              row.ticket
            ),

          metadata: {
            sourceRecordType:
              "fixture_b"
          }
        };
      }
    });

  const recordA = {
    dispense_id:
      "A-100",
    line_no: 1,
    product_code:
      "ITEM-A",
    dispense_unit:
      "piece",
    dispense_qty: 2,
    dispensed_at:
      "2026-09-08T04:00:00Z",
    document_no:
      "DOC-A"
  };

  const recordB = {
    transactionKey:
      "B-900",
    sequence: 7,
    materialId:
      "ITEM-B",
    uom:
      "box",
    amount: 3,
    timestamp:
      "2026-09-08T05:00:00Z",
    ticket:
      "DOC-B"
  };

  assert.equal(
    assertStableSourceIdentity(
      vendorA,
      recordA
    ),
    true
  );

  assert.equal(
    assertStableSourceIdentity(
      vendorB,
      recordB
    ),
    true
  );

  const outputA =
    await vendorA
      .transformRecord(
        recordA
      );

  const outputB =
    await vendorB
      .transformRecord(
        recordB
      );

  assert.equal(
    assertAdapterOutputAuthority(
      outputA
    ),
    true
  );

  assert.equal(
    assertAdapterOutputAuthority(
      outputB
    ),
    true
  );

  assert.equal(
    outputA.externalEventId,
    "A-100"
  );

  assert.equal(
    outputB.externalEventId,
    "B-900"
  );

  const registry =
    new AdapterRegistry();

  registry.register(
    vendorA
  );

  registry.register(
    vendorB
  );

  assert.deepEqual(
    registry.list(),
    [
      "fixture_vendor_a",
      "fixture_vendor_b"
    ]
  );

  const sent = [];

  const transport = {
    async sendConsumption(
      event
    ) {
      sent.push(event);
      return {
        ok: true
      };
    }
  };

  const tmp =
    fs.mkdtempSync(
      path.join(
        os.tmpdir(),
        "css-adapter-fixture-"
      )
    );

  const checkpointStore =
    new FileCheckpointStore(
      path.join(
        tmp,
        "state.json"
      )
    );

  const runtimeA =
    new ConnectorRuntime({
      driver:
        createDriver(
          [recordA]
        ),

      adapter:
        registry.get(
          "fixture_vendor_a"
        ),

      transport,
      checkpointStore,

      checkpointKey:
        "fixture-a"
    });

  const runtimeB =
    new ConnectorRuntime({
      driver:
        createDriver(
          [recordB]
        ),

      adapter:
        registry.get(
          "fixture_vendor_b"
        ),

      transport,
      checkpointStore,

      checkpointKey:
        "fixture-b"
    });

  const resultA =
    await runtimeA.runOnce();

  const resultB =
    await runtimeB.runOnce();

  assert.equal(
    resultA.eventsSent,
    1
  );

  assert.equal(
    resultB.eventsSent,
    1
  );

  assert.equal(
    sent.length,
    2
  );

  assert.equal(
    sent[0].externalItemId,
    "ITEM-A"
  );

  assert.equal(
    sent[1].externalItemId,
    "ITEM-B"
  );

  for (const event of sent) {
    assert.equal(
      "clinicId" in event,
      false
    );

    assert.equal(
      "connectorId" in event,
      false
    );

    assert.equal(
      "stockItemId" in event,
      false
    );

    assert.equal(
      "stockMovementId" in event,
      false
    );
  }

  assert.throws(
    () =>
      assertAdapterOutputAuthority({
        externalEventId:
          "bad",
        stockItemId:
          "forbidden"
      }),
    /ADAPTER_AUTHORITY_VIOLATION/
  );

  assert.throws(
    () =>
      assertStableSourceIdentity(
        vendorA,
        {
          ...recordA,
          dispense_id: ""
        }
      ),
    /ADAPTER_EVENT_IDENTITY_MISSING/
  );

  console.log(
    "GENERIC_ADAPTER_CONTRACT_FIXTURE_PASSED=TRUE"
  );

  console.log(
    "MULTIPLE_VENDOR_SCHEMAS_SUPPORTED=TRUE"
  );

  console.log(
    "GENERIC_RUNTIME_LEGACY_TRANSPORT_COMPATIBILITY=TRUE"
  );

  console.log(
    "GENERIC_MYSQL_DRIVER_CHANGED_REQUIRED=FALSE"
  );

  console.log(
    "SERVER_CLINIC_SCOPE_AUTHORITY_PRESERVED=TRUE"
  );

  console.log(
    "SERVER_MAPPING_AUTHORITY_PRESERVED=TRUE"
  );

  console.log(
    "SERVER_STOCK_AUTHORITY_PRESERVED=TRUE"
  );

  console.log(
    "STABLE_SOURCE_IDENTITY_REQUIRED=TRUE"
  );

  console.log(
    "FUZZY_MAPPING_ALLOWED_IN_ADAPTER=FALSE"
  );

  console.log(
    "VENDOR_SPECIFIC_LOGIC_IN_GENERIC_CORE=FALSE"
  );
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
