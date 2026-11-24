# Open POS

Open POS is an open source point of sale project built with Flutter and Dart. The register is designed to run on phones, desktop computers, and the web. Sales are written to the device's local SQLite database before sync is attempted, so checkout can continue while the hub is offline.

The current implementation covers register checkout, offline sale and inventory queues, register-specific cash shifts, tax and sale discounts, customer and loyalty records, returns and voids, printable receipts, product modifiers, supplier records, purchase orders, and partial stock receiving. Tendering currently supports cash through a payment-provider boundary; payment terminals and multi-store tenancy remain follow-on work.

## Current features

- Responsive Flutter checkout screen for web, Android, iOS, Windows, macOS, and Linux targets.
- Cash checkout with centavo-safe integer arithmetic and change calculation.
- Local SQLite persistence through Drift. Flutter Web uses the included SQLite WASM module and Drift worker.
- Durable pending-sync queues. Offline sales and stock operations remain on the register until accepted by the hub; rejected stock operations are marked as conflicts and can be retried or discarded by a manager.
- A versioned sync event feed with independent register cursors, bounded page reads, explicit acknowledgements, and exponential retry backoff.
- First-run setup creates one store and its first administrator for each hub deployment. New stores start with an empty catalog. Administrators can create manager and cashier accounts; the server enforces role permissions and temporarily locks repeated failed sign-ins.
- Administrators and managers can create, edit, and archive catalog items with categories, prices, SKUs, and barcodes. Product edits queue locally while offline; the hub applies them idempotently against an expected version. Managers can keep their edit or use the hub version after a conflict.
- Administrators and managers can create, archive, and restore category records. Category snapshots sync to every register and remain cached for offline product editing; categories in use by active products cannot be archived.
- Products can define required or optional modifier groups with per-option price adjustments. Checkout saves the product version and selected options on each sale line; the hub verifies them before accepting offline sales.
- Inventory records receiving, signed adjustments, and transfers between named stock locations. Managers can set low-stock thresholds and review movement history. Cached balances include queued offline stock operations and unsynced sales; the hub applies accepted changes once.
- Managers can maintain suppliers and create, place, or cancel purchase orders. Partial receipts atomically update ordered quantities and inventory, and repeated receipt IDs do not receive stock twice. Supplier and order snapshots remain available for offline viewing; purchasing changes require a connection to the hub.
- Each enrolled register has its own active cash shift. Shifts track opening float, paid-in/out, expected cash, counted cash, and variance. The register caches its identity and active shift so offline sales remain linked and are reconciled after sync.
- Managers can configure exclusive or inclusive tax. Each sale stores a versioned tax snapshot so queued sales keep the configured rate used at checkout. Managers can also apply reasoned flat discounts.
- Customer records include optional phone and email details and a points balance. The loyalty program has versioned earn and redemption rules; sale retries do not award or spend points twice.
- Managers can partially return sold quantities, choose whether returned products go back into stock, and issue cash refunds from an open register shift. Voids restore sale quantities and cash, and are blocked after a return. Recent sales show return and void status.
- Manager reports summarize UTC sales, discounts, tax, refunds, voids, daily totals, top products, cash movements, and register shifts for ranges up to 366 days.
- Payment capture and refund state are stored separately from sales. The current cash provider records captures, partial refunds, and voids; payment terminal integrations are not included yet.
- Checkout creates an itemized receipt preview and can send it to the platform print dialog as a PDF.
- Audit events record store setup, sign-ins, staff and catalog changes, accepted sales, tax and loyalty settings, customer edits, and inventory and sale operations. Administrators can read recent audit records through the API.
- Dart Shelf API with SQLite storage, liveness and authenticated operational health endpoints, bearer-token sessions, idempotent sale/payment/catalog sync, duplicate ID conflict detection, payload validation, and configurable CORS origins.
- Maintenance commands create validated plain or encrypted SQLite backups, verify and restore encrypted backups with an automatic pre-restore recovery copy, prune old backups, and prune only sync events acknowledged by every register. Audit records are retained.
- Versioned SQLite schema epochs, explicit migration command, database readiness probe, secure response headers, and graceful hub shutdown.
- Cloud host Compose profile with a required durable per-store mount and exact HTTPS origin; hub and register containers run without root privileges.
- Docker images and Compose configuration for a self-hosted web register and hub.
- Dart unit, hub API, repository, and Flutter widget tests. Playwright browser tests cover the web register.

## Run locally

Install the Flutter SDK (which includes Dart), then open two terminals.

Start the hub from the repository root:

