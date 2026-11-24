# Open POS: Full Implementation Plan

**Updated:** 2026-11-25  
**Project stack:** Flutter and Dart for the register and hub; SQLite locally and on a single-store hub; Playwright with TypeScript only for browser automation.

This document combines the implemented work with the remaining roadmap for an open-source, offline-capable POS that can be self-hosted per store or deployed on a cloud host. The register remains one Flutter application for web, Android, iOS, Windows, macOS, and Linux. The production application stays in Dart; the TypeScript code is test tooling, not a second register implementation.

## Checklist key

- `[x]` Implemented in the current repository.
- `[ ]` Remaining work. Items marked **Partial** have a working foundation but do not meet the full production scope described here.
- **P0** Required for a dependable advanced general-purpose retail release.
- **P1** Important for multi-store operations, larger deployments, and operational completeness.
- **P2** Optional vertical or provider-specific expansion.

“Implemented” means there is code in the repository. It does not imply that every platform is signed, certified, or ready for public app-store release.

## Current implementation

### Phase 1: Register checkout and offline sale sync — implemented core

- [x] Responsive Flutter register with product search, cart, cash tender, and change calculation.
- [x] Persist sales locally before attempting network sync.
- [x] Retry queued sales with stable IDs; the hub accepts identical retries once and rejects conflicting reuse.
- [x] Run a self-hosted web register and hub with Docker Compose.
- [x] Cover core behavior with domain, Flutter, hub API, and browser tests.

### Phase 2: Store setup, users, and catalog — implemented core

- [x] First-run setup creates a single store and its first administrator.
- [x] Admin, manager, and cashier accounts, role checks, bearer sessions, and repeated sign-in lockout.
- [x] Product create/edit/archive with categories, SKU, barcode, price, and product versions.
- [x] Versioned catalog snapshots and offline product caching.
- [x] Offline catalog edit queue with version conflict handling.
- [x] Managed categories with archive/restore, audit history, and sync to registers.
- [x] Required/optional product modifier groups with sale-time price and product snapshots.
- [x] Versioned tax setting with exclusive/inclusive calculation and tax snapshots on sales.
- [x] Audit events for core setup, staff, catalog, sales, inventory, and settings changes.
- [ ] **Partial:** a hub deployment is one store. Shared-hub multi-store access and consolidated catalogs are not implemented.

### Phase 3: Inventory and store operations — implemented core

- [x] Inventory balances by named location and an idempotent movement ledger.
- [x] Receive, adjust, and transfer stock; set low-stock thresholds and inspect movement history.
- [x] Queue offline stock movements and overlay pending movements and unsynced sales in cached balances.
- [x] Expose stock conflicts and allow managers to retry or discard rejected movements.
- [x] Register enrollment and one active cash drawer shift per register.
- [x] Opening float, paid-in/out, linked sales, closing count, and cash variance.
- [x] Reconcile shifts when offline sales sync after close.
- [ ] **Partial:** stock counts, purchase planning, costing/valuation, and vendor returns need fuller workflows; see Phases 10 and 13.

### Phase 4: Sync, customer records, and payment boundary — implemented foundation

- [x] Versioned sync event feed with per-register cursors, pagination, acknowledgements, and retry backoff.
- [x] Separate local/server records for sale and payment state, with a `PaymentProvider` interface and cash provider.
- [x] Customer records and versioned loyalty earn/redeem settings.
- [x] Sale history, item-level partial returns, optional return restocking, manager-only voids, and cash refunds from an open shift.
- [x] Loyalty adjustments on accepted sales, returns, and voids.
- [x] Itemized receipt preview and platform print dialog PDF output.
- [ ] **Partial:** non-cash tenders, terminal integrations, exchanges, store credit, and offline return/refund policies remain incomplete; see Phases 12 and 14.

### Phase 5: Self-hosted and cloud-host deployment — implemented foundation

