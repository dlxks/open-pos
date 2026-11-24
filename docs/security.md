# Security and threat model

## Deployment boundary

The current hub is a single-store service backed by one SQLite database. Treat a deployment, its writable database volume, its allowed browser origins, and its register devices as one store boundary. The cloud host Compose profile uses a separate persistent data path per store and does not expose the hub port outside its Docker network. It is not a shared-hub multi-tenant SaaS design.

The main assets are staff credentials and sessions, customer contact and loyalty data, catalog and inventory history, sales and cash-shift records, payment status, and the audit log. Backups contain the same records and need protection equivalent to the live database.

## Trust boundaries and controls

- **Browser/native client to hub:** bearer-token authentication protects application routes; CORS permits only configured browser origins. CORS does not authenticate native clients or prevent non-browser requests. Network deployments need TLS at a reverse proxy.
- **Staff credentials:** passwords are derived with PBKDF2-HMAC-SHA256 using random per-user salts. The hub stores only password hashes. Opaque random session tokens are stored server-side as SHA-256 hashes and expire after 30 days. Repeated failures are locked by normalized email in the hub database.
- **Roles:** the hub checks admin, manager, and cashier permissions on protected operations. Operational health and audit retrieval are administrator-only.
- **Request input:** JSON bodies are read with route-specific size limits. Catalog versions, tax and loyalty snapshots, modifier options, operation IDs, and sale totals are validated by the hub before mutation.
- **Sync delivery:** sale, catalog, stock, payment, return, and sync-feed records use stable IDs or cursors for retry handling. A register's local queue remains mutable by a person with device access; hub validation limits catalog and calculation tampering but does not cryptographically attest the physical till's cash handling.
- **HTTP responses:** the hub sends no-store, content-type, frame, referrer, and content-security policy headers. The web register sends frame, referrer, content-type, and permissions-policy headers. TLS-only HSTS is left to the TLS-terminating proxy.
- **Containers:** the hub and register application images run as unprivileged users. The self-hosted profile uses a short-lived root init container to normalize ownership of the named database volume before the hub starts. The cloud profile instead requires its persistent host mount to be writable by UID `65532`.

## Operational safeguards

1. Terminate HTTPS before serving any non-local network client. Set `POS_ALLOWED_ORIGINS` to exact HTTPS origins; do not use `*`.
2. Give each store a separate hub deployment and persistent volume. Do not share the SQLite file over NFS/SMB or run multiple hub replicas against it.
3. Restrict access to `/data` and backup destinations. Use `backup-encrypted` for AES-256-GCM exports, keep the 32-byte key in a separate secret manager, and test `verify-encrypted` and restore procedures. The live database remains unencrypted; configure and schedule the backup script to transfer encrypted files to independent off-host storage.
4. Keep Docker, Flutter/Dart, operating system, and dependency updates under review. The current CI checks tests and image builds but does not perform dependency, container, or static security scanning.
5. Protect release signing keys as repository secrets. Never use the Android debug key for releases. Apple and desktop signing are not configured by this project.
6. Use `/health/ready` for database readiness and `/health` for process liveness. The authenticated operations endpoint provides sync backlog and database diagnostics; it is not a metrics exporter or alerting system.

## Known gaps

- No MFA, administrator recovery workflow, IP-based login throttling, or tenant billing/quota service.
- Login throttling is per email and stored in the local database; it does not coordinate across replicas.
- Register SQLite data is not encrypted by the application. Use operating-system disk encryption, device access controls, and remote device-management policies.
- Cash is the only payment provider. The application does not store card numbers or terminal credentials.
- Host scheduler setup, rclone provider configuration and remote retention, external key management, intrusion monitoring, penetration testing, and disaster recovery exercises remain deployment responsibilities. Losing an encrypted backup key makes its backup unrecoverable.
- The native artifact workflow can sign Android only when configured with a keystore. iOS, macOS, Windows, and Linux artifacts are unsigned and cannot be submitted to app stores as-is.
