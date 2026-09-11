"use strict";

const {
  FD_VERIFIED_SCHEMA,
  assertFdSchemaContract
} = require("./verifiedSchemaContract");

function freezeList(items) {
  return Object.freeze(
    items.map((item) =>
      Object.freeze({
        ...item,
        ...(item.left
          ? { left: Object.freeze({ ...item.left }) }
          : {}),
        ...(item.right
          ? { right: Object.freeze({ ...item.right }) }
          : {})
      })
    )
  );
}

function buildFdObservedXferSourceProfile() {
  assertFdSchemaContract(FD_VERIFIED_SCHEMA);

  const poll = Object.freeze({
    schema: "FD5_5",
    table: "xferdtl",
    alias: "d",

    columns: freezeList([
      { tableAlias: "d", column: "id", as: "id" },
      { tableAlias: "d", column: "XferNum", as: "fd_xfer_num" },
      { tableAlias: "d", column: "ProdNum", as: "fd_prod_num" },
      { tableAlias: "d", column: "DocUnit", as: "fd_doc_unit" },
      { tableAlias: "d", column: "ReceiveUnit", as: "fd_receive_unit" },
      { tableAlias: "d", column: "OnhandUnit", as: "fd_onhand_unit" },
      { tableAlias: "d", column: "Status", as: "fd_detail_status" },
      { tableAlias: "d", column: "InputDate", as: "fd_detail_input_date" },
      { tableAlias: "d", column: "PrvAmountUnit", as: "fd_previous_amount_unit" },
      { tableAlias: "d", column: "AmountUnit", as: "fd_amount_unit" },

      { tableAlias: "h", column: "id", as: "fd_header_id" },
      { tableAlias: "h", column: "InputDate", as: "fd_header_input_date" },
      { tableAlias: "h", column: "FromLocat", as: "fd_from_locat" },
      { tableAlias: "h", column: "ToLocat", as: "fd_to_locat" },
      { tableAlias: "h", column: "DocType", as: "fd_doc_type" },
      { tableAlias: "h", column: "Dist_Return", as: "fd_dist_return" }
    ]),

    joins: freezeList([
      {
        type: "inner",
        table: "xferhdr",
        alias: "h",
        left: {
          tableAlias: "d",
          column: "XferNum"
        },
        right: {
          tableAlias: "h",
          column: "XferNum"
        }
      }
    ]),

    /*
     * Intentionally empty.
     *
     * No DocType, Status, location, patient-destination, return,
     * or cancellation value is allowed to become a production
     * predicate until its business semantics are verified.
     */
    predicates: Object.freeze([]),

    /*
     * xferdtl.id is a verified primary key and is therefore the
     * structural cursor candidate for forward-only observation.
     * This does not make the source movement semantics verified.
     */
    cursorColumn: "id",
    cursorTableAlias: "d",
    tieBreakerColumn: "",
    tieBreakerTableAlias: "",
    limit: 500
  });

  const candidateAdapterMapping = Object.freeze({
    eventId: "id",
    lineId: "",
    itemId: "fd_prod_num",
    quantityCandidate: "fd_doc_unit",
    unitCandidate: "fd_receive_unit",
    occurredAtCandidate: "fd_detail_input_date",
    referenceNo: "fd_xfer_num",
    referenceTypeCandidate: "fd_doc_type"
  });

  const semanticRequirements = Object.freeze([
    "Verify which xfer document class represents a completed patient dispense",
    "Verify whether xferdtl.DocUnit is the authoritative dispensed quantity",
    "Verify unit semantics and any ReceiveUnit/SendUnit conversion",
    "Verify xferdtl.Status final/cancel semantics",
    "Verify xferhdr.Dist_Return and linked return/correction behavior",
    "Verify whether edits can mutate an existing xferdtl row after first observation",
    "Verify clinic/location interpretation without making FD the clinic-scope authority"
  ]);

  return Object.freeze({
    id: "fd_xfer_relational_candidate_v1",
    status: "relational_source_candidate_semantics_unverified",

    source: Object.freeze({
      vendor: "fd",
      database: "FD5_5",
      engine: "mysql",
      poll
    }),

    candidateAdapterMapping,
    semanticRequirements,

    production: Object.freeze({
      schemaCoordinatesVerified: true,
      relationalSourceShapeVerified: true,
      movementSemanticsVerified: false,
      adapterActivationAllowed: false,
      stockAuthority: false,
      clinicScopeAuthority: false,
      fuzzyMappingAllowed: false
    })
  });
}

const FD_OBSERVED_XFER_SOURCE_PROFILE =
  buildFdObservedXferSourceProfile();

module.exports = {
  FD_OBSERVED_XFER_SOURCE_PROFILE,
  buildFdObservedXferSourceProfile
};