- [x] Self-hosted Compose deployment serves the Flutter Web register and Dart hub with durable SQLite storage.
- [x] Single-store cloud-host Compose profile uses a required persistent mount, private hub network, exact HTTPS browser origin, and loopback web publication for TLS termination.
- [x] Liveness/readiness checks, secure response headers, unprivileged application containers, schema epochs, controlled migrations, and graceful hub shutdown.
- [x] CI formats, analyzes, tests, builds the web app, runs browser tests, and builds self-hosted images.
- [x] Workflow can package Android, Windows, Linux, macOS, and iOS artifacts.
- [ ] **Partial:** Android signing is optional; the other native artifacts are unsigned. App-store submission, notarization, release upgrade validation, and device certification remain.
- [ ] **Partial:** cloud deployment is an independently deployed single-store hub, not shared SaaS tenancy or a cloud control plane.

### Phase 6: Backup and recovery — implemented foundation

- [x] Plain SQLite backup, verification, and restore with pre-restore recovery copy.
- [x] Chunked AES-256-GCM encrypted exports, integrity verification, encrypted restore, and backup retention.
- [x] Bash and PowerShell backup scripts can transfer encrypted files with rclone and verify remote bytes before pruning local files.
- [ ] **Partial:** operators still configure scheduling, key management/rotation, remote retention, and regular restore drills.

### Phase 7: Managed categories — implemented

- [x] Admins and managers create/archive/restore categories; names are case-insensitive and changes are audited and synced.
- [x] Offline category snapshots and safe archive checks for categories assigned to active products.
- [ ] Category-specific tax, category ordering/color, and multi-store category ownership remain future work.

### Phase 8: Manager sales reports — implemented core

- [x] Admins and managers can query a selected UTC date range for sales, discounts, tax, refunds, voids, top products, cash movements, and shift reconciliation.
- [x] Validate dates, cap ranges at 366 days, limit detailed shifts, and report truncation.
- [ ] CSV/PDF exports, richer report filters, cost/margin reporting, scheduled delivery, and cross-store consolidation remain.

### Phase 9: Suppliers and purchase orders — implemented core

- [x] Admins and managers create/edit/archive/restore suppliers with version checks and audit events.
- [x] Create purchase order drafts, place and cancel eligible orders, and receive full or partial quantities by location.
- [x] Commit receipt records, received quantities, stock balances, inventory movements, and audit events atomically.
- [x] Stable receipt IDs make retries idempotent; conflicting reuse and over-receiving are rejected.
- [x] Cache supplier and order snapshots for offline viewing.
- [ ] **Partial:** supplier and purchase order changes require a live hub connection; there is no offline purchasing outbox, supplier invoice matching, or vendor return workflow.

## Remaining implementation phases

### Phase 10: Offline-first completion and sync operations — P0

- [ ] Add stable-ID outboxes for supported manager mutations that should work offline, starting with supplier and purchase order drafts/receipts; explicitly identify actions that must remain online-only.
- [ ] Define conflict rules for purchase orders, suppliers, customers, inventory counts, and settings. Show server/local values and provide manager resolution where safe.
- [ ] Refresh and cache the operational snapshots needed to start and continue a register session offline, with visible age and last successful sync.
- [ ] Add sync status for each queue item: pending, retrying, accepted, conflict, and action required; support safe retry and discard actions.
- [ ] Test interrupted sync, duplicate delivery, out-of-order events, cursor recovery, hub restart, clock/time-zone differences, and app restart while offline.
- [ ] Set retention and compaction rules for local queues and sync events without deleting unacknowledged work or audit evidence.
- [ ] Assess local database encryption, key storage, device logout/lock behavior, and recovery on each target platform.

**Exit criteria:** a register can restart without a network, complete supported work locally, and reconcile it once when the hub returns; conflicting changes are visible and recoverable.

### Phase 11: Advanced catalog, pricing, tax, and promotions — P0

- [ ] Add product variants with their own SKU/barcode/price/stock; retain current modifier support for selectable options.
- [ ] Add units of measure and weighed/barcoded goods with tested rounding rules.
- [ ] Add bundles/kits and define whether component stock is consumed at sale time.
- [ ] Support multiple tax classes/rules, exemptions, inclusive/exclusive combinations, and historical tax snapshots per line.
- [ ] Add price lists, scheduled prices, customer-specific pricing, and audited manager overrides.
- [ ] Add promotion rules such as coupons, buy-X-get-Y, fixed/percent discounts, eligibility limits, and stacking rules.
- [ ] Add safe bulk catalog import/export and bulk edit with validation preview and rollback/error reporting.
- [ ] Add product image handling with size limits and an offline cache policy.

