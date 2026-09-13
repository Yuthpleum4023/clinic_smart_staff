# Generic Local Connector Runtime

Architecture:

External clinic program
→ read-only Source Driver
→ Vendor Adapter
→ normalized event
→ HTTPS + connector credential
→ inventory_service

The runtime owns source connectivity, polling, checkpointing, translation, and delivery.

The runtime does not own clinic scope, connector scope, internal stock item identity, item mapping, stock validation, stock movement, or reprocessing policy.

Adding another clinic program should normally require only a new driver (if needed) and/or a new adapter. Core runtime and inventory_service should remain unchanged.

Production deployment config contains deployment coordinates only. Database schema,
polling structure, cursor ownership, and movement mapping are resolved from the
runtime's verified-profile registry. Installer input must not carry or override
those semantic fields.