```powershell
cd apps/hub
$env:PORT = '8080'
$env:POS_HUB_DATABASE = "$PWD/pos_hub.sqlite"
dart run bin/server.dart
```

Start the register in another terminal:

```powershell
cd apps/register
flutter pub get
flutter run -d chrome --web-port 5000 --dart-define=POS_HUB_URL=http://127.0.0.1:8080
```

The Docker Compose web register uses its same-origin `/api/` proxy. When running Flutter's development server directly, set `POS_HUB_URL` to the hub address as shown above. For a phone or native desktop client, use an address reachable from that device, for example `--dart-define=POS_HUB_URL=http://192.168.1.20:8080`.

## Run a native register

Install the Flutter platform tools for the target device, start the hub as shown above, then run from `apps/register`:

```sh
flutter devices
flutter run -d windows --dart-define=POS_HUB_URL=http://127.0.0.1:8080
```

For an Android emulator, use the host's emulator gateway as the hub address (commonly `10.0.2.2:8080`). For a physical phone, use the computer's LAN address and publish the hub port on the LAN; the default Compose port is loopback-only. Configure `POS_ALLOWED_ORIGINS` for browser clients hosted at a different origin. Native clients still require a reachable hub address, sign-in, and valid TLS for networks outside a trusted development LAN.

Flutter's Windows target requires Visual Studio's Desktop development with C++ workload. Android builds require Android Studio and its SDK. macOS and iOS builds require macOS and Xcode. The Flutter source is shared across these targets; platform packaging, signing, and peripheral certification are deployment-specific.

To run the server with a non-default web origin, set `POS_ALLOWED_ORIGINS` to a comma-separated list of exact origins such as `http://localhost:5000,http://127.0.0.1:5000`.

## Self-host with Docker Compose

Docker Compose serves the Flutter Web register on port 8081, proxies its API requests to the hub, and stores hub sales in a named volume.

```sh
docker compose up --build -d
```

Open `http://localhost:8081` and complete the first-run form. The hub creates one store and its first administrator. Data (including accounts, catalog, suppliers, purchase orders and receipts, audit log, inventory, registers, shifts, tax and loyalty history, customers, returns, payment records, and sales) is stored in the `open-pos-hub-data` volume. Back up that volume as part of the deployment. Use HTTPS through a TLS-terminating reverse proxy whenever the hub is reachable beyond localhost. CORS limits browser origins; it does not replace authentication or transport encryption.

Create a named backup while the hub is running:

```sh
docker compose exec hub /maintenance/bin/maintenance backup \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite
docker compose exec hub /maintenance/bin/maintenance prune-backups /data/backups 30
```

Generate a 256-bit backup key once and store it in a password manager or secret manager outside this repository and the backup storage. The encrypted export uses AES-256-GCM; the live database remains unencrypted.

```sh
docker compose exec -T hub /maintenance/bin/maintenance generate-backup-key
export POS_BACKUP_KEY_BASE64='<load the stored key from your secret manager>'
docker compose exec -T -e POS_BACKUP_KEY_BASE64 hub \
  /maintenance/bin/maintenance backup-encrypted \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite.enc
docker compose exec -T -e POS_BACKUP_KEY_BASE64 hub \
  /maintenance/bin/maintenance verify-encrypted \
  /data/backups/open-pos-2026-11-23.sqlite.enc
docker compose exec hub /maintenance/bin/maintenance prune-backups /data/backups 30
```

