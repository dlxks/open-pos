#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/../.." && pwd)"

if [[ -n "${OPEN_POS_BACKUP_ENV_FILE:-}" ]]; then
  backup_env_file="$OPEN_POS_BACKUP_ENV_FILE"
  if [[ "$backup_env_file" != /* ]]; then
    backup_env_file="$project_root/$backup_env_file"
  fi
  if [[ ! -f "$backup_env_file" || ! -r "$backup_env_file" ]]; then
    printf 'Backup environment file is missing or unreadable.\n' >&2
    exit 1
  fi
  set -a
  # shellcheck source=/dev/null
  . "$backup_env_file"
  set +a
fi

: "${POS_BACKUP_KEY_BASE64:?Load POS_BACKUP_KEY_BASE64 from a secret manager or protected env file}"
: "${OPEN_POS_BACKUP_REMOTE:?Set an rclone remote directory for off-site backups}"

compose_file="${OPEN_POS_COMPOSE_FILE:-docker-compose.yml}"
if [[ "$compose_file" != /* ]]; then
  compose_file="$project_root/$compose_file"
fi
if [[ ! -f "$compose_file" ]]; then
  printf 'Compose file does not exist: %s\n' "$compose_file" >&2
  exit 1
fi

compose_env_args=()
if [[ -n "${OPEN_POS_COMPOSE_ENV_FILE:-}" ]]; then
  compose_env_file="$OPEN_POS_COMPOSE_ENV_FILE"
  if [[ "$compose_env_file" != /* ]]; then
    compose_env_file="$project_root/$compose_env_file"
  fi
  if [[ ! -f "$compose_env_file" ]]; then
    printf 'Compose env file does not exist: %s\n' "$compose_env_file" >&2
    exit 1
  fi
  compose_env_args=(--env-file "$compose_env_file")
fi

compose() {
  docker compose "${compose_env_args[@]}" -f "$compose_file" "$@"
}

for command_name in docker rclone; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is not installed: %s\n' "$command_name" >&2
    exit 1
  fi
done

keep_local="${OPEN_POS_BACKUP_KEEP_LOCAL:-30}"
if [[ ! "$keep_local" =~ ^[1-9][0-9]*$ ]]; then
  printf 'OPEN_POS_BACKUP_KEEP_LOCAL must be a positive integer.\n' >&2
  exit 1
fi

backup_name="open-pos-$(date -u +%Y%m%dT%H%M%SZ)-$$.sqlite.enc"
container_backup="/data/backups/$backup_name"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-pos-backup.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT

compose exec -T -e POS_BACKUP_KEY_BASE64 hub \
  /maintenance/bin/maintenance backup-encrypted \
  /data/open_pos.sqlite "$container_backup"
compose exec -T -e POS_BACKUP_KEY_BASE64 hub \
  /maintenance/bin/maintenance verify-encrypted "$container_backup"

staged_backup="$staging_dir/$backup_name"
compose cp "hub:$container_backup" "$staged_backup"

remote_dir="${OPEN_POS_BACKUP_REMOTE%/}"
remote_backup="$remote_dir/$backup_name"
rclone copyto --immutable "$staged_backup" "$remote_backup"
rclone check --download --one-way "$staging_dir" "$remote_dir" \
  --include "$backup_name"

compose exec -T hub /maintenance/bin/maintenance prune-backups \
  /data/backups "$keep_local"
printf 'Encrypted backup verified off-site: %s\n' "$remote_backup"
