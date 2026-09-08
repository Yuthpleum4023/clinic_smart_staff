# Vendor Adapters

A vendor adapter translates source records into the canonical normalized event contract.

A vendor adapter must not:
- decide clinic scope
- select internal StockItem identity
- write stock
- call StockMovement directly
- perform fuzzy item mapping
- write back to the vendor system

Exact mapping and stock processing remain owned by inventory_service.