For scheduled off-site backups, configure an [rclone remote](https://rclone.org/) for the host account that runs the job. Copy the environment template to the ignored `.env.backup` file, set the generated key and remote, and restrict the file to the deployment administrator:

```sh
cp ops/backup/open-pos-backup.env.example .env.backup
chmod 600 .env.backup
# Edit .env.backup and set POS_BACKUP_KEY_BASE64 from your secret manager.
```

Set `OPEN_POS_BACKUP_REMOTE` to the configured rclone destination, such as `archive:open-pos/store-001`. For the cloud Compose profile, set `OPEN_POS_COMPOSE_FILE=docker-compose.cloud.yml` and `OPEN_POS_COMPOSE_ENV_FILE=.env.cloud` in `.env.backup`. Run it manually with Bash:

```sh
OPEN_POS_BACKUP_ENV_FILE=.env.backup bash ops/backup/open-pos-backup.sh
```

Or from PowerShell:

```powershell
.\ops\backup\open-pos-backup.ps1
```

For daily Linux scheduling, add this line to the host's crontab:

```cron
0 2 * * * cd /srv/open-pos && OPEN_POS_BACKUP_ENV_FILE=.env.backup bash ops/backup/open-pos-backup.sh >> /var/log/open-pos-backup.log 2>&1
```

On Windows, configure Task Scheduler to run `powershell.exe -File <project-path>\ops\backup\open-pos-backup.ps1` daily. The script reads the same `.env.backup` file; restrict its ACL to the account that runs the task. Make sure the scheduled account has access to Docker, rclone, and its configured remote.

The script creates and verifies the encrypted snapshot, copies only the encrypted file to rclone, checks the remote bytes, and prunes local backups only after remote verification succeeds. Configure remote retention with the storage provider. The file embeds a short key fingerprint; the original key is required to verify or restore it.

Restore only after stopping the hub so its database file can be replaced:

```sh
docker compose stop hub
docker compose run --rm --no-deps -e POS_BACKUP_KEY_BASE64 \
  --entrypoint /maintenance/bin/maintenance hub restore-encrypted \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite.enc --force
docker compose start hub
```

For an unencrypted SQLite backup, use the plain `restore` command with the same explicit maintenance entrypoint:

```sh
docker compose stop hub
docker compose run --rm --no-deps \
  --entrypoint /maintenance/bin/maintenance hub restore \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite --force
docker compose start hub
```

The restore command validates the backup and creates a timestamped pre-restore recovery copy. The host scripts schedule encrypted off-site backups and local retention. `GET /api/v1/operations/health` reports database integrity and sync backlog to administrators.

The same hub image can run in a cloud container service with a persistent volume mounted at `/data`. The Flutter Web image can be hosted as static content behind a reverse proxy that forwards `/api/` to the hub. Each hub deployment is a single-store boundary; a business with multiple stores currently runs separate hub deployments. The Compose hub port is bound to loopback at `127.0.0.1:8080` for native clients on the same host. LAN clients need an explicit port mapping and an address reachable from the device. Register sessions and operational snapshots are retained locally so checkout can continue while the hub is temporarily offline.

### Cloud host profile

For a single-store cloud host with durable local block storage, copy `.env.cloud.example` to `.env.cloud`, set the HTTPS origin and persistent data path, and create the path writable by container UID `65532`:

```sh
cp .env.cloud.example .env.cloud
sudo mkdir -p /var/lib/open-pos/store-001
sudo chown 65532:65532 /var/lib/open-pos/store-001
docker compose --env-file .env.cloud -f docker-compose.cloud.yml up --build -d
```

The web container is published on host loopback for a TLS reverse proxy. It forwards `/api/` to the hub over a private Docker network. Native clients can use the same HTTPS origin as their hub URL. Use a separate deployment and data directory for each store. Do not run multiple hub replicas against the SQLite database or place it on a shared network filesystem. This is a cloud host profile, not a shared SaaS tenant or billing control plane; see the [security threat model](docs/security.md) and [roadmap](docs/roadmap.md).

## Tests and analysis

Run the Dart domain tests:

```sh
cd packages/pos_domain && dart test
```

Run the hub API tests and analysis:

```sh
cd apps/hub && dart test && dart analyze
```

For a controlled schema upgrade, back up the database, stop the hub, and run the migration command before restarting:

```sh
docker compose exec hub /maintenance/bin/maintenance backup \
  /data/open_pos.sqlite /data/backups/open-pos-before-upgrade.sqlite
docker compose stop hub
docker compose run --rm --no-deps \
  --entrypoint /maintenance/bin/maintenance hub migrate \
  /data/open_pos.sqlite
docker compose start hub
```

Run register widget/repository tests and analysis:

```sh
cd apps/register && flutter test && flutter analyze
```

Run browser tests after installing Node.js dependencies and the Playwright Chromium browser:

```sh
cd apps/register
npm ci
npx playwright install chromium
npm run test:e2e
```

The `Native artifacts` workflow builds Android, Windows, Linux, macOS, and iOS artifacts on a `v*` tag or manual dispatch. Android signing is optional and uses the `OPEN_POS_ANDROID_KEYSTORE_BASE64`, `OPEN_POS_ANDROID_KEYSTORE_PASSWORD`, `OPEN_POS_ANDROID_KEY_ALIAS`, and `OPEN_POS_ANDROID_KEY_PASSWORD` repository secrets. iOS, macOS, Windows, and Linux artifacts remain unsigned; the workflow does not submit packages to app stores.

## Architecture and next phases

See [docs/architecture.md](docs/architecture.md), [docs/roadmap.md](docs/roadmap.md), and the [full implementation plan](docs/implementation-plan.md) for project boundaries, sync direction, implemented capabilities, and remaining work.

## License

Open POS is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE). Third-party assets are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
