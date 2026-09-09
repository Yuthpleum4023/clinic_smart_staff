# FD5_5 Verified Schema Contract

This document records only schema facts established by the FD schema discovery.

## Source

- Vendor adapter: `fd`
- Database: `FD5_5`
- Database engine: MySQL
- Observed server version: `4.1.1a-alpha-nt`

## Verified inventory-related tables

### product

Verified product/master coordinates include:

- `ProdNum`
- `ProdName`
- `ReceiveUnit`
- `SendUnit`
- `PerUnit`
- `TotalAmt`
- `Minimum`
- `ReOrderUnit`
- `ReOrderPoint`
- `SalePrice`
- `BuyPrice`
- `BarCode`
- `OutStock`

Primary key: `ProdNum`.

### xferdtl

Verified coordinates include:

- `id`
- `XferNum`
- `ProdNum`
- `DocUnit`
- `ReceiveUnit`
- `OnhandUnit`
- `InputDate`
- `Status`
- `atLocat`
- `ProcProd`
- `ProcRxNum`
- `PrvAmountUnit`
- `AmountUnit`
- `AvgCost`

Primary key: `id`.

### xferhdr

Verified coordinates include:

- `id`
- `XferNum`
- `InputDate`
- `FromLocat`
- `ToLocat`
- `DocType`
- `PONum`
- `BillNum`

Primary key: `id`.

### procprod

Verified coordinates include:

- `ProcProd`
- `ProdNum`
- `AmtUnit`
- `SendUnit`
- `InputDate`
- `ProcStatus`

Primary key: `ProcProd`.

## Candidate structural relationships

Schema coordinates support investigation of:

- `product.ProdNum` ↔ `xferdtl.ProdNum`
- `product.ProdNum` ↔ `procprod.ProdNum`
- `xferhdr.XferNum` ↔ `xferdtl.XferNum`

These are candidate structural relationships only.

They do not establish inventory-event semantics.

## Fail-closed boundary

The following remain unresolved:

- authoritative dispense/movement source
- quantity/sign semantics
- transfer document type semantics
- status semantics
- unit conversion semantics
- clinic/location mapping semantics

Therefore:

- movement semantics verified = false
- adapter activation allowed = false
- FD adapter has no stock authority
- FD adapter has no clinic-scope authority
- fuzzy mapping is prohibited

The generic MySQL read-only driver remains the database-read owner.
The FD adapter may translate only semantics that have been separately verified.
The inventory backend remains the stock/mapping/scope authority.
