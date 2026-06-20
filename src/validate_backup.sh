#!/usr/bin/env bash
set -u

BACKUP=""
EXPECTED_SHA=""
TEST_RESTORE=false
MAX_AGE_DAYS=30
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup) BACKUP="${2:-}"; shift 2 ;;
    --expected-sha256) EXPECTED_SHA="${2:-}"; shift 2 ;;
    --test-restore) TEST_RESTORE=true; shift ;;
    --max-age-days) MAX_AGE_DAYS="${2:-30}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: $0 --backup FILE [--expected-sha256 HASH] [--test-restore] [--max-age-days N] [--output DIR]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$BACKUP" ]] || { echo "--backup is required" >&2; exit 2; }
[[ -f "$BACKUP" ]] || { echo "Backup file not found: $BACKUP" >&2; exit 1; }
[[ "$MAX_AGE_DAYS" =~ ^[0-9]+$ ]] || { echo "--max-age-days must be numeric" >&2; exit 2; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./backup-validation-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/validation-report.txt"
JSON="$OUTPUT_DIR/validation-summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"

ABS_BACKUP="$(readlink -f "$BACKUP" 2>/dev/null || realpath "$BACKUP")"
SIZE="$(stat -c %s "$BACKUP")"
MTIME="$(stat -c %Y "$BACKUP")"
NOW="$(date +%s)"
AGE_DAYS="$(( (NOW - MTIME) / 86400 ))"
SHA256="$(sha256sum "$BACKUP" | awk '{print $1}')"
CHECKSUM_STATUS="not_provided"
if [[ -n "$EXPECTED_SHA" ]]; then
  CHECKSUM_STATUS="failed"
  [[ "${SHA256,,}" == "${EXPECTED_SHA,,}" ]] && CHECKSUM_STATUS="passed"
fi

ARCHIVE_TYPE="unknown"
INTEGRITY="failed"
FILE_COUNT=0
case "$BACKUP" in
  *.tar.gz|*.tgz)
    ARCHIVE_TYPE="tar.gz"
    tar -tzf "$BACKUP" > "$OUTPUT_DIR/archive-contents.txt" 2>> "$ERRORS" && INTEGRITY="passed"
    ;;
  *.tar.xz|*.txz)
    ARCHIVE_TYPE="tar.xz"
    tar -tJf "$BACKUP" > "$OUTPUT_DIR/archive-contents.txt" 2>> "$ERRORS" && INTEGRITY="passed"
    ;;
  *.tar)
    ARCHIVE_TYPE="tar"
    tar -tf "$BACKUP" > "$OUTPUT_DIR/archive-contents.txt" 2>> "$ERRORS" && INTEGRITY="passed"
    ;;
  *.zip)
    ARCHIVE_TYPE="zip"
    unzip -t "$BACKUP" > "$OUTPUT_DIR/archive-test.txt" 2>> "$ERRORS" && INTEGRITY="passed"
    unzip -Z1 "$BACKUP" > "$OUTPUT_DIR/archive-contents.txt" 2>> "$ERRORS" || true
    ;;
  *)
    file "$BACKUP" > "$OUTPUT_DIR/file-type.txt" 2>> "$ERRORS" || true
    ;;
esac
[[ -f "$OUTPUT_DIR/archive-contents.txt" ]] && FILE_COUNT="$(grep -cv '/$' "$OUTPUT_DIR/archive-contents.txt" 2>/dev/null || true)"

RESTORE_STATUS="not_requested"
RESTORE_DIR=""
RESTORED_COUNT=0
if $TEST_RESTORE; then
  RESTORE_DIR="$OUTPUT_DIR/test-restore"
  mkdir -p "$RESTORE_DIR"
  RESTORE_STATUS="failed"
  case "$ARCHIVE_TYPE" in
    tar.gz) tar -xzf "$BACKUP" -C "$RESTORE_DIR" --no-same-owner --no-same-permissions 2>> "$ERRORS" && RESTORE_STATUS="passed" ;;
    tar.xz) tar -xJf "$BACKUP" -C "$RESTORE_DIR" --no-same-owner --no-same-permissions 2>> "$ERRORS" && RESTORE_STATUS="passed" ;;
    tar) tar -xf "$BACKUP" -C "$RESTORE_DIR" --no-same-owner --no-same-permissions 2>> "$ERRORS" && RESTORE_STATUS="passed" ;;
    zip) unzip -q "$BACKUP" -d "$RESTORE_DIR" 2>> "$ERRORS" && RESTORE_STATUS="passed" ;;
    *) echo "Unsupported archive type for test restore." >> "$ERRORS" ;;
  esac
  RESTORED_COUNT="$(find "$RESTORE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
fi

AGE_STATUS="passed"
[[ "$AGE_DAYS" -gt "$MAX_AGE_DAYS" ]] && AGE_STATUS="warning"
OVERALL="passed"
[[ "$INTEGRITY" != "passed" ]] && OVERALL="failed"
[[ "$CHECKSUM_STATUS" == "failed" ]] && OVERALL="failed"
[[ "$RESTORE_STATUS" == "failed" ]] && OVERALL="failed"
[[ "$AGE_STATUS" == "warning" && "$OVERALL" == "passed" ]] && OVERALL="warning"

cat > "$REPORT" <<EOF
Backup validation report
========================
Collected: $(date -Is)
Backup: $ABS_BACKUP
Archive type: $ARCHIVE_TYPE
Size bytes: $SIZE
Age days: $AGE_DAYS
Maximum age days: $MAX_AGE_DAYS
Age status: $AGE_STATUS
SHA-256: $SHA256
Checksum comparison: $CHECKSUM_STATUS
Archive integrity: $INTEGRITY
Archive file count: $FILE_COUNT
Test restore: $RESTORE_STATUS
Test restore directory: ${RESTORE_DIR:-none}
Restored file count: $RESTORED_COUNT
Overall result: $OVERALL
EOF

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "backup": "$ABS_BACKUP",
  "archive_type": "$ARCHIVE_TYPE",
  "size_bytes": $SIZE,
  "age_days": $AGE_DAYS,
  "age_status": "$AGE_STATUS",
  "sha256": "$SHA256",
  "checksum_status": "$CHECKSUM_STATUS",
  "integrity_status": "$INTEGRITY",
  "archive_file_count": ${FILE_COUNT:-0},
  "test_restore_status": "$RESTORE_STATUS",
  "restored_file_count": ${RESTORED_COUNT:-0},
  "overall_result": "$OVERALL"
}
EOF

cat "$REPORT"
[[ "$OVERALL" == "failed" ]] && exit 1
exit 0
