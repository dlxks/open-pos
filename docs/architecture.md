# Architecture

## Applications and packages

- `apps/register` is the Flutter cashier application. Flutter provides the native Android, iOS, Windows, macOS, and Linux runners and the browser build from one Dart UI.
- `apps/hub` is a Dart Shelf HTTP service. A self-hosted deployment runs one hub per store deployment and stores accounts, hashed sessions, catalog, audit events, inventory balances, cash shifts, and synced sales in SQLite.
- `packages/pos_domain` contains Dart models and calculations shared by the register and hub. Sale amounts are integer minor units to avoid floating point currency arithmetic.

## Checkout and synchronization

```text
Cashier UI
    |
    v
Sale domain validation
    |
    v
Register SQLite (commit first) ---> HTTP sync ---> Hub API ---> Hub SQLite
          |
          +--- network failure: keep pending; retry at next app startup
```

Each sale gets a client-generated ID. The hub treats a retry with identical contents as accepted and rejects reuse of the same ID for different contents. This supports at-least-once delivery from a register without creating duplicate sale records.

The hub also appends audited changes to a versioned sync event feed. Each enrolled register pages from its own cursor and acknowledges only after its local snapshots have been refreshed. Register queues use capped exponential backoff and retain a stable operation ID across retries. Sale, stock, catalog, and payment records are stored in separate local queues.

Sales store integer centavo amounts for subtotal, discount, tax, total, tender, and change. Tax and loyalty settings have version history; the sale carries the versions and values used at checkout. This lets a disconnected register sync a sale created under an older configuration while the hub rejects a payload whose values do not match that version. Customer balance updates and accepted sale records commit in one hub transaction.

## Store access and catalog sync

Each hub can be initialized once with a store and its first administrator. Passwords are derived with PBKDF2, opaque random bearer tokens are stored on the hub as SHA-256 hashes, and sessions expire after 30 days. The server checks each role on protected routes: admins manage staff and audit events, admins and managers maintain products, and all signed-in roles can use the register and read the active catalog. Failed sign-ins are rate-limited per email.

The register stores its active catalog, managed category snapshot, and hub catalog version in its local Drift database. It refreshes after sign-in and falls back to the last cached version if the hub is unavailable. Product edits are stored in a local outbox with the expected product version. The hub applies an operation ID once or returns the current product after a conflict; a manager can keep the register's version or use the hub's. Product versions are retained so the hub can verify modifiers and prices on offline sale lines. Category names are case-insensitive per store. Archived categories remain visible to managers and can be restored; the hub blocks archiving while an active product still uses the category. A product sync using a new category creates its managed category record as part of the catalog transaction.

## Inventory and cash shifts

The hub inventory ledger is authoritative. Receiving and manual adjustments affect a named stock location; transfers change source and destination balances in one SQLite transaction. A sale that first reaches the hub decrements each matching product once in the same transaction that stores the sale. Offline stock movements are written to a Drift outbox before sync. Cached inventory overlays queued movements and unsynced sales. The hub rejects a movement with insufficient stock or a reused ID; the register marks the movement as a conflict and managers can retry it or discard it.

Registers enroll with a stable locally stored ID and name. Each register can have one open cash shift at a time. Opening float, paid-in/out movements, linked cash sales, counted cash, and variance are stored on the hub. The register caches the active shift snapshot locally so its ID remains attached to offline sales. If an offline sale arrives after its shift closes, the hub recomputes expected cash and variance; the shift API exposes the updated reconciliation.

Returns and voids use the open shift on the acting register for cash refunds. Return quantities refer to a specific sale line, including its modifiers, and cannot exceed sold quantities; repeated return IDs are idempotent. Returns can restock items, and voids restock all items. Voids are manager-only and blocked after any return. Loyalty points are updated with sales and adjusted for returns or voids.

Payment records are stored separately from sales and track provider, method, capture status, refunded amount, and void status. The register exposes a `PaymentProvider` interface with a cash implementation. Sale sync must succeed before its payment record is submitted; both have durable local persistence and retry IDs. Card and terminal adapters are not included.

Flutter Web stores the local database using Drift's web backend. The packaged `sqlite3.wasm` and worker files are served from the app's `web/` directory. Native builds use the platform SQLite implementation.

## Deployment

Docker Compose builds a static Flutter Web register container and a Dart hub container. Nginx serves the register and proxies `/api/` requests to the hub. The hub database directory is backed by a named volume. Backup uses SQLite's online backup API; restore requires the hub to be stopped and saves a pre-restore recovery copy. Maintenance can export plain SQLite files or chunked AES-256-GCM files that authenticate each record and an end marker. Encrypted verification and restore decrypt into a private temporary directory and validate SQLite before use. Bash and PowerShell host scripts use rclone to move encrypted backups off-host and verify the remote copy before local retention runs. Deployments configure the schedule, remote, key storage, and remote retention. Cloud deployments can run the hub container with a persistent volume and serve the web build from any static host or reverse proxy.

The current hub uses a local SQLite file and is intended to run as a single service instance for one store. Horizontal hub replicas and shared network filesystems are outside the current sync design. Deployments reachable over a network should terminate TLS at a reverse proxy.

The hub records its schema epoch in SQLite `PRAGMA user_version`. Compatible legacy upgrades run through idempotent DDL, an explicit maintenance command supports stopped upgrades, and a newer schema epoch fails closed. `/health` is a liveness probe; `/health/ready` performs a SQLite quick check. SIGTERM stops new connections, drains requests for up to eight seconds, then closes remaining connections and SQLite. The hub and Nginx register containers run as unprivileged users and send cache, framing, and content-type security headers.

`docker-compose.cloud.yml` is a single-store cloud-host profile. It requires an exact allowed HTTPS origin and a durable host bind mount writable by UID `65532`, keeps the hub private to the Docker network, and publishes the web register only on host loopback for a TLS reverse proxy. Allocate separate databases and deployments per store. This does not provide shared-hub tenant routing or a cloud billing control plane.

## Current limits

The current release supports cash tender only, flat sale discounts, one tax rule per store, customer loyalty, product modifiers, cash returns, voids, basic supplier records and purchase orders, and PDF receipts through the platform print dialog. Supplier and purchase-order changes require a live hub connection; invoice matching and vendor returns are not implemented. The payment-provider boundary does not include card or terminal payments. Multiple tax classes per product, exchanges, shared-hub multi-store isolation, and centralized cloud billing remain future work. CORS is an origin allowlist; bearer tokens provide API authentication, and TLS is needed for network deployments.
