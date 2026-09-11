# FD Movement Semantic Closure

Evidence: `FD_XFER_FINAL_CLOSURE_V5_REPORT.txt`.

Verified contract:

- source identity: `xferdtl.id`
- external product identity: `xferdtl.ProdNum`
- signed movement: `AmountUnit - PrvAmountUnit`
- validation witness: `DocUnit`
- invariant: `abs(AmountUnit-PrvAmountUnit) == abs(DocUnit)`
- negative delta -> `inventory_out`
- positive delta -> `inventory_in`
- zero delta -> no materialized movement

V5 inspected 5,300 rows:
- invariant matches: 5,300
- invariant mismatches: 0
- negative delta: 5,165
- positive delta: 135
- zero delta: 0

`DocType` and `Status` remain audit/source metadata, not movement direction
authority. `ProcRxNum` is correlation metadata only.

No generic conversion is inferred from `PerUnit`. The connector emits
`fd_balance_unit`; any conversion to the Clinic Smart Staff inventory unit
must be explicit in backend item mapping.

FD remains read-only. Backend remains authority for clinic scope, mapping,
unit conversion, stock, ledger, audit, idempotency, and reprocessing.

Production connector runtime belongs on supported Windows 10/11 or Windows
Server on the same LAN. The Windows 7 FD workstation remains a source/probe
machine, not the production connector host.
