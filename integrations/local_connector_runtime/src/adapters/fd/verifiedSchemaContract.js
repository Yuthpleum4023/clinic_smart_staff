"use strict";

/*
 * FD5_5 schema contract.
 *
 * Authority boundary:
 * - This module records only schema facts proven by discovery.
 * - It does NOT decide inventory movement semantics.
 * - It does NOT decide clinic scope.
 * - It does NOT normalize stock quantity.
 * - It does NOT enable the FD adapter for production ingestion.
 */

const FD_VERIFIED_SCHEMA = Object.freeze({
  source: Object.freeze({
    vendor: "fd",
    database: "FD5_5",
    engine: "mysql",
    observedServerVersion: "4.1.1a-alpha-nt"
  }),

  tables: Object.freeze({
    product: Object.freeze({
      primaryKey: Object.freeze(["ProdNum"]),
      columns: Object.freeze([
        "ProdNum",
        "ProdName",
        "ReceiveUnit",
        "SendUnit",
        "PerUnit",
        "UseFlag",
        "SaleFlag",
        "ProdGroup",
        "TotalAmt",
        "Minimum",
        "ReOrderUnit",
        "ReOrderPoint",
        "ItemOrder",
        "SalePrice",
        "BuyPrice",
        "OftenUse",
        "OftenSale",
        "BarCode",
        "IsHidden",
        "Maximum",
        "pic",
        "OutStock",
        "Lab",
        "NoOrder",
        "SaleOther",
        "IsReturn",
        "NoDiscount"
      ])
    }),

    xferdtl: Object.freeze({
      primaryKey: Object.freeze(["id"]),
      columns: Object.freeze([
        "id",
        "SeqNum",
        "XferNum",
        "ProdNum",
        "ProdName",
        "DocUnit",
        "ReceiveUnit",
        "OnhandUnit",
        "ExpireDate",
        "BuyPrice",
        "SalePrice",
        "InputDate",
        "Status",
        "remark",
        "atLocat",
        "ProcProd",
        "ProcRxNum",
        "PrvAmountUnit",
        "AmountUnit",
        "AvgCost"
      ]),
      indexedColumns: Object.freeze([
        "id",
        "atLocat",
        "ProcProd",
        "XferNum",
        "InputDate"
      ])
    }),

    xferhdr: Object.freeze({
      primaryKey: Object.freeze(["id"]),
      columns: Object.freeze([
        "id",
        "XferNum",
        "InputDate",
        "Amount",
        "Price",
        "FromLocat",
        "ToLocat",
        "DocType",
        "item",
        "UpdateName",
        "Prv_xferNum",
        "PONum",
        "BillNum",
        "PrtBillNum",
        "Receipt_PrtBillNum",
        "Dist_Return"
      ]),
      indexedColumns: Object.freeze([
        "id",
        "DocType",
        "FromLocat",
        "ToLocat",
        "XferNum",
        "InputDate"
      ])
    }),

    procprod: Object.freeze({
      primaryKey: Object.freeze(["ProcProd"]),
      columns: Object.freeze([
        "ProcProd",
        "PatNum",
        "ProdNum",
        "AmtUnit",
        "SendUnit",
        "SalePrice",
        "ProdFee",
        "InputDate",
        "PayNum",
        "BillNum",
        "Discount_pct",
        "Discount",
        "Checkin_id",
        "ActNum",
        "ActName",
        "e_printed",
        "NoDiscount",
        "ProcStatus",
        "IsGive",
        "Give_ProvNum",
        "Give_DF",
        "Give_TF"
      ]),
      indexedColumns: Object.freeze([
        "ProcProd",
        "PatNum",
        "ProdNum",
        "InputDate"
      ])
    })
  }),

  relationships: Object.freeze({
    productIdentityCandidate: Object.freeze({
      product: "product.ProdNum",
      xferdtl: "xferdtl.ProdNum",
      procprod: "procprod.ProdNum",
      status: "schema_coordinate_verified_semantics_unresolved"
    }),

    transferJoinCandidate: Object.freeze({
      header: "xferhdr.XferNum",
      detail: "xferdtl.XferNum",
      status: "schema_coordinate_verified_semantics_unresolved"
    })
  }),

  unresolvedSemantics: Object.freeze([
    "Which source table is authoritative for a dispensed inventory event",
    "Meaning and sign semantics of xferdtl.DocUnit",
    "Meaning and sign semantics of xferdtl.ReceiveUnit",
    "Meaning and sign semantics of xferdtl.OnhandUnit",
    "Meaning and sign semantics of xferdtl.PrvAmountUnit",
    "Meaning and sign semantics of xferdtl.AmountUnit",
    "Meaning of xferhdr.DocType values",
    "Meaning of xferdtl.Status values",
    "Whether procprod.AmtUnit represents inventory consumption",
    "Meaning of procprod.ProcStatus values",
    "Authoritative unit conversion between ReceiveUnit and SendUnit",
    "Authoritative location/clinic mapping for atLocat FromLocat ToLocat"
  ]),

  production: Object.freeze({
    schemaCoordinatesVerified: true,
    movementSemanticsVerified: false,
    adapterActivationAllowed: false,
    stockAuthority: false,
    clinicScopeAuthority: false,
    fuzzyMappingAllowed: false
  })
});

function assertFdSchemaContract(contract = FD_VERIFIED_SCHEMA) {
  if (contract?.source?.database !== "FD5_5") {
    throw new Error("FD_DATABASE_CONTRACT_MISMATCH");
  }

  for (const table of [
    "product",
    "xferdtl",
    "xferhdr",
    "procprod"
  ]) {
    if (!contract.tables?.[table]) {
      throw new Error(`FD_REQUIRED_TABLE_MISSING:${table}`);
    }
  }

  if (
    contract.production?.movementSemanticsVerified !== false ||
    contract.production?.adapterActivationAllowed !== false
  ) {
    throw new Error("FD_UNVERIFIED_SEMANTICS_MUST_FAIL_CLOSED");
  }

  if (
    contract.production?.stockAuthority !== false ||
    contract.production?.clinicScopeAuthority !== false
  ) {
    throw new Error("FD_AUTHORITY_BOUNDARY_VIOLATION");
  }

  return true;
}

module.exports = {
  FD_VERIFIED_SCHEMA,
  assertFdSchemaContract
};