**Exit criteria:** catalog, tax, and promotion calculations are deterministic, stored as sale snapshots, and validated by the hub against the applicable version.

### Phase 12: Tendering, payments, and devices — P0

- [ ] Extend the provider boundary for card, contactless, QR, and locally relevant payment methods without storing payment card data in Open POS.
- [ ] Support split/mixed tender and partial payment according to the selected store policy.
- [ ] Implement provider-specific capture, authorization, reversal, refund, timeout, duplicate callback, and reconciliation behavior.
- [ ] Integrate at least one supported card terminal and document the exact certified devices, countries, and provider constraints.
- [ ] Add cash drawer, receipt printer, barcode scanner, customer display, and supported scale adapters where the platform permits.
- [ ] Support receipt templates, reprints, store/legal details, and printer fallback to PDF/platform print.
- [ ] Build a provider test harness and sandbox-mode API tests; never use production credentials in CI.

**Exit criteria:** retries and terminal timeouts cannot double-charge; payment and sale states reconcile after app/hub/network interruptions; peripherals have a tested compatibility matrix.

### Phase 13: Inventory and procurement depth — P0/P1

- [ ] Edit or duplicate draft purchase orders and preserve supplier/product/cost snapshots after catalog changes.
- [ ] Add expected delivery tracking, backorders, partial supplier fulfillment, and closed/short receipt reasons.
- [ ] Add supplier price history, lead time, minimum order quantities, and reorder suggestions from sales/stock levels.
- [ ] Add purchase invoice matching to ordered and received quantities, with cost variance review.
- [ ] Add stocktake/cycle-count workflows with blind counts, variance approval, and audited adjustments.
- [ ] Add vendor returns and write-off/damage reasons with inventory movements.
- [ ] Define item-cost and stock-valuation rules; expose cost of goods and gross margin only when source data is reliable.
- [ ] Add serial/lot/expiry tracking if required by the target businesses; keep it optional for stores that do not need it.

**Exit criteria:** stock quantities and purchase costs reconcile across sales, receipts, returns, counts, and adjustments with an auditable movement history.

### Phase 14: Customer retention, exchanges, and stored value — P1

- [ ] Add customer search, deduplication, merge policy, consent/retention controls, and export/delete workflows required by deployment jurisdictions.
- [ ] Extend loyalty to configurable tiers/rewards, expiry, redemption constraints, and manager correction with an audit trail.
- [ ] Add gift cards and store credit with secure balances, partial redemption, refunds, expiry policy, and idempotent ledger entries.
- [ ] Add exchanges that link return and replacement lines and handle price differences as tender or store credit.
- [ ] Add promotion/customer eligibility and receipt lookup without exposing customer data to unauthorized roles.
- [ ] Define offline behavior for loyalty, stored value, and customer changes so cached balances cannot be spent twice across devices.

### Phase 15: Staff permissions and daily controls — P1

- [ ] Add granular permissions and role templates while retaining admin/manager/cashier defaults.
- [ ] Add configurable approval requirements for discounts, refunds, voids, cash movements, price overrides, and stock adjustments.
- [ ] Add shift assignment and operational handoff controls across registers.
- [ ] Add staff activity and exception reports from auditable events.
- [ ] Add time/attendance only if it is in scope; keep payroll calculations outside the POS unless a separate payroll requirement is agreed.
- [ ] Add MFA, administrator recovery, session revocation, and stronger login rate limits for network deployments.

### Phase 16: Reporting, exports, and accounting — P1

- [ ] Add filters by store/register/user/category/payment type/product and local business day while retaining UTC event timestamps.
- [ ] Add sales, returns, tax, tender settlement, cash drawer, inventory movement, purchase, shrinkage, loyalty, and margin reports.
- [ ] Add CSV exports and printable/PDF report output with permission checks and export audit events.
- [ ] Add accounting exports and documented mapping for supported accounting systems; keep integrations optional.
- [ ] Add scheduled reports only after secure delivery, permissions, retention, and operator configuration are defined.
- [ ] Test report totals against source ledger records, including voids, partial returns, refunds, late sync, and multiple time zones.

### Phase 17: Multi-store and shared-cloud option — P1

