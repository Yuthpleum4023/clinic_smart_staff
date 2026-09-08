"use strict";

const {
  createAdapterContract,
  assertAdapterOutputAuthority,
  assertStableSourceIdentity
} = require("./adapterContract");

function s(value) {
  return String(value ?? "").trim();
}

function requiredFieldName(value, label) {
  const out = s(value);
  if (!out) {
    throw new Error(`${label}_REQUIRED`);
  }
  return out;
}

function requiredProfile(profile = {}) {
  if (
    !profile ||
    typeof profile !== "object" ||
    Array.isArray(profile)
  ) {
    throw new Error("FD_PROFILE_REQUIRED");
  }

  if (profile.schemaVerified !== true) {
    throw new Error("FD_SCHEMA_VERIFICATION_REQUIRED");
  }

  const fields = profile.fields;

  if (
    !fields ||
    typeof fields !== "object" ||
    Array.isArray(fields)
  ) {
    throw new Error("FD_FIELDS_REQUIRED");
  }

  return {
    schemaVerified: true,
    sourceName: s(profile.sourceName) || "fd",
    fields: {
      eventId: requiredFieldName(fields.eventId, "FD_EVENT_ID_FIELD"),
      lineId: s(fields.lineId),
      itemId: requiredFieldName(fields.itemId, "FD_ITEM_ID_FIELD"),
      quantity: requiredFieldName(fields.quantity, "FD_QUANTITY_FIELD"),
      unit: requiredFieldName(fields.unit, "FD_UNIT_FIELD"),
      occurredAt: requiredFieldName(fields.occurredAt, "FD_OCCURRED_AT_FIELD"),
      referenceNo: s(fields.referenceNo),
      referenceType: s(fields.referenceType)
    }
  };
}

function requiredValue(record, fieldName, code) {
  const value = record[fieldName];

  if (
    value === null ||
    value === undefined ||
    s(value) === ""
  ) {
    throw new Error(code);
  }

  return value;
}

function createFdAdapter(profileInput = {}) {
  const profile = requiredProfile(profileInput);
  const f = profile.fields;

  const adapter = createAdapterContract({
    id: "fd",

    sourceIdentity: {
      eventField: f.eventId,
      lineField: f.lineId
    },

    async transformRecord(row) {
      const externalEventId =
        requiredValue(
          row,
          f.eventId,
          "FD_EVENT_ID_VALUE_REQUIRED"
        );

      const externalLineId =
        f.lineId
          ? requiredValue(
              row,
              f.lineId,
              "FD_LINE_ID_VALUE_REQUIRED"
            )
          : "0";

      const externalItemId =
        requiredValue(
          row,
          f.itemId,
          "FD_ITEM_ID_VALUE_REQUIRED"
        );

      const quantity =
        requiredValue(
          row,
          f.quantity,
          "FD_QUANTITY_VALUE_REQUIRED"
        );

      const unit =
        requiredValue(
          row,
          f.unit,
          "FD_UNIT_VALUE_REQUIRED"
        );

      const occurredAt =
        requiredValue(
          row,
          f.occurredAt,
          "FD_OCCURRED_AT_VALUE_REQUIRED"
        );

      const event = {
        externalEventId:
          String(externalEventId),

        externalLineId:
          String(externalLineId),

        externalItemId:
          String(externalItemId),

        quantity:
          Number(quantity),

        unit:
          String(unit),

        eventType:
          "dispensed",

        occurredAt,

        referenceType:
          f.referenceType
            ? s(row[f.referenceType])
            : "dispense",

        referenceNo:
          f.referenceNo
            ? s(row[f.referenceNo])
            : "",

        metadata: {
          sourceAdapter:
            profile.sourceName
        }
      };

      assertAdapterOutputAuthority(event);
      return event;
    }
  });

  return Object.freeze({
    ...adapter,

    assertSourceRecord(record) {
      return assertStableSourceIdentity(
        adapter,
        record
      );
    },

    schemaVerified: true
  });
}

module.exports = {
  requiredProfile,
  createFdAdapter
};
