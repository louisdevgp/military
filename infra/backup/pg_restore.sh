#!/usr/bin/env bash
# Restores an encrypted export into an EMPTY database only (never over an
# existing one: create a new database, restore, check, then switch).
# Usage: TARGET_DATABASE_URL=... BACKUP_PASSPHRASE=... ./pg_restore.sh <file.pgc.gpg>
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL manquant}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE manquant}"
file="${1:?fichier .pgc.gpg manquant}"
dir="$(dirname "$file")"
if [ -f "$dir/SHA256SUMS" ]; then
  # "hash  name" (Linux) or "hash *name" (binary mode, Windows).
  (cd "$dir" && grep -E "[ *]$(basename "$file")\$" SHA256SUMS | sha256sum --check --quiet)
fi
tables="$(psql --dbname="$TARGET_DATABASE_URL" --tuples-only --no-align \
  --command="select count(*) from information_schema.tables where table_schema = 'public'")"
if [ "$tables" != "0" ]; then
  echo "Base cible non vide ($tables tables) : restauration refusée." >&2
  exit 3
fi
plain="$(mktemp)"
trap 'rm -f "$plain"' EXIT
gpg --batch --yes --quiet --pinentry-mode loopback --decrypt \
  --passphrase-fd 3 --output "$plain" "$file" 3<<<"$BACKUP_PASSPHRASE"
# The target was checked empty above: replacing its empty public schema is safe.
pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error \
  --dbname="$TARGET_DATABASE_URL" "$plain"
psql --dbname="$TARGET_DATABASE_URL" --tuples-only --no-align \
  --command="select version_num from alembic_version"
echo "Restauration terminée."
