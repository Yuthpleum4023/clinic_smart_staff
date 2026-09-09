"use strict";

const {
  createAdapterContract,
  assertAdapterOutputAuthority,
  assertStableSourceIdentity
} = require("./adapterContract");

function s(value) {
  return String(value ?? "").trim();
}

function requiredFieldName(
  value,
  label
) {
  const out = s(value);

  if (!out) {
    throw new Error(
      `${label}_REQUIRED`
    );
  }

  return out;
}

function requiredProfile(
  profile = {}
) {
  if (
    !profile ||
    typeof profile !== "object" ||
    Array.isArray(profile)
  ) {
    throw new Error(
      "FD_PROFILE_REQUIRED"
    );
  }

  if (
    profile.schemaVerified !== true
  ) {
    throw new Error(
      "FD_SCHEMA_VERIFICATION_REQUIRED"
    );
  }

  if (
    profile
      .movementSemanticsVerified !==
    true
  ) {
    throw new Error(
      "FD_MOVEMENT_SEMANTICS_VERIFICATION_REQUIRED"
    );
  }

  const fields = profile.fields;

  if (
    !fields ||
    typeof fields !== "object" ||
    Array.isArray(fields)
  ) {
    throw new Error(
      "FD_FIELDS_REQUIRED"
    );
  }

  const unitField =
    s(fields.unit);

  const unitLiteral =
    s(profile.unitLiteral);

  if (
    !unitField &&
    !unitLiteral
  ) {
    throw new Error(
      "FD_UNIT_SOURCE_REQUIRED"
    );
  }

  return {
    schemaVerified: true,
    movementSemanticsVerified:
      true,
    sourceName:
      s(profile.sourceName) ||
      "fd",
    unitLiteral,
    fields: {
      eventId:
        requiredFieldName(
          fields.eventId,
          "FD_EVENT_ID_FIELD"
        ),
      lineId:
        s(fields.lineId),
      itemId:
        requiredFieldName(
          fields.itemId,
          "FD_ITEM_ID_FIELD"
        ),
      previousAmountUnit:
        requiredFieldName(
          fields.previousAmountUnit,
          "FD_PREVIOUS_AMOUNT_UNIT_FIELD"
        ),
      amountUnit:
        requiredFieldName(
          fields.amountUnit,
          "FD_AMOUNT_UNIT_FIELD"
        ),
      unit:
        unitField,
      occurredAt:
        requiredFieldName(
          fields.occurredAt,
          "FD_OCCURRED_AT_FIELD"
        ),
      referenceNo:
        s(fields.referenceNo),
      referenceType:
        s(fields.referenceType)
    }
  };
}

function requiredValue(
  record,
  fieldName,
  code
) {
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

function requiredNumber(
  record,
  fieldName,
  code
) {
  const value =
    Number(
      requiredValue(
        record,
        fieldName,
        code
      )
    );

  if (!Number.isFinite(value)) {
    throw new Error(code);
  }

  return value;
}

function createFdAdapter(
  profileInput = {}
) {
  const profile =
    requiredProfile(
      profileInput
    );

  const f = profile.fields;

  const adapter =
    createAdapterContract({
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

        const previousAmountUnit =
          requiredNumber(
            row,
            f.previousAmountUnit,
            "FD_PREVIOUS_AMOUNT_UNIT_VALUE_REQUIRED"
          );

        const amountUnit =
          requiredNumber(
            row,
            f.amountUnit,
            "FD_AMOUNT_UNIT_VALUE_REQUIRED"
          );

        const delta =
          amountUnit -
          previousAmountUnit;

        // V8 closure: zero-delta rows do not represent
        // a stock movement and must not be materialized.
        if (delta === 0) {
          return null;
        }

        const unit =
          f.unit
            ? requiredValue(
                row,
                f.unit,
                "FD_UNIT_VALUE_REQUIRED"
              )
            : profile.unitLiteral;

        const occurredAt =
          requiredValue(
            row,
            f.occurredAt,
            "FD_OCCURRED_AT_VALUE_REQUIRED"
          );

        const event = {
          externalEventId:
            String(
              externalEventId
            ),

          externalLineId:
            String(
              externalLineId
            ),

          externalItemId:
            String(
              externalItemId
            ),

          quantity:
            Math.abs(delta),

          unit:
            String(unit),

          eventType:
            delta > 0
              ? "inventory_in"
              : "inventory_out",

          occurredAt,

          referenceType:
            f.referenceType
              ? s(
                  row[
                    f.referenceType
                  ]
                )
              : "fd_movement",

          referenceNo:
            f.referenceNo
              ? s(
                  row[
                    f.referenceNo
                  ]
                )
              : "",

          metadata: {
            sourceAdapter:
              profile.sourceName,
            movementDerivation:
              "amount_unit_delta"
          }
        };

        assertAdapterOutputAuthority(
          event
        );

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

    schemaVerified: true,
    movementSemanticsVerified:
      true
  });
}

module.exports = {
  requiredProfile,
  createFdAdapter
};
