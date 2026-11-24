# Open POS Hub

The Dart Shelf API handles first-run store setup, staff authentication, register
enrollment, versioned catalog and pricing configuration, inventory, customer
loyalty, register-specific cash shifts, sale sync, returns, voids, and audit
events. Each deployment currently serves one store and one hub database.

## Run locally

```sh
dart pub get
dart run bin/server.dart
```

The server listens on port `8080` by default. Set `PORT` to change it and
`POS_HUB_DATABASE` to select the SQLite file (defaults to `pos_hub.sqlite`).
The first register connected to the hub will show the store setup form.

## API areas

- `GET /health`
- `GET /health/ready` (SQLite quick check and supported schema version)
- `GET /api/v1/setup/status` and `POST /api/v1/setup`
- `POST /api/v1/auth/login`, `POST /api/v1/auth/logout`, and `GET /api/v1/auth/me`
- `POST /api/v1/registers` (register enrollment)
- `GET /api/v1/sync/events` and `POST /api/v1/sync/ack` (per-register change cursors)
- `GET /api/v1/tax`, `PUT /api/v1/tax`, `GET /api/v1/loyalty/settings`, and `PUT /api/v1/loyalty/settings` (manager/admin)
- `GET /api/v1/categories`, `POST /api/v1/categories`, and `PUT /api/v1/categories/:id` (manager/admin writes)
- `GET /api/v1/customers`, `POST /api/v1/customers`, and `PUT /api/v1/customers/:id`
- `GET /api/v1/products`, `POST /api/v1/products`, and `PUT /api/v1/products/:id`
- `POST /api/v1/catalog/operations` (idempotent, version-checked catalog outbox)
- `GET /api/v1/users` and `POST /api/v1/users` (administrator only)
- `GET /api/v1/audit` (administrator only)
- `GET /api/v1/inventory`, `GET /api/v1/inventory/movements`, and `POST /api/v1/inventory/movements`
- `PUT /api/v1/inventory/items/:id/threshold` (manager/admin)
- `GET /api/v1/shifts/current`, `POST /api/v1/shifts`, `GET /api/v1/shifts/:id`, and shift cash-movement/close actions
- `POST /api/v1/sales`, `GET /api/v1/sales`, `GET /api/v1/sales/:id`, and `POST /api/v1/sales/:id/void`
- `POST /api/v1/sales/:id/payments` and `GET /api/v1/sales/:id/payment` (payment state is separate from the sale)
- `POST /api/v1/returns`
- `GET /api/v1/operations/health` (administrator only)

## Backups and retention

The maintenance executable is included in the hub container. A backup uses SQLite's online backup API:

```sh
docker compose exec hub /maintenance/bin/maintenance backup \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite
docker compose exec hub /maintenance/bin/maintenance prune-backups /data/backups 30
docker compose exec hub /maintenance/bin/maintenance prune-sync-events \
  /data/open_pos.sqlite 90
```

Generate and protect a 32-byte key outside the repository and backup storage. Encrypted exports use AES-256-GCM in authenticated chunks; only the exported backup is encrypted, not the live SQLite database:

```sh
docker compose exec -T hub /maintenance/bin/maintenance generate-backup-key
export POS_BACKUP_KEY_BASE64='<load the stored key from your secret manager>'
docker compose exec -T -e POS_BACKUP_KEY_BASE64 hub \
  /maintenance/bin/maintenance backup-encrypted \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite.enc
docker compose exec -T -e POS_BACKUP_KEY_BASE64 hub \
  /maintenance/bin/maintenance verify-encrypted \
  /data/backups/open-pos-2026-11-23.sqlite.enc
```

The encrypted file includes a key fingerprint for selecting the matching secret. Losing the key makes that backup unrecoverable. The repository's Bash and PowerShell automation scripts schedule from the host and send verified encrypted files to a configured rclone destination.

Restore after stopping the hub. Both restore commands validate the backup and write a pre-restore recovery copy before replacing the database:

```sh
docker compose stop hub
docker compose run --rm --no-deps -e POS_BACKUP_KEY_BASE64 \
  --entrypoint /maintenance/bin/maintenance hub restore-encrypted \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite.enc --force
docker compose start hub
```

For a plain SQLite backup, run:

```sh
docker compose stop hub
docker compose run --rm --no-deps \
  --entrypoint /maintenance/bin/maintenance hub restore \
  /data/open_pos.sqlite /data/backups/open-pos-2026-11-23.sqlite --force
docker compose start hub
```

Sync-event pruning removes only events acknowledged by every registered device and older than the selected retention window. It never deletes audit records. The repository's [Bash and PowerShell backup scripts](../../ops/backup/) create encrypted exports, copy and verify them through a configured rclone remote, then prune local backups. Configure a host schedule, external key storage, and remote retention; the scripts do not provision an object-storage account.

The hub records its schema epoch in SQLite `PRAGMA user_version`, applies compatible idempotent upgrades, and refuses a database from a newer server. For a controlled upgrade, stop the service after taking a backup, then run `docker compose run --rm --no-deps --entrypoint /maintenance/bin/maintenance hub migrate /data/open_pos.sqlite` and restart the hub. The self-hosted Compose profile fixes ownership of its named data volume before the hub starts, including volumes created by older root-running images.

Protected routes require an `Authorization: Bearer <token>` header. Keep the
SQLite data volume backed up and put a TLS-terminating reverse proxy in front
of any network-accessible deployment. The hub binds to all interfaces in its
container; Compose publishes it on host loopback by default.

See the root [README](../../README.md) for Flutter register and Docker Compose
instructions.

The cloud host profile is `docker-compose.cloud.yml`; it requires a durable bind mount, an exact HTTPS browser origin, and host-side TLS termination. Both application containers run as unprivileged users. See the [security threat model](../../docs/security.md) before exposing a deployment.
