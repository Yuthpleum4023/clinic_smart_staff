# Clinic Smart Staff — inventory_service Phase 1

Semantic owner of clinic inventory.

## Core invariants

- `inventory_service` is the only service allowed to materialize stock balance.
- Flutter and other services never write `currentQty` directly.
- Every balance change creates an immutable `StockMovement`.
- User-facing records are always scoped by `clinicId` from the verified JWT.
- Staff stock-in is immediate, but staff manual correction creates a pending adjustment request.
- Clinic Admin approves/rejects staff corrections.
- External clinic-program integration is reserved through movement types/source/idempotency, but no on-prem connector endpoint is exposed in Phase 1.
- Do not give an on-prem connector the global `INTERNAL_SERVICE_KEY`; connector credentials must be per-clinic/scoped when Phase 2 is added.

## Routes

Both `/inventory/...` and `/api/inventory/...` are mounted, matching the existing payroll-service compatibility pattern.


- `POST /api/inventory/items` (or `/inventory/items`) admin
- `GET /api/inventory/items` admin/employee
- `GET /api/inventory/items/low-stock` admin/employee
- `GET /api/inventory/items/:id` admin/employee
- `GET /api/inventory/items/:id/card` admin/employee
- `PATCH /api/inventory/items/:id` admin, no balance/threshold fields
- `PATCH /api/inventory/items/:id/threshold` admin
- `POST /api/inventory/stock/in` admin/employee
- `POST /api/inventory/stock/consume` admin/employee
- `POST /api/inventory/stock/admin-adjust` admin
- `POST /api/inventory/adjustments` employee
- `GET /api/inventory/adjustments/pending` admin
- `POST /api/inventory/adjustments/:id/approve` admin
- `POST /api/inventory/adjustments/:id/reject` admin

## Required env

- `MONGO_URI`
- `JWT_SECRET`
- `STAFF_SERVICE_URL`
- `STAFF_SERVICE_INTERNAL_KEY` or `INTERNAL_SERVICE_KEY`

Optional:

- `PORT` (local default `3105`)
- `NODE_ENV`
- `CORS_ORIGINS`
- `ALLOW_NEGATIVE_STOCK=false`
- `STAFF_EMPLOYEE_BASE_PATH=/api/employees`


## Inventory access authority

Inventory access is scoped by the authenticated clinicId.

- Helper is explicitly excluded from clinic inventory.
- Clinic admin/owner may access inventory through authenticated clinic authority.
- Any other clinic role must have an active Employee membership in staff_service
  for the same userId and clinicId.
- Role/position names are not whitelisted individually.
- Item read and stock-in use this generic clinic-member authority.
- Item configuration, threshold changes, Financial Stock Card, admin adjustment,
  and adjustment approval/rejection remain admin-only unless explicitly changed
  by a separate business contract.
- Stock consumption permissions are not broadened by this rule.
