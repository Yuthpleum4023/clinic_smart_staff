# Vendor Adapters

A vendor adapter translates one external program's source records into the canonical normalized event contract.

## Adapter authority

An adapter owns only:

- interpretation of the vendor record shape
- selection of stable source event identity fields
- translation to:
  - externalEventId
  - externalLineId
  - externalItemId
  - unit
  - quantity
  - eventType
  - occurredAt
  - reference fields
  - non-authoritative metadata

An adapter must not own:

- clinicId
- connectorId
- externalSystem authority
- internal StockItem identity
- InventoryItemMapping selection
- normalizedQuantity
- StockMovement
- reprocess policy
- fuzzy item matching
- source-system writes

## Adding a new program

A new program should normally add only:

1. a new adapter, and
2. a source driver only if its transport technology is not already supported.

The generic runtime and `inventory_service` core should remain unchanged.

The adapter must use stable source identity. Generated timestamps, row-order position, or mutable display text must not be used as event identity when the source exposes a stable record key.
