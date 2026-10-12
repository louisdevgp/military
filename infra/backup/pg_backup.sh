#!/usr/bin/env bash
# Encrypted export of the application schema (public) of the server database.
# Usage: DATABASE_URL=... BACKUP_PASSPHRASE=... ./pg_backup.sh <output-dir>
# Neither the URL nor the passphrase is ever printed.
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL manquant}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE manquant}"
if [ "${#BACKUP_PASSPHRASE}" -lt 20 ]; then
  echo "Mot de passe de sauvegarde : 20 caractères minimum." >&2
  exit 2
fi
out="${1:-.}"
mkdir -p "$out"
stamp="$(date -u +%Y%m%d-%H%M%S)"
plain="$(mktemp)"
trap 'rm -f "$plain"' EXIT
# Custom format: compressed, restorable table by table; no owner or grants so
# that it restores into any empty database.
pg_dump --format=custom --schema=public --no-owner --no-privileges \
  --dbname="$DATABASE_URL" --file="$plain"
test -s "$plain"
target="$out/mono-pg-$stamp.pgc.gpg"
gpg --batch --yes --quiet --pinentry-mode loopback --symmetric --cipher-algo AES256 \
  --passphrase-fd 3 --output "$target" "$plain" 3<<<"$BACKUP_PASSPHRASE"
(cd "$out" && sha256sum "$(basename "$target")" >> SHA256SUMS)
echo "Sauvegarde chiffrée : $target"
