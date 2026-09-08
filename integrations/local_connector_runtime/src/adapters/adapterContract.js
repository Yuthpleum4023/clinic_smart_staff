"use strict";

function s(value) {
  return String(value ?? "").trim();
}

function ensureObject(value, code) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw new Error(code);
  }

  return value;
}

function createAdapterContract(definition = {}) {
  ensureObject(
    definition,
    "ADAPTER_DEFINITION_REQUIRED"
  );

  const id = s(definition.id);

  if (!id) {
    throw new Error("ADAPTER_ID_REQUIRED");
  }

  if (
    typeof definition.transformRecord !==
    "function"
  ) {
    throw new Error(
      `ADAPTER_TRANSFORM_REQUIRED:${id}`
    );
  }

  const contract = {
    id,

    sourceIdentity: Object.freeze({
      eventField:
        s(
          definition.sourceIdentity
            ?.eventField
        ),
      lineField:
        s(
          definition.sourceIdentity
            ?.lineField
        )
    }),

    async transformRecord(
      rawRecord,
      context = {}
    ) {
      ensureObject(
        rawRecord,
        "ADAPTER_RAW_RECORD_REQUIRED"
      );

      const result =
        await definition.transformRecord(
          Object.freeze({
            ...rawRecord
          }),
          Object.freeze({
            ...context
          })
        );

      return result;
    }
  };

  if (
    !contract.sourceIdentity.eventField
  ) {
    throw new Error(
      `ADAPTER_SOURCE_EVENT_IDENTITY_REQUIRED:${id}`
    );
  }

  return Object.freeze(contract);
}

function assertAdapterOutputAuthority(
  output
) {
  const events =
    Array.isArray(output)
      ? output
      : [output];

  for (const event of events) {
    if (!event) continue;

    ensureObject(
      event,
      "ADAPTER_OUTPUT_INVALID"
    );

    const forbidden = [
      "clinicId",
      "connectorId",
      "externalSystem",
      "stockItemId",
      "mappingId",
      "stockMovementId",
      "normalizedQuantity",
      "reprocess"
    ];

    for (const field of forbidden) {
      if (
        Object.prototype.hasOwnProperty.call(
          event,
          field
        )
      ) {
        throw new Error(
          `ADAPTER_AUTHORITY_VIOLATION:${field}`
        );
      }
    }
  }

  return true;
}

function assertStableSourceIdentity(
  adapter,
  record
) {
  ensureObject(
    record,
    "ADAPTER_RAW_RECORD_REQUIRED"
  );

  const eventField =
    adapter.sourceIdentity.eventField;

  const lineField =
    adapter.sourceIdentity.lineField;

  const eventId =
    record[eventField];

  if (
    eventId === null ||
    eventId === undefined ||
    s(eventId) === ""
  ) {
    throw new Error(
      "ADAPTER_EVENT_IDENTITY_MISSING"
    );
  }

  if (lineField) {
    const lineId =
      record[lineField];

    if (
      lineId === null ||
      lineId === undefined ||
      s(lineId) === ""
    ) {
      throw new Error(
        "ADAPTER_LINE_IDENTITY_MISSING"
      );
    }
  }

  return true;
}

module.exports = {
  createAdapterContract,
  assertAdapterOutputAuthority,
  assertStableSourceIdentity
};
