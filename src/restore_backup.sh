#!/usr/bin/env bash
set -u

BACKUP=""
DESTINATION=""
EXPECTED_SHA256=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: restore_backup.sh --backup FILE --destination DIR [options]

  --expected-sha256 HASH  Verify the archive against an expected SHA-256 value.
  --dry-run               Validate and show the restore plan without writing data.
  --yes                   Skip confirmation prompts.
  --output DIR            Save logs and staging data in DIR.
  -h, --help              Show help.

The destination must be absent or empty. Existing files are never overwritten.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --backup) BACKUP="${2:-}"; shift 2 ;;
    --destination) DESTINATION="${2:-}"; shift 2 ;;
    --expected-sha256) EXPECTED_SHA256="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ -f "$BACKUP" ] || { echo "Backup file not found: $BACKUP" >&2; exit 2; }
[ -n "$DESTINATION" ] || { echo "--destination is required." >&2; exit 2; }
case "$DESTINATION" in /|/etc|/usr|/var|/bin|/sbin|/boot|/home) echo "Refusing unsafe destination: $DESTINATION" >&2; exit 2 ;; esac

if [ -e "$DESTINATION" ]; then
  [ -d "$DESTINATION" ] || { echo "Destination exists and is not a directory." >&2; exit 2; }
  [ -z "$(find "$DESTINATION" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ] || { echo "Destination must be empty: $DESTINATION" >&2; exit 20; }
fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./backup-restore-$STAMP}"
STAGING="$OUTPUT_DIR/staging"
LOG="$OUTPUT_DIR/restore.log"
VERIFY="$OUTPUT_DIR/verification.txt"
mkdir -p "$OUTPUT_DIR"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
archive_type() {
  case "$BACKUP" in
    *.tar) echo tar ;;
    *.tar.gz|*.tgz) echo targz ;;
    *.tar.xz|*.txz) echo tarxz ;;
    *.zip) echo zip ;;
    *) echo unknown ;;
  esac
}
verify_archive() {
  local type="$1"
  case "$type" in
    tar) tar -tf "$BACKUP" >/dev/null ;;
    targz) tar -tzf "$BACKUP" >/dev/null ;;
    tarxz) tar -tJf "$BACKUP" >/dev/null ;;
    zip) command -v unzip >/dev/null 2>&1 && unzip -tq "$BACKUP" >/dev/null ;;
    *) return 1 ;;
  esac
}
extract_archive() {
  local type="$1"
  case "$type" in
    tar) tar -xf "$BACKUP" -C "$STAGING" ;;
    targz) tar -xzf "$BACKUP" -C "$STAGING" ;;
    tarxz) tar -xJf "$BACKUP" -C "$STAGING" ;;
    zip) unzip -q "$BACKUP" -d "$STAGING" ;;
    *) return 1 ;;
  esac
}

TYPE=$(archive_type)
[ "$TYPE" != "unknown" ] || { echo "Unsupported archive type." >&2; exit 2; }

ACTUAL_SHA256=$(sha256sum "$BACKUP" | awk '{print $1}')
if [ -n "$EXPECTED_SHA256" ] && [ "${ACTUAL_SHA256,,}" != "${EXPECTED_SHA256,,}" ]; then
  log "Checksum mismatch. Expected $EXPECTED_SHA256 but calculated $ACTUAL_SHA256."
  exit 20
fi

if ! verify_archive "$TYPE"; then
  log "Archive integrity test failed. No restore was attempted."
  exit 20
fi

{
  echo "Backup: $BACKUP"
  echo "Archive type: $TYPE"
  echo "SHA-256: $ACTUAL_SHA256"
  echo "Destination: $DESTINATION"
  echo "Backup size: $(du -h "$BACKUP" | awk '{print $1}')"
} > "$VERIFY"

confirm "Restore the verified archive into the empty destination $DESTINATION?" || { log "Restore cancelled."; exit 10; }

if $DRY_RUN; then
  log "DRY-RUN: archive passed validation; restore would extract to staging and copy into $DESTINATION."
  exit 0
fi

mkdir -p "$STAGING"
run_action "Extracting archive into isolated staging directory" extract_archive "$TYPE" || true
[ "$FAILURES" -eq 0 ] || exit 20

RESTORED_FILES=$(find "$STAGING" -type f | wc -l | tr -d ' ')
RESTORED_BYTES=$(du -sb "$STAGING" 2>/dev/null | awk '{print $1}')
printf 'Restored files in staging: %s\nRestored bytes in staging: %s\n' "$RESTORED_FILES" "${RESTORED_BYTES:-unknown}" >> "$VERIFY"

mkdir -p "$DESTINATION"
if command -v rsync >/dev/null 2>&1; then
  run_action "Copying restored content without overwriting existing files" rsync -a --ignore-existing "$STAGING"/ "$DESTINATION"/ || true
else
  run_action "Copying restored content into destination" cp -a "$STAGING"/. "$DESTINATION"/ || true
fi

if [ "$FAILURES" -gt 0 ]; then exit 20; fi
DEST_FILES=$(find "$DESTINATION" -type f | wc -l | tr -d ' ')
printf 'Files present in destination after restore: %s\n' "$DEST_FILES" >> "$VERIFY"
log "Verified restore completed successfully. Files restored: $DEST_FILES"
exit 0
