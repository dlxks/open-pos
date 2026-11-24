# Roadmap

This roadmap keeps the first release deployable while building the advanced POS features in testable vertical slices.

## Phase 1: Register and offline sale sync

- Cashier register with product search, cart, cash tender, and change.
- Local sale persistence before network calls.
- Idempotent hub sale ingestion and retry queue.
- Unit, widget/API feature, and Playwright browser coverage.
- Self-hosted Docker Compose deployment.

## Phase 2: Tenant setup, users, and catalog

- **Implemented core:** first-run store and administrator setup, session-based sign-in, administrator/manager/cashier permissions, staff creation, sign-in lockout, and signed-in role checks on sales and catalog APIs.
- **Implemented core:** product name, category, SKU, barcode, price, active/archive status, and a management screen for administrators and managers.
- **Implemented core:** versioned catalog snapshots downloaded into each register's local Drift database for offline startup.
- **Implemented core:** audit records for setup, sign-ins, staff and catalog changes, and accepted sales; administrator-only audit API.
- **Implemented core:** stable register enrollment and device-specific shift identity.
- **Implemented core:** versioned tax configuration supports tax-exclusive and tax-inclusive sale snapshots. The hub validates the recorded rate and version during sync.
- **Implemented core:** managed category records with case-insensitive names, active/archive states, audit events, category sync, and offline register caching.
- **Remaining:** multi-store isolation within one hub deployment. A store currently uses its own hub deployment.

## Phase 3: Inventory and operations

- **Implemented core:** inventory balances and an idempotent movement ledger for receiving, signed adjustments, and transfers between named locations. Managers can set low-stock thresholds and review movement history. Synced sales reduce stock once.
- **Implemented core:** a local stock-operation outbox overlays cached balances and unsynced sales. The hub reports stock conflicts; managers can retry or discard a rejected operation.
- **Implemented core:** one active cash drawer shift per enrolled register, opening float, paid-in/out entries, linked cash sales, closing count, and variance. Offline sales retain their shift ID; late sync recalculates a closed shift's expected cash and variance.
- **Implemented core:** configurable exclusive/inclusive tax, manager-authorized flat discounts with a reason, customer records, versioned loyalty earn/redeem settings, and sale history.
- **Implemented core:** item-level partial returns with optional restocking, manager-only voids, cash refunds from the active shift, loyalty adjustments, and printable itemized receipts.
- **Current limit:** cash is the only payment method; tax is one rule per store; returned cash requires sufficient drawer cash in an open shift.

## Phase 4: Conflict-safe sync and payments

- **Implemented:** a versioned event feed with per-register cursors, paginated reads, explicit acknowledgements, and exponential retry scheduling for offline sales, stock changes, and catalog edits.
- **Implemented:** an idempotent catalog-edit outbox with optimistic product versions and manager conflict choices to keep a local edit or accept the hub version. Modifier groups validate required and optional selections, option price adjustments, and historical sale snapshots.
- **Implemented boundary:** payment capture and refund state are stored separately from sales. The register uses a payment-provider interface and a cash provider; card or terminal providers still require integrations.
- **Implemented:** administrator-only operational health reports database integrity and sync backlog. Maintenance commands validate backups, restore with a recovery copy, retain recent backup files, and prune sync events only after every register has acknowledged them. Audit records are not pruned.
- **Remaining:** configure and schedule off-site backup transfer, terminal certification, and production-grade observability and disaster recovery procedures.

## Phase 5: Cloud operations and release hardening

- **Implemented foundation:** cloud host Compose profile requires a durable per-store data mount and an exact HTTPS browser origin, keeps the hub private, and publishes the register on loopback for TLS termination. Both containers run unprivileged.
- **Implemented foundation:** SQLite schema epochs, controlled migration command, fail-closed handling of newer schemas, separate readiness/liveness probes, browser security headers, and graceful hub shutdown.
- **Implemented foundation:** CI builds the self-hosted Docker images; a tagged/manual workflow packages Android, Windows, Linux, macOS, and iOS artifacts. Android signing can use repository secrets; the other native packages remain unsigned and are not submitted to stores.
- **Remaining:** shared-hub tenant routing, tenant billing and quotas, load testing, production alerting, and disaster recovery exercises.
- **Remaining:** Apple and desktop signing/notarization, store submission automation, accessibility and localization audits, and peripheral certification.

## Phase 6: Encrypted backup and recovery

- **Implemented foundation:** maintenance generates a random 256-bit key and creates chunked AES-256-GCM backup files with random per-record nonces, authenticated ordering and end markers, and a key fingerprint. Encrypted backups can be verified and restored; restore validates SQLite and preserves a pre-restore recovery copy. Retention includes encrypted files.
- **Implemented foundation:** Bash and PowerShell host scripts create and verify encrypted backups, transfer them with rclone, verify remote bytes, and prune local files only after remote verification succeeds.
- **Remaining:** configure and schedule the host script and rclone destination, manage key rotation and recovery procedures, configure remote retention, and conduct recurring restore drills. The project does not configure an object-storage provider for deployments.

## Phase 7: Managed catalog categories

- **Implemented:** administrators and managers can create, archive, and restore categories. Names are case-insensitive and category changes are audited and published through the register sync feed.
- **Implemented:** category names are included in versioned catalog snapshots and cached on each register for offline product management. Existing product categories are migrated automatically; older clients that create a product category still produce a managed category record.
- **Implemented:** active products must be reassigned before their category can be archived. Product editors select from active categories when the catalog has managed records.
- **Remaining:** multi-store catalogs, category-specific tax and reporting, category ordering, and category-specific colors remain future work.

## Phase 8: Manager sales reports

- **Implemented:** managers and administrators can view sales summaries for a selected UTC date range, including daily totals, discounts, tax, refunds, voids, top products, cash movements, and shift reconciliation.
- **Implemented:** report queries validate dates, limit ranges to 366 days, and cap detailed shift rows while reporting when results are truncated.
- **Current limit:** report history is limited to records present on the selected hub deployment. Cross-store consolidation and export formats remain future work.

## Phase 9: Suppliers and purchase orders

- **Implemented:** managers and administrators can create, edit, archive, and restore suppliers. Supplier edits use optimistic versions and are audited.
- **Implemented:** managers and administrators can save purchase order drafts, place and cancel orders, and receive stock in partial deliveries across named locations.
- **Implemented:** receipt posting updates order quantities and the inventory movement ledger in one transaction. Retrying a receipt ID with the same payload is idempotent; conflicting reuse is rejected. Register caches keep supplier and order snapshots available for offline viewing.
- **Current limit:** supplier and purchase order writes require a hub connection; offline order drafting and receipt queues are not included. Suppliers and purchase orders are currently scoped to their single-store hub deployment.

Each phase should add migration coverage, offline/retry coverage, API contract tests, and Playwright tests for the user-visible browser flows it introduces.

See the [full implementation plan](implementation-plan.md) for a checked inventory of implemented work, remaining production phases, and release criteria.