- [ ] Define store, organization, membership, register, and location boundaries before adding shared-hub tenant routing.
- [ ] Add store scoping to every business row, query, cache key, event, backup, and authorization decision; test cross-tenant isolation at the API and database levels.
- [ ] Support organization users with scoped roles and safe store switching; retain a separate independent deployment as the simplest self-host mode.
- [ ] Add store-level catalogs/prices/taxes/inventory with controlled organization-wide sharing where requested.
- [ ] Add organization-level reports with explicit time-zone and access rules.
- [ ] Design provisioning, domain/HTTPS, persistent storage, upgrade, backup/restore, quotas, and deletion for a shared cloud service.
- [ ] Reassess the hub storage topology and benchmark concurrent use before choosing a shared-cloud database. Keep the self-hosted single-store path documented and supportable.
- [ ] Treat billing, subscription management, and hosted control-plane features as optional service operations, not requirements for the open-source self-hosted product.

### Phase 18: Production release, platform quality, and operations — P0

- [ ] Add supported Flutter/Dart dependency and container scanning to CI; publish an SBOM and define vulnerability response/update policy.
- [ ] Complete security review and penetration testing for auth, tenant boundaries, sync validation, backups, and local device data.
- [ ] Add metrics, structured logs, alerting, sync backlog visibility, uptime targets, and documented incident response without leaking customer data.
- [ ] Configure and rehearse encrypted off-site backups, key rotation, retention, and restore drills for representative deployments.
- [ ] Automate database upgrade tests from supported older schema versions and publish upgrade/rollback instructions.
- [ ] Sign/notarize supported native artifacts and document store submission; keep release keys in protected secrets.
- [ ] Run a platform matrix for web, Android, iOS, Windows, macOS, and Linux, including offline restart, keyboard/scanner use, printing, and upgrade behavior.
- [ ] Complete accessibility, localization, currency/rounding, date/time-zone, and supported-region compliance reviews.
- [ ] Publish installation, upgrade, backup, restore, security, API, extension, and troubleshooting documentation for independent self-hosters.

### Phase 19: Optional vertical extensions — P2

- [ ] Decide whether the first supported vertical is general retail only or includes hospitality/food service.
- [ ] If hospitality is in scope, add tables/seating, open tickets, kitchen routing/display, coursing, tips, split checks, and kitchen-printer workflows.
- [ ] Keep vertical workflows modular so they do not complicate the general retail checkout for stores that do not use them.
- [ ] Add jurisdiction/provider-specific e-invoicing, fiscal printer, tax authority, and accounting integrations as optional adapters after requirements are identified.

## Cross-cutting test and release checklist

Apply this checklist to every new phase, not just at final release:

- [x] Dart domain unit tests cover money, tax, modifiers, sale/return calculations, and core model serialization.
- [x] Hub API/feature tests exercise auth, roles, validation, idempotency, inventory, shifts, reports, migrations, and recovery paths.
- [x] Flutter widget and repository tests cover checkout, local persistence, cached data, queues, and offline behavior.
- [x] Playwright tests cover the web register, manager flows, and a narrow 375-pixel layout.
- [ ] Add missing positive, negative, replay, stale-version, and permission tests with each new API mutation.
- [ ] Add UI tests for loading, empty, offline, stale-cache, conflict, and retry states for each new screen.
- [ ] Add native smoke automation and manual device/peripheral acceptance for supported Android/iOS/desktop builds.
- [ ] Add performance/load tests before supporting shared-hub or high-volume deployments.
- [ ] Make formatting, analysis, domain/API/Flutter/browser tests, web build, migration checks, and image build required release gates.

## Definition of a full advanced POS release

The project is ready to call a full advanced general-purpose POS release when the P0 phases have defined acceptance criteria and pass them; all supported deployments can be installed/upgraded/backed up/restored from the published instructions; supported tender and peripheral combinations are named and tested; queued offline work is recoverable and idempotent; and the release test matrix passes on every platform claimed as supported. Shared SaaS tenancy and vertical packs remain separately versioned scope so that they do not block an independently deployable self-hosted release.

## Related documents

- [Roadmap](roadmap.md)
- [Architecture](architecture.md)
- [Security and threat model](security.md)
- [Project README and run instructions](../README.md)
